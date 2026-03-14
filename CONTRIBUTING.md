# Contributing to WorkersUnite

Thanks for your interest in contributing! This document covers setup, conventions, and the PR process.

## Getting Started

### Prerequisites

- Elixir ~> 1.18 / OTP 27 (see `.tool-versions`)
- PostgreSQL 15+
- Git 2.x

### Setup

```bash
git clone https://github.com/monocursive/workers-unite.git
cd workers_unite
mix setup
mix phx.server
```

Or with Docker:

```bash
docker compose up --build
```

## Development Workflow

### Running Tests

```bash
mix test
```

### Pre-commit Checks

Run the full check suite before submitting a PR:

```bash
mix precommit
```

This runs:
- `mix compile --warnings-as-errors`
- `mix deps.unlock --unused`
- `mix format`
- `mix test`

### Code Style

- Run `mix format` before committing
- Payload keys must be strings (not atoms) for Postgres JSONB consistency
- Use `WorkersUnite.Identity` for all crypto operations, never call `:crypto` directly
- All IDs are content-addressed SHA-256 hashes, not UUIDs

### Architecture Conventions

- **Events are the API.** Agents communicate through the EventStore + PubSub, never directly
- **One GenServer per agent/repo.** Horde distributes them across nodes
- **Schema validates at the edge.** Payloads are validated when events enter the EventStore
- See `CLAUDE.md` for the full list of conventions

## Pull Request Process

1. Fork the repo and create a feature branch from `main`
2. Make your changes with tests where applicable
3. Run `mix precommit` and ensure it passes
4. Open a PR with a clear description of what changed and why
5. PRs require at least one review before merging

## Test Coverage Gaps

The following areas have limited or no test coverage and would benefit from contributions:

- Control plane modules (job scheduler, node manager, workflow engine, master)
- MCP tool implementations
- Agent detail / repo detail LiveViews
- Git module
- Schema validation edge cases

## Code of Conduct

Be respectful, constructive, and collaborative. We're building tools for machines, but the community is made of humans.
