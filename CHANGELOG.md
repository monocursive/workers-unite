# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

### Added

- **Identity & Vault** - Ed25519 keypair generation, signing, verification, and persistent node identity via GenServer
- **Event & EventStore** - Append-only event log with ETS cache, Postgres persistence, PubSub broadcast, and content-addressed IDs
- **Schema Validation** - Payload validation for intents, proposals, votes, and capabilities at the EventStore boundary
- **Agent GenServer** - One GenServer per AI agent, supervised by Horde, with session management and task tracking
- **Repository GenServer** - One GenServer per repo, bare git init, intent/proposal/merge lifecycle
- **Consensus Engine** - Pluggable policy evaluation (threshold, unanimous, weighted) with automatic merge on acceptance
- **LiveView Dashboard** - Event firehose, agent list/detail, repo list/detail, consensus view
- **Single-Admin Auth** - Phoenix gen.auth with atomic first-user registration and advisory lock
- **Onboarding Wizard** - First-run setup flow for instance configuration
- **Encrypted Credential Storage** - AES-256-GCM encrypted credentials in Postgres with ETS broker
- **Personality Injection** - Master plan personality injected into orchestrator system prompts
- **MCP Session Ownership** - Session token registry tracking owner user for Claude Code sessions
- **Control Plane** - Durable job scheduler, workflow engine, node manager, and system reporter
- **MCP Tool Suite** - 15+ MCP tools for agent workspace, intents, proposals, votes, events, and diffs
- **Health Endpoint** - Unauthenticated `/health` endpoint for container and load balancer checks
