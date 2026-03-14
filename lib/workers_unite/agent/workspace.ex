defmodule WorkersUnite.Agent.Workspace do
  @moduledoc """
  Manages per-session workspace directories and repo-local checkouts.
  """

  require Logger

  alias WorkersUnite.{Git, Identity, Repository}

  def create_session_root do
    base =
      Application.get_env(
        :workers_unite,
        :session_workspace_base,
        Path.join(System.tmp_dir!(), "workers-unite-sessions")
      )

    session_root = Path.join(base, "session-#{System.unique_integer([:positive, :monotonic])}")
    File.mkdir_p!(Path.join(session_root, "repos"))
    {:ok, session_root}
  end

  def cleanup(session_root) do
    File.rm_rf(session_root)
    :ok
  end

  def ensure_repo_checkout(session_root, repo_id) do
    with {:ok, repo} <- fetch_repo(repo_id) do
      repo_path = Path.join([session_root, "repos", Base.encode16(repo_id, case: :lower)])

      cond do
        File.dir?(repo_path) ->
          with :ok <- Git.fetch_all(repo_path) do
            {:ok, repo_path}
          end

        true ->
          File.mkdir_p!(Path.dirname(repo_path))

          with :ok <- Git.clone(repo.path, repo_path) do
            {:ok, repo_path}
          end
      end
    end
  end

  def prepare_task_checkout(session_root, repo_id, agent_id, intent_ref) do
    branch_name = task_branch_name(agent_id, intent_ref)
    fingerprint = Identity.fingerprint(agent_id)

    with {:ok, repo_path} <- ensure_repo_checkout(session_root, repo_id),
         :ok <-
           Git.configure_identity(
             repo_path,
             "WorkersUnite #{fingerprint}",
             "#{fingerprint}@workers_unite.local"
           ),
         :ok <- Git.checkout_branch(repo_path, branch_name, "origin/#{Git.default_branch()}"),
         {:ok, base_sha} <- Git.rev_parse(repo_path, "HEAD") do
      {:ok,
       %{
         repo_path: repo_path,
         branch_name: branch_name,
         base_branch: Git.default_branch(),
         base_sha: base_sha,
         head_sha: base_sha
       }}
    end
  end

  def checkout_task_branch(session_root, repo_id, agent_id, intent_ref) do
    branch_name = task_branch_name(agent_id, intent_ref)

    with {:ok, repo_path} <- ensure_repo_checkout(session_root, repo_id),
         :ok <- Git.checkout_existing_branch(repo_path, branch_name),
         {:ok, head_sha} <- Git.rev_parse(repo_path, "HEAD") do
      {:ok, %{repo_path: repo_path, branch_name: branch_name, head_sha: head_sha}}
    end
  end

  def task_branch_name(agent_id, intent_ref) do
    "agent/#{Identity.fingerprint(agent_id)}/#{String.slice(intent_ref, 0, 12)}"
  end

  defp fetch_repo(repo_id) do
    {:ok, Repository.get_state(repo_id)}
  catch
    :exit, _reason ->
      Logger.warning("Workspace: repo not found for checkout")
      {:error, :repo_not_found}
  end
end
