defmodule WorkersUniteWeb.OperatorMCP.Tools.InspectRepo do
  @moduledoc """
  Returns the detailed state of a single repository, including active intents,
  proposals, participating agents, and consensus policy.
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.Identity
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "wu_inspect_repo",
      "description" =>
        "Returns the full state of a specific repository identified by its hex-encoded ID. " <>
          "Includes path, active intents with details, active proposals, participating agents, " <>
          "and consensus policy.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["repo_id"],
        "properties" => %{
          "repo_id" => %{
            "type" => "string",
            "description" => "Hex-encoded repository ID"
          }
        }
      }
    }
  end

  @impl true
  def call(%{"repo_id" => repo_id}, _context) do
    with {:ok, state} <- Helpers.fetch_repo(repo_id) do
      intents =
        state.active_intents
        |> Enum.map(fn {ref, event} ->
          %{
            ref: ref,
            title: event.payload["title"],
            description: event.payload["description"],
            priority: event.payload["priority"],
            tags: event.payload["tags"] || [],
            author_fingerprint: Identity.fingerprint(event.author),
            timestamp: event.timestamp
          }
        end)

      proposals =
        state.active_proposals
        |> Enum.map(fn {ref, event} ->
          %{
            ref: ref,
            intent_ref: event.payload["intent_ref"],
            author_fingerprint: Identity.fingerprint(event.author),
            timestamp: event.timestamp,
            artifact: event.payload["artifact"]
          }
        end)

      agents =
        state.agents
        |> MapSet.to_list()
        |> Enum.map(&Identity.fingerprint/1)

      {:ok,
       %{
         repo_id: repo_id,
         name: state.name,
         policy: state.policy,
         active_intents: intents,
         active_proposals: proposals,
         participating_agents: agents
       }}
    end
  end

  def call(_params, _context), do: {:error, :invalid_params}
end
