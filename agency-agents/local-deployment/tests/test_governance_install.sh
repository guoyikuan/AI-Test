#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALL_SCRIPT="${PROJECT_ROOT}/install-all-local.sh"
REGISTER_SCRIPT="${PROJECT_ROOT}/register-openclaw-agents.mjs"

TESTS_PASSED=0
TESTS_FAILED=0

test_env_home=""
test_workspace_root=""
test_backup_root=""
test_config_path=""
test_manifest_path=""
test_governance_hash=""

log() { printf '%s\n' "$*"; }

mk_fake_home() { mktemp -d; }

file_sha256() {
  local target="$1"
  python3 - "$target" <<'__PY__'
import hashlib
import sys

path = sys.argv[1]
with open(path, "rb") as f:
    data = f.read()
print(hashlib.sha256(data).hexdigest())
__PY__
}

create_openclaw_workspace() {
  local workspace_root="$1"
  local id
  mkdir -p "$workspace_root"
  for id in alpha beta gamma; do
    mkdir -p "$workspace_root/$id"
    printf '# %s\n' "$id" > "$workspace_root/$id/SOUL.md"
    printf 'agent %s\n' "$id" > "$workspace_root/$id/AGENTS.md"
    printf 'identity %s\n' "$id" > "$workspace_root/$id/IDENTITY.md"
  done
}

manifest_gov_hash() {
  local workspace_root="$1"
  node - "$workspace_root" <<'__NODE__'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const root = process.argv[2];
const files = [];

const walk = (dir) => {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full);
      continue;
    }
    if (!entry.isFile()) {
      continue;
    }
    files.push({
      rel: path.relative(root, full),
      size: fs.statSync(full).size,
      full,
    });
  }
};
walk(root);
files.sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));

const h = crypto.createHash('sha256');
for (const entry of files) {
  h.update(entry.rel);
  h.update('|');
  h.update(String(entry.size));
  h.update('\0');
  h.update(fs.readFileSync(entry.full));
}
process.stdout.write(h.digest('hex'));
__NODE__
}

write_manifest() {
  local manifest_path="$1" governance_hash="$2"
  cat > "$manifest_path" <<EOF
{
  "schema": "agency-agents.local-installation-manifest/v1",
  "governanceHash": "${governance_hash}",
  "generatedAt": "2026-08-01T00:00:00+08:00",
  "upstream": {
    "repository": "https://github.com/msitarzewski/agency-agents"
  }
}
EOF
}

write_openclaw_config() {
  local config_path="$1"
  mkdir -p "$(dirname "$config_path")"
  cat > "$config_path" <<'EOF'
{
  "schema": "openclaw-config/v1",
  "agents": {
    "list": []
  }
}
EOF
}

build_signature_file() {
  local manifest_path="$1"
  local workspace_root="$2"
  local backup_root="$3"
  local governance_hash="$4"
  local token="${5:-agent-install}"
  local signature_file
  signature_file="$(mktemp)"

  local manifest_digest
  manifest_digest="$(node -e 'const fs=require("fs"); const crypto=require("crypto"); const p=process.argv[1]; const data=fs.readFileSync(p); console.log(crypto.createHash("sha256").update(data).digest("hex"));' "$manifest_path")"
  local payload_digest
  payload_digest="$(node -e 'const crypto=require("crypto"); const material=[process.argv[1],process.argv[2],process.argv[3],process.argv[4]||"",process.argv[5]||"agent-install"].join("\\n"); console.log(crypto.createHash("sha256").update(material).digest("hex"));' "$manifest_path" "$workspace_root" "$backup_root" "$governance_hash" "$token")"

  cat > "$signature_file" <<EOF
{
  "entrypoint": "${INSTALL_SCRIPT}",
  "issuedAt": "2026-08-01T00:00:00Z",
  "workflow": "local-install-gov",
  "manifestDigest": "${manifest_digest}",
  "backupRoot": "${backup_root}",
  "token": "${token}",
  "payloadDigest": "${payload_digest}"
}
EOF
  echo "$signature_file"
}

prepare_case() {
  test_env_home="$(mk_fake_home)"
  export HOME="$test_env_home"
  export OPENCLAW_HOME="$test_env_home"

  test_workspace_root="$test_env_home/.openclaw/agency-agents"
  test_backup_root="$test_env_home/.openclaw/backups"
  test_config_path="$test_env_home/.openclaw/openclaw.json"
  test_manifest_path="$test_env_home/.openclaw/manifest.json"

  create_openclaw_workspace "$test_workspace_root"
  test_governance_hash="$(manifest_gov_hash "$test_workspace_root")"
  write_manifest "$test_manifest_path" "$test_governance_hash"
  write_openclaw_config "$test_config_path"

  mkdir -p "$test_backup_root"
}

