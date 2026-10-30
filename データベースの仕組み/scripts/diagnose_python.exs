# Pythonを起動できない(:eacces など)ときの診断スクリプト。
#
# 使い方(アプリのフォルダで):
#   mix run --no-start scripts/diagnose_python.exs
#   mix run --no-start scripts/diagnose_python.exs <pythonのパス>   # パスを指定して試す場合
#
# 読み取りと、Pythonの起動確認(print(1)・sqlite3の読み込み・一時フォルダ内の一時DBへのSQL実行)
# だけを行う。設定の変更・ファイルの書き換え・外部への通信はしない。
# 最後の「== まとめ ==」から下を、そのまま貼ってください。

defmodule Diagnose do
  @timeout 15_000

  # expect: 出力に含まれるべき文字列(終了コード0でも、期待した出力が無ければ失敗とみなす)
  def run_cmd(exe, args, expect \\ nil) do
    task =
      Task.async(fn ->
        try do
          System.cmd(exe, args, stderr_to_stdout: true, env: [{"PYTHONIOENCODING", "utf-8"}])
        rescue
          e -> {:raised, Exception.message(e)}
        catch
          kind, reason -> {:raised, "#{kind}: #{inspect(reason)}"}
        end
      end)

    case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:raised, msg}} ->
        {:ng, msg}

      {:ok, {out, 0}} ->
        out = clean(out)

        if is_nil(expect) or out =~ expect,
          do: {:ok, out},
          else: {:ng, "終了コード0だが、期待した出力(#{expect})が無い: #{out}"}

      {:ok, {out, status}} ->
        {:ng, "終了コード#{status}: #{clean(out)}"}

      nil ->
        {:ng, "#{div(@timeout, 1000)}秒以内に終わりませんでした"}
    end
  end

  # cmd.exeのエラーは日本語のOEM文字コードで出ることがあり、そのまま表示すると落ちるため、
  # 文字として読めない部分は ? に置き換える
  def clean(out), do: out |> String.replace_invalid("?") |> String.trim()

  def show(label, {:ok, detail}), do: IO.puts("[OK] #{label}  #{detail}")
  def show(label, {:ng, detail}), do: IO.puts("[NG] #{label}  #{detail}")
  def ok?({:ok, _}), do: true
  def ok?(_), do: false
end

override = List.first(System.argv())
configured = Application.get_env(:database_mission, :sql_runner)[:executable]
exe = override || configured

IO.puts("== 診断を開始します ==")
IO.puts("ホームフォルダ    : #{System.user_home()}")
IO.puts("アプリが選ぶPython : #{configured}")
IO.puts("今回試すPython     : #{exe}#{if override, do: "（指定）", else: ""}")
IO.puts("Erlang(erl.exe)    : #{System.find_executable("erl") || "(PATHに無し)"}")
IO.puts("")

exists = File.exists?(exe)

stat =
  case File.stat(exe) do
    {:ok, s} -> {:ok, "種類=#{s.type} サイズ=#{s.size}バイト 権限=#{s.access}"}
    {:error, reason} -> {:ng, "読み取れません: #{inspect(reason)}"}
  end

IO.puts("-- ファイル --")
Diagnose.show("ファイルがある", if(exists, do: {:ok, ""}, else: {:ng, "見つかりません"}))
Diagnose.show("ファイルの情報", stat)
IO.puts("")

# venvのpython.exeは、pyvenv.cfgの home に書かれた本体のPythonを使う。
# 本体が読めない・無いと、venvのPythonも起動できない
cfg_path = Path.join(Path.dirname(Path.dirname(exe)), "pyvenv.cfg")

case File.read(cfg_path) do
  {:ok, text} ->
    lines =
      text
      |> String.split(["\r\n", "\n"], trim: true)
      |> Enum.filter(&String.match?(&1, ~r/^(home|version|executable|implementation)\s*=/))

    Diagnose.show("pyvenv.cfg", {:ok, Enum.join(lines, " | ")})

    base_home =
      Enum.find_value(lines, fn line ->
        case String.split(line, "=", parts: 2) do
          ["home" <> _, value] -> String.trim(value)
          _ -> nil
        end
      end)

    if base_home do
      base_py = Path.join(base_home, "python.exe")

      Diagnose.show(
        "本体のPython(home)がある",
        if(File.exists?(base_py), do: {:ok, base_py}, else: {:ng, "見つかりません: #{base_py}"})
      )
    end

  {:error, _} ->
    Diagnose.show("pyvenv.cfg", {:ng, "読み取れません(venvではない、または権限なし): #{cfg_path}"})
