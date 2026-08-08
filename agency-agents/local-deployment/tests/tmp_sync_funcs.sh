#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="${SCRIPT_DIR}/../sync-all-local.sh"
MANIFEST_PATH="${SCRIPT_DIR}/../frozen-action-manifest.json"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SOURCE_ROOT="${REPO_ROOT}/integrations"
FIXTURE_ROOT=""
CANONICAL_SOURCE=""

manifest_tool_count="$(jq -r '.tools | length' "$MANIFEST_PATH")"
manifest_target_count="$(jq -r '[.tools[].targets[]] | length' "$MANIFEST_PATH")"
manifest_expected_sections="$(jq -r '.expectedSections // 269' "$MANIFEST_PATH")"

canonical_trust_home() {
  local user_name
  local trust_home

  user_name="$(id -un 2>/dev/null || whoami 2>/dev/null || echo '')"
  if [[ -n "$user_name" ]] && command -v dscl >/dev/null 2>&1; then
    trust_home="$(dscl . -read "/Users/${user_name}" NFSHomeDirectory 2>/dev/null | awk '/NFSHomeDirectory/ {print $2}' | tail -n1)"
  fi

  if [[ -z "$trust_home" ]] && [[ -n "$user_name" ]] && [[ -r /etc/passwd ]]; then
    trust_home="$(awk -F: -v user="$user_name" '$1==user {print $6}' /etc/passwd 2>/dev/null)"
  fi

  if [[ -z "$trust_home" ]]; then
    trust_home="${HOME}"
  fi

  printf '%s\n' "$trust_home"
}

physical_root() {
  local raw_root="$1"
  printf '%s\n' "$(cd -- "$raw_root" && pwd -P)"
}

trust_authority_prep() {
  local work_root="$1"
  local trust_root
  trust_root="$(canonical_trust_home)/.codex/supervisor-authority"
  mkdir -p "$trust_root"
  chmod 700 "$trust_root"
  : >"$trust_root/owner-only-ledger.jsonl"

  local key="$work_root/key"
  local allowed_signers="$trust_root/allowed_signers"
  ssh-keygen -t ed25519 -N "" -f "$key" >/dev/null 2>&1
  printf 'supervisor-approver %s\n' "$(cat "${key}.pub")" > "$allowed_signers"
  printf '%s\n' "$allowed_signers"
}

json_get() {
  local file="$1"
  local path="$2"
  python3 - "$file" "$path" <<'PY'
import json
import sys

path = sys.argv[2]
raw = open(sys.argv[1], "r", encoding="utf-8", errors="ignore").read()
decoder = json.JSONDecoder()
obj = None
idx = 0
while idx < len(raw):
    while idx < len(raw) and raw[idx].isspace():
        idx += 1
    if idx >= len(raw):
        break
    try:
        parsed, end = decoder.raw_decode(raw, idx)
    except json.JSONDecodeError:
        idx += 1
        continue
    obj = parsed
    idx += end

if obj is None:
    raise SystemExit(f"no-json output in {sys.argv[1]}")

parts=[p for p in sys.argv[2].split('.') if p]
cur=obj
for p in parts:
    if '[' in p and p.endswith(']'):
        key,idx=p[:-1].split('[',1)
        cur=cur[key][int(idx)]
    else:
        cur=cur[p]
print(cur)
PY
}

file_hash() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
    return
  fi
  node -e 'const fs=require("fs");const crypto=require("crypto");process.stdout.write(crypto.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"));' "$file"
}

