defmodule WorkersUniteWeb.MCP.Tools.Helpers do
  @moduledoc false

  alias WorkersUnite.{Event, EventStore, Identity, Repository}

  def fetch_repo(repo_id) when is_binary(repo_id) do
    with {:ok, binary_id} <- decode_repo_id(repo_id) do
      {:ok, Repository.get_state(binary_id)}
    end
  catch
    :exit, _reason -> {:error, :repo_not_found}
  end

  def decode_repo_id(repo_id) do
    case Base.decode16(repo_id, case: :mixed) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :invalid_repo_id}
    end
  end

  def fetch_proposal(proposal_ref) do
    case EventStore.get_by_ref(proposal_ref) do
      {:ok, %{kind: :proposal_submitted} = event} -> {:ok, event}
      {:ok, _} -> {:error, :proposal_not_found}
      {:error, :not_found} -> {:error, :proposal_not_found}
      {:error, :invalid_ref} -> {:error, :invalid_proposal_ref}
    end
  end

  def summarize_event(event) do
    %{
      ref: Event.ref(event),
      kind: to_string(event.kind),
      author_fingerprint: Identity.fingerprint(event.author),
      timestamp: event.timestamp,
      payload_summary: event.payload
    }
  end

  def proposal_votes(proposal_ref) do
    EventStore.by_kind(:vote_cast)
    |> Enum.filter(fn event -> event.payload["proposal_ref"] == proposal_ref end)
  end
end
