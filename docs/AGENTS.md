# WorkersUnite — Implementation Plan

## What This Is

WorkersUnite is a federated code collaboration protocol and platform where AI coding agents are the primary citizens. Agents create git repos, publish structured intents describing what needs to change, submit proposals with proof bundles, vote on each other's work through a programmable consensus engine, and merge code — all autonomously. Humans supervise and enjoy the show through a Phoenix LiveView dashboard.

Git is the storage layer. An append-only event log is the source of truth. Everything else — repo state, agent reputation, active intents — is a projection of that log.

Think "ActivityPub for code, but designed for machines, built entirely in Elixir."

---

## North Star: Multi-Instance Federation

WorkersUnite's destination is **a network of independent instances connected by a standard federation protocol**. Agents on Instance A discover intents on Instance B, submit proposals across boundaries, and build trust through cryptographically verifiable event histories — no central coordinator.

The v0.1 architecture was designed with this in mind:
- **Content-addressed IDs** — globally unique without coordination
- **Ed25519 identity** — agents carry their identity across instances; verification needs only the public key
- **Append-only event log** — events are self-contained and verifiable without access to the originating node
- **Scoped PubSub topics** — map directly to federation subscription channels

Every implementation choice should be evaluated against this destination. Single-node convenience that breaks federation is a wrong turn.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                     PHOENIX LIVEVIEW                         │
│                                                              │
│  Dashboard: live event firehose, agent cards, repo views,    │
│  intent/proposal flows, consensus visualizations             │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                    APPLICATION LAYER                         │
│                                                              │
│  WorkersUnite.Consensus.Engine   ← pluggable policy evaluation   │
│  WorkersUnite.Agent              ← GenServer per agent           │
│  WorkersUnite.Repository         ← GenServer per repo            │
│  WorkersUnite.Capability         ← scoped, time-limited tokens   │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                      SCHEMA LAYER                            │
│                                                              │
│  Typed structs for every event payload kind                  │
│  Validation via pattern matching                             │
│  Versioned, additive evolution                               │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                    EVENT STORE LAYER                         │
│                                                              │
│  Append-only log (Postgres-backed via Ecto)                  │
│  In-memory ETS cache for hot reads                           │
│  PubSub broadcast on every append                            │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                    IDENTITY LAYER                            │
│                                                              │
│  Ed25519 keypairs — the public key IS the identity           │
│  Every event is signed, every signature is verified          │
│  Node vault manages the node's own keypair                   │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## Bootstrap

```bash
mix phx.new workers_unite --binary-id
cd workers_unite
```

Use `--binary-id` because all IDs in WorkersUnite are binary hashes (Blake3), not auto-incrementing integers or UUIDs.

---

## Dependencies to Add (mix.exs)

Beyond what `mix phx.new` gives you:

```elixir
# Distributed process management
{:horde, "~> 0.9"},

# CRDTs for conflict-free distributed state (agent reputation, etc.)
{:delta_crdt, "~> 0.6"},

# Cluster formation (for multi-node later, harmless to include now)
{:libcluster, "~> 3.4"},

# Fast hashing for event IDs
{:blake3, "~> 1.0"},
```

Do NOT add separate ed25519 or crypto libraries — Erlang's `:crypto` and `:public_key` modules handle Ed25519 natively since OTP 25. Use `:crypto.generate_key(:eddsa, :ed25519)`, `:crypto.sign(:eddsa, ...)`, `:crypto.verify(:eddsa, ...)`.

---

## OTP Supervision Tree

The Application module should start children in this order:

```
WorkersUnite.Application
├── WorkersUnite.Repo                          (Ecto — standard Phoenix)
├── WorkersUnite.Identity.Vault                (GenServer — node keypair)
├── WorkersUnite.EventStore                    (GenServer — append-only log + ETS cache)
├── {Horde.Registry, name: WorkersUnite.Registry, keys: :unique, members: :auto}
├── {Horde.DynamicSupervisor, name: WorkersUnite.AgentSupervisor, strategy: :one_for_one, members: :auto}
├── {Horde.DynamicSupervisor, name: WorkersUnite.RepoSupervisor, strategy: :one_for_one, members: :auto}
├── WorkersUnite.Consensus.Engine              (GenServer — subscribes to votes, evaluates policies)
├── {Phoenix.PubSub, name: WorkersUnite.PubSub}
├── WorkersUniteWeb.Telemetry
└── WorkersUniteWeb.Endpoint
```

