# Architecture Overview

This document describes the internal architecture of free-code: how components connect, how data flows, and where to find things when something breaks.

For setup and vLLM configuration, see `LOCAL-SETUP.md`.
For feature flags, see `FEATURES.md`.

---

## Top-Level Structure

```
src/
├── entrypoints/cli.tsx          Entry point — parses args, bootstraps runtime
├── screens/REPL.tsx             Interactive UI loop (Ink/React)
├── QueryEngine.ts               Core query pipeline: sends messages, runs tools
├── Tool.ts                      Base tool interface + buildTool() factory
├── tools.ts                     Tool registry — imports and exports all tools
├── commands.ts                  Slash command registry
├── types/                       Shared TypeScript types
├── constants/                   System prompt builder, feature prompts
├── services/                    External integrations (API, MCP, auth, analytics)
├── utils/                       Pure utilities (auth, model, permissions, git…)
├── tools/                       Tool implementations (one dir per tool)
├── commands/                    Slash command implementations
├── components/                  Ink/React terminal UI components
├── state/                       App state store (AppState)
├── hooks/                       React hooks for UI/flows
├── bridge/                      IDE bridge (VS Code / JetBrains)
├── memdir/                      Auto-memory system
├── skills/                      Skill loader and registry
└── plugins/                     Plugin system
```

---

## Request Flow

```
User types input
      │
      ▼
REPL.tsx (src/screens/REPL.tsx)
  handles keypress, slash commands, abort
      │
      ▼
QueryEngine.ts (src/QueryEngine.ts)
  builds messages array + system prompt
  calls LLM via API client
      │
      ▼
API client (src/services/api/client.ts)
  routes to provider:
    CLAUDE_CODE_USE_OPENAI=1  →  openaiShim.ts
    CLAUDE_CODE_USE_BEDROCK=1 →  Bedrock SDK
    default                   →  Anthropic SDK
      │
      ▼
LLM streams response
  text delta       → rendered by REPL
  tool_use block   → dispatched to toolExecution.ts
      │
      ▼
toolExecution.ts (src/services/tools/toolExecution.ts)
  runs pre-tool hooks  (toolHooks.ts → utils/hooks.ts)
  checks permissions   (utils/permissions/)
  calls tool.call()
  runs post-tool hooks
  returns tool result to QueryEngine
      │
      ▼
QueryEngine appends tool result, loops back to LLM
```

---

## Provider Routing

```typescript
// src/utils/model/providers.ts
getAPIProvider() → 'openai' | 'firstParty' | 'bedrock' | 'vertex' | 'foundry'

// src/services/api/client.ts  (routing order)
1. CLAUDE_CODE_USE_OPENAI  → openaiShim.ts   (local vLLM / OpenAI-compatible)
2. CLAUDE_CODE_USE_BEDROCK → Bedrock SDK
3. CLAUDE_CODE_USE_VERTEX  → Vertex SDK
4. CLAUDE_CODE_USE_FOUNDRY → Foundry client
5. (default)               → Anthropic SDK
```

The OpenAI shim (`src/services/api/openaiShim.ts`) translates:
- Anthropic message format → OpenAI chat completions format
- OpenAI SSE stream → Anthropic stream events
- `delta.reasoning_content` → `content_block_start/delta` (thinking blocks)

---

## System Prompt Assembly

```
src/constants/prompts.ts → getSystemPrompt()
  sections (each memoized via systemPromptSections.ts):
    ├── intro            "You are an interactive agent…"
    ├── system           tool call rules, hooks guidance
    ├── doing tasks      code style, file creation rules
    ├── actions          reversibility, blast radius
    ├── using tools      FileWriteTool / FileEditTool / GlobTool / GrepTool rules
    ├── tone & style     markdown, concise output
    ├── output efficiency lead with answer, no preamble
    ├── memory           memdir auto-memory prompt
    ├── env info         CWD, OS, git state, model name
    └── session-specific model-specific guidance
  +
  CLAUDE.md content      loaded from project dir + config dir
```

`CLAUDE_CONFIG_DIR/CLAUDE.md` (`.claude-local/CLAUDE.md`) is loaded as the global section — applies to all projects when using this free-code instance.

---

## Tool System

### Registry

`src/tools.ts` is the registry. All tools are imported here and exported as the `getTools()` function. Tools are conditionally included based on:
- `feature()` build flags (compile-time)
- `process.env.USER_TYPE === 'ant'` (internal-only tools)
- Runtime settings and permission mode

### Tool Interface (`src/Tool.ts`)

Every tool implements:

```typescript
{
  name: string
  inputSchema: ZodSchema         // validated before call()
  outputSchema: ZodSchema
  description(input): string     // shown in permission prompts
  prompt(options): string        // injected into system prompt
  checkPermissions(input, ctx)   // allow / ask / deny
  call(input, ctx)               // actual execution
  isReadOnly(): boolean
  isConcurrencySafe(): boolean
}
```

### Tool Execution Pipeline

