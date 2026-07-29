#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer currently supports macOS only." >&2
  exit 1
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
  BREW_BIN=/opt/homebrew/bin/brew
elif command -v brew >/dev/null 2>&1; then
  BREW_BIN="$(command -v brew)"
else
  echo "Homebrew is required." >&2
  exit 1
fi

if ! "${BREW_BIN}" list --formula node >/dev/null 2>&1; then
  "${BREW_BIN}" install node
fi

if ! "${BREW_BIN}" list --cask agency-agents >/dev/null 2>&1; then
  "${BREW_BIN}" tap msitarzewski/agency-agents
  "${BREW_BIN}" install --cask msitarzewski/agency-agents/agency-agents
fi

BREW_PREFIX="$("${BREW_BIN}" --prefix)"
export PATH="${HOME}/.local/bin:${BREW_PREFIX}/bin:/usr/bin:/bin:${PATH}"

mkdir -p "${HOME}/.local"
"${BREW_PREFIX}/bin/npm" --prefix "${HOME}/.local" install -g \
  openclaw@2026.7.1-2 --no-audit --no-fund

openclaw --version

cd "${REPO_ROOT}"
./scripts/convert.sh --parallel

TOOLS=(
  codex
  claude-code
  copilot
  antigravity
  gemini-cli
  opencode
  qwen
  cursor
  aider
  windsurf
  zcode
  osaurus
  hermes
  vibe
)

for tool in "${TOOLS[@]}"; do
  QWEN_AGENTS_DIR="${HOME}/.qwen/agents" \
    ./scripts/install.sh --no-interactive --tool "${tool}"
done

WORKSPACE_LIST="$(mktemp)"
REGISTERED_LIST="$(mktemp)"
OPENCLAW_JSON="$(mktemp)"
trap 'rm -f "${WORKSPACE_LIST}" "${REGISTERED_LIST}" "${OPENCLAW_JSON}"' EXIT

mkdir -p "${HOME}/.openclaw/agency-agents"
rsync -a integrations/openclaw/ "${HOME}/.openclaw/agency-agents/"
node local-deployment/register-openclaw-agents.mjs

find "${HOME}/.openclaw/agency-agents" \
  -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort > "${WORKSPACE_LIST}"
if ! perl -e 'alarm shift; exec @ARGV' 60 openclaw gateway restart; then
  openclaw gateway install
fi
openclaw gateway status --deep --require-rpc --json >/dev/null

openclaw agents list --json > "${OPENCLAW_JSON}"
jq -r '
  if type == "array" then .[].id
  elif (.agents | type) == "array" then .agents[].id
  elif (.items | type) == "array" then .items[].id
  else empty
  end
' "${OPENCLAW_JSON}" | sort > "${REGISTERED_LIST}"

if ! comm -23 "${WORKSPACE_LIST}" "${REGISTERED_LIST}" | diff - /dev/null; then
  echo "OpenClaw runtime registration is incomplete." >&2
  exit 1
fi

echo "Agency Agents local installation completed."
echo "OpenClaw workspaces: $(wc -l < "${WORKSPACE_LIST}" | tr -d ' ')"
echo "OpenClaw registered agents: $(wc -l < "${REGISTERED_LIST}" | tr -d ' ')"
