# Operator Copilot Spec

## Status

Draft

## Summary

WorkersUnite should stop trying to be the primary conversational copilot UI.

Instead:

- an external LLM operator app, with `OpenCode` as the primary target, becomes the main pilot console
- WorkersUnite remains the control plane, event store, agent runtime, and repository system
- the Phoenix web app becomes a maintenance, configuration, and observability interface

This direction is a better fit for subscription-backed coding tools such as Z.AI Coding Plan because the supported tool remains the actual model host. WorkersUnite only exposes tools and state.

## Decision

The preferred operating model is:

- use `OpenCode` as the main human-facing copilot
- connect `OpenCode` to WorkersUnite through a dedicated operator MCP surface
- keep the dashboard for onboarding, credentials, instance settings, token management, system health, and emergency operations

This supersedes the earlier "chat-first dashboard" direction in [jido-dashboard-agent-spec.md](/home/monocursive/code/forgelet/docs/jido-dashboard-agent-spec.md).

## Why This Makes More Sense

WorkersUnite already has:

- a working MCP transport at `/mcp/:token`
- a tool registry and tool handlers
- an OpenCode runtime adapter
- authenticated admin/settings screens
- a clean separation between protocol state and UI state

What it does not have is a clean economic or policy basis for embedding a subscription-backed copilot directly inside the dashboard.

By moving the conversational layer into a real operator app:

- the LLM app owns the subscription and chat UX
- WorkersUnite owns the protocol and execution state
- the dashboard no longer has to double as both maintenance console and reasoning runtime

## Product Goals

- Make `OpenCode` the default human pilot console for WorkersUnite
- Expose WorkersUnite capabilities through a dedicated operator MCP surface
- Keep the web UI focused on setup, maintenance, health, audit, and recovery
- Preserve existing internal agent MCP flows for coder/reviewer/orchestrator agents
- Avoid running a second, app-embedded copilot stack unless later proven necessary

## Non-Goals

- Replacing the current internal worker agents
- Replacing the event log with conversation state
- Making the web dashboard the main pilot UX
- Reusing internal ephemeral session tokens for human operator access

## Architecture

## Control Plane

WorkersUnite remains responsible for:

- event storage
- repository state
- agent spawning and reuse
- consensus
- credentials and model/provider configuration
- audit logging

## Operator Plane

The operator app is responsible for:

- chat UX
- local prompting/persona
- subscription-backed model usage
- conversation history
- tool invocation against WorkersUnite

## Interface Boundary

The interface between both sides is a dedicated operator MCP endpoint.

Key rule:

- WorkersUnite exposes tools
- the operator app provides the model

That keeps WorkersUnite independent of the subscription economics of the LLM app.

## Why OpenCode First

`OpenCode` should be the first-class target because:

- WorkersUnite already ships an OpenCode runtime adapter
- the existing tool surface is oriented toward coding-agent workflows
- Z.AI officially documents OpenCode support for Coding Plan login
- CLI-based operator workflows fit the current repo/agent model better than an embedded dashboard chat

`OpenClaw` can be considered later if it can consume the same tool boundary cleanly, but OpenCode is the primary target for v1.

## Current Code Constraints

The current MCP endpoint at `/mcp/:token` is not suitable for external human use.

Reasons:

- it is backed by `WorkersUnite.Agent.SessionRegistry`
- the tokens are ephemeral and tied to internal agent sessions
- the exposed tool set is authorized by internal worker `kind`

Relevant code:

