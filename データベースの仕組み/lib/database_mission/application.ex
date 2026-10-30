defmodule DatabaseMission.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # 前回の起動で残った受講者ごとのデータベースファイルを片付ける
    DatabaseMission.Sql.clean_workspace()

    children = [
      DatabaseMissionWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:database_mission, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DatabaseMission.PubSub},
      # Start to serve requests, typically the last entry
      DatabaseMissionWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DatabaseMission.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DatabaseMissionWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
