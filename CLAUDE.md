# CLAUDE.md

This file provides guidance to Claude Code (and local LLM agents) when working with code in this repository.

---

## Project Identity

**free-code** is a production-ready fork of Claude Code with two key enhancements:

1. **OpenAI-compatible provider shim** — routes all LLM calls through any OpenAI-compatible API (vLLM, Ollama, LM Studio, OpenRouter, etc.) instead of Anthropic's API
2. **45+ experimental feature flags unlocked** — the full `dev-full` build enables all stable experimental features from the upstream Claude Code feature flag system

This setup runs completely independently from the system `claude` installation. All config, history, and memory live under `.claude-local/` and never touch `~/.claude/`.

**Related projects in this workspace:**
- `../claw-code` — a parallel clean-room Python + Rust reimplementation of Claude Code's harness architecture (reference for tool patterns and architecture decisions)
- `../openclaude` — the original OpenAI shim source that was ported into this project

---

## Common Commands

```bash
# Install dependencies (first time or after package changes)
export PATH="$HOME/.bun/bin:$PATH"
bun install

# Build the full-feature local binary (./cli-dev)
bun run build:dev:full

# Standard build without experimental flags (./cli)
bun run build

# Run with local vLLM (preferred — handles all env setup automatically)
./start-local.sh

# Run with local vLLM, skip permission prompts
./start-local.sh --dangerously-skip-permissions

# Run a one-shot command (non-interactive)
./start-local.sh --print "your task here"

# Run tests
bun test tests/             # all tests
bun run test:shim           # openaiShim conversion logic
bun run test:webfetch       # redirect handling + URL validation
bun run test:tools          # provider routing + env isolation
```

---

## Running Environment

The local vLLM instance provides the LLM backend:

| Variable | Value |
|----------|-------|
| `CLAUDE_CODE_USE_OPENAI` | `1` |
| `OPENAI_BASE_URL` | `http://192.168.110.216:8000/v1` |
| `OPENAI_MODEL` | auto-detected from vLLM (currently `gpt-oss-120b`) |
| `OPENAI_API_KEY` | `dummy` (vLLM does not validate) |
| `CLAUDE_CONFIG_DIR` | `<repo>/.claude-local/` |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | same as `OPENAI_MODEL` |
| `ANTHROPIC_DEFAULT_OPUS_MODEL_SUPPORTED_CAPABILITIES` | `thinking,adaptive_thinking` |

All of these are set automatically by `./start-local.sh`.

---

## High-Level Architecture

```
src/entrypoints/cli.tsx          — CLI bootstrap, argument parsing
src/screens/REPL.tsx             — interactive UI loop (Ink/React)
src/QueryEngine.ts               — LLM query pipeline, tool orchestration
src/tools.ts                     — tool registry
src/commands.ts                  — slash command registry
src/Tool.ts                      — base tool interface

src/services/api/
  client.ts                      — API provider routing (firstParty / bedrock / vertex / openai)
  openaiShim.ts                  — [MODIFIED] OpenAI↔Anthropic format translator + thinking support

src/utils/
  auth.ts                        — [MODIFIED] 3P provider detection (openai treated as 3P)
  model/
    model.ts                     — [MODIFIED] model name resolution per provider
    providers.ts                 — getAPIProvider() → 'openai' | 'firstParty' | 'bedrock' | ...

src/bridge/bridgeEnabled.ts      — [MODIFIED] BRIDGE_MODE unlocked for openai provider
src/constants/prompts.ts         — system prompt builder (getSystemPrompt, all sections)
src/constants/systemPromptSections.ts — memoized section cache

src/tools/
  BashTool/                      — shell execution
  FileReadTool/                  — Read
  FileWriteTool/                 — Write (create new files)
  FileEditTool/                  — Edit (modify existing files)
  GlobTool/                      — file pattern matching
  GrepTool/                      — content search
  WebFetchTool/                  — [MODIFIED] prompt required, 303 redirect fix
  WebSearchTool/                 — web search
  AgentTool/                     — spawn sub-agents
  TaskCreateTool/ … TaskStopTool/ — background task management
```

---

## Modified Files Reference

These files were changed from upstream to support the local vLLM provider. Touch them carefully.