- MCP route: [router.ex](/home/monocursive/code/forgelet/lib/workers_unite_web/router.ex#L30)
- MCP session lookup: [plug.ex](/home/monocursive/code/forgelet/lib/workers_unite_web/mcp/plug.ex#L16)
- worker-kind tool authorization: [tool_registry.ex](/home/monocursive/code/forgelet/lib/workers_unite_web/mcp/tool_registry.ex#L8)
- OpenCode internal runtime: [opencode.ex](/home/monocursive/code/forgelet/lib/workers_unite/agent/runtime/opencode.ex#L17)

Therefore:

- keep the current `/mcp/:token` flow for internal worker sessions
- add a separate operator-facing MCP stack for human piloting

## Proposed Topology

```text
OpenCode (human operator)
  -> Operator MCP endpoint
    -> WorkersUnite operator tool layer
      -> EventStore / Repository / Agent / Consensus / Settings

Dashboard (browser)
  -> onboarding
  -> credentials
  -> operator token management
  -> health + audit + maintenance
```

## Routing And Auth

## Internal Worker MCP

Keep the existing route unchanged:

- `scope "/mcp", WorkersUniteWeb.MCP`
- `pipe_through :api`
- `post "/:token", Plug, []`

Why:

- it is already tied to internal agent sessions
- it should remain isolated from human/operator auth concerns

## Operator Token Bootstrap Routes

Add authenticated browser JSON routes for issuing and revoking operator tokens:

```elixir
scope "/operator", WorkersUniteWeb do
  pipe_through [:browser_json, :require_authenticated_user]

  post "/tokens", OperatorTokenController, :create
  get "/tokens", OperatorTokenController, :index
  delete "/tokens/:id", OperatorTokenController, :delete
end
```

Why:

- token issuance should require a normal authenticated session and `@current_scope`
- this keeps token minting behind existing login/onboarding rules
- it avoids inventing a separate bootstrap auth path on day one

## Operator MCP Transport

Add a dedicated operator MCP route:

```elixir
scope "/operator/mcp", WorkersUniteWeb.OperatorMCP do
  pipe_through :api

  post "/:token", Plug, []
end
```

Why:

- the operator app will not send browser cookies or CSRF tokens
- it needs token-based auth suitable for local tools like OpenCode
- it must not depend on `SessionRegistry`

## Admin Configuration Routes

Add operator settings under the existing admin live session:

- `scope "/", WorkersUniteWeb`
- `pipe_through [:browser, :require_authenticated_user]`
- `live_session :admin, on_mount: [{WorkersUniteWeb.UserAuth, :ensure_admin}]`

Recommended routes:

- `/settings/operator`
- `/settings/operator/tokens`

Why:

- operator exposure policy is instance-level configuration
- it belongs next to model, credentials, and personality settings

## Auth Model

## v1 Recommendation

Use persistent per-user operator access tokens.

Suggested table: `operator_access_tokens`

Fields:

- `id`
- `user_id`
- `name`
- `token_prefix`
- `token_hash`
- `scopes` as array of strings
- `last_used_at`
- `expires_at`
- `revoked_at`
- timestamps

Rules:

- tokens are created by authenticated users through the browser
- only hashed tokens are stored
- the plaintext token is shown once
- tokens execute tool calls as the owning user
- tokens are revocable without affecting browser sessions

## Future Option

Add device-code or local-loopback auth later if token UX proves too primitive.

Do not start there.

## Permissions Model

Suggested operator scopes:

- `observe`
- `control`
- `admin`

Defaults:

- normal admin/operator tokens get `observe` and `control`
- `admin` remains separate and should be required for sensitive maintenance tools

Important boundary:

- normal operator MCP should not expose raw credential values
- settings mutation and secret rotation should stay in the maintenance UI initially

## Tool Taxonomy

## Operator Read Tools

- list agents
- inspect agent state
- list repos
- inspect repo state
- query events
- list intents
- list proposals
- inspect consensus
- get proposal diff
- list active sessions

## Operator Control Tools

- publish intent
- claim intent
- start or resume worker session
- dispatch work to coder/reviewer/orchestrator roles
- publish comment
- cast vote
- request merge or other repo mutation
- cancel active worker session

## Maintenance Tools

Keep these out of operator MCP in v1 unless there is a strong reason:

- view decrypted credentials
- rotate provider secrets
- mutate global auth settings
- delete users
- change onboarding state

Those belong in the browser UI with existing auth and sudo protections.

## Tool Design Principle

Do not reuse the current worker-kind authorization model for human operators.

Current worker tools are keyed by `:coder`, `:reviewer`, and `:orchestrator`.
Operator tools should instead be authorized by:

- token scope
- current user role
- per-tool policy

Recommended extraction:

- move domain logic into shared service modules under `WorkersUnite.Tools.*`
- keep the current MCP tool handlers as thin adapters
- add a second adapter layer for operator MCP

## Worker Selection Policy

When the operator app asks WorkersUnite to do work:

- prefer reusing a suitable idle worker
- auto-spawn a new worker when no suitable idle worker exists
- keep this decision inside WorkersUnite, not in the operator app

This makes the operator workflow simple while still letting WorkersUnite manage isolation and efficiency.

Suggested service:

- `WorkersUnite.Operator.Dispatch`

Responsibilities:

- inspect existing workers
- choose reuse vs spawn
- start the appropriate task/session
- return a structured dispatch result to the operator app

## OpenCode Integration

## v1 Target

OpenCode is the primary operator client.

Setup flow:

1. user logs into WorkersUnite web UI
2. user generates an operator token from `/settings/operator/tokens`
3. user configures OpenCode with the WorkersUnite operator MCP endpoint
4. user keeps model/provider/subscription configuration entirely in OpenCode
5. OpenCode drives WorkersUnite through tools

## Prompting Strategy

WorkersUnite should not own the main operator persona.

Instead it should provide:

- recommended system prompt text
- tool descriptions tuned for chief-of-staff orchestration
- suggested workflows

Suggested operator prompt shape:

- strategic chief of staff
- coordinates specialized workers
- prefers existing workers before spawning new ones
- treats WorkersUnite as the execution fabric and source of truth
- narrates actions and references event/proposal refs in responses

## OpenCode Bootstrap UX

The maintenance UI should expose:

- MCP endpoint URL
- token creation UI
- copyable OpenCode setup instructions
- current recommended prompt text
- troubleshooting guidance for local connection issues

## OpenClaw Position

OpenClaw is a possible future client, but not the primary v1 target.

Reason:

- the current repo already has OpenCode-oriented runtime vocabulary
- OpenCode is directly aligned with coding-agent CLI workflows
- OpenClaw should be treated as a second client once the operator MCP layer is stable

## Web UI Role

The web UI becomes maintenance-first.

## Root Dashboard

`/` should become a maintenance overview, not a copilot chat.

It should show:

- instance health
- event count
- active agents
- active repos
- current provider/model readiness
- operator MCP status
- recent audit activity

## Settings

The web UI remains the place for:

- onboarding
- credentials
- model catalog/provider setup
- operator token management
- operator policy settings
- health and audit review

## Emergency Operations

The web UI should eventually provide:

- revoke operator token
- stop active worker session
- disable operator MCP globally
- inspect recent dangerous mutations

This is the operational fallback when the external copilot misbehaves or loses context.

## Persistence

WorkersUnite should not persist full operator chat transcripts in v1.

Persist instead:

- operator token records
- tool audit entries
- dispatch records
- mutation events that already belong in the event log

Suggested table: `operator_tool_audits`

Fields:

- `id`
- `user_id`
- `token_id`
- `tool_name`
- `arguments_summary`
- `result_status`
- `result_ref`
- `client_name`
- timestamps

The operator app keeps conversation history. WorkersUnite keeps execution/audit history.

## Safety Boundaries

Even with a powerful operator copilot, retain these boundaries:

- no credential disclosure through MCP
- no direct browser-session reuse for external tools
- no dependence on the operator app for source-of-truth state
- no raw shell execution inside the web process

If shell or filesystem work is needed, route it through existing worker agents or dedicated runtimes.

## Z.AI Coding Plan Fit

This architecture is the best available fit for subscription-backed tools such as Z.AI Coding Plan because:

- the supported tool remains the actual client
- WorkersUnite acts as a backend/tool server
- the dashboard is not pretending to be the subscribed coding tool

However, this spec intentionally assumes personal/local operator use when a subscription-backed coding tool is involved. If WorkersUnite is later offered as a hosted shared service, this assumption must be revisited.

## Implementation Phases

### Phase 0: Service Extraction

- extract shared domain services from current MCP tool handlers
- keep current worker MCP behavior unchanged

### Phase 1: Operator Auth

- add `operator_access_tokens`
- add token issuance and revocation flows
- add operator MCP plug and route

### Phase 2: Operator Tool Surface

- add operator tool registry with scope-based auth
- implement observe/control tools
- add tool audit logging

### Phase 3: Maintenance UI Shift

- simplify `/` into maintenance overview
- add operator settings and token management screens
- add OpenCode bootstrap instructions

### Phase 4: Worker Dispatch UX

- add hybrid worker selection service
- expose worker reuse/spawn behavior to operator tools
- add cancel/stop capabilities and audit visibility

### Phase 5: Optional Secondary Clients

- evaluate OpenClaw or other operator clients against the stable operator MCP layer

## Recommendation

Proceed with:

- OpenCode as the main operator cockpit
- WorkersUnite operator MCP as the integration boundary
- dashboard/web UI as maintenance and configuration only

This is a cleaner fit for the current codebase and the subscription-backed tool strategy than forcing a native copilot into the Phoenix dashboard.
