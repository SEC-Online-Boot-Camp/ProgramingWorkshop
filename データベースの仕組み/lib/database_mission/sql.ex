defmodule DatabaseMission.Sql do
  @moduledoc """
  受講者が書いたSQLを、受講者ごとのSQLiteファイルに対して実行する。

  実行は `priv/python/run_sql.py` をPythonの外部プロセスとして起動して行う。
  Python標準の`sqlite3`を使うので、ElixirからSQLiteを扱うためのNIF（exqlite等）は
  入れていない。教室のPCでネイティブライブラリのビルドに失敗するのを避けるため。

  データベースファイルは `System.tmp_dir!()/database_mission/` に置き、
  アプリの起動時に `clean_workspace/0` でまとめて消す。
  """

  @type result ::
          %{
            sql: String.t(),
            type: :rows,
            columns: [String.t()],
            rows: [list()],
            truncated: boolean()
          }
          | %{sql: String.t(), type: :change, count: integer()}

  @type table :: %{columns: [String.t()], rows: [list()]}

  @type outcome :: %{
          results: [result()],
          error: nil | %{sql: String.t(), message: String.t()},
          extras: [table() | nil],
          tracked: [boolean()]
        }

  @doc "データベースファイルの置き場所。"
  def workspace, do: Path.join(System.tmp_dir!(), "database_mission")

  @doc "前回の起動で残ったデータベースファイルを消す。"
  def clean_workspace do
    File.rm_rf(workspace())
    :ok
  end

  @doc """
  新しいデータベースファイルを作り、`seed_sql`（テーブル作成と初期データ）を流し込む。

  `path` を指定すると、その場所に作る（同じ名前のファイルがあれば、作り直す）。
  指定しなければ、ランダムな名前で作る。
  """
  @spec new_database(String.t(), Path.t() | nil) :: {:ok, Path.t()} | {:error, String.t()}
  def new_database(seed_sql, path \\ nil) do
    File.mkdir_p!(workspace())

    path =
      path || Path.join(workspace(), "#{System.unique_integer([:positive])}_#{random_id()}.db")

    File.rm(path)

    case run(path, seed_sql) do
      {:ok, %{error: nil}} -> {:ok, path}
      {:ok, %{error: %{message: message}}} -> {:error, message}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "データベースファイルを消す。"
  def delete_database(nil), do: :ok

  def delete_database(path) do
    File.rm(path)
    :ok
  end

  @doc """
  `sql` を実行する。続けて `extras`（アプリ側の確認用SELECT）を実行し、
  その結果を `:extras` に同じ順番で返す。

  `track`（アプリ側の確認用SELECT）は、`sql` の1文ごとに実行し、行が返ったことが
  一度でもあれば `:tracked` の同じ位置を `true` にする。最後の状態からは分からない、
  途中の状態（INSERTしてすぐDELETEした、など）を知るために使う。
  """
  @spec run(Path.t(), String.t(), [String.t()], [String.t()]) ::
          {:ok, outcome()} | {:error, String.t()}
  def run(db_path, sql, extras \\ [], track \\ []) do
    payload = %{sql: sql, extras: extras, track: track}

    case call_python("run_sql.py", db_path, payload) do
      {:ok, output} -> decode(output)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  読み取り専用で、1文のSELECTを実行する（`priv/python/run_query.py`）。

  `params` は SQL の `?` に値として渡す（プレースホルダ）。「SQLインジェクション」タブの
  SQLインジェクションの体験で、入力をそのままSQLに入れた場合も、値として渡した場合も、
  この関数で実行する。データベースは読み取り専用で開き、SELECT以外は拒否し、
  複数の文は実行できず、3秒で打ち切り、結果は200行までにしている。
  """
  @spec query(Path.t(), String.t(), [term()]) ::
          {:ok, %{columns: [String.t()], rows: [list()], truncated: boolean()}}
          | {:error, String.t()}
  def query(db_path, sql, params \\ []) do
    with {:ok, output} <- call_python("run_query.py", db_path, %{sql: sql, params: params}) do
      decode_query(output)
    end
  end

  # Pythonのスクリプトを外部プロセスとして起動し、標準出力を返す
  defp call_python(script, db_path, payload) do
    cfg = Application.get_env(:database_mission, :sql_runner)
    input_path = Path.rootname(db_path) <> "_#{System.unique_integer([:positive])}.json"
    File.write!(input_path, Jason.encode!(payload))

    task =
      Task.async(fn ->
        System.cmd(
          cfg[:executable],
          ["-X", "utf8", script_path(script), db_path, input_path],
          stderr_to_stdout: true,
          env: [{"PYTHONIOENCODING", "utf-8"}]
        )
      end)

    try do
      case Task.yield(task, cfg[:run_timeout_ms]) || Task.shutdown(task, :brutal_kill) do
        {:ok, {output, 0}} -> {:ok, output}
        {:ok, {output, _status}} -> {:error, String.trim(output)}
        nil -> {:error, "実行がタイムアウトしました"}
      end
    after
      File.rm(input_path)
    end
  end

  @doc "SQLの文字列リテラルとして安全に埋め込めるよう、シングルクォートを重ねる。"
  def quote_string(value), do: "'" <> String.replace(value, "'", "''") <> "'"

  defp decode(output) do
    line = output |> String.trim() |> String.split("\n") |> List.last()

    case Jason.decode(line) do
      {:ok, %{"results" => results, "error" => error, "extras" => extras} = body} ->
        {:ok,
         %{
           results: Enum.map(results, &to_result/1),
           error: error && %{sql: error["sql"], message: error["message"]},
           extras: Enum.map(extras, &to_table/1),
           tracked: Map.get(body, "tracked", [])
         }}

      _ ->
        {:error, String.trim(output)}
    end
  end

  defp decode_query(output) do
    line = output |> String.trim() |> String.split("\n") |> List.last()

    case Jason.decode(line) do
      {:ok, %{"error" => nil, "columns" => columns, "rows" => rows, "truncated" => truncated}} ->
        {:ok, %{columns: columns, rows: rows, truncated: truncated}}

      {:ok, %{"error" => message}} when is_binary(message) ->
        {:error, message}

      _ ->
        {:error, String.trim(output)}
    end
  end

  defp to_result(%{"type" => "rows"} = r) do
    %{
      sql: r["sql"],
      type: :rows,
      columns: r["columns"],
      rows: r["rows"],
      truncated: r["truncated"]
    }
  end

  defp to_result(%{"type" => "change"} = r) do
    %{sql: r["sql"], type: :change, count: r["count"]}
  end

  defp to_table(nil), do: nil
  defp to_table(%{"columns" => columns, "rows" => rows}), do: %{columns: columns, rows: rows}
  defp to_table(_), do: nil

  defp script_path(name), do: Application.app_dir(:database_mission, "priv/python/#{name}")

  defp random_id, do: :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
end
