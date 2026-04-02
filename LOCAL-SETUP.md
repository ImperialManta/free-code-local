# free-code + 本地 vLLM 設定紀錄

## 概述

將 `free-code`（Claude Code 全功能解鎖版）移植支援 OpenAI-compatible API，
接上本機 vLLM 伺服器（`gpt-oss-120b`），完全不影響系統的 `claude` 指令。

---

## 環境資訊

| 項目 | 值 |
|------|----|
| 機器 OS | Rocky Linux 8.9 |
| vLLM 伺服器 | `192.168.110.216:8000` |
| 模型 | `/home/cycheng/models/gpt-oss-120b` |
| free-code 路徑 | `/home/cycheng/opencode/free-code` |
| 獨立 config 空間 | `/home/cycheng/opencode/free-code/.claude-local` |

---

## 啟動方式

```bash
cd /home/cycheng/opencode/free-code
./start-local.sh
```

---

## 移植修改清單

### 1. 新增 OpenAI Shim（核心）

**來源**：從 `openclaude` 移植

| 檔案 | 說明 |
|------|------|
| `src/services/api/openaiShim.ts` | 新增。將 Anthropic SDK 格式轉換成 OpenAI-compatible API |

### 2. `src/services/api/client.ts`

加入 OpenAI provider 路由，在 Bedrock 判斷之前插入：

```typescript
if (isEnvTruthy(process.env.CLAUDE_CODE_USE_OPENAI)) {
  const { createOpenAIShimClient } = await import('./openaiShim.js')
  return createOpenAIShimClient({ ... }) as unknown as Anthropic
}
```

### 3. `src/utils/auth.ts`（3 處）

讓 `CLAUDE_CODE_USE_OPENAI` 被視為第三方 provider，不需要 Anthropic API key：

- `is3P` 判斷加入 `|| isEnvTruthy(process.env.CLAUDE_CODE_USE_OPENAI)`
- 排除 Bedrock/Vertex/Foundry 的區塊加入 OpenAI
- `isUsing3PServices()` 加入 OpenAI

### 4. `src/utils/model/model.ts`（5 處）

讓所有 model 函數在 `openai` provider 下回傳 `OPENAI_MODEL`：

- `getSmallFastModel()`
- `getUserSpecifiedModelSetting()`
- `getDefaultOpusModel()`
- `getDefaultSonnetModel()`
- `getDefaultHaikuModel()`

### 5. `src/services/api/openaiShim.ts` — Thinking 支援

新增 `reasoning_content` → Anthropic thinking block 轉換，
對應 vLLM 的 `--reasoning-parser openai_gptoss` 輸出格式：

```typescript
if (delta.reasoning_content) {
  // emit content_block_start type: 'thinking'
  // emit content_block_delta type: 'thinking_delta'
}
```

### 6. `src/bridge/bridgeEnabled.ts` — BRIDGE_MODE 解鎖

移除 `isClaudeAISubscriber()` 的強制要求，openai provider 直接放行：

```typescript
return feature('BRIDGE_MODE')
  ? getAPIProvider() === 'openai' || (isClaudeAISubscriber() && ...)
  : false
```

### 7. `src/tools/WebFetchTool/prompt.ts` — WebFetch 說明修正

明確標注兩個參數都是必填，並附上範例，讓本地模型正確呼叫：

```
REQUIRED parameters (both must be provided):
  - url: ...
  - prompt: ... (e.g. "Return the full content", "Summarize the main findings")
```

### 8. `src/tools/WebFetchTool/WebFetchTool.ts` — prompt 描述修正

```typescript
prompt: z.string().describe('... Required. Example: ...')
```

### 9. `src/tools/WebFetchTool/utils.ts` — HTTP 303 Redirect 修正

原本只處理 `[301, 302, 307, 308]`，Nature.com 等網站會回 303：

```typescript
// 修改前
[301, 302, 307, 308].includes(error.response.status)

// 修改後
[301, 302, 303, 307, 308].includes(error.response.status)
```

---

## 環境變數說明

