defmodule WorkersUnite.Control.MasterTest do
  use WorkersUnite.DataCase

  alias WorkersUnite.Control.{Job, Master, Workflow}
  alias WorkersUnite.Repo

  test "submits a durable job and queues it" do
    assert {:ok, job} =
             Master.submit_job(%{
               kind: "implement_change",
               payload: %{"intent_ref" => "intent-123"}
             })

    assert job.status == "queued"
    assert job.kind == "implement_change"

    persisted_job = Repo.get!(Job, job.id)
    assert persisted_job.status == "queued"
    assert job.id in WorkersUnite.Control.JobScheduler.queued_jobs()
  end

  test "starts a workflow and marks it running" do
    assert {:ok, workflow} =
             Master.start_workflow(%{
               kind: "intent_to_proposal",
               subject_type: "repo",
               context: %{"repo_name" => "workers_unite"}
             })

    assert workflow.status == "running"
    assert workflow.kind == "intent_to_proposal"

    persisted_workflow = Repo.get!(Workflow, workflow.id)
    assert persisted_workflow.status == "running"
    assert workflow.id in WorkersUnite.Control.WorkflowEngine.active_workflows()
  end
end
