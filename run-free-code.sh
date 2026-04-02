#!/bin/bash

# 設定環境變數
export CLAUDE_CODE_USE_OPENAI=1
export OPENAI_BASE_URL=http://192.168.110.216:8000/v1
export OPENAI_MODEL=gpt-oss-120b   # 換成查到的名字
export OPENAI_API_KEY=dummy         # 任意值

# 執行（全功能解鎖版）
/home/cycheng/opencode/free-code/cli-dev
