defmodule WorkersUniteWeb.OperatorMCP.Tools.ClaimIntent do
  @moduledoc """
  Claims an intent by dispatching it to a suitable agent.
  If no agent_id is provided, uses the Dispatch service to find an idle coder agent.
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.{Agent, Identity}
  alias WorkersUnite.Operator.Dispatch
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "wu_claim_intent",
      "description" =>
        "Claims an intent by dispatching it to a worker agent. If no agent_id is " <>
          "specified, automatically selects an idle coder agent or spawns a new one.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["repo_id", "intent_ref"],
        "properties" => %{
          "repo_id" => %{
            "type" => "string",
            "description" => "Hex-encoded repository ID"
          },
          "intent_ref" => %{
            "type" => "string",
            "description" => "Hex-encoded event ref of the intent to claim"
          },
          "agent_id" => %{
            "type" => "string",
            "description" =>
              "Hex-encoded Ed25519 public key of a specific agent. " <>
                "If omitted, an idle coder agent is selected automatically."
          }
        }
      }
    }
  end

  @impl true
  def call(%{"repo_id" => repo_id_hex, "intent_ref" => intent_ref} = params, _context) do
    with {:ok, repo_id_binary} <- Helpers.decode_repo_id(repo_id_hex),
         {:ok, agent_id} <- resolve_agent(params),
         {:ok, event_ref} <-
           Agent.claim_intent(agent_id, repo_id_binary, intent_ref, {:repo, repo_id_binary}) do
      {:ok,
       %{
         event_ref: event_ref,
         agent_fingerprint: Identity.fingerprint(agent_id),
         repo_id: repo_id_hex,
         intent_ref: intent_ref
       }}
    end
  catch
    :exit, _reason -> {:error, :agent_not_found}
  end

  def call(_params, _context), do: {:error, :invalid_params}

  defp resolve_agent(%{"agent_id" => agent_id_hex}) when is_binary(agent_id_hex) do
    case Base.decode16(agent_id_hex, case: :mixed) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :invalid_agent_id}
    end
  end

  defp resolve_agent(_params) do
    Dispatch.find_or_spawn(:coder)
  end
end
