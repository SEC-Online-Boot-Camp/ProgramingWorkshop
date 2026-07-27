# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :codebreaking_mission,
  generators: [timestamp_type: :utc_datetime]

# Pythonコード実行の設定。
# 汎用的な"python"/"python3"だとPATH解決でWindows Store版のスタブ実行ファイルに
# 化けることがあるため、まず固有の実行ファイル名"python312"
# (scoopのpython312パッケージが提供するシム)を優先して探す。
config :codebreaking_mission, :python_runner,
  executable:
    System.find_executable("python312") ||
      System.find_executable("python3") ||
      System.find_executable("python") ||
      raise("""
      Python実行ファイルが見つかりません。
      `scoop install python312` などでPython 3.12系を導入してください。
      """),
  run_timeout_ms: 15_000

# Configure the endpoint
config :codebreaking_mission, CodebreakingMissionWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CodebreakingMissionWeb.ErrorHTML, json: CodebreakingMissionWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CodebreakingMission.PubSub,
  live_view: [signing_salt: "pk/Ok5/G"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r",
  # AutoScrollフックはassets/node_modulesから何もimportしないため、
  # シンボリックリンク作成失敗（Windowsで管理者権限が無い場合に発生）の警告は無効化する。
  colocated_assets: [disable_symlink_warning: true]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  codebreaking_mission: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  codebreaking_mission: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
