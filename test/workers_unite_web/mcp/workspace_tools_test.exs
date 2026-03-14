defmodule WorkersUniteWeb.MCP.WorkspaceToolsTest do
  use WorkersUnite.DataCase

  alias WorkersUnite.{Agent, Git, Identity, Repository, Event}
  alias WorkersUnite.Agent.Workspace
  alias WorkersUniteWeb.MCP.Tools.{PrepareWorkspace, PublishArtifact}

  test "prepare workspace and publish artifact produce a branch artifact" do
    {:ok, _coder_pid, coder_id} = Agent.spawn(:coder)
    owner = Identity.generate()
    {:ok, _repo_pid, repo_id} = Repository.create("tool-repo", owner)
    repo_hex = Base.encode16(repo_id, case: :lower)

    Process.sleep(100)

    {:ok, intent_event} = Repository.publish_intent(repo_id, owner, %{"title" => "Tool task"})
    intent_ref = Event.ref(intent_event)
    assert {:ok, _claim_ref} = Agent.claim_intent(coder_id, repo_id, intent_ref)

    {:ok, session_root} = Workspace.create_session_root()
    context = %{agent_id: coder_id, working_dir: session_root}

    try do
      assert {:ok, prepared} = PrepareWorkspace.call(%{"repo_id" => repo_hex}, context)
      assert prepared.branch_name =~ "agent/"
      File.write!(Path.join(prepared.repo_path, "TOOL_TEST.md"), "tool\n")

      assert {:ok, artifact_result} =
               PublishArtifact.call(
                 %{"repo_id" => repo_hex, "commit_message" => "Add tool test file"},
                 context
               )

      assert artifact_result.artifact.type == "branch"
      assert "TOOL_TEST.md" in artifact_result.affected_files

      assert {:ok, pushed_head} =
               Git.rev_parse(
                 Repository.get_state(repo_id).path,
                 "refs/heads/#{artifact_result.branch_name}"
               )

      assert pushed_head == artifact_result.head_sha
    after
      Workspace.cleanup(session_root)
    end
  end
end