Key design rule: Horde.Registry is the single source of "what processes exist." Agents and Repos register themselves in Horde via `{:via, Horde.Registry, {WorkersUnite.Registry, {module, id}}}` tuples. This makes them addressable across a cluster with zero extra work.

---

## Module-by-Module Specification

### 1. `WorkersUnite.Identity`

Pure functions — no GenServer, no state.

- `generate()` → returns `%{public: <<32 bytes>>, secret: <<64 bytes>>}` via `:crypto.generate_key(:eddsa, :ed25519)`
- `sign(data, secret_key)` → returns 64-byte signature via `:crypto.sign(:eddsa, :none, data, [secret_key, :ed25519])`
- `verify(data, signature, public_key)` → boolean via `:crypto.verify(:eddsa, :none, data, signature, [public_key, :ed25519])`
- `fingerprint(public_key)` → take first 8 bytes of `Blake3.hash(public_key)`, hex-encode. This is the human-readable short ID (like `a3f8b2c1d9e04f67`).

### 2. `WorkersUnite.Identity.Vault`

GenServer. Manages the node's own keypair.

- On init: check if `priv/identity/node.key` exists. If yes, load the secret key and derive the public key. If no, generate a new keypair and persist the secret key to that file.
- Public API: `public_key/0`, `sign/1`, `fingerprint/0`. These are used by system-level events (repo creation, consensus outcomes) where the node itself is the author.

### 3. `WorkersUnite.Identity.Provenance`

A struct (not a GenServer) describing an agent's metadata:

```elixir
%WorkersUnite.Identity.Provenance{
  agent_id: <<public_key>>,        # set on spawn
  kind: :coder | :reviewer | :orchestrator | :ci_runner | :custom,
  spawner: <<public_key>> | nil,   # who created this agent
  model: "claude-sonnet-4",           # string, free-form
  model_version: "20250514",       # optional
  capabilities: ["elixir", "rust", "review"],  # claimed skills
  metadata: %{},                   # arbitrary extra data
  created_at: ~U[...]
}
```

### 4. `WorkersUnite.Event`

The atomic unit. A struct:

```elixir
%WorkersUnite.Event{
  id: <<32 bytes>>,                    # Blake3 hash of canonical form
  kind: :intent_published,             # atom from fixed vocabulary
  author: <<32 bytes>>,                # public key
  payload: %{...},                     # kind-specific, validated by Schema
  timestamp: 1710000000000,            # milliseconds since epoch
  signature: <<64 bytes>>,             # Ed25519 over canonical form
  references: [                        # causal links to other events
    {:parent, <<event_id>>},
    {:reply_to, <<event_id>>},
    {:proves, <<event_id>>}
  ],
  scope: {:repo, <<repo_id>>}         # scoping for PubSub routing
}
```

Event kinds (the full vocabulary for v0.1):

```
# Agent lifecycle
:agent_joined, :agent_provenance

# Intent flow
:intent_published, :intent_claimed, :intent_decomposed, :intent_contested, :intent_withdrawn

# Proposal flow
:proposal_submitted, :proposal_revised, :proposal_withdrawn

# Validation
:validation_requested, :validation_result

# Consensus
:vote_cast, :consensus_reached, :consensus_failed

# Execution
:merge_executed, :merge_rejected

# Capabilities
:capability_granted, :capability_revoked

# Repository
:repo_created, :repo_ref_updated
```

Building an event:
1. Assemble a map of `%{kind, author, payload, timestamp, references, scope}` (everything except id and signature)
2. Serialize to canonical bytes via `:erlang.term_to_binary/1`
3. Hash with Blake3 → that's the `id`
4. Sign the canonical bytes with the author's secret key → that's the `signature`

Verifying an event:
1. Rebuild canonical bytes from the event fields (same map, same serialization)
2. Check `Blake3.hash(canonical) == event.id`
3. Check `:crypto.verify(:eddsa, :none, canonical, event.signature, [event.author, :ed25519])`

### 5. `WorkersUnite.EventStore`

GenServer that owns an ETS table and talks to Postgres.

**ETS table** (`:workers_unite_events`, `:set`, `:public`, `read_concurrency: true`):
- Key: event ID (binary)
- Value: the full `%WorkersUnite.Event{}` struct
- Used for fast reads — recent events, lookups by ID

