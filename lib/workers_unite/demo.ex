defmodule WorkersUnite.Demo do
  @moduledoc """
  Demonstrates the WorkersUnite collaboration workflow:
  1. Create a repository
  2. Spawn agents (coder, reviewer, orchestrator)
  3. Orchestrator publishes an intent
  4. Coder claims it and submits a proposal
  5. Reviewer and orchestrator vote to accept
  6. Consensus is reached and merge executes
  """

  alias WorkersUnite.{Agent, Event, EventStore, Git, Identity, Repository}
  alias WorkersUnite.Agent.Workspace

  def run do
    unless Application.get_env(:workers_unite, :allow_demo, false) or Mix.env() in [:dev, :test] do
      raise "Demo.run() is not allowed in production — set :allow_demo to true to override"
    end

    IO.puts("\n=== WorkersUnite Demo ===\n")

    # 1. Create a repository
    owner = Identity.generate()
    {:ok, _repo_pid, repo_id} = Repository.create("workers-unite-demo", owner)
    repo_hex = Base.encode16(repo_id, case: :lower)
    scope = {:repo, repo_id}
    IO.puts("[1/6] Repository created: #{repo_hex}")
    Process.sleep(200)

    # 2. Spawn 3 agents
    {:ok, _coder_pid, coder_pk} = Agent.spawn(:coder, model: "claude-sonnet-4")
    {:ok, _reviewer_pid, reviewer_pk} = Agent.spawn(:reviewer, model: "claude-sonnet-4")

    {:ok, _orchestrator_pid, orchestrator_pk} =
      Agent.spawn(:orchestrator, model: "claude-sonnet-4")

    IO.puts("[2/6] Agents spawned:")
    IO.puts("  Coder:        #{Identity.fingerprint(coder_pk)}")
    IO.puts("  Reviewer:     #{Identity.fingerprint(reviewer_pk)}")
    IO.puts("  Orchestrator: #{Identity.fingerprint(orchestrator_pk)}")
    Process.sleep(200)

    # 3. Orchestrator publishes an intent
    # Use a fresh keypair for signing intent events (agent keypairs are internal)
    orch_kp = Identity.generate()

    {:ok, intent_event} =
      Repository.publish_intent(repo_id, orch_kp, %{
        "title" => "Add federation protocol",
        "description" => "Implement node-to-node event sync via gossip protocol",
        "priority" => 0.8,
        "tags" => ["federation", "networking"]
      })

    intent_ref = Event.ref(intent_event)
    IO.puts("[3/6] Intent published: #{intent_ref}")
    Process.sleep(200)

    # 4. Coder claims the intent and submits a proposal
    {:ok, _claim_ref} = Agent.claim_intent(coder_pk, repo_id, intent_ref, scope)
    IO.puts("[4/6] Coder claimed intent")
    Process.sleep(200)

    {:ok, session_root} = Workspace.create_session_root()

    artifact_data =
      try do
        {:ok, checkout} =
          Workspace.prepare_task_checkout(session_root, repo_id, coder_pk, intent_ref)

        feature_file = Path.join(checkout.repo_path, "FEDERATION.md")
        File.write!(feature_file, "# Federation protocol\n\nInitial protocol sketch.\n")

        {:ok, _commit_sha} = Git.commit_all(checkout.repo_path, "Add federation protocol sketch")
        :ok = Git.push_branch(checkout.repo_path, checkout.branch_name)
        {:ok, head_sha} = Git.rev_parse(checkout.repo_path, "HEAD")

        %{
          "affected_files" => ["FEDERATION.md"],
          "artifact" => %{
            "type" => "branch",
            "name" => checkout.branch_name,
            "head" => head_sha
          }
        }
      after
        Workspace.cleanup(session_root)
      end

    {:ok, proposal_ref} =
      Agent.submit_proposal(
        coder_pk,
        %{
          "intent_ref" => intent_ref,
          "repo_id" => repo_hex,
          "summary" => "Add the initial federation protocol flow",
          "confidence" => 0.85,
          "affected_files" => artifact_data["affected_files"],
          "artifact" => artifact_data["artifact"]
        },
        scope
      )

    IO.puts("[5/6] Coder submitted proposal: #{proposal_ref}")
    Process.sleep(200)

    # 5. Reviewer and orchestrator vote to accept
    {:ok, _} = Agent.vote(reviewer_pk, proposal_ref, :accept, scope: scope, confidence: 0.9)
    {:ok, _} = Agent.vote(orchestrator_pk, proposal_ref, :accept, scope: scope, confidence: 0.85)

    IO.puts("[6/6] Votes cast — awaiting consensus...")
    Process.sleep(500)

    # Check results
    consensus_events = EventStore.by_kind(:consensus_reached)
    merge_events = EventStore.by_kind(:merge_executed)

    IO.puts("\n=== Results ===")
    IO.puts("Total events:       #{EventStore.count()}")
    IO.puts("Consensus reached:  #{length(consensus_events)}")
    IO.puts("Merges executed:    #{length(merge_events)}")

    agents = Agent.list_local()
    IO.puts("Active agents:      #{length(agents)}")

    repos = Repository.list_local()
    IO.puts("Active repos:       #{length(repos)}")

    IO.puts("\n=== Demo Complete ===\n")
    :ok
  end
end
