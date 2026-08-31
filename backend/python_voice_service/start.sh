#!/usr/bin/env bash
set -euo pipefail

SERVICE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${GPT_SOVITS_PYTHON:-}" ]]; then
  PYTHON="$GPT_SOVITS_PYTHON"
elif [[ -x "$SERVICE_ROOT/runtime/miniconda/bin/python" ]]; then
  PYTHON="$SERVICE_ROOT/runtime/miniconda/bin/python"
else
  PYTHON="${PYTHON_BIN:-python3}"
fi

export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8
export GPT_SOVITS_ROOT="${GPT_SOVITS_ROOT:-$SERVICE_ROOT/runtime/GPT-SoVITS}"
export GPT_SOVITS_PYTHON="$PYTHON"
export GPT_SOVITS_CONFIG="${GPT_SOVITS_CONFIG:-$SERVICE_ROOT/gpt_sovits_config.yaml}"
export GPT_SOVITS_MODEL_ROOT="${GPT_SOVITS_MODEL_ROOT:-$SERVICE_ROOT/models/staff_a/Staff_A_GPT-SoVITS_v2ProPlus}"
export GPT_SOVITS_OPEN_JTALK_DICT="${GPT_SOVITS_OPEN_JTALK_DICT:-$SERVICE_ROOT/runtime/open_jtalk_dic_utf_8-1.11}"
export GPT_SOVITS_API_URL="${GPT_SOVITS_API_URL:-http://127.0.0.1:9880}"

arguments=(
  "$SERVICE_ROOT/app/main.py"
  --host "${VOICE_HOST:-0.0.0.0}"
  --port "${VOICE_PORT:-8001}"
)

if [[ "${DISABLE_GPT_SOVITS:-0}" == "1" ]]; then
  arguments+=(--disable-gpt-sovits)
fi

exec "$PYTHON" "${arguments[@]}"
