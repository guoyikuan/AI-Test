#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REG_SCRIPT="${SCRIPT_DIR}/register-openclaw-agents.mjs"

MANIFEST_PATH="${AGENCY_INSTALL_MANIFEST:-${SCRIPT_DIR}/installation-manifest.json}"
DRY_RUN=false
APPLY_GOVERNANCE=false
OVERRIDE_HOME="${OPENCLAW_HOME:-${HOME}}"
WORKSPACE_ROOT="${OPENCLAW_WORKSPACE_ROOT:-${OVERRIDE_HOME}/.openclaw/agency-agents}"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OVERRIDE_HOME}/.openclaw/openclaw.json}"
BACKUP_ROOT="${OPENCLAW_BACKUP_ROOT:-${OVERRIDE_HOME}/.openclaw/backups}"
EXPECTED_GOVERNANCE_HASH="${OPENCLAW_EXPECTED_GOVERNANCE_HASH:-}"
SIGNATURE_PATH=""

USAGE() {
  cat <<'__USAGE__'
Usage:
  local-deployment/install-all-local.sh [--dry-run] [--apply-governance] [--manifest PATH] [--signature PATH]

Flags:
  --dry-run               Validate inputs only; no writes.
  --apply-governance      Run governance validation/registration only.
  --manifest PATH         Manifest path (default local-deployment/installation-manifest.json)
  --signature PATH        Signature file required for non-dry-run governance apply.
__USAGE__
}

require_file() {
  local name="$1"
  local target="$2"
  if [[ ! -e "$target" ]]; then
    echo "Missing required $name: $target" >&2
    return 1
  fi
}

file_sha256() {
  local target="$1"
  node -e 'const fs=require("fs"); const crypto=require("crypto"); const p=process.argv[1]; const data=fs.readFileSync(p); process.stdout.write(crypto.createHash("sha256").update(data).digest("hex"));' "$target"
}

workspace_signature_payload() {
  local manifest_path="$1"
  local workspace_path="$2"
  local backup_root="$3"
  local expected_hash="$4"
  local token="$5"
  node -e 'const crypto=require("crypto"); const material=[process.argv[1],process.argv[2],process.argv[3],process.argv[4]||"",process.argv[5]||"agent-install"].join("\\n"); console.log(crypto.createHash("sha256").update(material).digest("hex"));' "$manifest_path" "$workspace_path" "$backup_root" "$expected_hash" "$token"
}

run_register_verify_only() {
  local manifest_path="$1"
  local workspace_root="$2"
  local config_path="$3"
  local backup_root="$4"
  local expected_hash="$5"
  node "$REG_SCRIPT" --verify-only \
    --manifest "$manifest_path" \
    --workspace-root "$workspace_root" \
    --config-path "$config_path" \
    --backup-root "$backup_root" \
    --agent-root "${OVERRIDE_HOME}/.openclaw/agents" \
    --expected-governance-hash "$expected_hash"
}

run_register_apply() {
  local manifest_path="$1"
  local workspace_root="$2"
  local config_path="$3"
  local backup_root="$4"
  local expected_hash="$5"
  local signature_file="$6"
  node "$REG_SCRIPT" \
    --manifest "$manifest_path" \
    --workspace-root "$workspace_root" \
    --config-path "$config_path" \
    --backup-root "$backup_root" \
    --agent-root "${OVERRIDE_HOME}/.openclaw/agents" \
    --expected-governance-hash "$expected_hash" \
    --signature "$signature_file"
}

manifest_has_governance_hash() {
  local manifest_path="$1"
  node -e 'const fs=require("fs"); const path=process.argv[1]; const data=JSON.parse(fs.readFileSync(path, "utf8")); process.exit(data && typeof data.governanceHash === "string" && data.governanceHash.length > 0 ? 0 : 1);' "$manifest_path"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --apply-governance)
        APPLY_GOVERNANCE=true
        shift
        ;;
      --manifest)
        MANIFEST_PATH="$2"
        shift 2
	    ;;
      --signature)
        SIGNATURE_PATH="$2"
        shift 2
        ;;
      --help|-h)
        USAGE
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        USAGE
        exit 1
        ;;
    esac
  done
}

run_governance_stage() {
  local mode="$1"

  require_file manifest "$MANIFEST_PATH"
  require_file workspace "$WORKSPACE_ROOT"
  require_file config "$CONFIG_PATH"
  mkdir -p "$BACKUP_ROOT"

  if [[ "$mode" == "verify" ]]; then
    run_register_verify_only "$MANIFEST_PATH" "$WORKSPACE_ROOT" "$CONFIG_PATH" "$BACKUP_ROOT" "$EXPECTED_GOVERNANCE_HASH"
    return 0
  fi

  if [[ -n "$EXPECTED_GOVERNANCE_HASH" ]]; then
    :
  elif ! manifest_has_governance_hash "$MANIFEST_PATH"; then
    echo "Missing governance hash in manifest; set OPENCLAW_EXPECTED_GOVERNANCE_HASH." >&2
    return 1
  fi

  local signature_file="$SIGNATURE_PATH"
  if [[ -z "$signature_file" ]]; then
    echo "Missing governance signature: apply mode must pass --signature <path>." >&2
    return 1
  fi

  run_register_apply "$MANIFEST_PATH" "$WORKSPACE_ROOT" "$CONFIG_PATH" "$BACKUP_ROOT" "$EXPECTED_GOVERNANCE_HASH" "$signature_file"
}

main() {
  parse_args "$@"

  if $APPLY_GOVERNANCE; then
    if $DRY_RUN; then
      run_governance_stage verify
    else
      run_governance_stage apply
    fi
    return
  fi

  echo "--apply-governance is required for governance-focused runs in this checkpoint." >&2
  echo "Run with --dry-run --apply-governance for preflight validation." >&2
}

main "$@"