```
QueryEngine receives tool_use block
      │
      ▼
toolExecution.ts → runTool()
  1. validateInput()        — Zod schema check
  2. executePreToolHooks()  — user-configured shell hooks (utils/hooks.ts)
  3. checkPermissions()     — rule-based + interactive prompt
  4. tool.call()            — actual execution
  5. executePostToolHooks() — post-tool shell hooks
  6. return ToolResult
```

Hook execution (`src/utils/hooks.ts`) runs user shell commands configured in settings under `hooks.PreToolUse` and `hooks.PostToolUse`. Hooks can:
- **Block** tool execution (exit code 2 + message)
- **Modify** tool input (JSON on stdout)
- **Observe** without affecting execution

---

## Model Resolution

For the `openai` provider, all five model functions in `src/utils/model/model.ts` return `OPENAI_MODEL`:

| Function | Returns (openai provider) |
|----------|--------------------------|
| `getSmallFastModel()` | `OPENAI_MODEL` or `gpt-4o-mini` |
| `getUserSpecifiedModelSetting()` | `ANTHROPIC_MODEL` or `OPENAI_MODEL` |
| `getDefaultOpusModel()` | `OPENAI_MODEL` or `gpt-4o` |
| `getDefaultSonnetModel()` | `OPENAI_MODEL` or `gpt-4o` |
| `getDefaultHaikuModel()` | `OPENAI_MODEL` or `gpt-4o-mini` |

This prevents Claude model names (e.g. `claude-sonnet-4-6`) from being sent to vLLM, which would return a 404.

---

## Memory System

```
.claude-local/
└── projects/
    └── -home-cycheng-opencode-free-code/
        └── memory/
            ├── MEMORY.md          index (loaded into system prompt)
            └── *.md               individual memory files (frontmatter typed)
```

Memory path: `getAutoMemPath()` in `src/memdir/paths.ts`
→ resolves to `<CLAUDE_CONFIG_DIR>/projects/<sanitized-cwd>/memory/`

Memory types: `user`, `feedback`, `project`, `reference` (see `src/memdir/memoryTypes.ts`)

---

## Permission System

```
src/utils/permissions/
├── permissions.ts      rule matching (allow / ask / deny per tool + input)
├── PermissionResult.ts decision type + reason
└── filesystem.ts       path-based allow/deny rules (DANGEROUS_DIRECTORIES etc.)

src/state/AppState.ts → toolPermissionContext
  mode: 'default' | 'dangerousFullAccess' | 'acceptEdits'
  rules: per-tool allow/ask/deny rules (from settings.json)
```

DANGEROUS_DIRECTORIES (e.g. `~/.ssh`, `/etc`) are blocked by default even in `dangerousFullAccess` mode, except the auto-memory path.

---

## MCP Integration

```
src/services/mcp/
├── types.ts               Config schemas (McpStdioServerConfig, McpSSEServerConfig…)
├── client.ts              Connects to MCP servers, discovers tools
├── MCPConnectionManager   Lifecycle: start / stop / reconnect
└── mcp_stdio.ts           stdio transport

Transports: stdio | sse | sse-ide | http | ws | sdk
Config scope: local | user | project | dynamic | enterprise | claudeai | managed
```

MCP tools appear alongside built-in tools in the tool registry at runtime. The model sees them identically.

---

## Build System

`scripts/build.ts` bundles with Bun. Feature flags are compile-time constants via `bun:bundle`:

```bash
bun run build:dev:full   # ./cli-dev  — all 54 working experimental flags
bun run build            # ./cli      — stable build
bun run compile          # ./dist/cli — standalone compiled binary
```

54 of 88 flags build cleanly. The remaining 34 require internal `@ant/*` packages.

Key flags enabled in `dev-full`:
`ULTRATHINK`, `BRIDGE_MODE`, `COORDINATOR_MODE`, `PROACTIVE`, `KAIROS`, `EXTRACT_MEMORIES`, `CACHED_MICROCOMPACT`, `AGENT_TRIGGERS`, `EXPERIMENTAL_SKILL_SEARCH`, and 45 more.

---

## Key Files Quick Reference

| What you want to change | File |
|------------------------|------|
| Add/modify a tool | `src/tools/<ToolName>/<ToolName>.ts` + `prompt.ts` |
| Register a new tool | `src/tools.ts` |
| Change system prompt | `src/constants/prompts.ts` |
| Change provider routing | `src/services/api/client.ts` |
| Change model name resolution | `src/utils/model/model.ts` |
| Change provider detection | `src/utils/model/providers.ts` |
| Change auth / API key logic | `src/utils/auth.ts` |
| Change hook execution | `src/utils/hooks.ts` |
| Change permission rules | `src/utils/permissions/permissions.ts` |
| Change thinking/shim behavior | `src/services/api/openaiShim.ts` |
| Change BRIDGE_MODE logic | `src/bridge/bridgeEnabled.ts` |
| Add a slash command | `src/commands/<name>/` + register in `src/commands.ts` |