```bash
CLAUDE_CODE_USE_OPENAI=1                          # 啟用 OpenAI-compatible provider
OPENAI_BASE_URL=http://192.168.110.216:8000/v1    # vLLM endpoint
OPENAI_MODEL=/home/cycheng/models/gpt-oss-120b    # 模型名稱（自動偵測）
OPENAI_API_KEY=dummy                              # vLLM 不驗證 key，任意值即可
CLAUDE_CONFIG_DIR=.../free-code/.claude-local     # 獨立 config 空間，不碰 ~/.claude
ANTHROPIC_DEFAULT_OPUS_MODEL=<model>              # 讓 thinking 支援正確識別模型
ANTHROPIC_DEFAULT_OPUS_MODEL_SUPPORTED_CAPABILITIES=thinking,adaptive_thinking
```

---

## 功能狀態

| 功能 | 狀態 | 說明 |
|------|------|------|
| 本地 vLLM 接入 | ✅ | `gpt-oss-120b` 正常運作 |
| 所有工具（Bash/Read/Write/Grep 等） | ✅ | 完整可用 |
| WebFetch | ✅ | 修正 prompt 必填 + 303 redirect |
| Thinking / ULTRATHINK | ✅ | 透過 `reasoning_content` 轉換 |
| BRIDGE_MODE（IDE 整合） | ✅ | 解除 claude.ai OAuth 限制 |
| 45+ 實驗特性 | ✅ | `cli-dev` 全部解鎖 |
| Prefix Caching | ✅ | vLLM `--enable-prefix-caching` 自動運作 |
| VOICE_MODE | ❌ | 需要 claude.ai voice_stream 服務，無法本地化 |
| config/對話記錄隔離 | ✅ | `.claude-local/` 完全獨立於 `~/.claude/` |

---

## 重新 Build

```bash
cd /home/cycheng/opencode/free-code
export PATH="$HOME/.bun/bin:$PATH"
bun install          # 第一次或更新依賴時執行
bun run build:dev:full   # 建置全功能解鎖版 ./cli-dev
```

---

## Debug 方法

遇到問題時，先判斷是哪一層出錯，再對症下藥。

### 層次判斷流程

```
使用者輸入
    ↓
free-code 解析 → 問題：指令無反應、UI 卡住
    ↓
model 生成 tool call → 問題：工具呼叫格式錯、參數缺失
    ↓
openaiShim 轉換 → 問題：API error、stream 中斷
    ↓
vLLM 執行 → 問題：連線失敗、context 超限、模型回答異常
    ↓
tool 執行 → 問題：權限錯誤、schema 驗證失敗
```

---

### 1. 判斷是 vLLM 問題

**症狀**
- `Unable to connect. Is the computer able to access the url?`
- `API Error: OpenAI API error 5xx`
- 請求送出後沒有任何回應、永久等待

**診斷**
```bash
# 直接打 vLLM，確認服務活著
curl http://192.168.110.216:8000/v1/models

# 確認模型名稱正確
curl http://192.168.110.216:8000/v1/models | python3 -c \
  "import sys,json; [print(m['id']) for m in json.load(sys.stdin)['data']]"

# 送一個最小請求測試
curl http://192.168.110.216:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"/home/cycheng/models/gpt-oss-120b","messages":[{"role":"user","content":"hi"}],"max_tokens":10}'
```

**常見原因與處理**
| 現象 | 原因 | 處理 |
|------|------|------|
| connection refused | vLLM 未啟動 | 重跑 vLLM 啟動腳本 |
| 404 model not found | `OPENAI_MODEL` 名稱錯誤 | 用上方 curl 查正確名稱 |
| 上下文超限錯誤 | 對話超過 131072 tokens | `/compact` 壓縮對話 |

---

### 2. 判斷是 openaiShim 問題

**症狀**
- `API Error: OpenAI API error 4xx`（非 404）
- 模型回答後工具沒被觸發
- thinking 沒有出現但模型應該要推理

**診斷**
```bash
# 開啟 debug log，觀察實際送出的 HTTP 請求
ANTHROPIC_LOG=debug \
CLAUDE_CODE_USE_OPENAI=1 \
OPENAI_BASE_URL=http://192.168.110.216:8000/v1 \
OPENAI_MODEL=/home/cycheng/models/gpt-oss-120b \
OPENAI_API_KEY=dummy \
CLAUDE_CONFIG_DIR=.claude-local \
./cli-dev --print "hi" 2>&1 | grep -E "REQUEST|RESPONSE|Error|model"
```

