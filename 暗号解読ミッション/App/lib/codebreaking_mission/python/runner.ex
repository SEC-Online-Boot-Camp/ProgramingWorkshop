defmodule CodebreakingMission.Python.Runner do
  @moduledoc """
  1回の「実行」につき1つ起動されるGenServer。

  受け取ったPythonコードを一時ファイルに書き出し、`Port`経由で外部プロセスとして
  実行する。標準出力・標準エラー出力は1行ずつ`owner`（呼び出し元のLiveViewプロセス）
  へ`{:python_output, run_id, line}`として転送し、終了時に
  `{:python_done, run_id, exit_status}`を送る。

  `Pythonx`のようにBEAMと同一プロセスでPythonを動かす方式は採用していない。
  ユーザーコードの暴走・クラッシュがアプリ全体を巻き込むのを避けるため。
  """

  use GenServer, restart: :temporary

  @doc """
  実行を開始する。

    * `:code` - 実行するPythonソースコード
    * `:owner` - 結果の送信先プロセス
    * `:run_id` - この実行を識別するための一意な値
  """
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @doc "実行を強制停止する（OSプロセスをツリーごと終了させる）。"
  def stop(pid) do
    GenServer.call(pid, :stop)
  catch
    :exit, _ -> :ok
  end

  @impl true
  def init(%{code: code, owner: owner, run_id: run_id}) do
    cfg = Application.get_env(:codebreaking_mission, :python_runner)
    tmp_path = Path.join(System.tmp_dir!(), "codebreaking_mission_run_#{run_id}.py")
    File.write!(tmp_path, code)

    port =
      Port.open(
        {:spawn_executable, cfg[:executable]},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:line, 8192},
          args: ["-X", "utf8", "-u", tmp_path],
          env: [{~c"PYTHONIOENCODING", ~c"utf-8"}, {~c"PYTHONUNBUFFERED", ~c"1"}],
          cd: System.tmp_dir!()
        ]
      )

    os_pid =
      case Port.info(port, :os_pid) do
        {:os_pid, pid} -> pid
        nil -> nil
      end

    timer = Process.send_after(self(), :timeout, cfg[:run_timeout_ms])

    {:ok,
     %{
       port: port,
       os_pid: os_pid,
       owner: owner,
       run_id: run_id,
       tmp_path: tmp_path,
       timer: timer,
       # 8192バイトを超える1行は :noeol で分割されて届くため、
       # :eol が来るまでバッファに溜めておく。
       line_buffer: ""
     }}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    kill(state)
    send(state.owner, {:python_output, state.run_id, "[停止しました]"})
    send(state.owner, {:python_done, state.run_id, :stopped})
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({port, {:data, {:eol, chunk}}}, %{port: port} = state) do
    send(state.owner, {:python_output, state.run_id, state.line_buffer <> chunk})
    {:noreply, %{state | line_buffer: ""}}
  end

  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state) do
    {:noreply, %{state | line_buffer: state.line_buffer <> chunk}}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Process.cancel_timer(state.timer)
    send(state.owner, {:python_done, state.run_id, status})
    {:stop, :normal, state}
  end

  def handle_info(:timeout, state) do
    kill(state)
    send(state.owner, {:python_output, state.run_id, "[実行がタイムアウトしました]"})
    send(state.owner, {:python_done, state.run_id, :timeout})
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, state) do
    File.rm(state.tmp_path)
    :ok
  end

  # `Port.close/1`はErlang側のポートを閉じるだけで、Windowsでは配下のOSプロセス
  # （子プロセスを含む）を確実には終了させない。そのため taskkill を使って
  # プロセスツリーごと明示的に終了させる。
  defp kill(%{os_pid: nil, port: port}) do
    safe_close(port)
  end

  defp kill(%{os_pid: os_pid, port: port}) do
    System.cmd("taskkill", ["/F", "/T", "/PID", to_string(os_pid)], stderr_to_stdout: true)
    safe_close(port)
  end

  defp safe_close(port) do
    if Port.info(port) != nil, do: Port.close(port)
  catch
    :error, _ -> :ok
  end
end
