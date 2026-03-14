defmodule WorkersUnite.Agent.TaskContext do
  @moduledoc """
  Resolves repository and intent context for an agent's current task.
  """

  alias WorkersUnite.{Event, EventStore, Identity, Repository}

  def resolve(%{kind: :coder, current_task: nil}), do: {:error, :no_active_task}

  def resolve(%{kind: :coder, current_task: %{repo_id: nil}}), do: {:error, :missing_repo_context}

  def resolve(%{kind: :coder, current_task: current_task} = state) do
    with {:ok, repo} <- fetch_repo(current_task.repo_id),
         {:ok, task_event} <- EventStore.get_by_ref(current_task.ref),
         {:ok, intent_event} <- fetch_intent_event(current_task, task_event) do
      {:ok,
       %{
         agent_fingerprint: Identity.fingerprint(state.keypair.public),
         repo_id: current_task.repo_id,
         repo_id_hex: Base.encode16(current_task.repo_id, case: :lower),
         repo_name: repo.name,
         task_kind: current_task.kind,
         task_ref: current_task.ref,
         intent_ref: Event.ref(intent_event),
         intent_title: intent_event.payload["title"],
         intent_description: intent_event.payload["description"],
         intent_constraints: intent_event.payload["constraints"],
         intent_tags: intent_event.payload["tags"] || []
       }}
    end
  end

  def resolve(%{kind: kind}) when kind in [:reviewer, :orchestrator], do: {:ok, nil}

  defp fetch_repo(repo_id) do
    normalized_repo_id =
      case Base.decode16(repo_id, case: :mixed) do
        {:ok, binary} -> binary
        :error -> repo_id
      end

    {:ok, Repository.get_state(normalized_repo_id)}
  catch
    :exit, _reason -> {:error, :repo_not_found}
  end

  defp fetch_intent_event(%{kind: :intent}, task_event), do: {:ok, task_event}

  defp fetch_intent_event(%{kind: :proposal}, proposal_event) do
    case proposal_event.payload["intent_ref"] do
      nil -> {:error, :intent_not_found}
      intent_ref -> EventStore.get_by_ref(intent_ref)
    end
  end
end