**常見原因與處理**
| 現象 | 原因 | 處理 |
|------|------|------|
| tool call 格式錯 | shim 轉換有 bug | 查 `openaiShim.ts` `convertTools()` |
| thinking 沒出現 | vLLM 沒輸出 `reasoning_content` | 確認 vLLM 有 `--reasoning-parser openai_gptoss` |
| stream 中途斷掉 | SSE 解析失敗 | 查 `openaiStreamToAnthropic()` |

---

### 3. 判斷是 model 問題（模型本身）

**症狀**
- `Invalid tool parameters`（模型傳了錯誤的工具參數）
- 模型呼叫了不存在的工具
- 模型忽略工具、直接用文字回答本應用工具的任務
- 模型回答品質差、答非所問

**診斷**
```bash
# 用 --print 加簡單指令，觀察模型是否正確識別並呼叫工具
./start-local.sh --dangerously-skip-permissions \
  --print "read the file /etc/hostname and tell me its content"
```

若出現 `Invalid tool parameters`：
1. 看錯誤訊息裡的工具名稱（如 `WebFetch`、`Bash`）
2. 去 `src/tools/<ToolName>/<ToolName>.ts` 查 `inputSchema`
3. 確認模型漏傳了哪個欄位
4. 在 `src/tools/<ToolName>/prompt.ts` 的 `DESCRIPTION` 加強說明

**常見原因與處理**
| 現象 | 原因 | 處理 |
|------|------|------|
| 漏傳必填參數 | tool description 不夠明確 | 在 `prompt.ts` 加 `REQUIRED:` 說明與範例 |
| 呼叫不存在的工具 | 模型幻覺 | 無法根治，只能在 system prompt 補充可用工具清單 |
| 工具完全不觸發 | 模型不知道有這個工具 | 確認工具已在 `src/tools.ts` 正確註冊 |

---

### 4. 判斷是工具 Schema 問題

**症狀**
- `InputValidationError`
- `Error: Request failed with status code XXX`（工具執行時的 HTTP 錯誤）
- 工具執行成功但結果異常（空白、格式錯誤）

**診斷**
```bash
# 直接測試工具行為，不透過模型
CLAUDE_CODE_USE_OPENAI=1 \
OPENAI_BASE_URL=http://192.168.110.216:8000/v1 \
OPENAI_MODEL=/home/cycheng/models/gpt-oss-120b \
OPENAI_API_KEY=dummy \
CLAUDE_CONFIG_DIR=.claude-local \
./cli-dev --dangerously-skip-permissions \
  --print "fetch https://arxiv.org/abs/2301.00001 and return the title"
```

**常見 HTTP 錯誤對照**
| 狀態碼 | 原因 | 位置 |
|--------|------|------|
| 303 | Redirect 未處理 | `utils.ts` redirect list（已修） |
| 403 | 網站封鎖爬蟲 | 無法繞過 |
| 429 | 被限速 | 等待後重試 |
| 5xx | 目標網站錯誤 | 非 free-code 問題 |

---

### 快速判斷表

```
錯誤訊息包含...              → 問題層次
─────────────────────────────────────────
Unable to connect            → vLLM 未啟動或 IP/port 錯誤
API Error: 4xx               → shim 格式錯誤 或 model 名稱錯誤
API Error: 5xx               → vLLM 內部錯誤
Invalid tool parameters      → 模型漏傳參數（model 問題）
InputValidationError         → 同上
Request failed status 303    → WebFetch redirect 未處理（已修）
The model `claude-*` does    → model.ts 沒有正確覆蓋模型名稱
  not exist
```

---

## 已知限制

- **Context window**：vLLM 設定 `--max-model-len 131072`（128K），但 free-code 預設以為有 200K，對話過長可能超出 vLLM 上限
- **VOICE_MODE**：語音功能依賴 Anthropic 的即時語音服務，非模型 API，無法替換
- **付費內容**：WebFetch 無法抓取需要登入的網站（Nature、IEEE 等），可改用 arXiv preprint