end

IO.puts("")
IO.puts("-- 起動(アプリと同じ方法: Erlangが直接起動) --")
direct = Diagnose.run_cmd(exe, ["-X", "utf8", "-c", "print('hello')"], "hello")
Diagnose.show("Pythonを起動できる", direct)

sqlite =
  if Diagnose.ok?(direct),
    do:
      Diagnose.run_cmd(
        exe,
        ["-X", "utf8", "-c", "import sqlite3; print(sqlite3.sqlite_version)"],
        "."
      ),
    else: {:ng, "(起動できないので省略)"}

Diagnose.show("sqlite3を読み込める", sqlite)

IO.puts("")
IO.puts("-- 起動(参考: cmd.exe 経由) --")

via_cmd =
  if String.ends_with?(String.downcase(exe), ".exe"),
    do: Diagnose.run_cmd("cmd.exe", ["/c", exe, "-c", "print('hello')"], "hello"),
    else: {:ng, "(省略: .exe ではないため)"}

Diagnose.show("cmd.exe経由で起動できる", via_cmd)

IO.puts("")
IO.puts("-- アプリのSQL実行(一時フォルダ内の一時DBだけを使う) --")
workdir = Path.join(System.tmp_dir!(), "database_mission_diagnose")
File.mkdir_p!(workdir)
db = Path.join(workdir, "diagnose.db")
input = Path.join(workdir, "diagnose.json")
script = Application.app_dir(:database_mission, "priv/python/run_sql.py")
test_sql = "CREATE TABLE t(a); INSERT INTO t VALUES (1); SELECT * FROM t;"
File.write!(input, Jason.encode!(%{sql: test_sql, extras: []}))

sql =
  if Diagnose.ok?(direct) and File.exists?(script) do
    case Diagnose.run_cmd(exe, ["-X", "utf8", script, db, input]) do
      {:ok, out} -> if out =~ ~s("error": null), do: {:ok, "SQLを実行できた"}, else: {:ng, out}
      other -> other
    end
  else
    {:ng, "(省略: Pythonを起動できない、またはスクリプトが無い) script=#{script}"}
  end

Diagnose.show("run_sql.pyでSQLを実行できる", sql)
File.rm_rf(workdir)

IO.puts("")
IO.puts("== まとめ ==")
IO.puts("Python: #{exe}")

eacces? = match?({:ng, detail} when is_binary(detail), direct) and elem(direct, 1) =~ "eacces"

verdict =
  cond do
    Diagnose.ok?(direct) and Diagnose.ok?(sql) ->
      "問題なし: PythonもSQLの実行も動きます。アプリを再起動して、もう一度ミッション2を試してください。"

    not exists ->
      "Pythonのファイルがありません。パスか、venvの作成(pc-setup)を確認してください。"

    not Diagnose.ok?(direct) and Diagnose.ok?(via_cmd) ->
      "Erlangからの直接起動だけが拒否されています(cmd.exe経由は動く)。起動の仕方の問題の可能性があります。この結果を共有してください。"

    not Diagnose.ok?(direct) and not Diagnose.ok?(via_cmd) and eacces? ->
      "どちらの方法でもPythonを起動できません(eacces: OSが起動を拒否)。実行制限の可能性があります。この結果を管理者に共有してください(回避はしないでください)。"

    not Diagnose.ok?(direct) and not Diagnose.ok?(via_cmd) ->
      "どちらの方法でもPythonを起動できません。上の[NG]の内容を共有してください。"

    true ->
      "Pythonは起動できますが、SQLの実行に失敗しています。上の[NG]の内容を共有してください。"
  end

IO.puts("判定: #{verdict}")
