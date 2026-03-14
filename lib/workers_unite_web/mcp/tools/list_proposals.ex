defmodule WorkersUniteWeb.MCP.Tools.ListProposals do
  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.Repository
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "workers_unite_list_proposals",
      "description" => "Lists proposals pending review for a repository.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["repo_id"],
        "properties" => %{"repo_id" => %{"type" => "string"}}
      }
    }
  end

  @impl true
  def call(%{"repo_id" => repo_id}, _context) do
    repo_id_binary = Helpers.decode_repo_id(repo_id)
    repo = Repository.get_state(repo_id_binary)

    proposals =
      Repository.list_active_proposals(repo_id_binary)
      |> Enum.map(fn event ->
        intent = Map.get(repo.active_intents, event.payload["intent_ref"])

        %{
          ref: WorkersUnite.Event.ref(event),
          author_fingerprint: WorkersUnite.Identity.fingerprint(event.author),
          intent_ref: event.payload["intent_ref"],
          intent_title: intent && intent.payload["title"],
          submitted_at: event.timestamp
        }
      end)

    {:ok, proposals}
  catch
    :exit, _reason -> {:error, :repo_not_found}
  end

  def call(_params, _context), do: {:error, :invalid_params}
end
