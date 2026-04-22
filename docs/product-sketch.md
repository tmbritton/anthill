# Anthill — Product Sketch

**Status:** Design sketch, pre-implementation
**Supersedes:** Familiar (renamed back to Anthill; scope cut from "multi-agent coding harness" to mesh agent substrate)

## Vision

A BEAM-native agent mesh with a NATS boundary, aimed at being the long-running cognitive substrate of a homelab.

## Why this exists

Familiar was a multi-agent coding harness in Elixir, heavily AI-coded, that drifted into a shape already well-served by Pi and Claude Code. The codebase grew faster than my understanding of it; bug-fixing became whack-a-mole against scaffolding I didn't write. Anthill is the reset: same BEAM foundation, different scope, and this time the kernel is small enough that I own every line.

The real project that was trying to get out of Familiar was never a coding agent — it was the original Anthill idea of a protocol-addressable, OTP-supervised agent fabric. This document pins that scope down before another AI coding session drifts it back.

## What Anthill is

An Elixir application that runs as a BEAM node on each machine in the homelab (nasty, desktop, laptop). Nodes form an OTP cluster via native BEAM distribution. Each node hosts agents as supervised processes — an agent is a BEAM process with a typed mailbox, persistent state, access to tools, and a conversation loop against an LLM. Agents address each other directly across the cluster via process names and PubSub. External clients speak NATS; a Gateway process per node translates between NATS subjects and agent mailboxes.

## What Anthill is not

- Not a coding harness. Pi and Claude Code own that.
- Not a platform product. No users except me.
- Not competing with OpenClaw, Pi, or similar. Different shape, different goals.
- Not a coding project at heart — a systems project. The code is small by design.

## Architecture

Two protocols, layered cleanly:

- **Inside the mesh: BEAM distribution.** Typed messages, location-transparent addressing, supervision and monitoring, process links across nodes. This is the control plane.
- **At the boundary: NATS.** Language-agnostic clients, pub/sub subjects, request-reply, durable streams via JetStream, account-scoped auth. This is the data / integration plane.

The two layers are not redundant. BEAM distribution coordinates agents; NATS coordinates everything that isn't an agent (CLI tools, phone clients, future protocol gateways, federated participants).

## Network posture

**Near-term: Tailscale only.** All NATS and BEAM traffic over the tailnet. Zero public exposure. Phone and laptop reach the fabric by being on the tailnet. Tailscale is the trust boundary.

**Later, if a concrete use case demands it:** Cloud NATS broker on a DO droplet, home nodes connect as outbound leaf nodes, selective subject bridging between the home/cloud tiers. Home network never opens an inbound port. Justified when (and only when) something meaningful can't be done over Tailscale alone — probably when Dirt Comics or a federated protocol gateway needs to participate.

## First milestone — the forcing function

