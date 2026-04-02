#!/usr/bin/env bash
# ============================================================
# free-code + 本地 vLLM 啟動腳本
# 完全獨立空間，不影響系統 claude 的設定與 key
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY="${SCRIPT_DIR}/cli-dev"

# 若還沒 build，先 build
if [ ! -f "$BINARY" ]; then
  echo "[start-local] 找不到 cli-dev，正在建置..."
  export PATH="$HOME/.bun/bin:$PATH"
  cd "$SCRIPT_DIR" && bun run build:dev:full
fi

# ── 獨立 config 空間 ─────────────────────────────────────────
# 所有設定、對話記錄、memory 都存在這裡，不碰 ~/.claude
export CLAUDE_CONFIG_DIR="${SCRIPT_DIR}/.claude-local"
mkdir -p "$CLAUDE_CONFIG_DIR"

# ── 本地 vLLM 設定 ───────────────────────────────────────────
export CLAUDE_CODE_USE_OPENAI=1
export OPENAI_BASE_URL="http://192.168.110.216:8000/v1"
export OPENAI_API_KEY="dummy"

# 自動抓 vLLM 上的第一個 model name（若能連到的話）
DETECTED_MODEL=$(curl -sf "${OPENAI_BASE_URL}/models" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null)

if [ -n "$DETECTED_MODEL" ]; then
  export OPENAI_MODEL="$DETECTED_MODEL"
  echo "[start-local] 偵測到模型: $OPENAI_MODEL"
else
  export OPENAI_MODEL="${OPENAI_MODEL:-gpt-oss-120b}"
  echo "[start-local] 無法連到 vLLM，使用預設模型: $OPENAI_MODEL"
fi

# ── 宣告模型能力（讓 free-code 知道本地模型支援 thinking）──────
# vLLM 啟動時有 --reasoning-parser openai_gptoss，會輸出 reasoning_content
export ANTHROPIC_DEFAULT_OPUS_MODEL="$OPENAI_MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL_SUPPORTED_CAPABILITIES="thinking,adaptive_thinking"

# ── 輸出 token 上限 ───────────────────────────────────────────
# 預設 8K cap 太小，寫大檔案或長回答會被截斷
# gpt-oss-120b 支援 64K output，vLLM max-model-len=131072
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000

# ── Thinking（推理）token 預算 ────────────────────────────────
# 給模型足夠空間做內部推理，提升回答品質
# vLLM 的 --reasoning-parser openai_gptoss 會輸出 reasoning field
export MAX_THINKING_TOKENS=16000

# ── Context window 上限 ───────────────────────────────────────
# free-code 預設以為 context = 200K，但 vLLM 實際只有 131K
# 設定正確值讓 auto-compact 在 131K 前觸發，避免 vLLM error
export CLAUDE_CODE_MAX_CONTEXT_TOKENS=131072

# ── LSP 整合 ─────────────────────────────────────────────────
# 啟用 LSPTool，提供 hover / definition / diagnostics
# typescript-language-server 已安裝於 ~/.npm-global/bin/
# pylsp 已安裝於 miniforge3 環境
export ENABLE_LSP_TOOL=1
export PATH="$HOME/.npm-global/bin:$PATH"

# ── Ripgrep（GrepTool 依賴）──────────────────────────────────
# free-code 外部 build 沒有內建 ripgrep vendor binary
# 用系統 claude-code 的 rg binary
RG_VENDOR="$HOME/.npm-global/lib/node_modules/@anthropic-ai/claude-code/vendor/ripgrep/x64-linux"
if [ -f "$RG_VENDOR/rg" ]; then
  export PATH="$RG_VENDOR:$PATH"
fi

# ── BRIDGE_MODE（IDE 插件整合）────────────────────────────────
# 允許 VS Code / JetBrains 插件直接控制 Claude Code
# bridgeEnabled.ts 已修改為 openai provider 也可啟用
export BRIDGE_MODE=1

echo "[start-local] Config 目錄: $CLAUDE_CONFIG_DIR"
echo "[start-local] API Endpoint: $OPENAI_BASE_URL"
echo "[start-local] LSP Tool: enabled (typescript-language-server + pylsp)"
echo "[start-local] Bridge Mode: enabled"
echo ""

exec "$BINARY" "$@"