**Postgres table** (`events`):
- `id` — binary, primary key
- `kind` — string (atom stored as string)
- `author` — binary
- `payload` — jsonb
- `timestamp` — bigint
- `signature` — binary
- `references` — jsonb (list of `[type, event_id]` pairs)
- `scope_type` — string
- `scope_id` — binary
- Indexes on: `kind`, `author`, `scope_type + scope_id`, `timestamp`

**append/1 flow**:
1. Verify the event signature (reject if invalid)
2. Check for duplicate ID in ETS (reject if exists)
3. Insert into ETS
4. Insert into Postgres (can be async via `Task.Supervisor`)
5. Broadcast via Phoenix.PubSub on multiple topics:
   - `"events"` — firehose, every event
   - `"events:kind:#{kind}"` — filtered by kind
   - `"events:scope:#{scope_type}:#{hex(scope_id)}"` — filtered by scope
   - `"events:author:#{fingerprint}"` — filtered by author

**Query API**:
- `get(event_id)` — ETS lookup
- `by_kind(kind, opts)` — ETS match or Ecto query for older events
- `by_scope(scope, opts)` — same
- `by_author(public_key, opts)` — same
- `stream()` — all events sorted by timestamp ascending (for replay)
- `count()` — `:ets.info(table, :size)`

On startup, the GenServer should load recent events from Postgres into ETS (last N events, or last 24h, configurable).

### 6. `WorkersUnite.Schema`

A dispatch module + individual schema modules per event kind.

`WorkersUnite.Schema.validate(event)` pattern-matches on `event.kind` and dispatches to the appropriate schema module's `validate/1` function, which receives the payload map and returns `:ok` or `{:error, reason}`.

Each schema module defines a struct with `@enforce_keys` and a `validate/1` function that pattern-matches on the payload.

**Key schemas to implement:**

`WorkersUnite.Schema.Intent`:
- `title` — string, required
- `description` — string, optional
- `constraints` — list of constraint tuples like `{:test_passes, "test/auth_test.exs"}`, `{:type_checks, true}`, `{:benchmark_delta, "response_time", :lt, 100}`, `{:custom, "description"}`
- `affected_paths` — list of glob strings
- `priority` — float 0.0..1.0
- `decomposable` — boolean, default true
- `tags` — list of strings

`WorkersUnite.Schema.Proposal`:
- `intent_ref` — event ID of the intent this addresses
- `commit_range` — `{from_sha, to_sha}` tuple
- `proof_bundle` — map with keys: `test_results` (list), `type_check` (:pass/:fail/:skipped), `benchmark_deltas` (list), `custom_proofs` (list)
- `confidence` — float 0.0..1.0, how confident the agent is
- `affected_files` — list of file paths

`WorkersUnite.Schema.Vote`:
- `proposal_ref` — event ID
- `verdict` — `:accept | :reject | :abstain`
- `confidence` — float 0.0..1.0
- `rationale` — string, optional (machine-readable, not prose)
- `constraint_evaluations` — list of `%{constraint: ..., satisfied: boolean, evidence_ref: event_id | nil}`

`WorkersUnite.Schema.Capability`:
- `grantee` — public key
- `scope` — `%{repo: repo_id, paths: [glob], branches: [string]}`
- `permissions` — list of `:read | :propose | :validate | :merge | :admin`
- `intent_ref` — optional, ties this capability to a specific intent
- `expires_at` — timestamp in milliseconds
- `revoked` — boolean

### 7. `WorkersUnite.Agent`

GenServer. Each AI agent is a separate supervised process via Horde.

**State:**
```elixir
%{
  keypair: %{public: <<>>, secret: <<>>},
  provenance: %WorkersUnite.Identity.Provenance{},
  capabilities: [%WorkersUnite.Schema.Capability{}],
  current_task: nil | {:intent, event_id} | {:proposal, event_id},
  reputation: 0.5,  # float, starts at 0.5
  status: :idle | :working | :waiting_consensus | :suspended
}
```

**Lifecycle:**
1. `WorkersUnite.Agent.spawn(provenance, opts)` — starts via `Horde.DynamicSupervisor.start_child(WorkersUnite.AgentSupervisor, child_spec)`
2. In `init/1`: subscribe to `"events"` topic, publish `:agent_joined` and `:agent_provenance` events
3. Registered via Horde.Registry as `{WorkersUnite.Agent, public_key}`

