# WorkersUnite — Distributed Agent Node Architecture

## What Changes From `AGENTS.md`

This version keeps the original WorkersUnite idea intact:

- Git remains the storage layer for code.
- The append-only event log remains the source of truth.
- Agents still collaborate through signed events, not direct RPC between agent processes.

What changes is the runtime topology.

Instead of treating the cluster as a mostly flat collection of symmetric nodes, WorkersUnite is split into:

- a control plane running one or more master/orchestrator nodes
- a worker plane running agent nodes
- a deployment plane responsible for staged rollout, rollback, and repair

The explicit goal is to let WorkersUnite modify and redeploy itself without requiring the entire system to stop.

## Design Position

WorkersUnite may be self-hosting, but it must not be self-destructive.

That means:

- agents may propose changes to WorkersUnite itself
- agents may validate and vote on those changes
- approved changes may be merged into the WorkersUnite repository
- deployment is a separate controlled action
- production activation must be staged and reversible

The control plane must never depend on a single in-memory process for truth. Durable state lives in the event log and database, not in the master node's heap.

## High-Level Architecture

```text
┌──────────────────────────────────────────────────────────────────┐
│                         CONTROL PLANE                           │
│                                                                  │
│  WorkersUnite.Control.Master        schedules work                   │
│  WorkersUnite.Control.NodeManager   tracks node health               │
│  WorkersUnite.Deploy.Orchestrator   rolls out releases               │
│  WorkersUnite.Consensus.Engine      evaluates votes                  │
│  WorkersUnite.EventStore            durable event log                │
│  Phoenix LiveView               dashboard and supervision UI     │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│                          WORKER PLANE                            │
│                                                                  │
│  Worker Node A                                                   │
│    WorkersUnite.Worker                                               │
│    DynamicSupervisor for agents                                  │
│    repo worktree / sandbox / tool runners                        │
│                                                                  │
│  Worker Node B                                                   │
│    WorkersUnite.Worker                                               │
│    DynamicSupervisor for agents                                  │
│    repo worktree / sandbox / tool runners                        │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│                        DEPLOYMENT PLANE                          │
│                                                                  │
│  Release artifacts                                               │
│  version metadata                                                │
│  canary rollout                                                  │
│  rollback targets                                                │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## Core Principles

### 1. Event Log Is Still The Truth

The event log remains authoritative for:

- intents
- proposals
- votes
- merges
- deployments
- node membership
- node failures
- repair attempts

No master process is allowed to be the only place where cluster state exists.

### 2. Control Plane And Worker Plane Are Separate

Worker nodes run agents and execute jobs.

Control nodes:

- decide where work should go
- detect failures
- reassign unfinished work
- coordinate deployment
- record repair activity

Worker nodes should be replaceable. Losing one should degrade capacity, not destroy the system.

### 3. Self-Modification Is Allowed, Self-Activation Is Controlled

WorkersUnite may modify the WorkersUnite repository through normal repo workflows:

- publish an intent
- claim it
- submit a proposal
- collect validation evidence
- reach consensus
- merge

But merge is not deploy.

A merged change to WorkersUnite must go through a release and deployment workflow before it affects running nodes.

### 4. Hot Upgrade Is Supported, But Not The Default

BEAM hot code upgrade is useful for some infrastructure processes, but it is not the safest default for arbitrary agent logic.

WorkersUnite should prefer:

- rolling worker replacement for most releases
- canary deployment before cluster-wide rollout
- blue/green or restart-based deployment for control nodes

Hot upgrade should be reserved for:

- narrowly scoped OTP services
- schema-compatible transitions
- cases where preserving in-memory state is materially valuable

## Node Roles

### Control Node

A control node runs:

- `WorkersUnite.EventStore`
- `WorkersUnite.Consensus.Engine`
- `WorkersUnite.Control.Master`
- `WorkersUnite.Control.NodeManager`
- `WorkersUnite.Deploy.Orchestrator`
- `WorkersUnite.Identity.Vault`
- Phoenix dashboard services

Responsibilities:

- observe node membership and heartbeats
- assign work to worker nodes
- monitor deployment progress
- detect node loss and emit repair events
- decide rollback when staged rollout fails

### Worker Node

A worker node runs:

- `WorkersUnite.Worker`
- `WorkersUnite.Worker.AgentSupervisor`
- `WorkersUnite.Worker.RepositoryRuntime`
- optional local caches and sandboxes
- its own `WorkersUnite.Identity.Vault`

Responsibilities:

- host agent processes
- execute repo operations
- run validations and tests
- report health and workload
- drain and restart on deployment command

### Bootstrap / Recovery Constraint

The system must be able to recover from total loss of running workers using:

- the WorkersUnite repository
- release artifacts
- database state
- event log replay

No worker node may contain unrecoverable system truth.

## Revised Supervision Model

### Control Plane Supervision Tree

```text
WorkersUnite.Application
├── WorkersUnite.Repo
├── WorkersUnite.Identity.Vault
├── WorkersUnite.EventStore
├── {Phoenix.PubSub, name: WorkersUnite.PubSub}
├── WorkersUnite.Control.NodeManager
├── WorkersUnite.Control.Master
├── WorkersUnite.Consensus.Engine
├── WorkersUnite.Deploy.ReleaseStore
├── WorkersUnite.Deploy.Orchestrator
├── WorkersUniteWeb.Telemetry
└── WorkersUniteWeb.Endpoint
```

### Worker Plane Supervision Tree

```text
WorkersUnite.WorkerApplication
├── WorkersUnite.Identity.Vault
├── {Phoenix.PubSub, name: WorkersUnite.PubSub}
├── WorkersUnite.Worker
├── {DynamicSupervisor, name: WorkersUnite.Worker.AgentSupervisor, strategy: :one_for_one}
└── WorkersUnite.Worker.RepositoryRuntime
```

`Horde` may still be used for distributed registry if needed, but the system should not assume fully symmetric placement of all critical processes. Control-plane processes should have explicit ownership and failover behavior.

## New Modules

### `WorkersUnite.Control.Master`

The cluster orchestrator.

State should be reconstructible from durable sources.

Responsibilities:

- assign intents or execution jobs to worker nodes
- requeue work when a worker disappears
- coordinate with deployment orchestration
- prevent new work from being scheduled to draining or unhealthy nodes

Important rule:

`WorkersUnite.Control.Master` is an orchestrator, not a source of truth.

### `WorkersUnite.Control.NodeManager`

Tracks node liveness and capacity.

Responsibilities:

- monitor node up/down events
- maintain node status: `:healthy | :degraded | :draining | :down | :repairing`
- ingest periodic worker heartbeats
- emit node lifecycle events into the event log
- expose current node status to the dashboard and scheduler

Use both:

- BEAM node monitoring
- durable heartbeat leases persisted through events or database records

This avoids making recovery decisions based only on transient cluster signals.

### `WorkersUnite.Deploy.ReleaseStore`

Tracks release metadata.

Each release record should include:

- git SHA
- semantic or monotonic version
- build artifact location
- compatibility metadata
- rollback target
- creation timestamp

### `WorkersUnite.Deploy.Orchestrator`

Coordinates deploy and rollback.

Responsibilities:

- accept deploy requests tied to an approved release
- canary on one or more worker nodes
- verify health after rollout
- continue, pause, or rollback based on outcome
- update control nodes last

The deploy orchestrator must support partial failure without losing track of rollout state.

### `WorkersUnite.Worker`

Represents a worker node runtime.

Responsibilities:

- send periodic heartbeats
- advertise capacity and active workload
- enter drain mode on command
- stop accepting new assignments during drain
- terminate agents cleanly during redeploy

## Self-Hosting Workflow

WorkersUnite may modify WorkersUnite by using the same protocol it uses for other repositories.

### Phase 1: Propose

An agent publishes an intent against the WorkersUnite repo:

- bug fix
- feature addition
- deployment logic update
- policy change

### Phase 2: Implement And Validate

Agents submit proposals containing:

- commit range
- proof bundle
- test results
- compatibility evidence

For self-modifying changes, proof should additionally include:

- migration safety notes
- rollout strategy
- rollback target
- protocol/schema compatibility statement

### Phase 3: Consensus

Changes to WorkersUnite itself should use stricter policy than ordinary repository work.

Recommended examples:

- minimum more reviewers
- mandatory reviewer diversity by agent kind
- no single agent allowed to both author and cast decisive approval
- deploy capability separated from code authoring capability

### Phase 4: Merge

If consensus passes, the proposal is merged into the WorkersUnite repository.

This does not change running nodes yet.

### Phase 5: Build Release

A release is created from the merged commit:

- immutable git SHA
- release artifact
- metadata recorded in `ReleaseStore`

### Phase 6: Deploy

Deployment proceeds in stages:

1. canary worker nodes
2. wider worker rollout
3. control-plane rollout

If canary validation fails, rollback happens before wider activation.

## Why Merge And Deploy Must Be Separate

If merged code were immediately activated:

- a bad merge could destroy the control plane
- rollback logic might not remain functional
- a malicious or buggy policy change could weaken future governance

Separating merge from deploy gives you a hard safety boundary.

## Deployment Strategy

### Default Strategy: Rolling Replacement

Use restart-based rollout for most releases.

Per worker node:

1. mark node `:draining`
2. stop assigning new work
3. wait for running jobs to finish or time out
4. record unfinished work for reassignment
5. deploy new release
6. restart worker node
7. verify heartbeat and version report
8. mark node `:healthy`

This is safer than generic hot code swapping for agent-heavy workloads.

### Optional Strategy: Hot Code Upgrade

Allowed only if:

- release metadata marks it as hot-upgrade compatible
- affected modules implement proper upgrade handling
- event schemas are backward compatible
- orchestrator has a tested rollback path

Use this for stable OTP services, not by default for agent runtimes that orchestrate external tools.

### Control Plane Rollout

Control plane should be updated last.

Safer patterns:

- active/passive control nodes
- blue/green replacement
- rolling restart with leader handoff

Least safe pattern:

- in-place hot upgrade of the only active master node

Avoid making that your first implementation.

## Failure Detection And Repair

### Failure Model

WorkersUnite should distinguish:

- agent process failure
- worker runtime failure
- BEAM node disconnection
- host failure
- deployment-induced failure

Not every failure is repaired the same way.

### Detection

Detection inputs:

- `:net_kernel.monitor_nodes/2`
- worker heartbeats
- deployment health checks
- absence of expected progress on assigned work

### Repair Policy

When a worker node is considered down:

1. emit `:node_down_detected`
2. mark the node unavailable for scheduling
3. reassign unfinished work
4. emit `:node_repair_requested`
5. ask external infrastructure to restart or replace the worker
6. await `:node_joined` and fresh heartbeat

Important constraint:

WorkersUnite can coordinate repair, but actual machine or container resurrection is better handled by an external runtime such as systemd, Nomad, Kubernetes, or similar infrastructure.

Application-level “repair” should mean:

- detect failure
- preserve workflow continuity
- restore desired topology when infrastructure cooperates

It should not assume a broken VM can heal itself from inside the broken VM.

## Event Model Additions

Add these event kinds.

### Node Lifecycle

- `:node_joined`
- `:node_heartbeat`
- `:node_draining`
- `:node_down_detected`
- `:node_repair_requested`
- `:node_repair_succeeded`
- `:node_repair_failed`
- `:node_removed`

### Deployment

- `:release_created`
- `:deploy_requested`
- `:deploy_started`
- `:deploy_canary_succeeded`
- `:deploy_canary_failed`
- `:deploy_progressed`
- `:deploy_succeeded`
- `:deploy_failed`
- `:rollback_requested`
- `:rollback_succeeded`
- `:rollback_failed`

### Work Recovery

- `:work_assigned`
- `:work_requeued`
- `:work_reassigned`
- `:work_abandoned`

## Schema Additions

### `WorkersUnite.Schema.NodeHeartbeat`

Fields:

- `node_id`
- `role`
- `status`
- `version`
- `release_sha`
- `capacity`
- `active_work_count`
- `reported_at`

### `WorkersUnite.Schema.Release`

Fields:

- `repo_ref`
- `commit_sha`
- `version`
- `artifact_ref`
- `compatibility`
- `hot_upgrade?`
- `rollback_to`
- `created_at`

### `WorkersUnite.Schema.DeployRequest`

Fields:

- `release_ref`
- `target`
- `strategy`
- `initiator`
- `reason`
- `created_at`

### `WorkersUnite.Schema.Rollback`

Fields:

- `failed_release_ref`
- `rollback_release_ref`
- `scope`
- `reason`
- `created_at`

## Capability Model Changes

Self-hosting requires more granular permissions.

Recommended capabilities:

- `:propose_code`
- `:review_code`
- `:merge_code`
- `:create_release`
- `:deploy_worker`
- `:deploy_control`
- `:rollback_release`
- `:change_policy`
- `:repair_node`

Strong recommendation:

- separate `:merge_code` from `:deploy_worker`
- separate `:deploy_worker` from `:deploy_control`
- require stronger authority for policy changes and control-plane deployment

The system should not let one routine coding agent unilaterally modify and activate the runtime that governs it.

## Consensus Rules For Self-Modifying Changes

For changes targeting the WorkersUnite repository itself:

- require more reviewers than normal repo work
- require at least one reviewer that did not participate in authorship
- require passing deployability checks
- require explicit rollback metadata
- require additive schema compatibility first

For changes affecting:

- deployment logic
- consensus policy
- capability enforcement
- event validation

Use an even stronger policy than ordinary self-hosted changes.

These are governance-critical modules.

## Compatibility Rules

To allow zero-downtime or low-downtime rollout:

- event schemas must evolve additively first
- old nodes must ignore unknown additive fields when possible
- new nodes must understand old events
- protocol-breaking changes require a migration plan and staged activation

Do not deploy cluster-splitting changes casually.

## Suggested Implementation Order

### Phase 1

- add node lifecycle events
- implement `NodeManager`
- implement worker heartbeats
- make work assignments durable enough to be requeued

### Phase 2

- add `ReleaseStore`
- add `Deploy.Orchestrator`
- implement rolling worker deploy
- implement drain and reassignment

### Phase 3

- allow WorkersUnite repo intents/proposals/merges
- require stronger consensus for self-modification
- create release artifacts from approved WorkersUnite merges

### Phase 4

- add canary deployment
- add rollback workflow
- add control-plane staged upgrades

### Phase 5

- add carefully constrained hot upgrade support for infrastructure modules

Hot code upgrade should come late, not first.

## Final Position

Yes, the system can be designed so agents modify WorkersUnite code through commits and merges, then cause the system to redeploy itself.

But the sound version of that design is:

- self-hosting, not self-trusting
- orchestrated, not implicit
- staged, not immediate
- recoverable, not optimistic

WorkersUnite should be able to survive:

- a worker node disappearing
- a failed canary deploy
- a bad release that must be rolled back
- a control-plane restart

If it cannot survive those, it is not ready to self-update.
