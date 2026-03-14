defmodule Forgelet.CredentialStoreTest do
  use ExUnit.Case, async: true

  alias Forgelet.CredentialStore

  test "returns only configured runtime environment variables" do
    {:ok, pid} =
      CredentialStore.start_link(
        runtime_registry: %{
          claude_code: %{
            credentials: %{"ANTHROPIC_API_KEY" => {:literal, "secret-key"}}
          }
        },
        name: nil
      )

    env =
      CredentialStore.runtime_env(:claude_code, [{"HOME", "/tmp/forgelet"}], name: pid)

    assert {:ok, resolved_env} = env
    assert {"HOME", "/tmp/forgelet"} in resolved_env
    assert {"ANTHROPIC_API_KEY", "secret-key"} in resolved_env
    refute {"OPENAI_API_KEY", "secret-key"} in resolved_env
  end

  test "redacts credential values from runtime metadata" do
    {:ok, pid} =
      CredentialStore.start_link(
        runtime_registry: %{
          claude_code: %{
            credentials: %{"ANTHROPIC_API_KEY" => {:literal, "secret-key"}},
            models: %{fast_coder: %{id: "claude-sonnet-4-6"}}
          }
        },
        name: nil
      )

    metadata = CredentialStore.runtime_metadata(:claude_code, name: pid)

    assert metadata.credentials["ANTHROPIC_API_KEY"] == :configured
    refute inspect(metadata) =~ "secret-key"
  end

  test "reports missing credentials without crashing startup" do
    {:ok, pid} =
      CredentialStore.start_link(
        runtime_registry: %{
          codex: %{
            credentials: %{"OPENAI_API_KEY" => {:system, "FORGELET_MISSING_OPENAI_KEY"}}
          }
        },
        name: nil
      )

    assert {:error, {:missing_credentials, ["FORGELET_MISSING_OPENAI_KEY"]}} =
             CredentialStore.runtime_env(:codex, [], name: pid)
  end
end