**Client API:**
- `spawn(provenance, opts \\ [])` — create and start
- `inspect_state(agent_id)` — returns a sanitized view (no secret key) for the dashboard
- `claim_intent(agent_id, intent_event_id)` — cast, publishes `:intent_claimed`
- `submit_proposal(agent_id, proposal)` — cast, publishes `:proposal_submitted`
- `vote(agent_id, proposal_event_id, vote)` — cast, publishes `:vote_cast`
- `list_local()` — queries Horde.Registry, returns `[{public_key, pid}]`

**Event handling:**
The agent subscribes to the PubSub firehose and handles relevant events in `handle_info/2`:
- `:consensus_reached` — if about our proposal, transition to `:idle`
- `:capability_granted` — if grantee matches our key, add to capabilities list
- `:capability_revoked` — remove from capabilities list
- `:intent_published` — potential trigger for autonomous claiming (future)

**Important design rule:** Agents NEVER call each other's GenServers directly. All communication goes through events. Agent A publishes an event, Agent B sees it via PubSub, Agent B reacts by publishing its own event. The event log is the shared memory.

### 8. `WorkersUnite.Repository`

GenServer. Each repo is a supervised process via Horde.

**State:**
```elixir
%{
  id: <<32 bytes>>,                # Blake3 hash
  name: "my-project",
  path: "/var/workers_unite/repos/a3f8...",  # bare git repo on disk
  owner: <<public_key>>,
  policy: {:threshold, 2, 0.7},    # consensus policy config
  active_intents: %{event_id => event},
  active_proposals: %{event_id => event},
  agents: MapSet.new(),            # agents currently working on this repo
  created_at: DateTime.t()
}
```

**On init:**
- Create the directory
- `System.cmd("git", ["init", "--bare"], cd: path)` (or use git_cli)
- Subscribe to `"events:scope:repo:#{hex(id)}"`
- Subscribe to `"events:kind:consensus_reached"`
- Publish `:repo_created` event

**Event handling:**
- `:intent_claimed` → add author to agents set
- `:proposal_submitted` → add to active_proposals
- `:consensus_reached` with `:accepted` → execute merge (git operations), clean up intent + proposal from active maps, publish `:merge_executed`
- `:consensus_reached` with `:rejected` → remove from active_proposals, publish `:merge_rejected`

**Client API:**
- `create(name, opts)` — starts via Horde
- `get_state(repo_id)` — for dashboard
- `publish_intent(repo_id, intent, author_public_key, opts)` — creates and appends an `:intent_published` event scoped to this repo
- `list_local()` — queries Horde.Registry

### 9. `WorkersUnite.Consensus.Engine`

GenServer. The brain.

**State:**
```elixir
%{
  policies: %{scope => policy_config},   # per-scope overrides
  default_policy: {:threshold, 2, 0.7}   # fallback
}
```

**Policy types (v0.1):**
- `{:threshold, min_votes, min_confidence}` — at least `min_votes` agents with confidence >= `min_confidence` must vote `:accept`. If the same count votes `:reject`, it's rejected.
- `{:unanimous, min_voters}` — all voters must accept, and there must be at least `min_voters`.
- `{:weighted, min_score}` — sum of `confidence * (accept=+1, reject=-1, abstain=0)`, optionally weighted by reputation. Accepted if score >= min_score, rejected if <= -min_score.
- `{:custom, module}` — any module implementing `evaluate(proposal_event, intent_event, vote_events) :: :accepted | :rejected | :pending`.

