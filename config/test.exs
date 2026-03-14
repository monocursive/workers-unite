import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :workers_unite, WorkersUnite.Repo,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("DB_HOST", "localhost"),
  database: "workers_unite_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :workers_unite, WorkersUniteWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "AGppTIvUc3UVeH/v64NKp15LI7fwaqMfgMfB3c0YdnQ9d67pTDs6E0GDmpThNfdx",
  server: false

# In test we don't send emails
config :workers_unite, WorkersUnite.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# WorkersUnite test overrides
config :workers_unite,
  repo_base_path: Path.expand("../tmp/test_repos", __DIR__),
  default_consensus_policy: {:threshold, 2, 0.7},
  opencode_cli_path: Path.expand("../test/support/mock_opencode.sh", __DIR__),
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
      credentials: %{"ANTHROPIC_API_KEY" => {:system, "WORKERS_UNITE_TEST_ANTHROPIC_API_KEY"}}
    },
    openai: %{
      credentials: %{"OPENAI_API_KEY" => {:system, "WORKERS_UNITE_TEST_OPENAI_API_KEY"}}
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
      key: "gpt-4o",
      label: "GPT-4o",
      provider: :openai,
      model_id: "gpt-4o"
    }
  ],
  session_workspace_base: Path.expand("../tmp/test_sessions", __DIR__),
  default_test_command: ["sh", "-lc", "exit 0"],
  mcp_public_base_url: "http://localhost:4002",
  credential_encryption_key: :crypto.strong_rand_bytes(32)
