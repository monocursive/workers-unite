defmodule WorkersUniteWeb.OperatorMCP.Tools.InspectAgent do
  @moduledoc """
  Returns the detailed state of a single agent, including provenance,
  capabilities, and active session info.
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.{Agent, Identity}

  @impl true
  def definition do
    %{
      "name" => "wu_inspect_agent",
      "description" =>
        "Returns the full state of a specific agent identified by its hex-encoded " <>
          "public key. Includes provenance, capabilities, reputation, current task, " <>
          "and active session information.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["agent_id"],
        "properties" => %{
          "agent_id" => %{
            "type" => "string",
            "description" => "Hex-encoded Ed25519 public key of the agent"
          }
        }
      }
    }
  end

  @impl true
  def call(%{"agent_id" => agent_id_hex}, _context) do
    with {:ok, agent_id} <- decode_agent_id(agent_id_hex) do
      state = Agent.inspect_state(agent_id)

      {:ok,
       %{
         fingerprint: Identity.fingerprint(agent_id),
         kind: state.kind,
         status: state.status,
         reputation: state.reputation,
         current_task: state.current_task,
         model: state.model,
         provenance: state.provenance,
         capabilities: state.capabilities,
         active_session: state.active_session
       }}
    end
  catch
    :exit, _reason -> {:error, :agent_not_found}
  end

  def call(_params, _context), do: {:error, :invalid_params}

  defp decode_agent_id(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :invalid_agent_id}
    end
  end
end