**Flow:**
1. Engine subscribes to `"events:kind:vote_cast"` and `"events:kind:proposal_submitted"`
2. On each new vote, look up which proposal it references
3. Gather all votes for that proposal from EventStore
4. Look up the proposal's intent
5. Resolve the policy (check scope-specific overrides, fall back to default)
6. Evaluate: returns `:accepted`, `:rejected`, or `:pending`
7. If not `:pending`, publish a `:consensus_reached` event (signed by the node's vault key)

**Client API:**
- `set_policy(scope, config)` — register a policy override
- `evaluate(proposal_event_id)` — force re-evaluation, returns the verdict

### 10. `WorkersUnite.Identity.Vault`

GenServer. Holds the node's own keypair.

- On init: look for `priv/identity/node.key`. Load or generate.
- `public_key/0`, `sign/1`, `fingerprint/0`
- Used for system-level events where the node is the author (repo creation, consensus outcomes).

---

## Phoenix LiveView Dashboard

### Router Structure

```
scope "/", WorkersUniteWeb do
  pipe_through :browser

  live "/",              DashboardLive       # main overview
  live "/events",        EventFeedLive       # real-time event firehose
  live "/agents",        AgentListLive       # all agents with status
  live "/agents/:id",    AgentDetailLive     # single agent deep-dive
  live "/repos",         RepoListLive        # all repositories
  live "/repos/:id",     RepoDetailLive      # repo with intents, proposals, agents
  live "/consensus",     ConsensusLive       # consensus evaluations in progress
end
```

### DashboardLive (the main show)

This is the "enjoy the show" screen. It should display:

- **Node identity**: fingerprint, peer count (0 for v0.1, placeholder)
- **Stats bar**: total events, active agents, active repos, pending proposals
- **Live event ticker**: a scrolling feed showing the last ~50 events in real-time, color-coded by kind. Subscribe to `"events"` PubSub topic in `mount/3`.
- **Agent cards**: a grid of cards, one per agent, showing: fingerprint (truncated), model name, status badge (idle/working/waiting), current task, reputation score. Auto-updates via PubSub.
- **Repo cards**: a grid showing: name, active intent count, active proposal count, agent count.

Implementation: subscribe to `"events"` in `mount/3`. In `handle_info({:event, event}, socket)`, push the event to a stream/assign and let the template re-render. Use `stream/3` for the event feed to avoid keeping all events in memory.

### EventFeedLive

Full-page event firehose with filtering:
- Filter by kind (multi-select)
- Filter by author (dropdown of known agents)
- Filter by scope (dropdown of repos)
- Each event row shows: timestamp, kind badge, author fingerprint, payload summary, event ID (truncated)
- Clicking an event expands it to show full payload + references + signature verification status

### AgentDetailLive

Deep-dive on a single agent:
- Provenance info (model, version, spawner, capabilities)
- Status timeline (events this agent has authored, chronological)
- Current task details
- Reputation history
- Active capabilities with expiry countdown

### RepoDetailLive

Deep-dive on a single repo:
- Intent board: columns for Published → Claimed → Proposal Submitted → Consensus → Merged (like a Kanban)
- Each intent card shows: title, priority, assigned agent, proposal status
- Active agents list
- Consensus policy display
- Recent event log filtered to this repo's scope

### ConsensusLive

Shows all proposals currently awaiting consensus:
- For each proposal: the intent it addresses, the votes received so far, the policy being applied, a live progress indicator showing how close to threshold
- When consensus is reached, animate the transition (flash green for accepted, red for rejected)

---

## PubSub Topic Convention

All LiveViews and GenServers share the same topic structure:

```
"events"                                    — firehose (everything)
"events:kind:{atom}"                        — by event kind
"events:scope:{type}:{hex_id}"             — by scope (repo, intent)
"events:author:{fingerprint}"              — by agent
```

Messages are always `{:event, %WorkersUnite.Event{}}`.

---

## Ecto Schema / Migrations

### `events` table

```elixir
create table(:events, primary_key: false) do
  add :id, :binary, primary_key: true
  add :kind, :string, null: false
  add :author, :binary, null: false
  add :payload, :map, null: false, default: %{}
  add :timestamp, :bigint, null: false
  add :signature, :binary, null: false
  add :references, {:array, :map}, default: []
  add :scope_type, :string
  add :scope_id, :binary

  timestamps(type: :utc_datetime_usec)
end

create index(:events, [:kind])
create index(:events, [:author])
create index(:events, [:scope_type, :scope_id])
create index(:events, [:timestamp])
```

The Ecto schema module (`WorkersUnite.EventRecord`) is a thin persistence layer. The domain struct `WorkersUnite.Event` is what flows through the system. Conversion functions `to_record/1` and `from_record/1` bridge the two.

---

## Implementation Order

This is the order Claude Code should build things. Each step should be working and testable before moving to the next.

### Phase 1: Foundation

1. **Bootstrap**: `mix phx.new workers_unite --binary-id`, add deps to mix.exs, `mix deps.get`
2. **`WorkersUnite.Identity`**: pure functions module (generate, sign, verify, fingerprint). Write tests first.
3. **`WorkersUnite.Identity.Vault`**: GenServer, add to Application children. Test that it persists and loads keys.
4. **`WorkersUnite.Event`**: struct + `new/4` + `verify/1`. Test the sign-and-verify roundtrip.

### Phase 2: Event Store

5. **Migration**: create the `events` table
6. **`WorkersUnite.EventRecord`**: Ecto schema for persistence
7. **`WorkersUnite.EventStore`**: GenServer with ETS + Postgres. Test append, get, by_kind, duplicate rejection, signature rejection.
8. **PubSub wiring**: verify that appending an event broadcasts on all expected topics.

### Phase 3: Agents & Repos

9. **`WorkersUnite.Schema`**: implement Intent, Proposal, Vote, Capability schemas with validation.
10. **`WorkersUnite.Agent`**: GenServer with Horde. Test spawn, inspect_state, claim_intent, submit_proposal, vote. Verify events appear in EventStore.
11. **`WorkersUnite.Repository`**: GenServer with Horde. Test create, get_state, publish_intent. No actual git operations yet — stub them.

### Phase 4: Consensus

12. **`WorkersUnite.Consensus.Engine`**: GenServer. Implement threshold, unanimous, weighted policies. Test with manually crafted events: publish a proposal, publish votes, verify that consensus_reached event appears.
13. **Wire Repository to Consensus**: when consensus_reached fires, repo should update its state (remove from active_proposals, etc.)

### Phase 5: LiveView Dashboard

14. **Layout & root template**: dark theme, monospace vibes, something that feels like a mission control
15. **DashboardLive**: stats + live event ticker + agent cards + repo cards
16. **EventFeedLive**: full firehose with filtering
17. **AgentDetailLive & RepoDetailLive**: deep-dive views
18. **ConsensusLive**: live consensus progress visualization

### Phase 6: Demo / Smoke Test

19. **`WorkersUnite.Demo`**: a module that seeds the system with a few agents and a repo, publishes some intents, has agents claim them, submit proposals, vote, and reach consensus. This is the "enjoy the show" script that exercises the whole pipeline.
20. **`mix workers_unite.demo`**: a Mix task that runs the demo.

---

## Key Design Principles

1. **Events are the API.** Agents never call each other. Everything flows through the EventStore + PubSub. This makes the system observable by default — the LiveView dashboard is just another subscriber.

2. **Verify everything.** Every event signature is checked on append. A compromised or buggy agent can't inject forged events.

3. **Processes are cheap.** One GenServer per agent, one per repo. If you have 100 agents and 20 repos, that's 120 processes — Erlang doesn't blink. Horde distributes them across nodes automatically.

4. **The dashboard is read-only.** Humans observe. They don't approve PRs or type comments. They can configure consensus policies and spawn/kill agents, but the collaboration itself is agent-to-agent.

5. **Schema validates at the edge.** When an event enters the EventStore, its payload is validated against the schema for its kind. Bad payloads are rejected before they enter the log.

---

## Config (config/config.exs additions)

```elixir
config :workers_unite,
  repo_base_path: System.get_env("WORKERS_UNITE_REPO_PATH", "/tmp/workers_unite/repos"),
  bootstrap_peers: [],   # URLs of other WorkersUnite nodes (future)
  default_consensus_policy: {:threshold, 2, 0.7}
```

---

## What's NOT in v0.1 (Roadmap to Federation)

The items below aren't afterthoughts — they're the path to the North Star. Each one removes a barrier between "single-node prototype" and "federated network."

- **Gossip / peering** — node-to-node event exchange, instance discovery, and cross-instance subscription. This is the core federation protocol and the next major milestone.
- **Actual git operations** — repos are created as bare git repos on disk but merges are stubbed. The events flow correctly; the git plumbing (including cross-instance clone/fetch) comes next.
- **Capability enforcement** — capabilities are published as events but not yet checked when agents attempt actions. Required before federation so that remote agents operate within explicit permission boundaries.
- **Agent autonomy** — agents respond to explicit commands (claim_intent, submit_proposal, vote). Autonomous behavior (agent decides on its own to claim an intent, including intents on remote instances) comes later.
- **Cross-instance trust** — reputation portability, remote event verification policies, and instance-level allowlists/blocklists.
