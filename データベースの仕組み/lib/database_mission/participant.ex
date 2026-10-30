defmodule DatabaseMission.Participant do
  @moduledoc """
  受講者（同じブラウザ）を見分ける識別子と、その受講者のデータベースの置き場所。

  識別子はブラウザのセッション（署名つきのcookie）に入れる。ミッションの画面と、別ページの
  通販サイト（`/shop`）が、同じ識別子から、同じ受講者のミッション2・3・4のデータベースを
  引けるようにするためのもの。

  ミッション2・3・4のデータベースは `<識別子>_<ミッション>.db` という決まった名前にする
  （ミッションを始めたとき・最初のデータに戻すときに作り直す）。画面を再読み込みすると、
  ミッションの画面はデータが最初に戻るので、その受講者のデータベースも消す。
  """

  alias DatabaseMission.Sql

  @missions ~w(m2 m3 m4)
  @id_pattern ~r/\A[A-Za-z0-9_-]{8,64}\z/

  @doc "ミッションのうち、通販サイトから見えるデータベースを持つもの。"
  def missions, do: @missions

  @doc "新しい識別子を作る（URLやファイル名に使える文字だけ）。"
  def new_id, do: :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)

  @doc "識別子として正しいか。ファイル名に使うので、決まった文字だけを許す。"
  def valid?(id), do: is_binary(id) and Regex.match?(@id_pattern, id)

  @doc "受講者のミッションのデータベースのパス。"
  def db_path(id, mission) when mission in @missions do
    unless valid?(id), do: raise(ArgumentError, "識別子が正しくありません")
    Path.join(Sql.workspace(), "#{id}_#{mission}.db")
  end

  @doc "受講者のミッションのデータベースがあるか（ミッションを始めているか）。"
  def db_exists?(id, mission), do: valid?(id) and File.exists?(db_path(id, mission))

  @doc "受講者のミッション2・3・4のデータベースを消す。"
  def delete_databases(id) do
    if valid?(id), do: Enum.each(@missions, &File.rm(db_path(id, &1)))
    :ok
  end

  @doc "この受講者への通知（ミッション4の会員登録の結果など）を流すPubSubのトピック。"
  def topic(id), do: "participant:#{id}"

  @doc """
  ミッション4のデータベースに、会員を登録する。通販サイト（別ページ）からも、ミッションの
  画面に埋め込んだ会員登録画面からも、この関数を呼ぶ。結果は、この受講者のトピックに
  `{:m4_register, record}` として流す（サーバーの記録の表示と、課題の判定に使う）。
  """
  def register_member(id, name, email) do
    sql =
      "INSERT INTO 会員 (名前, メールアドレス) VALUES (#{Sql.quote_string(name)}, #{Sql.quote_string(email)});"

    record =
      case Sql.run(db_path(id, "m4"), sql) do
        {:ok, %{error: nil}} -> %{sql: sql, error: nil}
        {:ok, %{error: %{message: message}}} -> %{sql: sql, error: message}
        {:error, reason} -> %{sql: sql, error: reason}
      end

    Phoenix.PubSub.broadcast(DatabaseMission.PubSub, topic(id), {:m4_register, record})

    record
  end
end
