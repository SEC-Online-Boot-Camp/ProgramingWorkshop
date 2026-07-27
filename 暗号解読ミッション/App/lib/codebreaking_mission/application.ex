defmodule CodebreakingMission.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CodebreakingMissionWeb.Telemetry,
      {DNSCluster,
       query: Application.get_env(:codebreaking_mission, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CodebreakingMission.PubSub},
      # 「実行」クリックごとにPythonRunnerを1つ起動する（:temporaryで自動再起動しない）
      {DynamicSupervisor, name: CodebreakingMission.Python.RunSupervisor, strategy: :one_for_one},
      # Start to serve requests, typically the last entry
      CodebreakingMissionWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CodebreakingMission.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CodebreakingMissionWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
