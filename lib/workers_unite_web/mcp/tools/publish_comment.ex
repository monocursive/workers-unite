defmodule WorkersUniteWeb.MCP.Tools.PublishComment do
  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.Agent
  alias WorkersUnite.EventStore

  @impl true
  def definition do
    %{
      "name" => "workers_unite_publish_comment",
      "description" => "Publishes a review comment on a proposal.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["proposal_ref", "body"],
        "properties" => %{
          "proposal_ref" => %{"type" => "string"},
          "body" => %{"type" => "string"},
          "file" => %{"type" => "string"},
          "line" => %{"type" => "integer"}
        }
      }
    }
  end

  @impl true
  def call(%{"proposal_ref" => proposal_ref, "body" => body} = params, %{agent_id: agent_id}) do
    with {:ok, proposal} <- fetch_proposal(proposal_ref),
         {:ok, event_ref} <-
           Agent.publish_comment(
             agent_id,
             build_payload(proposal_ref, body, params),
             proposal.scope
           ) do
      {:ok, %{event_ref: event_ref}}
    end
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

  defp build_payload(proposal_ref, body, params) do
    %{"proposal_ref" => proposal_ref, "body" => body}
    |> maybe_put("file", params["file"])
    |> maybe_put("line", params["line"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
