# Claude Code × 本地 vLLM 完整整合指南

> **業餘研究專案** — 純屬個人樂趣，歡迎一起玩壞再修好
>
> 這不是官方產品。源碼版權屬於 [Anthropic](https://www.anthropic.com)。

---

## 這是什麼

這個 repo 是把以下四個社群專案的精華整合在一起，讓 Claude Code 可以完全跑在**本地 vLLM** 上，不需要 Anthropic API Key，不需要付費，不需要網路：

| 來源 | 貢獻 | 原始連結 |
|------|------|----------|
| **ClaudeCode**（源碼還原）| 從 npm source map 還原的完整 TypeScript 原始碼，1,987 個 TS 檔案 | 研究學習用 |
| **openclaude** | OpenAI shim — 讓任何 OpenAI-compatible API 都能接上 Claude Code | [@gitlawb/openclaude](https://github.com/gitlawb) |
| **claw-code** | 工具架構研究與 Python 重寫實驗 | [instructkr/claw-code](https://github.com/instructkr/claw-code) |
| **free-code** | 解鎖所有 45+ 編譯開關、移除遙測、可本地 build | [paoloanzn/free-code](https://github.com/paoloanzn/free-code) |

> **背景**：2026年3月31日，Claude Code 的源碼透過 npm source map 意外公開。社群在幾小時內就出現了多個 fork。這個專案是在這些 fork 基礎上，專門針對「本地模型」使用場景的整合與修復。

---

## 目前可以做什麼

### ✅ 確認可用

- **完整 Claude Code 工具系統**：Bash、FileRead、FileWrite、FileEdit、Glob、Grep、Agent、MCP、LSP
- **本地 vLLM 接入**（透過 openclaude 的 OpenAI shim）
- **串流輸出**：即時 token streaming
- **多步工具鏈**：模型呼叫工具 → 取得結果 → 繼續推理
- **Slash 命令**：`/compact`、`/commit`、`/diff`、`/review`、`/buddy` 等
- **思考模式**：vLLM `--reasoning-parser openai_gptoss` 啟用後，推理過程會顯示為 thinking block
- **LSP 整合**：TypeScript Language Server + pylsp（hover、definition、diagnostics）
- **CLAUDE.md 行為設定**：per-project 系統 prompt
- **Hook 系統**：PreToolUse / PostToolUse shell hooks
- **記憶系統**：自動 memory 提取與儲存
- **BUDDY 電子寵物**：`/buddy` 查看你的終端小動物 🐱

### ⚠️ 已知問題（需要社群一起修）

- **本地模型品質**：gpt-oss-120b 等模型的 RLHF 訓練可能過度保守，會拒絕合理請求。建議換模型（見下方）
- **WORKFLOW_SCRIPTS flag**：有循環依賴 bug，目前已停用（`commands.ts → createWorkflowCommand.ts → commands.ts`）
- **部分 experimental flag**：互動式 UI 在某些 flag 組合下會崩潰，原因是 Bun bundler 的 TDZ 初始化順序問題
- **ripgrep**：外部 build 沒有內建 binary，需要手動指定路徑
- **Thinking block 顯示**：reasoning token 存在但 UI 顯示條件還在調整中

---

## 快速開始

### 前置需求

```bash
# 1. Bun runtime
curl -fsSL https://bun.sh/install | bash

# 2. Node.js（LSP 用）
npm install -g typescript-language-server typescript

# 3. Python LSP（選擇性）
pip install python-lsp-server

# 4. 本地 vLLM（需要 GPU，見下方設定）
```

### 安裝

```bash
git clone <this-repo> free-code-local
cd free-code-local
bun install
bun run build:dev:full   # 產生 ./cli-dev
```

### 第一次設定（跳過 onboarding）

```bash
mkdir -p .claude-local
cat > .claude-local/config.json << 'EOF'
{
  "hasCompletedOnboarding": true,
  "theme": "dark",
  "numStartups": 2,
  "projects": {
    "/your/project/path": { "hasTrustDialogAccepted": true }
  }
}
EOF
```

### 啟動

```bash
./start-local.sh
```

---

## vLLM 設定

### 推薦設定（~/start-vllm.sh）

```bash
python -m vllm.entrypoints.openai.api_server \
  --model /path/to/your/model \
  --host 0.0.0.0 \
  --port 8000 \
  --max-model-len 131072 \
  --max-num-seqs 32 \
  --max-num-batched-tokens 32768 \
  --reasoning-parser openai_gptoss \   # 啟用推理 token 輸出
  --enable-auto-tool-choice \
  --tool-call-parser hermes
```

> **重要**：`--reasoning-parser openai_gptoss` 後面**不能有逗號**，否則推理功能會靜默失敗（這個 bug 找了很久）

### 關鍵環境變數

```bash
CLAUDE_CODE_USE_OPENAI=1                # 啟用 OpenAI shim
OPENAI_BASE_URL=http://192.168.x.x:8000/v1
OPENAI_API_KEY=dummy
CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000     # 避免輸出被截斷
CLAUDE_CODE_MAX_CONTEXT_TOKENS=131072   # 對齊 vLLM 實際 context window
MAX_THINKING_TOKENS=16000               # 推理 token 預算
```

---

## 模型推薦

這是實測後的建議，**非常重要**：

| 模型 | VRAM | 工具呼叫 | 聽從指令 | 中文 | 推薦度 |
|------|------|---------|---------|------|--------|
| **Qwen2.5-72B-Instruct** | ~40GB | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | 頂尖 | ✅ 首選 |
| **Llama-3.3-70B-Instruct** | ~40GB | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | 好 | ✅ 推薦 |
| **DeepSeek-Coder-V2-Instruct** | ~80GB | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | 好 | ✅ 程式專用 |
| **Qwen2.5-Coder-32B-Instruct** | ~20GB | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | 好 | ✅ 小顯卡 |
| gpt-oss-120b | ~70GB | ⭐⭐⭐ | ⭐⭐ | 普通 | ⚠️ 會拒絕請求 |

> **結論**：如果你的 GPU 能跑 120B，用 `Qwen2.5-72B-Instruct` 效果會好很多。它不拒絕台股分析，也不拒絕幫你寫程式 😅

---

## 我們解決了什麼問題

這個整合過程中發現並修復了一堆問題，記錄在這裡給後人參考：

### Bug 修復清單

| 問題 | 原因 | 修法 |
|------|------|------|
| `returnV_ is not defined` | Bun bundler TDZ，stub 檔案有循環 import | 移除 `import type { Command } from 'commands.js'`，改用 `unknown[]` |
| 輸出被截斷在 8K | free-code 的 slot reservation cap | `CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000` |
| Auto-compact 太晚觸發 | free-code 誤以為 context = 200K | `CLAUDE_CODE_MAX_CONTEXT_TOKENS=131072` |
| `--reasoning-parser` 失效 | vLLM 參數後有多餘逗號 | 移除 trailing comma |
| 互動式 UI 崩潰 | 特定 flag 組合的循環依賴 | 移除 `WORKFLOW_SCRIPTS` 等問題 flag |
| ripgrep 找不到 | 外部 build 沒有 vendor binary | 加真正的 ripgrep 路徑到 PATH |
| `shouldGenerateTaskSummary is not a function` | stub 缺少函數 | 補上 stub export |
| `startSkillDiscoveryPrefetch is not a function` | stub 缺少函數 | 補上 stub export |
| Onboarding 卡住無法輸入 | config.json 不存在 → 顯示精靈 | 預先建立 config.json |
| `/buddy` TypeError | command call signature 錯誤 | 修正為 `call(args: string)` |

### 目前啟用的 Feature Flags

```
AGENT_MEMORY_SNAPSHOT, AGENT_TRIGGERS, AGENT_TRIGGERS_REMOTE,
AWAY_SUMMARY, BASH_CLASSIFIER, BRIDGE_MODE, BUILTIN_EXPLORE_PLAN_AGENTS,
CACHED_MICROCOMPACT, CCR_AUTO_CONNECT, CCR_MIRROR, CCR_REMOTE_SETUP,
COMPACTION_REMINDERS, CONNECTOR_TEXT, EXTRACT_MEMORIES, HISTORY_PICKER,
HOOK_PROMPTS, KAIROS_BRIEF, KAIROS_CHANNELS, LODESTONE, MCP_RICH_OUTPUT,
MESSAGE_ACTIONS, NATIVE_CLIPBOARD_IMAGE, NEW_INIT, POWERSHELL_AUTO_MODE,
PROMPT_CACHE_BREAK_DETECTION, QUICK_SEARCH, SHOT_STATS, TEAMMEM,
TOKEN_BUDGET, TREE_SITTER_BASH, TREE_SITTER_BASH_SHADOW, ULTRAPLAN,
ULTRATHINK, UNATTENDED_RETRY, VERIFICATION_AGENT, VOICE_MODE,
BUDDY, PROACTIVE
```

### 暫時停用（有 bug，待修）

```
WORKFLOW_SCRIPTS  — 循環依賴問題
AUTO_THEME, BG_SESSIONS, COMMIT_ATTRIBUTION, CONTEXT_COLLAPSE,
EXPERIMENTAL_SKILL_SEARCH, FORK_SUBAGENT, HISTORY_SNIP,
MCP_SKILLS, MONITOR_TOOL, REACTIVE_COMPACT
```

---

## 修改的核心檔案

```
src/services/api/openaiShim.ts      — Anthropic ↔ OpenAI 串流轉換（來自 openclaude）
src/services/api/client.ts          — 路由到 shim
src/utils/model/providers.ts        — 加入 openai provider
src/utils/model/model.ts            — 使用 OPENAI_MODEL 作為預設
src/utils/auth.ts                   — 接受 openai 為合法 provider
src/bridge/bridgeEnabled.ts         — openai provider 也可啟用 bridge
src/proactive/index.ts              — 從 ClaudeCode 還原的真正實作
src/buddy/                          — 完整電子寵物系統（從 ClaudeCode 複製）
scripts/build.ts                    — 自訂 feature flag 清單
start-local.sh                      — 本地啟動腳本（含所有設定）
.claude-local/CLAUDE.md             — Agent 行為設定（系統 prompt）
```

---

## 如何貢獻

這是**業餘樂趣專案**，沒有 roadmap，沒有 deadline，就是玩。

如果你：
- 修好了某個 flag 的 stub 讓它能用 → PR 歡迎
- 找到更好的本地模型 → 開 issue 分享
- 發現新的 bug → issue 或直接修
- 想加新功能 → fork 自己玩然後告訴我們

特別需要幫忙的地方：
- [ ] `WORKFLOW_SCRIPTS` 循環依賴修復
- [ ] 暫時停用的 10 個 flag 逐一修復並測試
- [ ] 更多本地模型的相容性測試
- [ ] Thinking block 在 UI 的完整顯示驗證

---

## 致謝

這個專案完全建立在社群的工作上：

- **[instructkr/claw-code](https://github.com/instructkr/claw-code)** — 架構研究與 Python 重寫的先驅
- **[openclaude](https://github.com/gitlawb)** — OpenAI shim 的核心實作，讓本地模型接入成為可能
- **[paoloanzn/free-code](https://github.com/paoloanzn/free-code)** — Feature flag 解鎖與 telemetry 移除
- **ClaudeCode 源碼還原** — 完整 TypeScript 原始碼，讓我們能理解並修復問題
- **[Anthropic](https://anthropic.com)** — 原始 Claude Code 的開發者

---

## 免責聲明

- Claude Code 源碼版權屬於 [Anthropic](https://www.anthropic.com)
- 本專案僅供個人研究與學習
- 使用前請遵守 Anthropic 的使用條款
- 這不是 Anthropic 官方產品，使用風險自負
- 本專案不提供任何保證，也不對任何損失負責

---

*"Just a hobby project. Let's break things and fix them together."* 🛠️