| File | What Changed |
|------|--------------|
| `src/services/api/openaiShim.ts` | **NEW** — Anthropic↔OpenAI stream translator, reasoning_content→thinking block |
| `src/services/api/client.ts` | Added `CLAUDE_CODE_USE_OPENAI` routing before Bedrock check |
| `src/utils/auth.ts` | Three locations: openai treated as 3P provider, no Anthropic key required |
| `src/utils/model/model.ts` | Five model functions return `OPENAI_MODEL` when provider is `openai` |
| `src/bridge/bridgeEnabled.ts` | BRIDGE_MODE allowed when `getAPIProvider() === 'openai'` |
| `src/tools/WebFetchTool/prompt.ts` | Both params declared REQUIRED with examples |
| `src/tools/WebFetchTool/WebFetchTool.ts` | `prompt` schema description updated |
| `src/tools/WebFetchTool/utils.ts` | HTTP 303 added to redirect handling list |

---

## Tool Usage Rules

When making code changes in this repository, follow these rules precisely:

- **Read existing files** with `FileReadTool` before editing them
- **Create new files** with `FileWriteTool` — do not use Bash heredoc or echo redirection
- **Edit existing files** with `FileEditTool` — do not use `sed` or `awk`
- **Search for files** with `GlobTool` — do not use `find` or `ls`
- **Search file content** with `GrepTool` — do not use `grep` or `rg`
- **Run build/test commands** with `BashTool` only when no dedicated tool covers the operation

When asked to "write a file", "create a script", or "implement X in a new file":
→ Always use `FileWriteTool` with the full target path.
→ Do not output the file content as a code block and stop there.

---

## Build System

`scripts/build.ts` is the Bun-based build system. Feature flags are compile-time constants via `bun:bundle`.

```bash
# Full experimental build (preferred for local use)
bun run build:dev:full    # → ./cli-dev

# Standard build
bun run build             # → ./cli

# Compiled standalone binary
bun run compile           # → ./dist/cli
```

The `build:dev:full` preset enables 54 out of 88 feature flags. The remaining 34 require internal Anthropic packages (`@ant/*`) and cannot be enabled in external builds.

---

## Key Provider Logic

```typescript
// src/utils/model/providers.ts
getAPIProvider() → 'openai' | 'firstParty' | 'bedrock' | 'vertex' | 'foundry'

// Triggered by:
CLAUDE_CODE_USE_OPENAI=1   → 'openai'
CLAUDE_CODE_USE_BEDROCK=1  → 'bedrock'
(default)                  → 'firstParty'
```

All five model resolution functions in `src/utils/model/model.ts` check `getAPIProvider() === 'openai'` and return `process.env.OPENAI_MODEL` to prevent Claude model names from leaking to vLLM.

---

## Thinking / Reasoning Support

The `openaiShim.ts` translates vLLM's `reasoning_content` SSE field into Anthropic thinking blocks:

```
vLLM delta.reasoning_content  →  content_block_start (type: 'thinking')
                                  content_block_delta (type: 'thinking_delta')
```

This requires vLLM to be started with `--reasoning-parser openai_gptoss`.

Declare capabilities via:
```bash
ANTHROPIC_DEFAULT_OPUS_MODEL=<model-name>
ANTHROPIC_DEFAULT_OPUS_MODEL_SUPPORTED_CAPABILITIES=thinking,adaptive_thinking
```

---

## Working Agreement

- Prefer small, targeted edits over large rewrites
- Read a file before modifying it — never modify code you haven't seen
- When fixing a bug, fix the root cause; do not add workarounds that hide the problem
- When the shim, model routing, or auth logic is involved, test with `./start-local.sh --print "hi"` before and after
- Do not modify the five model functions in `model.ts` without also verifying the `getAPIProvider()` branch
- Do not commit `.claude-local/` contents — this directory is local state only

---

## Debug Quick Reference

```
Error symptom                       → Layer to investigate
────────────────────────────────────────────────────────────
Unable to connect to URL            → vLLM not running (curl 192.168.110.216:8000/v1/models)
API Error 5xx                       → vLLM internal error
API Error 4xx                       → openaiShim format mismatch or wrong model name
The model `claude-*` does not exist → model.ts not returning OPENAI_MODEL for openai provider
Invalid tool parameters             → model didn't send required fields; improve tool prompt.ts
InputValidationError                → same as above
Request failed status 303           → WebFetch redirect list (already fixed in utils.ts)
Thinking not appearing              → vLLM missing --reasoning-parser openai_gptoss
```

Full debug guide: see `LOCAL-SETUP.md`.

---

## Known Constraints

- **Context window**: vLLM is configured with `--max-model-len 131072` (128K). free-code assumes 200K. Use `/compact` when conversations grow long.
- **VOICE_MODE**: Requires `claude.ai` real-time voice streaming — not replaceable with local models.
- **Authenticated URLs**: `WebFetchTool` cannot access login-gated content (Nature, IEEE, GitHub private repos).
- **@ant/* packages**: 34 feature flags require internal Anthropic packages that are not publicly available.