One agent, one job, on nasty: **acquisition**. Accepts natural-language download requests over NATS — "download all the Friday the 13th movies", "grab season 3 of Severance when it drops", "add the Criterion horror collection" — resolves them against TMDB/TVDB (preferring TMDB's canonical collection IDs where available, LLM enumeration as fallback), de-duplicates against what's already in Radarr/Sonarr/Jellyfin, presents a plan for approval, then drives the Radarr and Sonarr HTTP APIs to add titles and trigger searches.

Why this agent first:

- **Request-response is simpler than event-subscribed.** No log-stream consumption, no always-on loop, no fuzzy success criteria. Either the titles appeared in Radarr or they didn't.
- **It forces NATS to be real from day one.** The whole point is to be addressable from something that isn't the *arr web UI — laptop, phone, eventually SMS/XMPP. A purely-internal agent wouldn't exercise the boundary protocol.
- **Immediate payoff.** Useful the first evening it works, not after waiting for failures to happen.
- **Legible to humans who aren't me.** "I texted my server and it queued twelve movies" is a story that lands.

Evaluated after 30 days of real use:

- Does typing one sentence beat the *arr UI for batch work?
- How often does it misinterpret a request badly enough that I'd rather have used the UI?
- Do I reach for it unprompted?

If it pulls weight: add a triage agent next (log-stream consumption, failure remediation — a much better second project once the kernel and NATS layer are real). If it doesn't: the mesh thesis was wrong, and I learned that cheaply instead of after a six-month platform build.

### Design notes for acquisition

- **Collection resolution:** prefer TMDB's collection API first; fall back to LLM enumeration + per-title TMDB lookup for non-canonical requests ("'70s European horror").
- **Hardcoded defaults:** quality profile and root folder are config, not per-request negotiation. No clarifying questions unless the request is genuinely ambiguous.
- **Duplication:** always check Radarr/Sonarr/Jellyfin before adding. Summary distinguishes added vs skipped vs already-monitored.
- **Approval gate:** present the plan (titles, count, destination) and require explicit approval before executing. This is the kind of agent where the human-in-the-loop pattern earns its keep.
- **Add-only, v1.** No delete, no move, no edit of existing entries. Destructive operations are a separate scope, later, maybe never.
- **Prompt injection defense:** treat all text retrieved from TMDB/TVDB/*arr responses as untrusted data, never as instructions. Retrieved text enters the context clearly labeled as tool-call output, never as system prompt. Approval plans show titles for human verification.

## Scope — in

- Elixir application, one OTP app, single-node first.
- `Supervisor` + `DynamicSupervisor` for agent lifecycle.
- Agent = `GenServer` with typed message enum, tool-call loop, persistent state in per-agent SQLite.
- Tool = Elixir behaviour with `name/0`, `description/0`, `schema/0`, `call/1`.
- LLM client = behaviour; first implementation OpenAI-compatible (covers Anthropic via proxy, OpenRouter, Ollama, DeepSeek).
- NATS gateway per node using Gnat. NATS broker is external (not embedded) — one `nats-server` binary, running on nasty initially.
- Acquisition agent as the first real workload, with tools for TMDB, Radarr, Sonarr, and Jellyfin.
- Small NATS client (Go escript or Elixir mix task) on the laptop for sending acquisition requests and receiving plans/progress; same protocol usable from a phone or bash one-liner.

## Scope — out (deferred or rejected)

- **Multi-node clustering.** Defer until one node is real and working.
- **Cloud NATS / leaf nodes.** Defer until Tailscale is insufficient.
- **Knowledge store / RAG.** Defer until an agent actually needs it. When needed, reuse well-known patterns (SQLite + sqlite-vec + BM25), not novel architecture.
- **Workflow engine.** Defer. Agents can coordinate via PubSub for now.
- **Markdown-driven roles/skills/workflows.** Was in Familiar. Not needed for hand-built agents. Elixir modules are fine.
- **MCP client/server.** Defer indefinitely.
- **Web dashboard.** LiveDashboard attaches trivially later if I want it.
- **TUI.** `iex --remsh` is the dev UI.
- **Hot code reload as a designed-in feature.** Works in Elixir; don't build anything that depends on it.
- **Plugin ecosystem / extension marketplace.** Rejected. Extensions are OTP apps I write when I need them. No registry, no discovery, no packaging story.
- **"AI-coded" kernel work.** AI assistance is fine for boring bits (schema encoders, test scaffolding). Architectural code is mine.

## Tradeoffs considered

### Why not just use Pi for everything?

Pi is the right tool for coding work and I should use it there. But Pi is a single local interactive harness for one human; it doesn't model always-on supervised agents across multiple machines with cross-node messaging. Different shape of problem, different software.

### Why not OpenClaw?

Architecturally closer to the vision than Pi, and has a mature memory plugin ecosystem. Rejected on security grounds: 156 advisories tracked as of Q1 2026, including CVSS 9.8–9.9 auth bypasses and a command-approval model with documented structural gaps. Runs with system-level access, making every auth bypass a potential RCE. Not safe to install on nasty given nasty's role (Pi-hole, ProtonVPN creds, *arr API keys, full media library). Also structurally a monolith-with-plugins rather than a mesh.

### Why not Gleam?

Considered seriously. Strong type story for LLM message blocks (sum types + exhaustive matching) is genuinely a good fit for agent code. Rejected for this project because:

- `gleam_otp` explicitly does not support hot code upgrades.
- Distribution is not type-safe across nodes.
- Ecosystem is thin for LLM and BEAM-cultural infrastructure (Gnat, Horde, Phoenix.PubSub, LiveDashboard are all Elixir).
- 1.5–2x build cost for a language I don't yet know well.

Deferred, not rejected — a future Gleam-native version could revisit this with the domain understood.

### Why NATS, not HTTP or custom TCP?

- HTTP/REST has wrong semantics for an agent fabric (no native pub/sub, no subscription model).
- Custom TCP means reinventing auth, reconnection, queue groups, durability that NATS already solved.
- NATS subject hierarchy maps naturally to agent addressing.
- Clients exist in every language I'd plausibly use.
- Conforming to an existing standard is more punk than inventing a new one.

### Why BEAM distribution *and* NATS instead of just NATS?

BEAM distribution gives a coherent **control plane**: process linking, monitoring, distributed supervision, atomic global naming, location-transparent calls, native term passing. NATS gives a coherent **data plane**: pub/sub, request/reply, durability, replay, polyglot clients, cross-trust auth.

For the specific workloads I care about (supervised long-lived agents, singletons that can migrate between nodes, cross-machine process coordination), BEAM distribution does real work that rebuilding on NATS would be painful. For everything outside the BEAM fabric, NATS is the right tool. The two layers serve different purposes.

### Why hand-build instead of forking something?

Familiar was AI-coded and became unmaintainable because I didn't own the code. This time the kernel must fit in my head and be explainable line-by-line without notes. AI assistance is a tool, not an author.

## Anti-goals (scope discipline)

Patterns to resist. When an AI suggestion, an idle evening, or a brainstorm goes in one of these directions, stop.

- *"What if we added a coding agent?"* No. Pi owns that.
- *"What if we added markdown-driven agent config?"* No. Elixir modules are fine.
- *"What if we made it a platform others can use?"* No. No users but me.
- *"What if we added an extension marketplace?"* No. Write OTP apps.
- *"The AI suggests hexagonal architecture / six Mox ports / workflow persistence / file transactions with rollback."* No. Ignore.
- *"Let's write tests before features work."* Write tests for the kernel and for code under genuine pressure. No premature scaffolding.
- *"What if we built a web UI?"* LiveDashboard attaches later if needed. Not now.
- *"Let's make the agent runtime configurable via YAML."* No.

## Open questions (for me, later)

- NATS subject naming convention (`anthill.<node>.<agent-id>.<event-type>` as a starting point). Design when the gateway is real.
- Agent state persistence: SQLite per agent, or one DB per node? Lean per-agent for isolation, revisit if it becomes painful.
- NATS auth on Tailscale: is tailnet-as-boundary sufficient, or set up NKeys from day one? Lean NKeys, because retrofitting auth is a nightmare.
- Agent definitions: Elixir modules vs markdown-in-git loaded at startup. Elixir for now. Revisit if recompile-per-definition-change becomes a drag.
- Tool sandboxing: process isolation is free in BEAM, but tools that shell out need OS-level sandboxing. Container-per-tool-call? `firejail`? Defer until an agent actually needs to run shell.

## What "done" looks like for the first milestone

- One BEAM node running on nasty.
- One NATS server running on nasty, listener bound to tailnet interface only.
- Acquisition agent running as a supervised process, with working Radarr and Sonarr integration, TMDB-backed collection resolution, and a two-phase plan-and-approve flow over NATS.
- Small NATS client on the laptop for sending acquisition requests and reviewing plans; same protocol usable from a phone or bash one-liner.
- 30-day real-use track record, honest evaluation at the end.

Everything past that milestone gets evaluated against pressure from real use, not from design speculation. The project exists to be useful in my homelab, not to be architecturally perfect.
