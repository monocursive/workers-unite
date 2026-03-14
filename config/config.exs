# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :workers_unite, :scopes,
  user: [
    default: true,
    module: WorkersUnite.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: WorkersUnite.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :workers_unite,
  ecto_repos: [WorkersUnite.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  repo_base_path: Path.expand("../priv/repos", __DIR__),
  bootstrap_peers: [],
  default_consensus_policy: {:threshold, 2, 0.7},
  opencode_cli_path: System.get_env("OPENCODE_CLI_PATH", "opencode"),
  runtime_registry: %{
    opencode: %{
      adapter: WorkersUnite.Agent.Runtime.OpenCode,
      credentials: %{},
      native_tools: %{
        coder: ["Read", "Write", "Edit", "Glob", "Grep"],
        reviewer: ["Read", "Glob", "Grep"],
        orchestrator: ["Read", "Glob", "Grep"]
      }
    }
  },
  provider_registry: %{
    anthropic: %{
      credentials: %{"ANTHROPIC_API_KEY" => {:system, "ANTHROPIC_API_KEY"}}
    },
    openai: %{
      credentials: %{"OPENAI_API_KEY" => {:system, "OPENAI_API_KEY"}}
    }
  },
  opencode_model_catalog: [
    %{
      key: "claude-sonnet-4",
      label: "Claude Sonnet 4",
      provider: :anthropic,
      model_id: "claude-sonnet-4-20250514"
    },
    %{
      key: "claude-opus-4",
      label: "Claude Opus 4",
      provider: :anthropic,
      model_id: "claude-opus-4-20250514"
    },
    %{
      key: "gpt-4o",
      label: "GPT-4o",
      provider: :openai,
      model_id: "gpt-4o"
    },
    %{
      key: "gpt-4-turbo",
      label: "GPT-4 Turbo",
      provider: :openai,
      model_id: "gpt-4-turbo"
    }
  ],
  agent_budgets: %{
    coder: %{timeout_ms: 600_000},
    reviewer: %{timeout_ms: 300_000},
    orchestrator: %{timeout_ms: 600_000}
  },
  session_workspace_base: Path.join(System.tmp_dir!(), "workers-unite-sessions"),
  default_test_command: ["mix", "test"],
  mcp_public_base_url: System.get_env("WORKERS_UNITE_MCP_BASE_URL", "http://localhost:4000")

# Configure the endpoint
config :workers_unite, WorkersUniteWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WorkersUniteWeb.ErrorHTML, json: WorkersUniteWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: WorkersUnite.PubSub,
  live_view: [signing_salt: "lsV6oiAq"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :workers_unite, WorkersUnite.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  workers_unite: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  workers_unite: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
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