run_case() {
  local name="$1" expected="$2"
  shift 2
  log "[case] $name"
  local rc=0
  if "$@"; then
    rc=0
  else
    rc=$?
  fi

  if [[ "$rc" == "$expected" ]]; then
    log "[pass] $name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "[fail] $name (rc=$rc, expect=$expected)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

case_dry_run() {
  prepare_case

  local before_backup
  local config_before
  before_backup="$(find "$test_backup_root" -type f | wc -l | tr -d ' ')"
  config_before="$(file_sha256 "$test_config_path")"

  if ! HOME="$test_env_home" OPENCLAW_HOME="$test_env_home" OPENCLAW_WORKSPACE_ROOT="$test_workspace_root" OPENCLAW_CONFIG_PATH="$test_config_path" OPENCLAW_BACKUP_ROOT="$test_backup_root" AGENCY_INSTALL_MANIFEST="$test_manifest_path" bash "$INSTALL_SCRIPT" --dry-run --apply-governance >/tmp/test-governance-run1.out 2>/tmp/test-governance-run1.err; then
    return 1
  fi

  local after_backup
  local config_after
  after_backup="$(find "$test_backup_root" -type f | wc -l | tr -d ' ')"
  config_after="$(file_sha256 "$test_config_path")"

  [[ "$after_backup" == "$before_backup" ]] || return 1
  [[ "$config_after" == "$config_before" ]] || return 1
  grep -q '"workspaceCount"' /tmp/test-governance-run1.out || return 1
}

case_missing_signature_fail() {
  prepare_case
  if HOME="$test_env_home" OPENCLAW_HOME="$test_env_home" OPENCLAW_WORKSPACE_ROOT="$test_workspace_root" OPENCLAW_CONFIG_PATH="$test_config_path" OPENCLAW_BACKUP_ROOT="$test_backup_root" AGENCY_INSTALL_MANIFEST="$test_manifest_path" bash "$INSTALL_SCRIPT" --apply-governance >/tmp/test-governance-run2.out 2>/tmp/test-governance-run2.err; then
    return 1
  fi
  grep -q 'must pass --signature' /tmp/test-governance-run2.err
}

case_verify_only_mismatch() {
  prepare_case
  local wrong_hash="bad-${test_governance_hash}"
  write_manifest "$test_manifest_path" "$wrong_hash"
  if node "$REGISTER_SCRIPT" --verify-only --manifest "$test_manifest_path" --workspace-root "$test_workspace_root" --config-path "$test_config_path" --backup-root "$test_backup_root" --agent-root "$test_env_home/.openclaw/agents" --expected-governance-hash "$test_governance_hash" >/tmp/test-governance-run3.out 2>/tmp/test-governance-run3.err; then
    return 1
  fi
  grep -q 'Governance hash mismatch' /tmp/test-governance-run3.err
}

case_register_verify_ok() {
  prepare_case
  node "$REGISTER_SCRIPT" --verify-only --manifest "$test_manifest_path" --workspace-root "$test_workspace_root" --config-path "$test_config_path" --backup-root "$test_backup_root" --agent-root "$test_env_home/.openclaw/agents" > /tmp/test-governance-run4.out 2> /tmp/test-governance-run4.err
}

case_register_apply_without_signature() {
  prepare_case
  if [[ ! -d "$test_env_home/.openclaw/agents" ]]; then
    mkdir -p "$test_env_home/.openclaw/agents"
  fi
  if node "$REGISTER_SCRIPT" --manifest "$test_manifest_path" --workspace-root "$test_workspace_root" --config-path "$test_config_path" --backup-root "$test_backup_root" --agent-root "$test_env_home/.openclaw/agents" --expected-governance-hash "$test_governance_hash" >/tmp/test-governance-run5.out 2>/tmp/test-governance-run5.err; then
    return 1
  fi
  grep -q 'Missing governance signature' /tmp/test-governance-run5.err
}

case_register_apply_invalid_signature() {
  prepare_case
  local sig_file
  sig_file="$(mktemp)"
  printf '{"entrypoint":"foo","issuedAt":"now","workflow":"local-install-gov","manifestDigest":"bad","backupRoot":"%s","token":"bad","payloadDigest":"bad"}' "$test_backup_root" > "$sig_file"
  if node "$REGISTER_SCRIPT" --manifest "$test_manifest_path" --workspace-root "$test_workspace_root" --config-path "$test_config_path" --backup-root "$test_backup_root" --agent-root "$test_env_home/.openclaw/agents" --expected-governance-hash "$test_governance_hash" --signature "$sig_file" >/tmp/test-governance-run6.out 2>/tmp/test-governance-run6.err; then
    return 1
  fi
  grep -q 'Invalid governance signature' /tmp/test-governance-run6.err
}

run_case "dry-run verifies manifest/backup root without writes" 0 case_dry_run
run_case "non-dry-run governance apply missing signature must fail" 0 case_missing_signature_fail
run_case "verify-only catches governance hash mismatch" 1 case_verify_only_mismatch
run_case "register verify-only succeeds for clean workspace" 0 case_register_verify_ok
run_case "register apply requires signature" 0 case_register_apply_without_signature
run_case "register apply with invalid signature fails" 1 case_register_apply_invalid_signature

log "tests passed: $TESTS_PASSED | failed: $TESTS_FAILED"
if [[ "$TESTS_FAILED" -gt 0 ]]; then
  exit 1
fi