resolve_manifest_path() {
  local raw="$1"
  local home="$2"
  local project="$3"
  local value="$raw"
  value="${value//\$\{HOME\}/${home}}"
  value="${value//\$HOME/${home}}"
  value="${value//\$\{PROJECT\}/${project}}"
  value="${value//\$PROJECT/${project}}"

  if [[ "${value:0:2}" == "~/" ]]; then
    printf '%s\n' "${home}/${value#\~/}"
    return
  fi

  if [[ "$value" == /* ]]; then
    printf '%s\n' "$value"
    return
  fi

  printf '%s\n' "${project}/${value}"
}

seed_qwen_kimi_sources() {
  local source_root_dir="$1"

  local counts
  local qwen_count
  local kimi_count
  local qwen_invalid
  local kimi_invalid

  counts="$(python3 - "${source_root_dir}/qwen" "${source_root_dir}/kimi" <<'PY'
import json
import os
import pathlib
import re
import sys

def count_roles(root):
    raw_ids=[]
    invalid_ids=[]
    if not os.path.isdir(root):
        return 0, 0

    ids=[]
    agent_files=[]
    for dirpath, _, filenames in os.walk(root):
        if 'agents.json' in filenames:
            agent_files.append(os.path.join(dirpath, 'agents.json'))

    if agent_files:
        for agents_json in agent_files:
            with open(agents_json, encoding='utf-8') as fh:
                data = json.load(fh)
            for row in data:
                if isinstance(row, dict) and isinstance(row.get('slug'), str):
                    raw = str(row.get('slug'))
                    ids.append(raw[7:] if raw.startswith('agency-') else raw)
    else:
        def collect_ids_from_path(base_dir):
            entries=[e for e in os.listdir(base_dir) if not e.startswith('.')]
            if not entries:
                return []

            dir_entries=[e for e in entries if os.path.isdir(os.path.join(base_dir, e))]
            if dir_entries:
                return sorted(dir_entries)

            file_entries=[os.path.splitext(e)[0] for e in entries if os.path.isfile(os.path.join(base_dir,e))]
            return sorted(file_entries)

        candidates=[]
        agents_dir=os.path.join(root, 'agents')
        rules_dir=os.path.join(root, 'rules')

        if os.path.isdir(agents_dir):
            candidates=[agents_dir]
        elif os.path.isdir(rules_dir):
            candidates=[rules_dir]
        else:
            children=[e for e in os.listdir(root) if not e.startswith('.')]
            child_dirs=[e for e in children if os.path.isdir(os.path.join(root,e))]
            if len(child_dirs)==1:
                single_dir=os.path.join(root, child_dirs[0])
                if os.listdir(single_dir):
                    candidates=[single_dir]
            if not candidates:
                candidates=[root]

        for cand in candidates:
            raw=collect_ids_from_path(cand)
            ids.extend(raw)

    ids=[pathlib.Path(item).stem[7:] if isinstance(item, str) and item.startswith('agency-') else item for item in ids]

    pat = re.compile(r'^[a-z0-9][a-z0-9-]*$')
    for item in ids:
        if pat.match(item):
            raw_ids.append(item)
        else:
            invalid_ids.append(item)

    return len(set(raw_ids)), len(invalid_ids)

qwen_count, qwen_invalid = count_roles(sys.argv[1])
kimi_count, kimi_invalid = count_roles(sys.argv[2])
print(f"{qwen_count} {qwen_invalid} {kimi_count} {kimi_invalid}")
PY
  )"

  read -r qwen_count qwen_invalid kimi_count kimi_invalid <<< "$counts"

  if [[ "$qwen_count" != "269" || "$kimi_count" != "269" || "$qwen_invalid" != "0" || "$kimi_invalid" != "0" ]]; then
    echo "FAIL: qwen/kimi source role seeds invalid (qwen=$qwen_count/$qwen_invalid kimi=$kimi_count/$kimi_invalid)"
    return 1
  fi
}

build_isolated_fixture() {
  FIXTURE_ROOT="$(physical_root "$(mktemp -d)")"
  chmod 700 "$FIXTURE_ROOT"

  CANONICAL_SOURCE="$FIXTURE_ROOT/source"
  mkdir -p "$CANONICAL_SOURCE"
  cp -R "${SOURCE_ROOT}/." "$CANONICAL_SOURCE/"

  if ! seed_qwen_kimi_sources "$CANONICAL_SOURCE"; then
    return 1
  fi
}

fixture_case_home() {
  local home
  home="$(mktemp -d "$FIXTURE_ROOT/home.XXXXXX")"
  physical_root "$home"
}

fixture_source_copy() {
  local home="$1"
  local src
  src="$home/source"
  rm -rf "$src"
  cp -R "${CANONICAL_SOURCE}/." "$src"
  printf '%s\n' "$src"
}

clear_qwen_kimi_targets() {
  local home="$1"
  rm -rf "${home}/.qwen" "${home}/.config/kimi"
}

collect_probe_paths() {
  local home="$1"
  local project="$2"
  local out="$3"
  local list
  list=$(mktemp)

  jq -r '.tools[].targets[].targetPath // empty' "$MANIFEST_PATH" > "$list"
  while IFS= read -r templ; do
    resolve_manifest_path "$templ" "$home" "$project" >> "$out"
  done < "$list"

  printf '%s\n' "${home}/.openclaw/agents/main" >> "$out"
  printf '%s\n' "${home}/.openclaw/agents/main/agent/auth-profiles.json" >> "$out"

  rm -f "$list"
}

snapshot_paths() {
  local list="$1"
  local out="$2"
  python3 - "$list" "$out" <<'PY'
import json
import os
import sys

paths_file, out_path = sys.argv[1:3]
paths = [line.strip() for line in open(paths_file, encoding="utf-8") if line.strip()]
state = {}
for p in paths:
    if os.path.lexists(p):
        st = os.lstat(p)
        state[p] = {
            "exists": True,
            "inode": st.st_ino,
            "mode": oct(st.st_mode & 0o7777),
            "size": st.st_size,
            "mtime": int(st.st_mtime),
            "type": "symlink" if os.path.islink(p) else "regular",
        }
    else:
        state[p] = {
            "exists": False,
        }
with open(out_path, 'w', encoding='utf-8') as fp:
    json.dump(state, fp, sort_keys=True)
PY
}

snapshot_diff_clean() {
  local before="$1"
  local after="$2"
  python3 - "$before" "$after" <<'PY'
import json
import sys

b = json.load(open(sys.argv[1], encoding='utf-8'))
a = json.load(open(sys.argv[2], encoding='utf-8'))
if b == a:
  print('ok')
else:
  print('changed')
  sys.exit(1)
PY
}

snapshot_diff_paths() {
  local before="$1"
  local after="$2"
  local out="$3"
  python3 - "$before" "$after" "$out" <<'PY'
import json
import sys

before = json.load(open(sys.argv[1], encoding='utf-8'))
after = json.load(open(sys.argv[2], encoding='utf-8'))
out_path = sys.argv[3]
changed = []
for path in sorted(set(before.keys()) | set(after.keys())):
  if before.get(path) != after.get(path):
    changed.append(path)

with open(out_path, 'w', encoding='utf-8') as out:
  for p in changed:
    out.write(f"{p}\n")

if changed:
  sys.exit(1)
PY
}

assert_counts() {
  local report="$1"
  local tx_count
  local tool_count
  local target_count
  local backup_count

  tool_count="$(json_get "$report" manifest.toolCount)"
  target_count="$(json_get "$report" manifest.targetRootCount)"
  tx_count="$(json_get "$report" manifest.transactionCount)"
  backup_count="$(json_get "$report" result.backupCount)"

  if [[ "$tool_count" != "$manifest_tool_count" ]]; then
    echo "FAIL: toolCount mismatch manifest=$manifest_tool_count report=$tool_count"
    return 1
  fi
  if [[ "$target_count" != "$manifest_target_count" ]]; then
    echo "FAIL: targetRootCount mismatch manifest=$manifest_target_count report=$target_count"
    return 1
  fi
  if [[ "$tx_count" != "$manifest_target_count" ]]; then
    echo "FAIL: transactionCount mismatch expected=$manifest_target_count report=$tx_count"
    return 1
  fi
  if [[ "$backup_count" != "$manifest_target_count" ]]; then
    echo "FAIL: backupCount mismatch expected=$manifest_target_count report=$backup_count"
    return 1
  fi
}

build_auth_bundle() {
  local base="$1"
  local namespace="$2"
  local principal="$3"
  local action_out="$4"
  local manifest="$5"
  local allowed_signers="${6:-}"
  local mode="${7:-}"
  local trust_root="${8:-${PROJECT:-${HOME:-}}}"
  local test_root="${9:-$trust_root}"

  local manifest_hash
  local entrypoint_hash
  local signers_hash
  local generated_key=""
  local ledger_path=""

  if [[ "$mode" == "isolated-test" ]]; then
    if [[ -n "$trust_root" ]]; then
      trust_root="$(cd "$trust_root" && pwd -P)"
    fi
    if [[ -n "$test_root" ]]; then
      test_root="$(cd "$test_root" && pwd -P)"
    fi
    trust_root="$test_root"
    mkdir -p "${trust_root}/.codex/supervisor-authority" "${trust_root}/.codex/supervisor-runtime-evidence"
    ledger_path="${trust_root}/.codex/supervisor-runtime-evidence/owner-only-ledger.jsonl"
  else
    if [[ -n "$trust_root" && -d "$trust_root" ]]; then
      mkdir -p "${trust_root}/.codex/supervisor-authority"
    fi
  fi

  mkdir -p "$base"
  local action_file="$action_out"
  local signature_file="${action_file}.sig"

  local mode_clause=''
  local root_clause=''

  if [[ "$mode" == "isolated-test" ]]; then
    mode_clause=",\"mode\": \"${mode}\""
    root_clause=",\"trust_root\": \"${trust_root}\""
  fi

  if [[ -z "$allowed_signers" ]]; then
    if [[ -n "$trust_root" && -d "$trust_root" ]]; then
      allowed_signers="${trust_root}/.codex/supervisor-authority/allowed_signers"
      generated_key="${trust_root}/.codex/supervisor-authority/key"
    else
      allowed_signers="$base/allowed_signers"
      generated_key="$base/key"
    fi
  fi
  if [[ -z "$generated_key" ]]; then
    generated_key="$base/key"
  fi

  if [[ ! -f "$generated_key" || ! -f "$allowed_signers" ]]; then
    ssh-keygen -t ed25519 -N "" -f "$generated_key" >/dev/null 2>&1
    printf 'supervisor-approver %s\n' "$(cat "${generated_key}.pub")" > "$allowed_signers"
  fi

  local key="$generated_key"

  manifest_hash="$(file_hash "$manifest")"
  entrypoint_hash="$(file_hash "$SYNC_SCRIPT")"
  signers_hash="$(file_hash "$allowed_signers")"

  if [[ -z "$mode_clause" && -n "$mode" ]]; then
    mode_clause=",\"mode\": \"${mode}\""
  fi

  printf '%s\n' "{\"kind\": \"supervisor.action-authorization/v1\", \"namespace\": \"${namespace}\", \"principal\": \"${principal}\", \"frozen_action_digest\": \"${manifest_hash}\", \"entrypoint_sha\": \"${entrypoint_hash}\", \"allowed_signers_digest\": \"${signers_hash}\"${mode_clause}${root_clause}, \"timestamp\": \"2026-08-02T21:00:00Z\"}" > "$action_file"

  ssh-keygen -Y sign -f "$key" -n "$namespace" -I "$principal" "$action_file" >/dev/null 2>&1
  printf '%s %s %s\n' "$action_file" "$signature_file" "$allowed_signers"
}

assert_role_contract() {
  local report="$1"
  python3 - "$report" "$manifest_target_count" "$manifest_expected_sections" <<'PY'
import json
import sys

report_path, expected_count, expected_sections = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
obj = json.load(open(report_path, encoding='utf-8'))
targets = obj['targets']

if len(targets) != expected_count:
    print(f'FAIL: target count {len(targets)} != expected {expected_count}')
    sys.exit(1)

ids = [t['id'] for t in targets]
if len(set(ids)) != len(ids):
    print('FAIL: target IDs not unique')
    sys.exit(1)

tool_counts = {}
section_failures = []
by_tool_paths = {}
for t in targets:
  if int(t.get('sourceSectionCount', -1)) != expected_sections or int(t.get('sourceRoleCount', -1)) != expected_sections:
    section_failures.append(t['id'])
    continue

  tool = t.get('tool', '')
  tool_counts[tool] = tool_counts.get(tool, 0) + 1
  by_tool_paths.setdefault(tool, []).append(t.get('targetPath', ''))

  if tool in ('aider', 'windsurf'):
    if t.get('kind') != 'file':
      print(f"FAIL: {tool} expected file kind, got {t.get('kind')}")
      sys.exit(1)
  elif t.get('kind') != 'directory':
    print(f"FAIL: {tool} expected directory kind, got {t.get('kind')}")
    sys.exit(1)

if section_failures:
  print(f"FAIL: non-canonical role count in {', '.join(section_failures)}")
  sys.exit(1)

if len(by_tool_paths.get('copilot', [])) != 2:
  print(f"FAIL: copilot target count {len(by_tool_paths.get('copilot', []))} != 2")
  sys.exit(1)

if len(by_tool_paths.get('vibe', [])) != 2:
  print(f"FAIL: vibe target count {len(by_tool_paths.get('vibe', []))} != 2")
  sys.exit(1)

if len(by_tool_paths.get('openclaw', [])) != 1:
  print(f"FAIL: openclaw target count {len(by_tool_paths.get('openclaw', []))} != 1")
  sys.exit(1)
if any(path.endswith('/.openclaw/agents/main') for path in by_tool_paths.get('openclaw', [])):
  print('FAIL: openclaw target points into protected owner path')
  sys.exit(1)

for tool_name in ('aider', 'windsurf', 'copilot', 'vibe', 'openclaw', 'kimi', 'qwen'):
  if tool_counts.get(tool_name, 0) == 0 and tool_name in ('copilot', 'vibe'):
    print(f'FAIL: {tool_name} missing target')
    sys.exit(1)

print('ok')
PY
}

TOTAL=0
PASS=0
FAIL=0

run_case() {
  local label="$1"
  local expect_rc="$2"
  shift 2

  TOTAL=$((TOTAL + 1))
  printf '[RUN] %s\n' "$label"

  local rc=0
  if "$@"; then
    rc=0
  else
    rc=$?
  fi

  if [[ "$rc" == "$expect_rc" ]]; then
    echo "[PASS] $label"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $label (rc=$rc, expect=$expect_rc)"
    FAIL=$((FAIL + 1))
  fi
}

case_dry_run() {
  local home report
  home="$(fixture_case_home)"
  local report_file
  local source_root_dir
  source_root_dir="$(fixture_source_copy "$home")"
  report_file="$(mktemp)"

  if ! HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --dry-run --manifest "$MANIFEST_PATH" --source-root "$source_root_dir" --project "$home" >"$report_file"; then
    return 1
  fi

  assert_counts "$report_file" || return 1
  if [[ "$(json_get "$report_file" result.status)" != "passed" ]]; then
    echo "FAIL: dry-run not passed"
    return 1
  fi

  local probe
  local pre post
  probe="$(mktemp)"
  collect_probe_paths "$home" "$home" "$probe"
  sort -u "$probe" -o "$probe"
  pre="$(mktemp)"
  post="$(mktemp)"
  snapshot_paths "$probe" "$pre"

  if ! HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --dry-run --manifest "$MANIFEST_PATH" --source-root "$source_root_dir" --project "$home" >"$report_file"; then
    rm -f "$probe" "$pre" "$post" "$home" "$report_file"
    return 1
  fi

  snapshot_paths "$probe" "$post"
  local changed
  changed="$(mktemp)"
  if ! snapshot_diff_paths "$pre" "$post" "$changed"; then
    echo "FAIL: dry-run touched probe paths"
    echo "Touched paths:"
    if [[ -s "$changed" ]]; then
      cat "$changed"
    fi
    rm -f "$probe" "$pre" "$post" "$changed" "$home" "$report_file"
    return 1
  fi
  rm -f "$changed"
  if ! snapshot_diff_clean "$pre" "$post"; then
    echo "FAIL: dry-run metadata compare mismatch"
    rm -f "$probe" "$pre" "$post" "$home" "$report_file"
    return 1
  fi

  rm -rf "$probe" "$pre" "$post" "$home" "$report_file"
  return 0
}

case_apply_success_and_protections() {
  local home report
  home="$(fixture_case_home)"
  local report_file
  local source_root_dir
  local evidence_root="$home/.codex/supervisor-runtime-evidence"
  local evidence_signers="$evidence_root/allowed_signers"
  local evidence_ledger="$evidence_root/owner-only-ledger.jsonl"
  source_root_dir="$(fixture_source_copy "$home")"
  report_file="$(mktemp)"

  clear_qwen_kimi_targets "$home"
  read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" aicc-supervisor-authorization supervisor-approver "$home/action.json" "$MANIFEST_PATH" "$evidence_signers" "isolated-test" "$home" "$home")

  mkdir -p "${home}/.openclaw/agents/main/agent"
  echo secret > "${home}/.openclaw/agents/main/agent/auth-profiles.json"
  chmod 000 "${home}/.openclaw/agents/main/agent/auth-profiles.json"

  mkdir -p "$home/.vibe/agents-ext" "$home/.vibe/prompts-ext"
  ln -snf "$home/.vibe/agents-ext" "$home/.vibe/agents"
  ln -snf "$home/.vibe/prompts-ext" "$home/.vibe/prompts"

  local probe_list
  local before_meta
  local after_meta
  probe_list="$(mktemp)"
  collect_probe_paths "$home" "$home" "$probe_list"
  sort -u "$probe_list" -o "$probe_list"
  before_meta="$(mktemp)"
  after_meta="$(mktemp)"
  snapshot_paths "$probe_list" "$before_meta"

  local pre_auth
  pre_auth=$(stat -f '%i|%p|%z|%m' "${home}/.openclaw/agents/main/agent/auth-profiles.json")

  if ! HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$MANIFEST_PATH" --source-root "$source_root_dir" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report_file"; then
    chmod 600 "${home}/.openclaw/agents/main/agent/auth-profiles.json" 2>/dev/null || true
    rm -rf "$home" "$report_file" "$probe_list" "$before_meta" "$after_meta"
    return 1
  fi

  if [[ "$(json_get "$report_file" result.status)" != "passed" ]]; then
    echo "FAIL: apply status not passed"
    return 1
  fi
  if [[ "$(json_get "$report_file" security.result)" != "passed" ]]; then
    echo "FAIL: security not passed"
    return 1
  fi

  local qwen_manifest
  local kimi_manifest
  local raw_qwen
  local raw_kimi
  qwen_manifest="$(json_get "$report_file" mapping.qwen.manifestPath)"
  kimi_manifest="$(json_get "$report_file" mapping.kimi.manifestPath)"

  raw_qwen="$(jq -r '.tools[] | select(.installTool=="qwen") | .targets[0].targetPath // empty' "$MANIFEST_PATH")"
  raw_kimi="$(jq -r '.tools[] | select(.installTool=="kimi") | .targets[0].targetPath // empty' "$MANIFEST_PATH")"
  if [[ "$qwen_manifest" != "$(resolve_manifest_path "$raw_qwen" "$home" "$home")" ]]; then
    echo "FAIL: qwen manifest path mismatch"
    rm -rf "$home" "$report_file" "$probe_list" "$before_meta" "$after_meta"
    return 1
  fi
  if [[ "$kimi_manifest" != "$(resolve_manifest_path "$raw_kimi" "$home" "$home")" ]]; then
    echo "FAIL: kimi manifest path mismatch"
    rm -rf "$home" "$report_file" "$probe_list" "$before_meta" "$after_meta"
    return 1
  fi

  if [[ ! -d "$qwen_manifest" || ! -d "$kimi_manifest" ]]; then
    echo "FAIL: qwen/kimi paths missing"
    return 1
  fi

  local post_auth
  post_auth=$(stat -f '%i|%p|%z|%m' "${home}/.openclaw/agents/main/agent/auth-profiles.json")
  if [[ "$pre_auth" != "$post_auth" ]]; then
    echo "FAIL: auth profile file metadata changed"
    return 1
  fi

  snapshot_paths "$probe_list" "$after_meta"
  local changed_paths
  changed_paths="$(mktemp)"
  if ! snapshot_diff_paths "$before_meta" "$after_meta" "$changed_paths"; then
    local touched_protected=0
    while IFS= read -r path; do
      case "$path" in
        "$home/.openclaw/agents/main"|"$home/.openclaw/agents/main/agent/auth-profiles.json"|"$home/.vibe/agents"|"$home/.vibe/prompts")
          touched_protected=1
          ;;
      esac
    done < "$changed_paths"
    if [[ "$touched_protected" -eq 1 ]]; then
      echo "FAIL: auth/vibe protected path touched"
      echo "Touched protected paths:"
      if [[ -s "$changed_paths" ]]; then
        cat "$changed_paths"
      fi
      chmod 600 "${home}/.openclaw/agents/main/agent/auth-profiles.json" 2>/dev/null || true
      rm -rf "$home" "$report_file" "$probe_list" "$before_meta" "$after_meta" "$changed_paths"
      return 1
    fi
  fi
  rm -f "$changed_paths"

  if [[ "$(readlink "$home/.vibe/agents")" != "$home/.vibe/agents-ext" ]]; then
    echo "FAIL: vibe agents symlink changed"
    return 1
  fi
  if [[ "$(readlink "$home/.vibe/prompts")" != "$home/.vibe/prompts-ext" ]]; then
    echo "FAIL: vibe prompts symlink changed"
    return 1
  fi

  assert_role_contract "$report_file" || return 1

  chmod 600 "${home}/.openclaw/agents/main/agent/auth-profiles.json" 2>/dev/null || true
  rm -rf "$home" "$report_file" "$probe_list" "$before_meta" "$after_meta"
  return 0
}

case_missing_qwen_kimi_targets() {
  local home report
  home="$(fixture_case_home)"
  local report_file
  local source_root_dir
  local evidence_root="$home/.codex/supervisor-runtime-evidence"
  local evidence_signers="$evidence_root/allowed_signers"
  local evidence_ledger="$evidence_root/owner-only-ledger.jsonl"
  source_root_dir="$(fixture_source_copy "$home")"

  rm -rf "$home/.qwen" "$home/.config/kimi"
  clear_qwen_kimi_targets "$home"

  read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" aicc-supervisor-authorization supervisor-approver "$home/action.json" "$MANIFEST_PATH" "$evidence_signers" "isolated-test" "$home" "$home")

  report_file="$(mktemp)"
  clear_qwen_kimi_targets "$home"

  if ! HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$MANIFEST_PATH" --source-root "$source_root_dir" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report_file"; then
    rm -rf "$home" "$report_file"
    return 1
  fi

  if [[ ! -d "$home/.qwen/agents" || ! -d "$home/.config/kimi/agents" ]]; then
    echo "FAIL: qwen/kimi dirs not created when target roots absent"
    rm -rf "$home" "$report_file"
    return 1
  fi

  rm -rf "$home" "$report_file"
  return 0
}

case_missing_qwen_or_kimi_source_is_blocked() {
  local missing_source="$1"
  local home report
  home="$(fixture_case_home)"
  local report_file
  local source_root_dir="$home/source"
  local evidence_root="$home/.codex/supervisor-runtime-evidence"
  local evidence_signers="$evidence_root/allowed_signers"
  local evidence_ledger="$evidence_root/owner-only-ledger.jsonl"
  source_root_dir="$(fixture_source_copy "$home")"
  rm -rf "$source_root_dir/$missing_source"

  read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" aicc-supervisor-authorization supervisor-approver "$home/action.json" "$MANIFEST_PATH" "$evidence_signers" "isolated-test" "$home" "$home")

  report_file="$(mktemp)"
  if HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$MANIFEST_PATH" --source-root "$source_root_dir" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report_file"; then
    echo "FAIL: missing ${missing_source} source should be BLOCK"
    rm -rf "$home" "$report_file"
    return 1
  fi

  rm -rf "$home" "$report_file"
  return 0
}

case_replay_rejected() {
  local home report
  home="$(fixture_case_home)"
  local report1 report2
  local evidence_root="$home/.codex/supervisor-runtime-evidence"
  local evidence_signers="$evidence_root/allowed_signers"
  local evidence_ledger="$evidence_root/owner-only-ledger.jsonl"
  local src_root="$home/source"
  report1=$(mktemp)
  report2=$(mktemp)

  src_root="$(fixture_source_copy "$home")"
  clear_qwen_kimi_targets "$home"
  read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" aicc-supervisor-authorization supervisor-approver "$home/action.json" "$MANIFEST_PATH" "$evidence_signers" "isolated-test" "$home" "$home")

  if ! HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$MANIFEST_PATH" --source-root "$src_root" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report1"; then
    rm -rf "$home" "$report1" "$report2"
    return 1
  fi

  if HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$MANIFEST_PATH" --source-root "$src_root" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report2"; then
    echo "FAIL: replay should fail"
    rm -rf "$home" "$report1" "$report2"
    return 1
  fi

  rm -rf "$home" "$report1" "$report2"
  return 0
}

case_bad_namespace_or_principal() {
  local ns="$1"
  local principal="$2"

  local home report
  home="$(fixture_case_home)"
  local evidence_root="$home/.codex/supervisor-runtime-evidence"
  local evidence_signers="$evidence_root/allowed_signers"
  local evidence_ledger="$evidence_root/owner-only-ledger.jsonl"
  local src_root="$home/source"
  report="$(mktemp)"

  src_root="$(fixture_source_copy "$home")"
  read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" "$ns" "$principal" "$home/action.json" "$MANIFEST_PATH" "$evidence_signers" "isolated-test" "$home" "$home")

  if HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$MANIFEST_PATH" --source-root "$src_root" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report"; then
    rm -rf "$home" "$report"
    return 1
  fi

  rm -rf "$home" "$report"
  return 0
}

case_wrong_namespace() {
  case_bad_namespace_or_principal wrong-namespace supervisor-approver
}

case_wrong_principal() {
  case_bad_namespace_or_principal aicc-supervisor-authorization wrong-principal
}

case_owner_symlink_block() {
  local home report
  home="$(fixture_case_home)"
  local evidence_root="$home/.codex/supervisor-runtime-evidence"
  local evidence_signers="$evidence_root/allowed_signers"
  local evidence_ledger="$evidence_root/owner-only-ledger.jsonl"
  local src_root="$home/source"
  report="$(mktemp)"

  mkdir -p "$home/.openclaw"
  ln -snf "$home/.openclaw/main-owner-target" "$home/.openclaw/agency-agents"

  src_root="$(fixture_source_copy "$home")"
  read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" aicc-supervisor-authorization supervisor-approver "$home/action.json" "$MANIFEST_PATH" "$evidence_signers" "isolated-test" "$home" "$home")

  if HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$MANIFEST_PATH" --source-root "$src_root" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report"; then
    rm -rf "$home" "$report"
    return 1
  fi

  rm -rf "$home" "$report"
  return 0
}

case_rollback_on_failure() {
  local home report
  home="$(fixture_case_home)"
  local evidence_root="$home/.codex/supervisor-runtime-evidence"
  local evidence_signers="$evidence_root/allowed_signers"
  local evidence_ledger="$evidence_root/owner-only-ledger.jsonl"
  local src_root="$home/source"
  local report_file
  report_file="$(mktemp)"

  mkdir -p "$home/.claude/agents"
  printf 'pre' > "$home/.claude/agents/rollback.txt"

  src_root="$(fixture_source_copy "$home")"
  clear_qwen_kimi_targets "$home"

  read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" aicc-supervisor-authorization supervisor-approver "$home/action.json" "$MANIFEST_PATH" "$evidence_signers" "isolated-test" "$home" "$home")

  if INJECT_FAIL_TOOL=kimi HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$MANIFEST_PATH" --source-root "$src_root" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report_file"; then
    rm -rf "$home" "$report_file"
    return 1
  fi

  if [[ ! -f "$home/.claude/agents/rollback.txt" ]]; then
    echo "FAIL: rollback did not restore existing file"
    rm -rf "$home" "$report_file"
    return 1
  fi

  if [[ "$(cat "$home/.claude/agents/rollback.txt")" != "pre" ]]; then
    echo "FAIL: rollback changed existing file"
    rm -rf "$home" "$report_file"
    return 1
  fi

  if [[ "$(json_get "$report_file" result.status)" != "failed" ]]; then
    echo "FAIL: failure case status not failed"
    rm -rf "$home" "$report_file"
    return 1
  fi

  rollback_performed="$(json_get "$report_file" rollback.performed)"
  if [[ "$rollback_performed" != "true" && "$rollback_performed" != "True" ]]; then
    echo "FAIL: rollback flag false"
    rm -rf "$home" "$report_file"
    return 1
  fi

  rm -rf "$home" "$report_file"
  return 0
}

