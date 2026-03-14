# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :forgelet, :scopes,
  user: [
    default: true,
    module: Forgelet.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Forgelet.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :forgelet,
  ecto_repos: [Forgelet.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  repo_base_path: Path.expand("../priv/repos", __DIR__),
  bootstrap_peers: [],
  default_consensus_policy: {:threshold, 2, 0.7},
  claude_cli_path: System.get_env("CLAUDE_CLI_PATH", "claude"),
  runtime_registry: %{
    claude_code: %{
      adapter: Forgelet.Agent.Runtime.ClaudeCode,
      credentials: %{},
      models: %{
        fast_coder: %{id: "claude-sonnet-4-6"},
        fast_reviewer: %{id: "claude-sonnet-4-6"},
        deep_orchestrator: %{id: "claude-opus-4-6"}
      },
      native_tools: %{
        coder: ["Read", "Write", "Edit", "Glob", "Grep"],
        reviewer: ["Read", "Glob", "Grep"],
        orchestrator: ["Read", "Glob", "Grep"]
      }
    },
    codex: %{
      adapter: Forgelet.Agent.Runtime.Codex,
      credentials: %{},
      models: %{
        coder: %{id: "codex-latest"}
      },
      native_tools: %{
        coder: ["Read", "Write", "Edit", "Glob", "Grep"],
        reviewer: ["Read", "Glob", "Grep"],
        orchestrator: ["Read", "Glob", "Grep"]
      }
    }
  },
  agent_profiles: %{
    coder: %{runtime: :claude_code, model: :fast_coder},
    reviewer: %{runtime: :claude_code, model: :fast_reviewer},
    orchestrator: %{runtime: :claude_code, model: :deep_orchestrator}
  },
  agent_models: %{
    coder: "claude-sonnet-4-6",
    reviewer: "claude-sonnet-4-6",
    orchestrator: "claude-opus-4-6"
  },
  agent_budgets: %{
    coder: %{timeout_ms: 600_000},
    reviewer: %{timeout_ms: 300_000},
    orchestrator: %{timeout_ms: 600_000}
  },
  session_workspace_base: Path.join(System.tmp_dir!(), "forgelet-sessions"),
  default_test_command: ["mix", "test"],
  mcp_public_base_url: System.get_env("FORGELET_MCP_BASE_URL", "http://localhost:4000")

# Configure the endpoint
config :forgelet, ForgeletWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ForgeletWeb.ErrorHTML, json: ForgeletWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Forgelet.PubSub,
  live_view: [signing_salt: "lsV6oiAq"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :forgelet, Forgelet.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  forgelet: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  forgelet: [
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
