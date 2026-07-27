defmodule CodebreakingMission.Python.RunSupervisor do
  @moduledoc """
  `CodebreakingMission.Python.Runner`用のDynamicSupervisorラッパー。

  実行クリックごとに新しいRunnerを起動する。Runnerは
  `restart: :temporary`（`Runner`モジュール側の`use GenServer`で指定）なので、
  終了・強制終了した実行が自動的に再起動されることはない。
  """

  alias CodebreakingMission.Python.Runner

  @doc """
  新しい実行を開始する。

  `owner`は結果の送信先プロセス（通常は呼び出し元のLiveViewプロセス）。
  戻り値の`pid`はUIの「停止」ボタンから`Runner.stop/1`に渡す。
  """
  def start_run(code, owner, run_id) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {Runner, %{code: code, owner: owner, run_id: run_id}}
    )
  end
end
