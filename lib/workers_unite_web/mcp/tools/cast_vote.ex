defmodule WorkersUniteWeb.MCP.Tools.CastVote do
  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.Agent
  alias WorkersUnite.EventStore

  @impl true
  def definition do
    %{
      "name" => "workers_unite_cast_vote",
      "description" => "Casts a review vote on a proposal.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["proposal_ref", "verdict", "confidence"],
        "properties" => %{
          "proposal_ref" => %{"type" => "string"},
          "verdict" => %{"type" => "string"},
          "confidence" => %{"type" => "number"},
          "rationale" => %{"type" => "string"}
        }
      }
    }
  end

  @impl true
  def call(%{"proposal_ref" => proposal_ref, "verdict" => verdict, "confidence" => confidence}, %{
        agent_id: agent_id
      }) do
    with {:ok, proposal} <- fetch_proposal(proposal_ref),
         {:ok, event_ref} <-
           Agent.vote(agent_id, proposal_ref, String.to_existing_atom(verdict),
             scope: proposal.scope,
             confidence: confidence
           ) do
      {:ok, %{event_ref: event_ref}}
    end
  rescue
    ArgumentError -> {:error, :invalid_verdict}
  end

  def call(_params, _context), do: {:error, :invalid_params}

  defp fetch_proposal(proposal_ref) do
    EventStore.by_kind(:proposal_submitted)
    |> Enum.find(&(WorkersUnite.Event.ref(&1) == proposal_ref))
    |> case do
      nil -> {:error, :proposal_not_found}
      proposal -> {:ok, proposal}
    end
  end
end
