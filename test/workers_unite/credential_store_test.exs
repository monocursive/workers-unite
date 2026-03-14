defmodule WorkersUnite.CredentialStoreTest do
  use ExUnit.Case, async: true

  alias WorkersUnite.CredentialStore

  test "returns only configured runtime environment variables" do
    {:ok, pid} =
      CredentialStore.start_link(
        runtime_registry: %{
          opencode: %{
            credentials: %{}
          }
        },
        provider_registry: %{
          anthropic: %{
            credentials: %{"ANTHROPIC_API_KEY" => {:literal, "secret-key"}}
          }
        },
        load_db_credentials?: false,
        name: nil
      )

    env =
      CredentialStore.runtime_env(:opencode, [{"HOME", "/tmp/workers_unite"}], name: pid)

    assert {:ok, resolved_env} = env
    assert {"HOME", "/tmp/workers_unite"} in resolved_env
  end

  test "returns provider environment variables" do
    {:ok, pid} =
      CredentialStore.start_link(
        runtime_registry: %{},
        provider_registry: %{
          anthropic: %{
            credentials: %{"ANTHROPIC_API_KEY" => {:literal, "secret-key"}}
          }
        },
        load_db_credentials?: false,
        name: nil
      )

    env =
      CredentialStore.provider_env(:anthropic, [{"HOME", "/tmp/workers_unite"}], name: pid)

    assert {:ok, resolved_env} = env
    assert {"HOME", "/tmp/workers_unite"} in resolved_env
    assert {"ANTHROPIC_API_KEY", "secret-key"} in resolved_env
  end

  test "redacts credential values from runtime metadata" do
    {:ok, pid} =
      CredentialStore.start_link(
        runtime_registry: %{
          opencode: %{
            credentials: %{}
          }
        },
        provider_registry: %{},
        load_db_credentials?: false,
        name: nil
      )

    metadata = CredentialStore.runtime_metadata(:opencode, name: pid)

    assert metadata.credentials == %{}
  end

  test "reports missing credentials without crashing startup" do
    {:ok, pid} =
      CredentialStore.start_link(
        runtime_registry: %{},
        provider_registry: %{
          openai: %{
            credentials: %{"OPENAI_API_KEY" => {:system, "WORKERS_UNITE_MISSING_OPENAI_KEY"}}
          }
        },
        load_db_credentials?: false,
        name: nil
      )

    assert {:error, {:missing_credentials, ["WORKERS_UNITE_MISSING_OPENAI_KEY"]}} =
             CredentialStore.provider_env(:openai, [], name: pid)
  end

  test "provider_configured? returns true when all credentials are set" do
    {:ok, pid} =
      CredentialStore.start_link(
        runtime_registry: %{},
        provider_registry: %{
          anthropic: %{
            credentials: %{"ANTHROPIC_API_KEY" => {:literal, "secret-key"}}
          }
        },
        load_db_credentials?: false,
        name: nil
      )

    assert CredentialStore.provider_configured?(:anthropic, name: pid)
  end

  test "provider_configured? returns false when credentials are missing" do
    {:ok, pid} =
      CredentialStore.start_link(
        runtime_registry: %{},
        provider_registry: %{
          openai: %{
            credentials: %{"OPENAI_API_KEY" => {:system, "WORKERS_UNITE_MISSING_OPENAI_KEY"}}
          }
        },
        load_db_credentials?: false,
        name: nil
      )

    refute CredentialStore.provider_configured?(:openai, name: pid)
  end

  test "provider_configured? returns false for unknown provider" do
    {:ok, pid} =
      CredentialStore.start_link(
        runtime_registry: %{},
        provider_registry: %{},
        load_db_credentials?: false,
        name: nil
      )

    refute CredentialStore.provider_configured?(:unknown, name: pid)
  end
end
