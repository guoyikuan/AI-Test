#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SYNC_SCRIPT="${REPO_ROOT}/local-deployment/sync-all-local.sh"
MANIFEST_PATH="${REPO_ROOT}/local-deployment/frozen-action-manifest.json"
SOURCE_ROOT="${REPO_ROOT}/integrations"
FIXTURE_ROOT=""
CANONICAL_SOURCE=""
CANONICAL_FIXTURE_REPO=""
CANONICAL_ROLE_PROFILE_SOURCE="${REPO_ROOT}/governance/role-governance-profiles.json"
CANONICAL_REPO_MANIFEST="${REPO_ROOT}/local-deployment/frozen-action-manifest.json"

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
with open(sys.argv[1], "r", encoding="utf-8") as fp:
    obj = json.load(fp)
if not isinstance(obj, dict):
    raise SystemExit(f"report root is not an object: {sys.argv[1]}")

parts=[p for p in sys.argv[2].split('.') if p]
cur=obj
for p in parts:
    if '[' in p and p.endswith(']'):
        key,idx=p[:-1].split('[',1)
        if not isinstance(cur, dict):
            raise SystemExit(f"non-object before {key}")
        cur=cur[key][int(idx)]
    else:
        if not isinstance(cur, dict):
            raise SystemExit(f"non-object before {p}")
        cur=cur[p]
if isinstance(cur, (dict, list)):
    print(json.dumps(cur, ensure_ascii=False, separators=(",", ":")))
else:
    print(cur)
PY
}

extract_report_json() {
  local file="$1"
  local out="$2"
  local temp_out

  [[ "$file" != "$out" ]] || return 1
  temp_out="$(mktemp "${out}.extract.XXXXXX")" || return 1
  if ! python3 - "$file" <<'PY' > "$temp_out"
import json
import sys

raw = open(sys.argv[1], encoding="utf-8", errors="ignore").read()
decoder = json.JSONDecoder()
matches = []
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
    if isinstance(parsed, dict) and parsed.get("schema") == "agency-agents.local-sync-report/v1":
        matches.append(parsed)
    idx = end

if len(matches) != 1:
    raise SystemExit(f"expected one local sync report, found {len(matches)}")

print(json.dumps(matches[0], ensure_ascii=False, separators=(",", ":")), end="")
PY
  then
    rm -f "$temp_out"
    return 1
  fi
  if ! python3 - "$temp_out" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fp:
    obj = json.load(fp)
if not isinstance(obj, dict) or obj.get("schema") != "agency-agents.local-sync-report/v1":
    raise SystemExit(1)
PY
  then
    rm -f "$temp_out"
    return 1
  fi
  mv -f "$temp_out" "$out"
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

compute_fixture_source_root_digest() {
  local source_root="$1"

  python3 - "$source_root" <<'PY'
import hashlib
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
if not root.is_dir():
    print('')
    sys.exit(1)

items = []
for dirpath, dirnames, filenames in os.walk(root):
    dirpath_obj = pathlib.Path(dirpath)
    dirnames.sort()
    filenames.sort()

    rel = dirpath_obj.relative_to(root).as_posix()
    if rel != '.':
        items.append(('dir', rel, ''))

    for name in dirnames:
        full = dirpath_obj / name
        items.append(('dir-entry', full.relative_to(root).as_posix(), ''))

    for name in filenames:
        full = dirpath_obj / name
        rel_path = full.relative_to(root).as_posix()
        st = full.lstat()
        if os.path.islink(full):
            items.append(('symlink', rel_path, os.readlink(full)))
            continue
        if os.path.isdir(full):
            items.append(('file-dir', rel_path, str(int(st.st_mode & 0o7777))))
            continue
        with open(full, 'rb') as fp:
            digest = hashlib.sha256(fp.read()).hexdigest()
        items.append(('file', rel_path, f"{st.st_size}:{int(st.st_mode & 0o7777)}:{digest}"))

items.sort()
digest = hashlib.sha256()
for kind, path, meta in items:
    digest.update(f"{kind}|{path}|{meta}\n".encode('utf-8'))
print(digest.hexdigest())
PY
}

refresh_fixture_source_root_digest() {
  local manifest_path="$1"
  local source_root="$2"
  local digest
  local temp_path

  digest="$(compute_fixture_source_root_digest "$source_root")" || return 1
  [[ -n "$digest" ]] || return 1
  temp_path="$(mktemp "${manifest_path}.source-root-digest.XXXXXX")" || return 1

  if ! jq --arg digest "$digest" '.sourceRootDigest = $digest' "$manifest_path" > "$temp_path"; then
    rm -f "$temp_path"
    return 1
  fi
  if ! jq -e . "$temp_path" >/dev/null; then
    rm -f "$temp_path"
    return 1
  fi
  mv -f "$temp_path" "$manifest_path"
}

refresh_fixture_entry_sha() {
  local manifest_path="$1"
  local entry_sha
  local temp_path

  entry_sha="$(shasum -a 256 "$SYNC_SCRIPT" | awk '{print $1}')" || return 1
  [[ "$entry_sha" =~ ^[0-9a-f]{64}$ ]] || return 1
  temp_path="$(mktemp "${manifest_path}.entry-sha.XXXXXX")" || return 1

  if ! jq --arg entry_sha "$entry_sha" '.entrySha256 = $entry_sha' "$manifest_path" > "$temp_path"; then
    rm -f "$temp_path"
    return 1
  fi
  if ! jq -e . "$temp_path" >/dev/null; then
    rm -f "$temp_path"
    return 1
  fi
  mv -f "$temp_path" "$manifest_path"
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

  CANONICAL_FIXTURE_REPO="$FIXTURE_ROOT/repo"
  mkdir -p "$CANONICAL_FIXTURE_REPO/local-deployment" "$CANONICAL_FIXTURE_REPO/governance"
  cp "$CANONICAL_REPO_MANIFEST" "$CANONICAL_FIXTURE_REPO/local-deployment/frozen-action-manifest.json"
  cp "$CANONICAL_ROLE_PROFILE_SOURCE" "$CANONICAL_FIXTURE_REPO/governance/role-governance-profiles.json"
  mkdir -p "$CANONICAL_FIXTURE_REPO/local-deployment/integrations"
  cp -R "${CANONICAL_SOURCE}/." "$CANONICAL_FIXTURE_REPO/local-deployment/integrations/"

  if ! seed_qwen_kimi_sources "$CANONICAL_SOURCE"; then
    return 1
  fi
}

ensure_fixture_codex_root() {
  local test_home="$1"
  python3 - "$test_home" <<'PY'
import os
import stat
import sys

root_path = sys.argv[1]
root_fd = None
codex_fd = None

def fail(code):
    print(code, file=sys.stderr)
    raise SystemExit(1)

def require_directory(st, code):
    if not stat.S_ISDIR(st.st_mode):
        fail(code)
    if st.st_uid != os.getuid():
        fail(code)
    if stat.S_IMODE(st.st_mode) != 0o700:
        fail(code)

try:
    flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0)
    root_fd = os.open(root_path, flags)
    require_directory(os.fstat(root_fd), "fixture-test-home-invalid")
    os.dup2(root_fd, 9)
    if root_fd != 9:
        os.close(root_fd)
        root_fd = None
    try:
        before = os.stat(".codex", dir_fd=9, follow_symlinks=False)
    except FileNotFoundError:
        os.mkdir(".codex", 0o700, dir_fd=9)
        before = os.stat(".codex", dir_fd=9, follow_symlinks=False)
    except OSError:
        fail("fixture-codex-root-invalid")
    require_directory(before, "fixture-codex-root-invalid")
    codex_fd = os.open(".codex", flags, dir_fd=9)
    after = os.fstat(codex_fd)
    require_directory(after, "fixture-codex-root-invalid")
    if (before.st_dev, before.st_ino, before.st_uid, stat.S_IMODE(before.st_mode)) != (
        after.st_dev,
        after.st_ino,
        after.st_uid,
        stat.S_IMODE(after.st_mode),
    ):
        fail("fixture-codex-root-invalid")
finally:
    for fd in (codex_fd, root_fd):
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass
    try:
        os.close(9)
    except OSError:
        pass
PY
}

fixture_case_home() {
  local home
  home="$(mktemp -d "$FIXTURE_ROOT/home.XXXXXX")"
  home="$(physical_root "$home")"
  ensure_fixture_codex_root "$home" || return 1
  printf '%s\n' "$home"
}

fixture_source_copy() {
  local home="$1"
  local src
  local fixture_repo
  local fixture_manifest

  fixture_repo="$home/repo"
  if [[ "${CANONICAL_FIXTURE_REPO:-}" != "$fixture_repo" ]]; then
    rm -rf "$fixture_repo"
    cp -R "${CANONICAL_FIXTURE_REPO}/." "$fixture_repo/"
  elif [[ ! -d "$fixture_repo/local-deployment/integrations" ]]; then
    return 1
  fi
  src="$fixture_repo/local-deployment/integrations"
  if [[ ! -d "$src" ]]; then
    mkdir -p "$src"
    cp -R "${CANONICAL_SOURCE}/." "$src/"
  fi
  fixture_manifest="$fixture_repo/local-deployment/frozen-action-manifest.json"
  [[ -f "$fixture_manifest" ]] || return 1
  refresh_fixture_entry_sha "$fixture_manifest" || return 1
  printf '%s\n' "$src"
}

fixture_manifest_path() {
  local home="$1"
  printf '%s\n' "$home/repo/local-deployment/frozen-action-manifest.json"
}

reorder_post_mutation_fault_manifest() {
  local isolated_manifest="$1"
  local original_manifest transformed_manifest production_sha_before production_sha_after

  [[ -f "$isolated_manifest" ]] || return 1
  original_manifest="$(mktemp "${isolated_manifest}.before.XXXXXX")" || return 1
  transformed_manifest="$(mktemp "${isolated_manifest}.after.XXXXXX")" || return 1
  cp "$isolated_manifest" "$original_manifest"
  production_sha_before="$(shasum -a 256 "$CANONICAL_REPO_MANIFEST" | awk '{print $1}')"
  if ! jq '.tools as $tools | .tools = ([$tools[] | select(.installTool == "aider")] + [$tools[] | select(.installTool == "kimi")] + [$tools[] | select(.installTool != "aider" and .installTool != "kimi")])' "$original_manifest" > "$transformed_manifest"; then
    return 1
  fi
  if ! python3 - "$original_manifest" "$transformed_manifest" <<'PY'
import json
import sys

before = json.load(open(sys.argv[1], encoding="utf-8"))
after = json.load(open(sys.argv[2], encoding="utf-8"))

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))

before_without_tools = {key: value for key, value in before.items() if key != "tools"}
after_without_tools = {key: value for key, value in after.items() if key != "tools"}
if canonical(before_without_tools) != canonical(after_without_tools):
    raise SystemExit("fault fixture changed non-tool manifest fields")
if sorted(canonical(tool) for tool in before.get("tools", [])) != sorted(canonical(tool) for tool in after.get("tools", [])):
    raise SystemExit("fault fixture changed tool or target semantics")

targets = []
for tool in after.get("tools", []):
    install_tool = tool.get("installTool", "")
    for target in tool.get("targets", []):
        targets.append((install_tool, target.get("targetPath", ""), target))
if len(targets) != 18 or len({(tool, path) for tool, path, _ in targets}) != 18:
    raise SystemExit("fault fixture target count or identity mismatch")
if len(after.get("tools", [])) < 2 or after["tools"][0].get("installTool") != "aider" or after["tools"][1].get("installTool") != "kimi":
    raise SystemExit("fault fixture kimi position mismatch")
if sum(tool.get("installTool") == "kimi" for tool in after["tools"]) != 1:
    raise SystemExit("fault fixture kimi multiplicity mismatch")
PY
  then
    return 1
  fi
  mv "$transformed_manifest" "$isolated_manifest"
  production_sha_after="$(shasum -a 256 "$CANONICAL_REPO_MANIFEST" | awk '{print $1}')"
  [[ "$production_sha_before" == "$production_sha_after" ]] || return 1
  FAULT_FIXTURE_MANIFEST_SHA="$(shasum -a 256 "$isolated_manifest" | awk '{print $1}')"
  [[ "$FAULT_FIXTURE_MANIFEST_SHA" =~ ^[a-f0-9]{64}$ ]]
}

clear_qwen_kimi_targets() {
  local home="$1"
  rm -rf "${home}/.qwen" "${home}/.config/kimi"
}

prepare_installed_manifest_targets() {
  local home="$1"
  local project="$2"
  local manifest_path="$3"
  local targets
  local target
  local kind
  local create_if_missing
  local resolved

  ensure_fixture_codex_root "$home" || return 1
  targets="$(mktemp)"
  jq -r '.tools[].targets[] | [ .targetPath, (.kind // "directory"), ((.createIfMissing // false) | tostring) ] | @tsv' "$manifest_path" > "$targets"
  while IFS=$'\t' read -r target kind create_if_missing; do
    [[ -z "$target" ]] && continue
    resolved="$(resolve_manifest_path "$target" "$home" "$project")"

    if [[ "$create_if_missing" == "true" ]]; then
      rm -rf "$resolved"
      continue
    fi

    mkdir -p "$(dirname "$resolved")"
    rm -rf "$resolved"
    if [[ "$kind" == "file" ]]; then
      printf 'stale file target fixture\n' > "$resolved"
    else
      mkdir -p "$resolved"
      printf 'stale directory target fixture\n' > "${resolved}/.stale-installed"
    fi
  done < "$targets"
  rm -f "$targets"
}

assert_manifest_targets_present() {
  local home="$1"
  local project="$2"
  local manifest_path="$3"
  local missing_ids=()
  local target
  local kind
  local create_if_missing
  local resolved
  local id
  local targets

  targets="$(mktemp)"
  jq -r '.tools[] as $tool | $tool.targets[] | [ ($tool.installTool // $tool.tool // "unknown"), .targetPath, (.kind // "directory"), ((.createIfMissing // false) | tostring) ] | @tsv' "$manifest_path" > "$targets"
  while IFS=$'\t' read -r tool target kind create_if_missing; do
    [[ -z "$target" ]] && continue
    resolved="$(resolve_manifest_path "$target" "$home" "$project")"
    id="${tool}:${target}"

    if [[ "$create_if_missing" == "true" ]]; then
      continue
    fi

    if [[ "$kind" == "file" ]]; then
      if [[ ! -f "$resolved" ]]; then
        missing_ids+=("$id")
      fi
    elif [[ ! -d "$resolved" ]]; then
      missing_ids+=("$id")
    fi
  done < "$targets"
  rm -f "$targets"

  if [[ "${#missing_ids[@]}" -gt 0 ]]; then
    printf '%s\n' "${missing_ids[@]}"
    return 1
  fi
}

collect_probe_paths() {
  local home="$1"
  local project="$2"
  local out="$3"
  local manifest_path="${4:-$MANIFEST_PATH}"
  local list
  list=$(mktemp)

  jq -r '.tools[].targets[].targetPath // empty' "$manifest_path" > "$list"
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

snapshot_paths_with_digest() {
  local list="$1"
  local out="$2"
  python3 - "$list" > "$out" <<'PY'
import hashlib
import json
import os
import re
import stat
import sys

def path_digest(path):
  if not os.path.lexists(path):
    return {"exists": False}

  st = os.lstat(path)
  mode = oct(st.st_mode & 0o7777)

  if stat.S_ISLNK(st.st_mode):
    return {
      "exists": True,
      "type": "symlink",
      "mode": mode,
      "size": st.st_size,
      "link": os.readlink(path),
    }

  if stat.S_ISREG(st.st_mode):
    h = hashlib.sha256()
    with open(path, "rb") as fp:
      while True:
        chunk = fp.read(1024 * 1024)
        if not chunk:
          break
        h.update(chunk)
    return {
      "exists": True,
      "type": "file",
      "mode": mode,
      "size": st.st_size,
      "digest": h.hexdigest(),
    }

  if not stat.S_ISDIR(st.st_mode):
    return {
      "exists": True,
      "type": "other",
      "mode": mode,
      "size": st.st_size,
    }

  h = hashlib.sha256()
  for dirpath, dirnames, filenames in os.walk(path):
    dirnames.sort()
    filenames.sort()
    rel = os.path.relpath(dirpath, path)
    for dname in dirnames:
      child = os.path.join(dirpath, dname)
      cst = os.lstat(child)
      rel_child = os.path.join(rel, dname)
      h.update(f"DIR:{rel_child}:{oct(cst.st_mode & 0o7777)}:{cst.st_size}\n".encode())
    for fname in filenames:
      child = os.path.join(dirpath, fname)
      cst = os.lstat(child)
      rel_child = os.path.join(rel, fname)
      if stat.S_ISLNK(cst.st_mode):
        h.update(f"LINK:{rel_child}:{os.readlink(child)}\n".encode())
      else:
        h.update(f"FILE:{rel_child}:{oct(cst.st_mode & 0o7777)}:{cst.st_size}\n".encode())
        if stat.S_ISREG(cst.st_mode):
          with open(child, "rb") as fp:
            while True:
              chunk = fp.read(1024 * 1024)
              if not chunk:
                break
              h.update(chunk)
  return {
    "exists": True,
    "type": "directory",
    "mode": mode,
    "size": st.st_size,
    "digest": h.hexdigest(),
  }

paths = [line.strip() for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
state = {}
for path in paths:
  state[path] = path_digest(path)
print(json.dumps(state, sort_keys=True))
PY
}

snapshot_paths_descriptor_no_follow() {
  if [[ "$#" -ne 3 ]]; then
    echo 'FAIL: descriptor snapshot requires trusted root, path list, and output' >&2
    return 64
  fi
  local trusted_root="$1"
  local list="$2"
  local out="$3"
  python3 - "$trusted_root" "$list" "$out" "${SYNC_SNAPSHOT_FD:-}" <<'PY'
import hashlib
import json
import os
import re
import stat
import sys

trusted_root, list_path, output_path, snapshot_fd_text = sys.argv[1:]
O_DIRECTORY = getattr(os, "O_DIRECTORY", 0)
O_NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
root_flags = os.O_RDONLY | O_DIRECTORY | O_NOFOLLOW
file_flags = os.O_RDONLY | O_NOFOLLOW

def kind_of(mode):
    if stat.S_ISREG(mode): return "file"
    if stat.S_ISDIR(mode): return "directory"
    if stat.S_ISLNK(mode): return "symlink"
    return "other"

def stable_digest(parent_fd, name, st):
    kind = kind_of(st.st_mode)
    if kind == "file":
        fd = os.open(name, file_flags, dir_fd=parent_fd)
        try:
            opened = os.fstat(fd)
            if (opened.st_dev, opened.st_ino, opened.st_mode, opened.st_size) != (st.st_dev, st.st_ino, st.st_mode, st.st_size):
                raise RuntimeError("file identity changed during descriptor open")
            digest = hashlib.sha256()
            while True:
                block = os.read(fd, 1024 * 1024)
                if not block: break
                digest.update(block)
            final = os.fstat(fd)
            if (final.st_dev, final.st_ino, final.st_mode, final.st_size, final.st_mtime_ns, final.st_ctime_ns) != (opened.st_dev, opened.st_ino, opened.st_mode, opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns):
                raise RuntimeError("file changed during descriptor read")
            return digest.hexdigest()
        finally:
            os.close(fd)
    if kind == "symlink":
        return hashlib.sha256(os.readlink(name, dir_fd=parent_fd).encode("utf-8", "surrogateescape")).hexdigest()
    if kind == "directory":
        fd = os.open(name, root_flags, dir_fd=parent_fd)
        try:
            opened = os.fstat(fd)
            if (opened.st_dev, opened.st_ino) != (st.st_dev, st.st_ino):
                raise RuntimeError("directory identity changed during descriptor open")
            rows = []
            for child in sorted(os.listdir(fd)):
                if not child or child in (".", "..") or "/" in child:
                    raise RuntimeError("unsafe directory entry")
                child_st = os.stat(child, dir_fd=fd, follow_symlinks=False)
                rows.append({
                    "name": child,
                    "type": kind_of(child_st.st_mode),
                    "inode": child_st.st_ino,
                    "mode": format(stat.S_IMODE(child_st.st_mode), "o"),
                    "size": child_st.st_size,
                    "digest": stable_digest(fd, child, child_st),
                })
            return hashlib.sha256(json.dumps(rows, separators=(",", ":"), sort_keys=True).encode("utf-8")).hexdigest()
        finally:
            os.close(fd)
    payload = f"{kind}:{stat.S_IMODE(st.st_mode):o}:{st.st_size}".encode("ascii")
    return hashlib.sha256(payload).hexdigest()

def capture(root_fd, relative):
    parts = [] if relative == "." else relative.split("/")
    if any(not part or part in (".", "..") for part in parts):
        raise RuntimeError("unsafe relative path")
    fd = os.dup(root_fd)
    try:
        for part in parts[:-1]:
            try:
                before = os.stat(part, dir_fd=fd, follow_symlinks=False)
            except FileNotFoundError:
                return {"exists": False}
            if stat.S_ISLNK(before.st_mode) or not stat.S_ISDIR(before.st_mode):
                raise RuntimeError("unsafe intermediate path")
            next_fd = os.open(part, root_flags, dir_fd=fd)
            after = os.fstat(next_fd)
            if (before.st_dev, before.st_ino) != (after.st_dev, after.st_ino):
                os.close(next_fd)
                raise RuntimeError("intermediate identity changed")
            os.close(fd)
            fd = next_fd
        if not parts:
            st = os.fstat(fd)
            return {"exists": True, "type": "directory", "inode": st.st_ino, "mode": format(stat.S_IMODE(st.st_mode), "o"), "size": st.st_size, "digest": "root"}
        name = parts[-1]
        try:
            st = os.stat(name, dir_fd=fd, follow_symlinks=False)
        except FileNotFoundError:
            return {"exists": False}
        return {
            "exists": True,
            "type": kind_of(st.st_mode),
            "inode": st.st_ino,
            "mode": format(stat.S_IMODE(st.st_mode), "o"),
            "size": st.st_size,
            "digest": stable_digest(fd, name, st),
        }
    finally:
        os.close(fd)

if snapshot_fd_text:
    if not snapshot_fd_text.isdigit():
        raise RuntimeError("invalid snapshot fd")
    root_fd = os.dup(int(snapshot_fd_text))
else:
    root_fd = os.open(trusted_root, root_flags)
try:
    root_st = os.fstat(root_fd)
    if not stat.S_ISDIR(root_st.st_mode) or root_st.st_uid != os.getuid() or stat.S_IMODE(root_st.st_mode) != 0o700:
        raise RuntimeError("trusted test root contract mismatch")
    normalized_root = os.path.normpath(trusted_root)
    state = {}
    with open(list_path, encoding="utf-8") as handle:
        paths = [line.rstrip("\n") for line in handle if line.rstrip("\n")]
    for path in paths:
        normalized_path = os.path.normpath(path)
        relative = os.path.relpath(normalized_path, normalized_root)
        if relative == ".." or relative.startswith("../") or os.path.isabs(relative):
            raise RuntimeError("snapshot path escapes trusted root")
        state[path] = capture(root_fd, relative)
finally:
    os.close(root_fd)
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(state, handle, separators=(",", ":"), sort_keys=True)
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

case_descriptor_snapshot_missing_semantics() {
  local root missing_list missing_out symlink_list symlink_out nondir_list nondir_out
  root="$(mktemp -d /tmp/agency-descriptor-verifier.XXXXXX)" || return 1
  chmod 700 "$root" || return 1
  missing_list="$root/missing.list"
  missing_out="$root/missing.json"
  symlink_list="$root/symlink.list"
  symlink_out="$root/symlink.json"
  nondir_list="$root/nondir.list"
  nondir_out="$root/nondir.json"

  printf '%s\n' "$root/missing-parent/leaf" >"$missing_list"
  if ! snapshot_paths_descriptor_no_follow "$root" "$missing_list" "$missing_out"; then
    echo 'FAIL: missing intermediate was not recorded as absent' >&2
    return 1
  fi
  if ! python3 - "$missing_out" "$root/missing-parent/leaf" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    state = json.load(handle)
raise SystemExit(0 if state == {sys.argv[2]: {"exists": False}} else 1)
PY
  then
    echo 'FAIL: missing intermediate absent record mismatch' >&2
    return 1
  fi

  mkdir "$root/symlink-target"
  ln -s "$root/symlink-target" "$root/symlink-parent"
  printf '%s\n' "$root/symlink-parent/leaf" >"$symlink_list"
  if snapshot_paths_descriptor_no_follow "$root" "$symlink_list" "$symlink_out" >/dev/null 2>&1; then
    echo 'FAIL: symlink intermediate was accepted as absent' >&2
    return 1
  fi

  printf 'not a directory\n' >"$root/plain-parent"
  printf '%s\n' "$root/plain-parent/leaf" >"$nondir_list"
  if snapshot_paths_descriptor_no_follow "$root" "$nondir_list" "$nondir_out" >/dev/null 2>&1; then
    echo 'FAIL: non-directory intermediate was accepted as absent' >&2
    return 1
  fi

  rm -rf "$root"
  echo 'DESCRIPTOR_VERIFIER_MISSING_SEMANTICS=PASS'
  return 0
}

snapshot_diff_paths() {
  if [[ "$#" -ne 3 ]]; then
    echo 'FAIL: snapshot_diff_paths requires exactly three arguments' >&2
    return 64
  fi
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

ensure_fixture_security_roots() {
  local test_root="$1"
  ensure_fixture_codex_root "$test_root" || return 1
  python3 - "$test_root" <<'PY'
import errno
import os
import stat
import sys

root_path = sys.argv[1]
root_fd = None
codex_fd = None
authority_fd = None
evidence_fd = None

def fail(code):
    print(code, file=sys.stderr)
    raise SystemExit(1)

def require_directory(st, code):
    if not stat.S_ISDIR(st.st_mode):
        fail(code)
    if st.st_uid != os.getuid():
        fail(code)
    if stat.S_IMODE(st.st_mode) != 0o700:
        fail(code)

def ensure_fixed_directory(parent_fd, leaf, code, create_missing):
    if leaf not in {".codex", "supervisor-authority", "supervisor-runtime-evidence"}:
        fail("fixture-security-root-leaf-invalid")
    try:
        before = os.stat(leaf, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        if not create_missing:
            fail(code)
        try:
            os.mkdir(leaf, 0o700, dir_fd=parent_fd)
        except OSError:
            fail(code)
        before = os.stat(leaf, dir_fd=parent_fd, follow_symlinks=False)
    except OSError:
        fail(code)
    require_directory(before, code)
    flags = os.O_RDONLY | os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        child_fd = os.open(leaf, flags, dir_fd=parent_fd)
    except OSError:
        fail(code)
    after = os.fstat(child_fd)
    require_directory(after, code)
    if (before.st_dev, before.st_ino, before.st_uid, stat.S_IMODE(before.st_mode)) != (
        after.st_dev,
        after.st_ino,
        after.st_uid,
        stat.S_IMODE(after.st_mode),
    ):
        os.close(child_fd)
        fail(code)
    return child_fd, after

try:
    flags = os.O_RDONLY | os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    root_fd = os.open(root_path, flags)
    root_st = os.fstat(root_fd)
    require_directory(root_st, "fixture-test-root-invalid")
    os.dup2(root_fd, 9)
    if root_fd != 9:
        os.close(root_fd)
        root_fd = None
    codex_fd, _ = ensure_fixed_directory(9, ".codex", "fixture-codex-root-invalid", False)
    authority_fd, authority_st = ensure_fixed_directory(
        codex_fd, "supervisor-authority", "fixture-authority-root-invalid", True
    )
    evidence_fd, evidence_st = ensure_fixed_directory(
        codex_fd, "supervisor-runtime-evidence", "fixture-evidence-root-invalid", True
    )
    if (authority_st.st_dev, authority_st.st_ino) == (evidence_st.st_dev, evidence_st.st_ino):
        fail("fixture-security-roots-not-disjoint")
finally:
    for fd in (evidence_fd, authority_fd, codex_fd, root_fd):
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass
    try:
        os.close(9)
    except OSError:
        pass
PY
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
  local source_root
  local source_root_count
  local source_root_digest
  local role_set_path
  local role_set_count
  local role_set_sha
  local role_set_file_sha
  local role_set_slug_digest

  local manifest_hash
  local entrypoint_hash
  local signers_hash
  local generated_key=""
  local ledger_path=""

  source_root="$(jq -r '.sourceRoot // ""' "$manifest")"
  if [[ -z "$source_root" ]]; then
    source_root="integrations"
  fi
  if [[ "$source_root" == /* ]]; then
    source_root="$(cd "$(dirname "$source_root")" && pwd -P)/$(basename "$source_root")"
  else
    if [[ "$source_root" == */* ]]; then
      source_root="$(cd "$(dirname "$manifest")" && cd "${source_root%/*}" && pwd -P)/$(basename "$source_root")"
    else
      source_root="$(cd "$(dirname "$manifest")" && pwd -P)/$source_root"
    fi
  fi
  source_root_count="$(jq -r '.sourceRoleCount // 0' "$manifest")"
  source_root_digest="$(jq -r '.sourceRootDigest // ""' "$manifest")"
  role_set_path="$(jq -r '.roleSetPath // ""' "$manifest")"
  role_set_count="$(jq -r '.roleSetCount // 0' "$manifest")"
  role_set_sha="$(jq -r '.roleSetSha256 // ""' "$manifest")"
  role_set_file_sha="$(jq -r '.roleSetFileSha256 // ""' "$manifest")"
  if [[ -n "$role_set_path" ]]; then
    if [[ "$role_set_path" == */* ]]; then
      role_set_path="$(cd "$(dirname "$manifest")" && cd "${role_set_path%/*}" && pwd -P)/$(basename "$role_set_path")"
    else
      role_set_path="$(cd "$(dirname "$manifest")" && pwd -P)/$role_set_path"
    fi
  fi
  if [[ -n "$role_set_path" && -f "$role_set_path" ]]; then
    role_set_slug_digest="$(python3 - "$role_set_path" <<'PY'
import hashlib
import json
import re
import sys

raw_path = sys.argv[1]
with open(raw_path, encoding="utf-8") as fp:
    rows = json.load(fp)

pat = re.compile(r"[^a-z0-9]+")
slugs = set()

for row in rows:
    if not isinstance(row, dict):
        continue
    role_name = str(row.get("role_name", ""))
    slug = role_name.strip().lower()
    slug = pat.sub("-", slug)
    slug = re.sub(r"-+", "-", slug).strip("-")
    if slug:
        slugs.add(slug)

print(hashlib.sha256("\n".join(sorted(slugs)).encode("utf-8")).hexdigest())
PY
)"
  fi

  if [[ "$mode" == "isolated-test" ]]; then
    if [[ -n "$trust_root" ]]; then
      trust_root="$(cd "$trust_root" && pwd -P)"
    fi
    if [[ -n "$test_root" ]]; then
      test_root="$(cd "$test_root" && pwd -P)"
    fi
    trust_root="$test_root"
    ensure_fixture_security_roots "$trust_root" || return 1
    ledger_path="${trust_root}/.codex/supervisor-authority/owner-only-ledger.jsonl"
  else
    if [[ -n "$trust_root" && -d "$trust_root" ]]; then
      ensure_fixture_security_roots "$trust_root" || return 1
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

  printf '%s\n' "{\"kind\": \"supervisor.action-authorization/v1\", \"namespace\": \"${namespace}\", \"principal\": \"${principal}\", \"frozen_action_digest\": \"${manifest_hash}\", \"entrypoint_sha\": \"${entrypoint_hash}\", \"allowed_signers_digest\": \"${signers_hash}\", \"source_root\": \"${source_root}\", \"source_root_count\": ${source_root_count}, \"source_root_digest\": \"${source_root_digest}\", \"role_set_path\": \"${role_set_path}\", \"role_set_count\": ${role_set_count}, \"role_set_sha256\": \"${role_set_sha}\", \"role_set_file_sha256\": \"${role_set_file_sha}\", \"role_name_slug_digest\": \"${role_set_slug_digest}\"${mode_clause}${root_clause}, \"timestamp\": \"2026-08-02T21:00:00Z\"}" > "$action_file"

  ssh-keygen -Y sign -f "$key" -n "$namespace" -I "$principal" "$action_file" >/dev/null 2>&1
  printf '%s %s %s\n' "$action_file" "$signature_file" "$allowed_signers"
}

assert_role_contract() {
  local report="$1"
  python3 - "$report" "$manifest_target_count" "$manifest_expected_sections" <<'PY'
import json
import sys

report_path, expected_count, expected_sections = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
raw = open(report_path, "r", encoding="utf-8", errors="ignore").read()
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
    print(f"FAIL: no-json output in {report_path}")
    sys.exit(1)
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
ROLLBACK_HARNESS_START_MS=''
ROLLBACK_HARNESS_LAST_MS=''

harness_now_ms() {
  python3 -c 'import time; print(time.time_ns() // 1000000)'
}

harness_marker() {
  local stage="$1"
  local marker_rc="${2:-0}"
  local cleanup_entries="${3:-0}"
  local now elapsed segment
  now="$(harness_now_ms)"
  if [[ -z "$ROLLBACK_HARNESS_START_MS" ]]; then
    ROLLBACK_HARNESS_START_MS="$now"
  fi
  if [[ -z "$ROLLBACK_HARNESS_LAST_MS" ]]; then
    ROLLBACK_HARNESS_LAST_MS="$ROLLBACK_HARNESS_START_MS"
  fi
  elapsed=$((now - ROLLBACK_HARNESS_START_MS))
  segment=$((now - ROLLBACK_HARNESS_LAST_MS))
  ROLLBACK_HARNESS_LAST_MS="$now"
  printf 'HARNESS_MARKER stage=%s elapsedMs=%s segmentMs=%s cleanupEntries=%s rc=%s\n' "$stage" "$elapsed" "$segment" "$cleanup_entries" "$marker_rc" >&2
}

harness_case_exit_marker() {
  local case_rc="$1"
  if [[ "${HARNESS_MARK_THIS_CASE:-false}" == true && "${CASE_FUNCTION_RETURN_MARKED:-false}" != true ]]; then
    harness_marker case-function-return "$case_rc" "${CASE_CLEANUP_ENTRIES:-0}"
  fi
}

run_case() {
  local label="$1"
  local expect_rc="$2"
  local filter="${SYNC_CASE_FILTER-}"
  if [[ -n "$filter" && "$label" != "$filter" ]]; then
    return 0
  fi
  shift 2

  TOTAL=$((TOTAL + 1))
  printf '[RUN] %s\n' "$label"

  if [[ "$label" == "fault injection triggers full rollback" ]]; then
    ROLLBACK_HARNESS_START_MS="$(harness_now_ms)"
    ROLLBACK_HARNESS_LAST_MS="$ROLLBACK_HARNESS_START_MS"
  fi

  local rc=0
  local mark_case=false
  if [[ "$label" == "fault injection triggers full rollback" || "${SYNC_HARNESS_CONTROL_SELFTEST:-}" == "1" ]]; then
    mark_case=true
  fi
  local parent_errexit=false
  case "$-" in *e*) parent_errexit=true ;; esac
  set +e
  (
    set -eu
    HARNESS_MARK_THIS_CASE="$mark_case"
    CASE_FUNCTION_RETURN_MARKED=false
    CASE_CLEANUP_ENTRIES=0
    trap 'case_rc=$?; harness_case_exit_marker "$case_rc" || :; exit "$case_rc"' EXIT
    "$@"
  )
  rc=$?
  if [[ "$parent_errexit" == true ]]; then set -e; else set +e; fi
  if [[ "$mark_case" == true ]]; then
    harness_marker run-case-return "$rc" 0
  fi

  if [[ "$rc" == "$expect_rc" ]]; then
    echo "[PASS] $label"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $label (rc=$rc, expect=$expect_rc)"
    FAIL=$((FAIL + 1))
  fi
}

harness_control_exit_probe() {
  exit 7
}

harness_command_not_found_probe() {
  __agency_intentionally_missing_command__
  echo 'FAIL: command-not-found probe continued unexpectedly' >&2
  return 0
}

harness_unbound_variable_probe() {
  /bin/bash -u -c 'printf "%s\\n" "$AGENCY_HARNESS_INTENTIONALLY_UNBOUND"' 2>/dev/null
}

task_harness_failure_propagation_selfcheck() {
  TOTAL=0
  PASS=0
  FAIL=0
  run_case "harness unbound-variable probe is collected as FAIL" 0 harness_unbound_variable_probe
  run_case "harness command-not-found probe is collected as FAIL" 0 harness_command_not_found_probe
  printf 'HARNESS_FAILURE_SELFTEST observedFailures=%s childNonzero=%s\n' "$FAIL" "$FAIL"
  printf 'TOTAL=%s\nPASS=%s\nFAIL=%s\n' "$TOTAL" "$PASS" "$FAIL"
  if [[ "$TOTAL" != 2 || "$PASS" != 0 || "$FAIL" != 2 ]]; then
    echo 'RC=1'
    return 1
  fi
  echo 'RC=0'
  return 0
}

if [[ "${SYNC_HARNESS_FAILURE_PROPAGATION_SELFTEST:-}" == "1" ]]; then
  task_harness_failure_propagation_selfcheck
  exit $?
fi

task_harness_command_not_found_selfcheck() {
  TOTAL=0
  PASS=0
  FAIL=0
  run_case "harness command-not-found probe" 127 harness_command_not_found_probe
  printf 'TOTAL=%s\nPASS=%s\nFAIL=%s\n' "$TOTAL" "$PASS" "$FAIL"
  if [[ "$TOTAL" != 1 || "$PASS" != 1 || "$FAIL" != 0 ]]; then
    echo 'RC=1'
    return 1
  fi
  echo 'RC=0'
  return 0
}

if [[ "${SYNC_HARNESS_COMMAND_NOT_FOUND_SELFTEST:-}" == "1" ]]; then
  task_harness_command_not_found_selfcheck
  exit $?
fi

task_harness_control_selfcheck() {
  TOTAL=0
  PASS=0
  FAIL=0
  run_case "harness-control exit probe" 7 harness_control_exit_probe
  harness_marker summary-start "$FAIL" 0
  printf 'TOTAL=%s\nPASS=%s\nFAIL=%s\n' "$TOTAL" "$PASS" "$FAIL"
  harness_marker summary-end "$FAIL" 0
  if [[ "$TOTAL" != 1 || "$PASS" != 1 || "$FAIL" != 0 ]]; then
    echo 'RC=1'
    return 1
  fi
  echo 'RC=0'
  return 0
}

if [[ "${SYNC_HARNESS_CONTROL_SELFTEST:-}" == "1" ]]; then
  task_harness_control_selfcheck
  exit $?
fi

snapshot_dry_run_roots() {
  local output_file="$1"
  local target_root="$2"
  local evidence_root="$3"
  local audit_output="$4"
  python3 - "$output_file" "$target_root" "$evidence_root" "$audit_output" <<'PY'
import hashlib
import json
import os
import stat
import sys

output_file, target_root, evidence_root, audit_output = sys.argv[1:]

def scan(path):
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        return {".": {"exists": False, "type": "absent", "inode": 0, "mode": "-", "size": 0, "digest": hashlib.sha256(b"absent").hexdigest()}}
    rows = {}

    def visit(current, relative):
        item_st = os.lstat(current)
        mode = format(stat.S_IMODE(item_st.st_mode), "o")
        if stat.S_ISLNK(item_st.st_mode):
            kind = "symlink"
            digest = hashlib.sha256(os.readlink(current).encode("utf-8", "surrogateescape")).hexdigest()
        elif stat.S_ISREG(item_st.st_mode):
            kind = "file"
            h = hashlib.sha256()
            with open(current, "rb") as fp:
                while True:
                    block = fp.read(1024 * 1024)
                    if not block:
                        break
                    h.update(block)
            digest = h.hexdigest()
        elif stat.S_ISDIR(item_st.st_mode):
            kind = "directory"
            child_rows = []
            for name in sorted(os.listdir(current)):
                child_relative = name if relative == "." else relative + "/" + name
                visit(os.path.join(current, name), child_relative)
                child = rows[child_relative]
                child_rows.append("|".join((child_relative, child["type"], child["mode"], str(child["size"]), child["digest"])))
            digest = hashlib.sha256(("\n".join(child_rows) + ("\n" if child_rows else "")).encode("utf-8")).hexdigest()
        else:
            kind = "special"
            digest = hashlib.sha256(f"special|{mode}|{item_st.st_size}".encode("ascii")).hexdigest()
        rows[relative] = {"exists": True, "type": kind, "inode": item_st.st_ino, "mode": mode, "size": item_st.st_size, "digest": digest}

    visit(path, ".")
    return rows

snapshot = {
    "target-home": scan(target_root),
    "ledger-root": scan(evidence_root),
    "runtime-evidence-root": scan(evidence_root),
    "test-audit-output": scan(audit_output),
}
with open(output_file, "w", encoding="utf-8") as fp:
    json.dump(snapshot, fp, separators=(",", ":"), sort_keys=True)
PY
}

diff_dry_run_roots() {
  local before_file="$1"
  local after_file="$2"
  python3 - "$before_file" "$after_file" <<'PY'
import json
import sys

before = json.load(open(sys.argv[1], encoding="utf-8"))
after = json.load(open(sys.argv[2], encoding="utf-8"))
result = {"added": [], "modified": [], "deleted": []}
for root_name in sorted(set(before) | set(after)):
    old = before.get(root_name, {})
    new = after.get(root_name, {})
    for relative in sorted(set(old) | set(new)):
        label = root_name + ":" + relative
        if relative not in old:
            result["added"].append(label)
        elif relative not in new:
            result["deleted"].append(label)
        elif old[relative] != new[relative]:
            result["modified"].append(label)
print("DRY_RUN_TREE_DIFF=" + json.dumps(result, separators=(",", ":"), sort_keys=True))
raise SystemExit(1 if any(result.values()) else 0)
PY
}

print_dry_run_report_diagnostic() {
  local report_file="$1"
  local command_rc="$2"
  local state_file="${3:-}"
  python3 - "$report_file" "$command_rc" "$state_file" >&2 <<'PY'
import json
import sys

raw = open(sys.argv[1], "rb").read()
decoder = json.JSONDecoder()
values = []
offset = 0
text = raw.decode("utf-8", "strict")
while offset < len(text):
    while offset < len(text) and text[offset].isspace():
        offset += 1
    if offset >= len(text):
        break
    value, offset = decoder.raw_decode(text, offset)
    values.append(value)

report = values[0] if len(values) == 1 and isinstance(values[0], dict) else {}
failure = report.get("failure", {})
manifest = report.get("manifest", {})
result = report.get("result", {})
rollback = report.get("rollback", {})
evidence_path_count = 0
if sys.argv[3]:
    state = json.load(open(sys.argv[3], encoding="utf-8"))
    for root_name in ("ledger-root", "runtime-evidence-root", "test-audit-output"):
        evidence_path_count += sum(1 for item in state.get(root_name, {}).values() if item.get("exists"))
print("DRY_RUN_DIAGNOSTIC=" + json.dumps({
    "rc": int(sys.argv[2]),
    "stdoutJsonValueCount": len(values),
    "stage": failure.get("stage"),
    "reason": failure.get("reason"),
    "operation": failure.get("operation"),
    "transactionCount": manifest.get("transactionCount"),
    "backupCount": result.get("backupCount"),
    "evidencePathCount": evidence_path_count,
    "rollback": {
        "performed": rollback.get("performed"),
        "attempted": rollback.get("attempted"),
        "restored": rollback.get("restored"),
        "restoreFailures": len(rollback.get("restoreFailures", [])) if isinstance(rollback.get("restoreFailures"), list) else None,
    },
}, separators=(",", ":"), sort_keys=True))
PY
}

assert_dry_run_security_audit() {
  local stderr_file="$1"
  python3 - "$stderr_file" <<'PY'
import sys

prefix = "DRY_RUN_SECURITY_AUDIT "
lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
matches = [line for line in lines if line.startswith(prefix)]
if len(matches) != 1:
    raise SystemExit(1)
fields = dict(item.split("=", 1) for item in matches[0][len(prefix):].split(" "))
expected = {
    "requested": "true",
    "authorized": "true",
    "configureSecurityBypassed": "true",
    "layoutValidatorCalled": "false",
    "verifyAuthorizationCalled": "false",
    "appendLedgerCalled": "false",
    "zeroSecurityAccess": "true",
}
if fields != expected:
    raise SystemExit(1)
PY
}

case_dry_run() {
  local case_root result_root report_file stderr_file evidence_root audit_output
  local source_root_dir manifest_path pre_state post_state command_rc diff_rc
  case_root="$(fixture_case_home)"
  result_root="$(mktemp -d "$FIXTURE_ROOT/dry-run-result.XXXXXX")"
  chmod 700 "$result_root"
  manifest_path="$(fixture_manifest_path "$case_root")"
  source_root_dir="$(fixture_source_copy "$case_root")"
  report_file="$result_root/stdout.json"
  stderr_file="$result_root/stderr.log"
  pre_state="$result_root/before.json"
  post_state="$result_root/after.json"
  evidence_root="$case_root/.codex/supervisor-runtime-evidence"
  audit_output="$case_root/.dry-run-test-audit"

  prepare_installed_manifest_targets "$case_root" "$case_root" "$manifest_path"
  snapshot_dry_run_roots "$pre_state" "$case_root" "$evidence_root" "$audit_output"

  if AGENCY_TEST_DRY_RUN_SECURITY_AUDIT=dry-run-no-security-v1 HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" --dry-run --home "$case_root" --test-mode --test-mode-root "$case_root" --manifest "$manifest_path" --source-root "$source_root_dir" --project "$case_root" >"$report_file" 2>"$stderr_file"; then
    command_rc=0
  else
    command_rc=$?
  fi
  snapshot_dry_run_roots "$post_state" "$case_root" "$evidence_root" "$audit_output"
  set +e
  diff_dry_run_roots "$pre_state" "$post_state" >&2
  diff_rc=$?
  set -e
  print_dry_run_report_diagnostic "$report_file" "$command_rc" "$post_state"

  if [[ "$command_rc" != "0" ]]; then
    return 1
  fi
  assert_raw_sync_report_json "$report_file" || return 1
  assert_counts "$report_file" || return 1
  if [[ "$(json_get "$report_file" result.status)" != "passed" ]]; then
    echo "FAIL: dry-run not passed"
    return 1
  fi
  assert_dry_run_security_audit "$stderr_file" || return 1
  if [[ "$diff_rc" != "0" ]]; then
    echo "FAIL: dry-run changed tested roots"
    return 1
  fi
  rm -rf "$case_root" "$result_root"
  return 0
}

case_dry_run_malicious_security_sentinels() {
  local case_root result_root manifest_path source_root_dir report_file stderr_file pre_state post_state audit_output
  local authority_path evidence_path sentinel_file action_path signature_path signer_path ledger_path command_rc diff_rc
  case_root="$(fixture_case_home)"
  result_root="$(mktemp -d "$FIXTURE_ROOT/dry-run-malicious-result.XXXXXX")" || return 1
  chmod 700 "$result_root" || return 1
  manifest_path="$(fixture_manifest_path "$case_root")"
  source_root_dir="$(fixture_source_copy "$case_root")" || return 1
  prepare_installed_manifest_targets "$case_root" "$case_root" "$manifest_path" || return 1

  authority_path="$case_root/.codex/supervisor-authority"
  evidence_path="$case_root/.codex/supervisor-runtime-evidence"
  sentinel_file="$case_root/security-sentinel"
  action_path="$case_root/action-link"
  signature_path="$case_root/signature-link"
  signer_path="$case_root/allowed-signers-fifo"
  ledger_path="$case_root/ledger-link"
  printf '%s\n' 'dry-run security sentinel' >"$sentinel_file"
  chmod 600 "$sentinel_file"
  ln -s "$sentinel_file" "$authority_path"
  mkfifo "$evidence_path" "$signer_path"
  chmod 600 "$evidence_path" "$signer_path"
  ln -s "$sentinel_file" "$action_path"
  ln -s "$sentinel_file" "$signature_path"
  ln -s "$sentinel_file" "$ledger_path"

  report_file="$result_root/stdout.json"
  stderr_file="$result_root/stderr.log"
  pre_state="$result_root/before.json"
  post_state="$result_root/after.json"
  audit_output="$case_root/.dry-run-security-audit"
  snapshot_dry_run_roots "$pre_state" "$case_root" "$evidence_path" "$audit_output"
  if AGENCY_TEST_DRY_RUN_SECURITY_AUDIT=dry-run-no-security-v1 HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" --dry-run --home "$case_root" --test-mode --test-mode-root "$case_root" --manifest "$manifest_path" --source-root "$source_root_dir" --project "$case_root" --action-file "$action_path" --signature-file "$signature_path" --allowed-signers "$signer_path" --ledger "$ledger_path" >"$report_file" 2>"$stderr_file"; then
    command_rc=0
  else
    command_rc=$?
  fi
  snapshot_dry_run_roots "$post_state" "$case_root" "$evidence_path" "$audit_output"
  set +e
  diff_dry_run_roots "$pre_state" "$post_state" >&2
  diff_rc=$?
  set -e
  [[ "$command_rc" == "0" && "$diff_rc" == "0" ]] || return 1
  assert_raw_sync_report_json "$report_file" || return 1
  assert_counts "$report_file" || return 1
  [[ "$(json_get "$report_file" result.status)" == "passed" ]] || return 1
  assert_dry_run_security_audit "$stderr_file" || return 1
  rm -rf "$case_root" "$result_root"
  return 0
}

case_dry_run_marker_fd_pollution() {
  local case_root result_root manifest_path source_root_dir report_file stderr_file sentinel12 sentinel13 sentinel14
  local before after command_rc diff_rc sentinel12_before sentinel13_before sentinel14_before
  case_root="$(fixture_case_home)"
  result_root="$(mktemp -d "$FIXTURE_ROOT/dry-run-marker-result.XXXXXX")" || return 1
  chmod 700 "$result_root" || return 1
  manifest_path="$(fixture_manifest_path "$case_root")"
  source_root_dir="$(fixture_source_copy "$case_root")" || return 1
  prepare_installed_manifest_targets "$case_root" "$case_root" "$manifest_path" || return 1
  sentinel12="$result_root/fd12-sentinel"
  sentinel13="$result_root/fd13-sentinel"
  sentinel14="$result_root/fd14-sentinel"
  printf '%s\n' fd12 fd13 fd14 >"$sentinel12"
  printf '%s\n' fd13 >>"$sentinel13"
  printf '%s\n' fd14 >>"$sentinel14"
  chmod 600 "$sentinel12" "$sentinel13" "$sentinel14" || return 1
  sentinel12_before="$(shasum -a 256 "$sentinel12" | awk '{print $1}')" || return 1
  sentinel13_before="$(shasum -a 256 "$sentinel13" | awk '{print $1}')" || return 1
  sentinel14_before="$(shasum -a 256 "$sentinel14" | awk '{print $1}')" || return 1
  before="$result_root/before.json"
  after="$result_root/after.json"
  report_file="$result_root/stdout.json"
  stderr_file="$result_root/stderr.log"
  snapshot_dry_run_roots "$before" "$case_root" "$case_root/.codex/supervisor-runtime-evidence" "$case_root/.dry-run-test-audit"
  exec 12<"$sentinel12"
  exec 13<"$sentinel13"
  exec 14<"$sentinel14"
  if AGENCY_TXN_ROOT_BOUND=v1 \
    AGENCY_TXN_WORK_ROOT="$case_root/forged-work" \
    AGENCY_TXN_BACKUP_ROOT="$case_root/forged-backup" \
    AGENCY_TXN_WORK_LEAF=forged-work \
    AGENCY_TXN_BACKUP_LEAF=forged-backup \
    AGENCY_REPORT_FD_BOUND=v1 AGENCY_REPORT_FD=14 \
    AGENCY_REPORT_FD_DEV=1 AGENCY_REPORT_FD_INO=1 \
    AGENCY_REPORT_FD_TYPE=regular AGENCY_REPORT_FD_UID=0 \
    AGENCY_REPORT_FD_MODE=600 AGENCY_REPORT_FD_NLINK=1 \
    HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" --dry-run --home "$case_root" \
      --test-mode --test-mode-root "$case_root" --manifest "$manifest_path" \
      --source-root "$source_root_dir" --project "$case_root" >"$report_file" 2>"$stderr_file"; then
    command_rc=0
  else
    command_rc=$?
  fi
  exec 12<&-
  exec 13<&-
  exec 14<&-
  snapshot_dry_run_roots "$after" "$case_root" "$case_root/.codex/supervisor-runtime-evidence" "$case_root/.dry-run-test-audit"
  set +e
  diff_dry_run_roots "$before" "$after" >&2
  diff_rc=$?
  set -e
  [[ "$command_rc" == "0" && "$diff_rc" == "0" ]] || return 1
  assert_raw_sync_report_json "$report_file" || return 1
  assert_counts "$report_file" || return 1
  [[ "$(json_get "$report_file" result.status)" == "passed" ]] || return 1
  [[ "$(shasum -a 256 "$sentinel12" | awk '{print $1}')" == "$sentinel12_before" ]] || return 1
  [[ "$(shasum -a 256 "$sentinel13" | awk '{print $1}')" == "$sentinel13_before" ]] || return 1
  [[ "$(shasum -a 256 "$sentinel14" | awk '{print $1}')" == "$sentinel14_before" ]] || return 1
  rm -rf "$case_root" "$result_root"
  return 0
}

case_apply_missing_security_layout() {
  local case_root result_root manifest_path source_root_dir raw_report clean_report stderr_file pre_state post_state audit_output
  local authority_path evidence_path command_rc diff_rc
  case_root="$(fixture_case_home)"
  result_root="$(mktemp -d "$FIXTURE_ROOT/apply-missing-layout-result.XXXXXX")" || return 1
  chmod 700 "$result_root" || return 1
  manifest_path="$(fixture_manifest_path "$case_root")"
  source_root_dir="$(fixture_source_copy "$case_root")" || return 1
  prepare_installed_manifest_targets "$case_root" "$case_root" "$manifest_path" || return 1
  authority_path="$case_root/.codex/supervisor-authority"
  evidence_path="$case_root/.codex/supervisor-runtime-evidence"
  [[ ! -e "$authority_path" && ! -e "$evidence_path" ]] || return 1

  raw_report="$result_root/raw.json"
  clean_report="$result_root/report.json"
  stderr_file="$result_root/stderr.log"
  pre_state="$result_root/before.json"
  post_state="$result_root/after.json"
  audit_output="$case_root/.apply-security-audit"
  snapshot_dry_run_roots "$pre_state" "$case_root" "$evidence_path" "$audit_output"
  if HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" --apply --home "$case_root" --test-mode --test-mode-root "$case_root" --manifest "$manifest_path" --source-root "$source_root_dir" --project "$case_root" --action-file "$authority_path/action.json" --signature-file "$authority_path/action.json.sig" --allowed-signers "$authority_path/allowed_signers" --ledger "$authority_path/owner-only-ledger.jsonl" >"$raw_report" 2>"$stderr_file"; then
    command_rc=0
  else
    command_rc=$?
  fi
  snapshot_dry_run_roots "$post_state" "$case_root" "$evidence_path" "$audit_output"
  set +e
  diff_dry_run_roots "$pre_state" "$post_state" >&2
  diff_rc=$?
  set -e
  read_isolated_sync_report "$result_root" "$raw_report" "$clean_report" || return 1
  [[ "$command_rc" != "0" && "$diff_rc" == "0" ]] || return 1
  python3 - "$clean_report" <<'PY' || return 1
import json
import sys

report = json.load(open(sys.argv[1], encoding="utf-8"))
failure = report.get("failure") or {}
security = report.get("security") or report.get("supervisorAuthorization") or {}
result = report.get("result") or {}
rollback = report.get("rollback") or {}
if report.get("schema") != "agency-agents.local-sync-report/v1" or result.get("status") != "failed":
    raise SystemExit(1)
if failure != {
    "stage": "authorization-validation",
    "target": "ledger",
    "tool": "authorization",
    "id": "ledger-layout",
    "reason": "authorization validation failed",
    "operation": "authorization-validation",
}:
    raise SystemExit(1)
if security.get("reason") != "isolated test security root layout invalid":
    raise SystemExit(1)
if result.get("backupCount") != 0 or rollback.get("performed") is not False or rollback.get("attempted") != 0 or rollback.get("restored") != 0:
    raise SystemExit(1)
PY
  rm -rf "$case_root" "$result_root"
  return 0
}

assert_raw_sync_report_json() {
  python3 - "$1" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fp:
    raw_report = fp.read()
try:
    report = json.loads(raw_report)
except json.JSONDecodeError:
    items = []
    for line in raw_report.splitlines():
        try:
            item = json.loads(line)
            items.append({"schema": item.get("schema"), "status": (item.get("result") or {}).get("status"), "stage": (item.get("failure") or {}).get("stage"), "reason": (item.get("failure") or {}).get("reason"), "operation": (item.get("failure") or {}).get("operation")})
        except Exception:
            items.append({"schema": None, "status": None, "stage": None})
    print("SYNC_RAW_REPORT_DIAGNOSTIC=" + json.dumps({"lineCount": len(raw_report.splitlines()), "byteCount": len(raw_report.encode("utf-8")), "items": items}, separators=(",", ":")), file=sys.stderr)
    raise
if not isinstance(report, dict) or report.get("schema") != "agency-agents.local-sync-report/v1":
    raise SystemExit(1)
PY
}

read_isolated_json_object_no_follow() {
  local trusted_root="$1"
  local input_file="$2"
  local required_schema="${3:-}"

  python3 - "$trusted_root" "$input_file" "$required_schema" <<'PY'
import json
import os
import stat
import sys

root, input_path, required_schema = sys.argv[1:]
root_st = os.lstat(root)
if stat.S_ISLNK(root_st.st_mode) or not stat.S_ISDIR(root_st.st_mode):
    raise SystemExit(1)
if stat.S_IMODE(root_st.st_mode) != 0o700 or root_st.st_uid != os.getuid():
    raise SystemExit(1)
if os.path.dirname(input_path) != root or not os.path.basename(input_path):
    raise SystemExit(1)

root_fd = os.open(root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0))
try:
    input_fd = os.open(os.path.basename(input_path), os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0), dir_fd=root_fd)
    try:
        input_st = os.fstat(input_fd)
        if not stat.S_ISREG(input_st.st_mode) or input_st.st_uid != os.getuid():
            raise SystemExit(1)
        chunks = []
        while True:
            chunk = os.read(input_fd, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
    finally:
        os.close(input_fd)
finally:
    os.close(root_fd)

value = json.loads(b"".join(chunks).decode("utf-8"))
if not isinstance(value, dict):
    raise SystemExit(1)
if required_schema and value.get("schema") != required_schema:
    raise SystemExit(1)
print(json.dumps(value, ensure_ascii=False, separators=(",", ":")), end="")
PY
}

read_isolated_sync_report() {
  local trusted_root="$1"
  local input_file="$2"
  local output_file="$3"
  local temp_output

  [[ "$input_file" != "$output_file" ]] || return 1
  [[ "$(dirname "$output_file")" == "$trusted_root" ]] || return 1
  temp_output="$(mktemp "$trusted_root/.sync-report.XXXXXX")" || return 1
  if ! read_isolated_json_object_no_follow "$trusted_root" "$input_file" 'agency-agents.local-sync-report/v1' >"$temp_output"; then
    rm -f "$temp_output"
    return 1
  fi
  mv -f "$temp_output" "$output_file"
}

report_reader_selfcheck() {
  local raw_root trusted_root raw_report clean_report symlink_report parsed
  raw_root="$(mktemp -d /tmp/agency-report-reader.XXXXXX)" || return 1
  trusted_root="$(physical_root "$raw_root")" || return 1
  chmod 700 "$trusted_root"
  trap "rm -rf -- '$trusted_root'" EXIT
  raw_report="$trusted_root/raw.json"
  clean_report="$trusted_root/clean.json"
  symlink_report="$trusted_root/report-link.json"
  printf '%s' '{"schema":"agency-agents.local-sync-report/v1","manifest":{"transactionCount":18},"result":{"status":"failed"},"failure":{"stage":"fault-injection","reason":"injected post-owner-install failure","operation":"test-fault-seam"},"rollback":{"performed":true,"attempted":1,"restored":1,"restoreFailures":[],"entries":[{"id":"aider:${PROJECT}/CONVENTIONS.md","ownerRelative":"__whole_file__","kind":"file","expected":{"digest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","mode":"640","size":23},"staged":{"digest":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","mode":"600","size":42}}]}}' >"$raw_report"
  chmod 600 "$raw_report"
  read_isolated_sync_report "$trusted_root" "$raw_report" "$clean_report" || return 1
  parsed="$(read_isolated_json_object_no_follow "$trusted_root" "$clean_report" 'agency-agents.local-sync-report/v1')" || return 1
  python3 - "$parsed" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
entry = report["rollback"]["entries"][0]
raise SystemExit(0 if report["schema"] == "agency-agents.local-sync-report/v1" and entry["expected"]["digest"] == "a" * 64 else 1)
PY
  ln -s "$raw_report" "$symlink_report"
  if read_isolated_json_object_no_follow "$trusted_root" "$symlink_report" 'agency-agents.local-sync-report/v1' >/dev/null 2>&1; then
    return 1
  fi
  echo 'REPORT_READER_SELFTEST=PASS'
}

if [[ "${SYNC_REPORT_READER_SELFTEST:-}" == "1" ]]; then
  report_reader_selfcheck
  exit $?
fi

assert_apply_blocked() {
  local home="$1"
  local source_root_dir="$2"
  local manifest_path="$3"
  local namespace="$4"
  local principal="$5"
  local case_label="$6"
  local expect_pattern="${7:-}"
  local canonical_role_ids_json="${8:-}"
  local canonical_role_tool="${9:-}"
  local cross_platform_role_sets_json="${10:-}"
  local expected_stage="${11:-}"
  local expected_operation="${12:-}"
  local expected_tool="${13:-}"
  local expected_id="${14:-}"
  local evidence_root="$home/.codex/supervisor-runtime-evidence"
  local evidence_signers="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/allowed_signers"
  local evidence_ledger="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/owner-only-ledger.jsonl"
  local action signature allowed_signers report report_json

  read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" "$namespace" "$principal" "$home/action.json" "$manifest_path" "$evidence_signers" "isolated-test" "$home" "$home")

  report="$(mktemp)"
  report_json="$(mktemp)"
  if AGENCY_TEST_EXPECTED_REASON="$expect_pattern" AGENCY_TEST_ROLE_TOOL="$canonical_role_tool" AGENCY_TEST_CANONICAL_ROLE_IDS_JSON="$canonical_role_ids_json" AGENCY_TEST_CROSS_PLATFORM_ROLE_SETS_JSON="$cross_platform_role_sets_json" HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$manifest_path" --source-root "$source_root_dir" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report" 2>&1; then
    echo "FAIL: ${case_label} should be blocked"
    rm -rf "$report" "$report_json" "$home"
    return 1
  fi
  if ! extract_report_json "$report" "$report_json"; then
    echo "FAIL: ${case_label} failed without a valid JSON report"
    rm -rf "$report" "$report_json" "$home"
    return 1
  fi
  local result_status failure_stage failure_reason failure_operation failure_tool failure_id
  result_status="$(json_get "$report_json" result.status)"
  failure_stage="$(json_get "$report_json" failure.stage)"
  failure_reason="$(json_get "$report_json" failure.reason)"
  failure_operation="$(json_get "$report_json" failure.operation)"
  failure_tool="$(json_get "$report_json" failure.tool)"
  failure_id="$(json_get "$report_json" failure.id)"
  if [[ "$result_status" != "failed" || -z "$failure_stage" || "$failure_stage" == "-1" || -z "$failure_reason" || -z "$failure_operation" ]]; then
    echo "FAIL: ${case_label} JSON failure contract incomplete"
    rm -rf "$report" "$report_json" "$home"
    return 1
  fi
  if [[ -n "$expect_pattern" ]] && [[ "$failure_reason" != "$expect_pattern" ]]; then
    echo "FAIL: ${case_label} JSON failure reason mismatch (reason=$failure_reason)"
    rm -rf "$report" "$report_json" "$home"
    return 1
  fi
  if [[ -n "$expected_stage" && "$failure_stage" != "$expected_stage" ]] || [[ -n "$expected_operation" && "$failure_operation" != "$expected_operation" ]] || [[ -n "$expected_tool" && "$failure_tool" != "$expected_tool" ]] || [[ -n "$expected_id" && "$failure_id" != "$expected_id" ]]; then
    echo "FAIL: ${case_label} JSON failure fields mismatch (stage=$failure_stage operation=$failure_operation tool=$failure_tool id=$failure_id)"
    rm -rf "$report" "$report_json" "$home"
    return 1
  fi

  rm -rf "$report" "$report_json" "$home"
  return 0
}

snapshot_tool_source_signature() {
  local source_root="$1"
  local tool_name="$2"

  python3 - "$source_root" "$tool_name" <<'PY'
import hashlib
import os
import sys

root = os.path.join(sys.argv[1], sys.argv[2])
if not os.path.isdir(root):
    raise SystemExit(1)

h = hashlib.sha256()
for dirpath, dirnames, filenames in os.walk(root):
    dirnames.sort()
    filenames.sort()
    rel = os.path.relpath(dirpath, root)
    h.update(("D:" + rel + "\n").encode())
    for dirname in dirnames:
        h.update(("DIR:" + os.path.join(rel, dirname) + "\n").encode())
    for filename in filenames:
        path = os.path.join(dirpath, filename)
        rel_path = os.path.relpath(path, root)
        if os.path.islink(path):
            h.update(("LINK:" + rel_path + ":" + os.readlink(path) + "\n").encode())
            continue
        st = os.lstat(path)
        h.update(("FILE:" + rel_path + ":" + str(st.st_size) + ":" + oct(st.st_mode & 0o7777) + "\n").encode())
        if os.path.isfile(path):
            with open(path, "rb") as fp:
                while True:
                    chunk = fp.read(1024 * 1024)
                    if not chunk:
                        break
                    h.update(chunk)

print(h.hexdigest())
PY
}

rewrite_tool_roles_agents_json() {
  local source_root="$1"
  local tool_name="$2"
  local mutation="$3"

  python3 - "$source_root" "$tool_name" "$mutation" <<'PY'
import json
import os
import pathlib
import sys
import shutil

source_root = pathlib.Path(sys.argv[1])
tool_name = sys.argv[2]
mutation = sys.argv[3]

tool_root = source_root / tool_name
if not tool_root.is_dir():
    raise SystemExit(1)


def collect_role_root(source):
    for dirpath, _, filenames in os.walk(source):
        if "agents.json" in filenames:
            return "agents_json", pathlib.Path(dirpath) / "agents.json", []

    if (source / "agents").is_dir():
        return "filesystem", (source / "agents"), []
    if (source / "rules").is_dir():
        return "filesystem", (source / "rules"), []

    children = [e for e in os.listdir(source) if not e.startswith(".")]
    child_dirs = [e for e in children if (source / e).is_dir() and (source / e).is_dir()]
    if len(child_dirs) == 1:
        single_dir = source / child_dirs[0]
        if os.listdir(single_dir):
            return "filesystem", single_dir, []
    return "filesystem", source, []


def collect_entries(root):
    entries = []
    for entry in sorted(root.iterdir(), key=lambda p: p.name):
        if entry.name.startswith("."):
            continue
        if entry.is_dir():
            entries.append(("dir", entry))
        elif entry.is_file():
            entries.append(("file", entry))
    return entries


mode, path_or_file, _ = collect_role_root(tool_root)
if mode == "agents_json":
    with open(path_or_file, encoding="utf-8") as fp:
        rows = json.load(fp)
    if not isinstance(rows, list):
        raise SystemExit(1)
    role_labels = [str(row.get("slug", "")) for row in rows if isinstance(row, dict) and isinstance(row.get("slug"), str)]
    if not role_labels:
        raise SystemExit(1)

    if mutation == "missing":
        role_labels = role_labels[:-1]
    elif mutation == "wrong":
        role_labels[-1] = "Bad ID"
    elif mutation == "duplicate":
        role_labels = role_labels[:] + [role_labels[0]]
    elif mutation == "canonical":
        pass
    else:
        raise SystemExit(2)

    with open(path_or_file, "w", encoding="utf-8") as fp:
        json.dump([{"slug": name} for name in role_labels], fp, ensure_ascii=False, indent=2)
    sys.exit(0)


entries = collect_entries(path_or_file)
if not entries:
    raise SystemExit(1)

if mutation == "missing":
    kind, target = entries[-1]
    if kind == "file":
        target.unlink()
    else:
        shutil.rmtree(target)
elif mutation == "wrong":
    kind, target = entries[-1]
    if kind == "file" and target.suffix:
        target = target.with_name(f"Bad ID{target.suffix}")
    else:
        target = target.with_name("Bad ID")
    entries[-1][1].rename(target)
elif mutation == "duplicate":
    kind, target = entries[0]
    if kind == "file":
        dup_target = target.with_name(f"{target.stem}--dup{target.suffix}")
        shutil.copy2(target, dup_target)
    else:
        dup_target = target.with_name(f"{target.name}--dup")
        shutil.copytree(target, dup_target)
elif mutation == "canonical":
    pass
else:
    raise SystemExit(2)
PY
}

case_missing_role_id() {
  local home source_root_dir manifest_source before_sig after_sig

  home="$(fixture_case_home)"
  manifest_source="$(fixture_manifest_path "$home")"
  source_root_dir="$(fixture_source_copy "$home")"

  before_sig="$(snapshot_tool_source_signature "$source_root_dir" qwen)"
  if [[ -z "$before_sig" ]] || ! rewrite_tool_roles_agents_json "$source_root_dir" qwen missing; then
    echo "FAIL: unable to mutate qwen roles for missing-id case"
    rm -rf "$home"
    return 1
  fi
  after_sig="$(snapshot_tool_source_signature "$source_root_dir" qwen)"
  if [[ "$before_sig" == "$after_sig" ]]; then
    echo "FAIL: qwen missing-id mutation did not change copied fixture"
    rm -rf "$home"
    return 1
  fi
  if ! refresh_fixture_source_root_digest "$manifest_source" "$source_root_dir"; then
    echo "FAIL: unable to refresh fixture manifest source digest for missing-role case"
    rm -rf "$home"
    return 1
  fi
  if ! assert_apply_blocked "$home" "$source_root_dir" "$manifest_source" "aicc-supervisor-authorization" "supervisor-approver" "missing role id" "directory role count mismatch" "" "" "" "manifest-validation" "manifest-validation"; then
    rm -rf "$home"
    return 1
  fi
  return 0
}

case_wrong_or_unknown_role_id() {
  local home source_root_dir manifest_source before_sig after_sig

  home="$(fixture_case_home)"
  manifest_source="$(fixture_manifest_path "$home")"
  source_root_dir="$(fixture_source_copy "$home")"

  before_sig="$(snapshot_tool_source_signature "$source_root_dir" qwen)"
  if [[ -z "$before_sig" ]] || ! rewrite_tool_roles_agents_json "$source_root_dir" qwen wrong; then
    echo "FAIL: unable to mutate qwen roles for wrong-id case"
    rm -rf "$home"
    return 1
  fi
  after_sig="$(snapshot_tool_source_signature "$source_root_dir" qwen)"
  if [[ "$before_sig" == "$after_sig" ]]; then
    echo "FAIL: qwen wrong-id mutation did not change copied fixture"
    rm -rf "$home"
    return 1
  fi
  if ! refresh_fixture_source_root_digest "$manifest_source" "$source_root_dir"; then
    echo "FAIL: unable to refresh fixture manifest source digest for wrong-role case"
    rm -rf "$home"
    return 1
  fi
  if ! assert_apply_blocked "$home" "$source_root_dir" "$manifest_source" "aicc-supervisor-authorization" "supervisor-approver" "wrong/unknown role id" "invalid role IDs in source" "" "" "" "manifest-validation" "manifest-validation"; then
    rm -rf "$home"
    return 1
  fi
  return 0
}

case_duplicate_role_id() {
  local home source_root_dir manifest_source duplicate_role_ids

  home="$(fixture_case_home)"
  manifest_source="$(fixture_manifest_path "$home")"
  source_root_dir="$(fixture_source_copy "$home")"

  duplicate_role_ids="$(python3 - "$home/repo/governance/role-governance-profiles.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fp:
    profile = json.load(fp)
role_ids = [row.get("role_id") for row in profile if isinstance(row, dict) and isinstance(row.get("role_id"), str)]
if not role_ids:
    raise SystemExit(1)
print(json.dumps([role_ids[0], role_ids[0]], separators=(",", ":")))
PY
)" || {
    echo "FAIL: unable to construct duplicate canonical role IDs"
    rm -rf "$home"
    return 1
  }
  if ! assert_apply_blocked "$home" "$source_root_dir" "$manifest_source" "aicc-supervisor-authorization" "supervisor-approver" "duplicate role id" "duplicate role IDs detected" "$duplicate_role_ids" qwen "" "manifest-validation" "manifest-validation"; then
    rm -rf "$home"
    return 1
  fi
  return 0
}

case_cross_platform_set_mismatch() {
  local home source_root_dir manifest_source cross_platform_sets

  home="$(fixture_case_home)"
  manifest_source="$(fixture_manifest_path "$home")"
  source_root_dir="$(fixture_source_copy "$home")"

  cross_platform_sets="$(python3 - "$home/repo/governance/role-governance-profiles.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fp:
    profile = json.load(fp)
role_ids = [row.get("role_id") for row in profile if isinstance(row, dict) and isinstance(row.get("role_id"), str)]
if len(role_ids) != 269 or len(set(role_ids)) != 269:
    raise SystemExit(1)
print(json.dumps({"left": role_ids[1:], "right": role_ids[:-1]}, separators=(",", ":")))
PY
)" || {
    echo "FAIL: unable to construct cross-platform canonical role sets"
    rm -rf "$home"
    return 1
  }
  if ! assert_apply_blocked "$home" "$source_root_dir" "$manifest_source" "aicc-supervisor-authorization" "supervisor-approver" "cross-platform role-set mismatch" "role id set mismatch" "" "" "$cross_platform_sets" "manifest-validation" "manifest-validation"; then
    rm -rf "$home"
    return 1
  fi
  return 0
}

case_aider_missing_section() {
  local home source_root_dir manifest_source before_sig after_sig

  home="$(fixture_case_home)"
  manifest_source="$(fixture_manifest_path "$home")"
  source_root_dir="$(fixture_source_copy "$home")"

  before_sig="$(snapshot_tool_source_signature "$source_root_dir" aider)"
  sed -i '' 's/^# 企业治理提示$//g' "$source_root_dir/aider/CONVENTIONS.md"
  after_sig="$(snapshot_tool_source_signature "$source_root_dir" aider)"
  if [[ -z "$before_sig" ]] || [[ -z "$after_sig" ]] || [[ "$before_sig" == "$after_sig" ]]; then
    echo "FAIL: aider missing section mutation did not change copied fixture"
    rm -rf "$home"
    return 1
  fi
  if ! refresh_fixture_source_root_digest "$manifest_source" "$source_root_dir"; then
    echo "FAIL: unable to refresh fixture manifest source digest for aider-section case"
    rm -rf "$home"
    return 1
  fi
  if ! assert_apply_blocked "$home" "$source_root_dir" "$manifest_source" "aicc-supervisor-authorization" "supervisor-approver" "aider missing section" "file role count mismatch" "" "" "" "manifest-validation" "role-validation" "aider" 'aider:${PROJECT}/CONVENTIONS.md'; then
    rm -rf "$home"
    return 1
  fi
  return 0
}

case_windsurf_missing_section() {
  local home source_root_dir manifest_source before_sig after_sig

  home="$(fixture_case_home)"
  manifest_source="$(fixture_manifest_path "$home")"
  source_root_dir="$(fixture_source_copy "$home")"

  before_sig="$(snapshot_tool_source_signature "$source_root_dir" windsurf)"
  sed -i '' 's/^# 企业治理提示$//g' "$source_root_dir/windsurf/.windsurfrules"
  after_sig="$(snapshot_tool_source_signature "$source_root_dir" windsurf)"
  if [[ -z "$before_sig" ]] || [[ -z "$after_sig" ]] || [[ "$before_sig" == "$after_sig" ]]; then
    echo "FAIL: windsurf missing section mutation did not change copied fixture"
    rm -rf "$home"
    return 1
  fi
  if ! refresh_fixture_source_root_digest "$manifest_source" "$source_root_dir"; then
    echo "FAIL: unable to refresh fixture manifest source digest for windsurf-section case"
    rm -rf "$home"
    return 1
  fi
  if ! assert_apply_blocked "$home" "$source_root_dir" "$manifest_source" "aicc-supervisor-authorization" "supervisor-approver" "windsurf missing section" "file role count mismatch" "" "" "" "manifest-validation" "role-validation" "windsurf" 'windsurf:${PROJECT}/.windsurfrules'; then
    rm -rf "$home"
    return 1
  fi
  return 0
}

case_role_contract_matrix() {
  local home source_root_dir
  local manifest_source

  home="$(fixture_case_home)"
  manifest_source="$(fixture_manifest_path "$home")"
  source_root_dir="$(fixture_source_copy "$home")"
  ensure_fixture_security_roots "$home" || return 1
  if ! rewrite_tool_roles_agents_json "$source_root_dir" qwen missing; then
    echo "FAIL: unable to mutate qwen roles for missing-id case"
    rm -rf "$home"
    return 1
  fi
  if ! assert_apply_blocked "$home" "$source_root_dir" "$manifest_source" "aicc-supervisor-authorization" "supervisor-approver" "missing role id"; then
    rm -rf "$home"
    return 1
  fi
  rm -rf "$home"

  # wrong role ID pattern
  home="$(fixture_case_home)"
  manifest_source="$(fixture_manifest_path "$home")"
  source_root_dir="$(fixture_source_copy "$home")"
  if ! rewrite_tool_roles_agents_json "$source_root_dir" qwen wrong; then
    echo "FAIL: unable to mutate qwen roles for wrong-id case"
    rm -rf "$home"
    return 1
  fi
  if ! refresh_fixture_source_root_digest "$manifest_source" "$source_root_dir"; then
    echo "FAIL: unable to refresh fixture manifest source digest for wrong-role case"
    rm -rf "$home"
    return 1
  fi
  if ! assert_apply_blocked "$home" "$source_root_dir" "$manifest_source" "aicc-supervisor-authorization" "supervisor-approver" "wrong role id"; then
    rm -rf "$home"
    return 1
  fi
  rm -rf "$home"

  # duplicate role ID from agents.json
  home="$(fixture_case_home)"
  manifest_source="$(fixture_manifest_path "$home")"
  source_root_dir="$(fixture_source_copy "$home")"
  if ! rewrite_tool_roles_agents_json "$source_root_dir" qwen duplicate; then
    echo "FAIL: unable to mutate qwen roles for duplicate-id case"
    rm -rf "$home"
    return 1
  fi
  if ! refresh_fixture_source_root_digest "$manifest_source" "$source_root_dir"; then
    echo "FAIL: unable to refresh fixture manifest source digest for duplicate-role case"
    rm -rf "$home"
    return 1
  fi
  if ! assert_apply_blocked "$home" "$source_root_dir" "$manifest_source" "aicc-supervisor-authorization" "supervisor-approver" "duplicate role id"; then
    rm -rf "$home"
    return 1
  fi
  rm -rf "$home"

  # cross-platform role-set mismatch between qwen and kimi
  home="$(fixture_case_home)"
  manifest_source="$(fixture_manifest_path "$home")"
  source_root_dir="$(fixture_source_copy "$home")"
  if ! rewrite_tool_roles_agents_json "$source_root_dir" kimi missing; then
    echo "FAIL: unable to mutate kimi roles for cross-platform mismatch case"
    rm -rf "$home"
    return 1
  fi
  if ! refresh_fixture_source_root_digest "$manifest_source" "$source_root_dir"; then
    echo "FAIL: unable to refresh fixture manifest source digest for cross-platform-role-set case"
    rm -rf "$home"
    return 1
  fi
  if ! assert_apply_blocked "$home" "$source_root_dir" "$manifest_source" "aicc-supervisor-authorization" "supervisor-approver" "cross-platform role-set mismatch"; then
    rm -rf "$home"
    return 1
  fi
  rm -rf "$home"

  # aider file path missing section marker
  home="$(fixture_case_home)"
  manifest_source="$(fixture_manifest_path "$home")"
  source_root_dir="$(fixture_source_copy "$home")"
  sed -i '' 's/^# 企业治理提示$//g' "$source_root_dir/aider/CONVENTIONS.md"
  if ! refresh_fixture_source_root_digest "$manifest_source" "$source_root_dir"; then
    echo "FAIL: unable to refresh fixture manifest source digest for aider-section case"
    rm -rf "$home"
    return 1
  fi
  if ! assert_apply_blocked "$home" "$source_root_dir" "$manifest_source" "aicc-supervisor-authorization" "supervisor-approver" "aider missing section"; then
    rm -rf "$home"
    return 1
  fi
  rm -rf "$home"

  # windsurf file path missing section marker
  home="$(fixture_case_home)"
  manifest_source="$(fixture_manifest_path "$home")"
  source_root_dir="$(fixture_source_copy "$home")"
  sed -i '' 's/^# 企业治理提示$//g' "$source_root_dir/windsurf/.windsurfrules"
  if ! refresh_fixture_source_root_digest "$manifest_source" "$source_root_dir"; then
    echo "FAIL: unable to refresh fixture manifest source digest for windsurf-section case"
    rm -rf "$home"
    return 1
  fi
  if ! assert_apply_blocked "$home" "$source_root_dir" "$manifest_source" "aicc-supervisor-authorization" "supervisor-approver" "windsurf missing section"; then
    rm -rf "$home"
    return 1
  fi

  rm -rf "$home"
  return 0
}

case_apply_success_and_protections() {
  local home report
  home="$(fixture_case_home)"
  local project="$home"
  local report_file
  local stderr_file
  local output_root
  local source_root_dir
  local manifest_path
  local evidence_root="$home/.codex/supervisor-runtime-evidence"
  local evidence_signers="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/allowed_signers"
  local evidence_ledger="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/owner-only-ledger.jsonl"
  local protected_audit=''
  local json_report_args=()
  local report_escape_root=''
  local report_mode="${SYNC_TEST_JSON_REPORT_MODE:-}"
  local report_race_stage=''
  local report_race_sentinel_before=''
  local d1_injection_rel_enum="${SYNC_D1_INJECT_REL_ENUM:-}"
  local d1_sentinel_scenario="${SYNC_D1_SENTINEL_SCENARIO:-legacy}"
  local d1_roots_before d1_roots_after
  source_root_dir="$(fixture_source_copy "$home")"
  manifest_path="$(fixture_manifest_path "$home")"
  output_root="$home/.case-apply-output"
  mkdir -p "$output_root"
  report_file="$(mktemp "$output_root/stdout-XXXXXX.json")"
  stderr_file="$(mktemp "$output_root/stderr-XXXXXX.log")"
  prepare_installed_manifest_targets "$home" "$project" "$manifest_path"
  if ! assert_manifest_targets_present "$home" "$project" "$manifest_path"; then
    rm -f "$report_file" "$stderr_file"
    rm -rf "$home"
    return 1
  fi
  read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" aicc-supervisor-authorization supervisor-approver "$home/action.json" "$manifest_path" "$evidence_signers" "isolated-test" "$home" "$home")

  d1_roots_before="$(mktemp)" || return 1
  d1_roots_after="$(mktemp)" || return 1
  setup_d1_openclaw_sentinels "$home" agents-baseline || return 1
  freeze_d1_manifest_target_roots "$home" "$project" "$manifest_path" "$d1_roots_before" || return 1
  setup_d1_openclaw_sentinels "$home" "$d1_sentinel_scenario" || return 1
  freeze_d1_manifest_target_roots "$home" "$project" "$manifest_path" "$d1_roots_after" || return 1
  assert_d1_manifest_target_roots_preserved "$d1_roots_before" "$d1_roots_after" "$d1_sentinel_scenario" || return 1
  if [[ "${SYNC_D1_PROTECTED_AUDIT:-}" == "1" ]]; then
    protected_audit="$home/.d1-protected-access-audit"
    : > "$protected_audit"
    chmod 600 "$protected_audit"
  fi

  if [[ "$report_mode" == "prefix-collision" ]]; then
    report_escape_root="${evidence_root}-escape"
    mkdir "$report_escape_root"
    chmod 700 "$report_escape_root"
    printf 'report sentinel\n' > "$report_escape_root/sentinel"
    chmod 600 "$report_escape_root/sentinel"
    json_report_args=(--json-report "$report_escape_root/nested/report.json")
  elif [[ "$report_mode" == "parent-symlink" ]]; then
    report_escape_root="$home/report-parent-escape"
    mkdir "$report_escape_root" "$evidence_root/custom-parent"
    chmod 700 "$report_escape_root" "$evidence_root/custom-parent"
    printf 'report sentinel\n' > "$report_escape_root/sentinel"
    chmod 600 "$report_escape_root/sentinel"
    rmdir "$evidence_root/custom-parent"
    ln -s "$report_escape_root" "$evidence_root/custom-parent"
    json_report_args=(--json-report "$evidence_root/custom-parent/report.json")
  elif [[ "$report_mode" == "existing-leaf" ]]; then
    printf 'existing report\n' > "$evidence_root/existing-report.json"
    chmod 600 "$evidence_root/existing-report.json"
    report_escape_root="$evidence_root"
    json_report_args=(--json-report "$evidence_root/existing-report.json")
  elif [[ "$report_mode" == "parent-replacement" ]]; then
    mkdir "$evidence_root/custom-parent" "$evidence_root/.report-race-replacement"
    chmod 700 "$evidence_root/custom-parent" "$evidence_root/.report-race-replacement"
    printf 'replacement sentinel\n' > "$evidence_root/.report-race-replacement/sentinel"
    chmod 600 "$evidence_root/.report-race-replacement/sentinel"
    report_escape_root="$evidence_root/.report-race-replacement"
    report_race_sentinel_before="$(test_root_sentinel_metadata "$report_escape_root/sentinel")"
    report_race_stage='after-report-parent-stat'
    json_report_args=(--json-report "$evidence_root/custom-parent/report.json")
  elif [[ "$report_mode" == "leaf-replacement" ]]; then
    printf 'replacement leaf sentinel\n' > "$evidence_root/.report-race-leaf-replacement"
    chmod 600 "$evidence_root/.report-race-leaf-replacement"
    report_escape_root="$evidence_root"
    report_race_sentinel_before="$(test_root_sentinel_metadata "$evidence_root/.report-race-leaf-replacement")"
    report_race_stage='after-report-leaf-prebind'
    json_report_args=(--json-report "$evidence_root/leaf-race.json")
  fi

  mkdir -p "$home/.vibe-external-alias"
  : >"$home/.vibe-external-alias/kept.txt"
  ln -snf "$home/.vibe-external-alias" "$home/.vibe-external-link"

  local probe_list
  local before_meta
  local after_meta
  probe_list="$(mktemp)"

  local external_link_in_manifest="false"
  while IFS= read -r target; do
    if [[ "$(resolve_manifest_path "$target" "$home" "$project")" == "$home/.vibe-external-link" ]]; then
      external_link_in_manifest="true"
      break
    fi
  done < <(jq -r '.tools[].targets[].targetPath // empty' "$manifest_path")
  if [[ "$external_link_in_manifest" == "true" ]]; then
    echo "FAIL: external vibe link path appears in manifest targets"
    rm -f "$probe_list" "$report_file" "$stderr_file"
    rm -rf "$home"
    return 1
  fi

  build_d1_probe_list "$home" "$project" "$manifest_path" "$d1_sentinel_scenario" "$probe_list" || return 1
  printf '%s\n' "$home/.vibe-external-link" >> "$probe_list"
  if [[ -n "$report_escape_root" && "$report_mode" != "parent-replacement" ]]; then
    printf '%s\n' "$report_escape_root/sentinel" >> "$probe_list"
  fi
  if [[ "$report_mode" == "existing-leaf" ]]; then
    printf '%s\n' "$evidence_root/existing-report.json" >> "$probe_list"
  fi
  sort -u "$probe_list" -o "$probe_list"
  before_meta="$(mktemp)"
  after_meta="$(mktemp)"
  if ! snapshot_paths_descriptor_no_follow "$home" "$probe_list" "$before_meta"; then
    echo 'FAIL: unable to capture D1 descriptor before snapshot'
    return 1
  fi

  if [[ -n "$d1_injection_rel_enum" ]]; then
    local d1_injection_relative=''
    local d1_command_rc=0
    local d1_changed_paths
    d1_changed_paths="$(mktemp)" || return 1
    case "$d1_injection_rel_enum" in
      main) d1_injection_relative='main' ;;
      auth-profile) d1_injection_relative='main/agent/auth-profiles.json' ;;
      *) d1_injection_relative="$d1_injection_rel_enum" ;;
    esac
    if AGENCY_TEST_D1_OWNER_ACCESS_STAGE='owner-plan-boundary' AGENCY_TEST_D1_OWNER_ACCESS_REL="$d1_injection_relative" SYNC_PROTECTED_ACCESS_AUDIT_FILE="$protected_audit" SYNC_PROTECTED_ACCESS_AUDIT="${SYNC_D1_PROTECTED_AUDIT:-}" HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$manifest_path" --source-root "$source_root_dir" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report_file" 2>"$stderr_file"; then
      d1_command_rc=0
    else
      d1_command_rc=$?
    fi
    if [[ "$d1_command_rc" == "0" ]]; then
      echo 'FAIL: D1 owner-access injection unexpectedly succeeded'
      return 1
    fi
    assert_raw_sync_report_json "$report_file" || return 1
    if [[ "$(json_get "$report_file" result.status)" != "failed" ]] || [[ "$(json_get "$report_file" failure.operation)" != "owner-path-validation" ]] || [[ "$(json_get "$report_file" failure.reason)" != "protected owner access injection blocked" ]]; then
      printf 'D1_INJECTION_REPORT={"operation":"%s","reason":"%s","stage":"%s","status":"%s"}\n' "$(json_get "$report_file" failure.operation)" "$(json_get "$report_file" failure.reason)" "$(json_get "$report_file" failure.stage)" "$(json_get "$report_file" result.status)" >&2
      return 1
    fi
    if ! snapshot_paths_descriptor_no_follow "$home" "$probe_list" "$after_meta"; then
      echo 'FAIL: unable to capture D1 injection descriptor after snapshot'
      return 1
    fi
    if ! snapshot_diff_paths "$before_meta" "$after_meta" "$d1_changed_paths" >/dev/null; then
      echo 'FAIL: D1 injection changed protected or owner-external sentinel metadata'
      return 1
    fi
    assert_d1_sentinel_snapshot "$before_meta" "$after_meta" "$home" "$d1_sentinel_scenario" injection || return 1
    assert_d1_protected_access_audit "$protected_audit" "injection-${d1_sentinel_scenario}" true "$d1_injection_rel_enum" || return 1
    rm -rf "$home" "$report_file" "$probe_list" "$before_meta" "$after_meta" "$d1_changed_paths"
    return 0
  fi

  local -a sync_args
  sync_args=(--home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$manifest_path" --source-root "$source_root_dir" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger")
  if [[ "${#json_report_args[@]}" -gt 0 ]]; then
    sync_args+=("${json_report_args[@]}")
  fi
  local command_rc=0
  set +e
  AGENCY_TEST_REPORT_RACE_STAGE="$report_race_stage" SYNC_PROTECTED_ACCESS_AUDIT_FILE="$protected_audit" SYNC_PROTECTED_ACCESS_AUDIT="${SYNC_D1_PROTECTED_AUDIT:-}" HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" "${sync_args[@]}" >"$report_file" 2>"$stderr_file"
  command_rc=$?
  set -e
  if [[ -n "$report_mode" ]]; then
    emit_focused_case_diagnostic "$report_file" "$stderr_file" "$command_rc"
  fi
  if [[ "$command_rc" != "0" ]]; then
    if [[ -n "$report_mode" ]]; then
      if ! assert_raw_sync_report_json "$report_file"; then
        echo 'FAIL: prefix-collision did not emit one JSON report' >&2
        return 1
      fi
      if [[ "$report_mode" == "prefix-collision" ]]; then
        [[ "$(json_get "$report_file" result.status)" == "failed" && "$(json_get "$report_file" failure.stage)" == "report-path-validation" && "$(json_get "$report_file" failure.operation)" == "report-path-validation" && "$(json_get "$report_file" failure.reason)" == "report path validation failed" ]] || {
          echo 'FAIL: prefix-collision report contract mismatch' >&2
          return 1
        }
      elif [[ "$report_mode" == "parent-symlink" ]]; then
        [[ "$(json_get "$report_file" result.status)" == "failed" && "$(json_get "$report_file" failure.stage)" == "report-path-validation" && "$(json_get "$report_file" failure.operation)" == "report-path-validation" && "$(json_get "$report_file" failure.reason)" == "report path validation failed" ]] || {
          echo "FAIL: $report_mode report contract mismatch" >&2
          return 1
        }
      elif [[ "$report_mode" == "existing-leaf" ]]; then
        [[ "$(json_get "$report_file" result.status)" == "failed" && "$(json_get "$report_file" failure.stage)" == "report-path-validation" && "$(json_get "$report_file" failure.operation)" == "report-path-validation" && "$(json_get "$report_file" failure.reason)" == "report path validation failed" ]] || {
          echo "FAIL: $report_mode report contract mismatch" >&2
          return 1
        }
      elif [[ "$report_mode" == "parent-replacement" ]]; then
        [[ "$(json_get "$report_file" result.status)" == "failed" && "$(json_get "$report_file" failure.stage)" == "report-path-validation" && "$(json_get "$report_file" failure.operation)" == "report-path-validation" && "$(json_get "$report_file" failure.reason)" == "report path validation failed" ]] || {
          printf 'FAIL: %s report contract mismatch actual=%s/%s/%s/%s expected=failed/report-path-validation/report-path-validation/report path validation failed\n' \
            "$report_mode" \
            "$(json_get "$report_file" result.status)" \
            "$(json_get "$report_file" failure.stage)" \
            "$(json_get "$report_file" failure.operation)" \
            "$(json_get "$report_file" failure.reason)" >&2
          return 1
        }
      elif [[ "$report_mode" == "leaf-replacement" ]]; then
        [[ "$(json_get "$report_file" result.status)" == "failed" && "$(json_get "$report_file" failure.stage)" == "report-path-validation" && "$(json_get "$report_file" failure.operation)" == "report-path-validation" && "$(json_get "$report_file" failure.reason)" == "report path validation failed" ]] || {
          echo "FAIL: $report_mode report contract mismatch" >&2
          return 1
        }
      elif [[ "$(json_get "$report_file" result.status)" != "failed" || "$(json_get "$report_file" failure.stage)" != "report-path-validation" || "$(json_get "$report_file" failure.operation)" != "report-path-validation" || "$(json_get "$report_file" failure.reason)" != "report path validation failed" ]]; then
        echo "FAIL: $report_mode report contract mismatch" >&2
        return 1
      fi
      if [[ -e "$report_escape_root/nested/report.json" ]]; then
        echo 'FAIL: prefix-collision created an escaped report leaf' >&2
        return 1
      fi
      if ! snapshot_paths_descriptor_no_follow "$home" "$probe_list" "$after_meta"; then
        echo 'FAIL: prefix-collision after snapshot failed' >&2
        return 1
      fi
      local collision_changed_paths
      collision_changed_paths="$(mktemp)"
      if snapshot_diff_paths "$before_meta" "$after_meta" "$collision_changed_paths"; then
        :
      else
        echo 'FAIL: prefix-collision changed target, ledger, or sentinel state' >&2
        return 1
      fi
      if [[ "$report_mode" == "parent-replacement" ]]; then
        local report_race_sentinel_after
        report_race_sentinel_after="$(test_root_sentinel_metadata "$evidence_root/custom-parent/sentinel")" || return 1
        [[ "$report_race_sentinel_before" == "$report_race_sentinel_after" ]] || {
          echo 'FAIL: report replacement sentinel metadata changed' >&2
          return 1
        }
      elif [[ "$report_mode" == "leaf-replacement" ]]; then
        local report_leaf_sentinel_after
        if ! rg -q '^REPORT_LEAF_RACE_HIT=after-report-leaf-prebind$' "$stderr_file"; then
          emit_post_auth_stage_last "$stderr_file"
          local binder_reason
          if binder_reason="$(read_binder_rc74_reason "$stderr_file")"; then
            printf 'BINDER_RC74_REASON=%s\n' "$binder_reason" >&2
          else
            echo 'FAIL: missing unique allowlisted binder rc74 receipt' >&2
          fi
          echo 'FAIL: report leaf replacement hook not hit' >&2
          return 1
        fi
        report_leaf_sentinel_after="$(test_root_sentinel_metadata "$evidence_root/leaf-race.json")" || return 1
        [[ "$report_race_sentinel_before" == "$report_leaf_sentinel_after" ]] || {
          python3 - "$report_race_sentinel_before" "$report_leaf_sentinel_after" <<'PY' >&2
import hashlib
import json
import sys
before_raw, after_raw = sys.argv[1:]
before = json.loads(before_raw)
after = json.loads(after_raw)
changed = ",".join(sorted(key for key in set(before) | set(after) if before.get(key) != after.get(key)))
print("FAIL: report leaf replacement sentinel metadata changed fields=%s before_sha256=%s after_sha256=%s" % (
    changed or "none",
    hashlib.sha256(before_raw.encode("utf-8")).hexdigest(),
    hashlib.sha256(after_raw.encode("utf-8")).hexdigest(),
))
PY
          return 1
        }
      fi
      unlink "$collision_changed_paths"
      rm -rf "$home" "$report_file" "$probe_list" "$before_meta" "$after_meta"
      return 0
    fi
    echo 'FAIL: apply command returned nonzero before a successful report' >&2
    rm -rf "$home" "$probe_list" "$before_meta" "$after_meta"
    return 1
  fi

  rm -f "$stderr_file"

  if ! assert_raw_sync_report_json "$report_file"; then
    echo "FAIL: apply stdout is not one local sync report JSON object"
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

  raw_qwen="$(jq -r '.tools[] | select(.installTool=="qwen") | .targets[0].targetPath // empty' "$manifest_path")"
  raw_kimi="$(jq -r '.tools[] | select(.installTool=="kimi") | .targets[0].targetPath // empty' "$manifest_path")"
  if [[ "$qwen_manifest" != "$(resolve_manifest_path "$raw_qwen" "$home" "$project")" ]]; then
    echo "FAIL: qwen manifest path mismatch"
    rm -rf "$home" "$report_file" "$probe_list" "$before_meta" "$after_meta"
    return 1
  fi
  if [[ "$kimi_manifest" != "$(resolve_manifest_path "$raw_kimi" "$home" "$project")" ]]; then
    echo "FAIL: kimi manifest path mismatch"
    rm -rf "$home" "$report_file" "$probe_list" "$before_meta" "$after_meta"
    return 1
  fi

  if [[ ! -d "$qwen_manifest" || ! -d "$kimi_manifest" ]]; then
    echo "FAIL: qwen/kimi paths missing"
    return 1
  fi

  if ! snapshot_paths_descriptor_no_follow "$home" "$probe_list" "$after_meta"; then
    echo 'FAIL: unable to capture D1 descriptor after snapshot'
    return 1
  fi
  local changed_paths
  changed_paths="$(mktemp)"
  if ! snapshot_diff_paths "$before_meta" "$after_meta" "$changed_paths"; then
    local touched_protected=0
    while IFS= read -r path; do
      case "$path" in
        "$home/.openclaw/agents/main"|"$home/.openclaw/agents/main/agent/auth-profiles.json")
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
      rm -rf "$home" "$report_file" "$probe_list" "$before_meta" "$after_meta" "$changed_paths"
      return 1
    fi
  fi

  assert_d1_sentinel_snapshot "$before_meta" "$after_meta" "$home" "$d1_sentinel_scenario" apply || return 1
  if [[ "$(readlink "$home/.vibe-external-link")" != "$home/.vibe-external-alias" ]]; then
    echo "FAIL: external vibe link changed"
    return 1
  fi
  if [[ ! -d "$home/.vibe/agents" || ! -d "$home/.vibe/prompts" ]]; then
    echo "FAIL: expected vibe targets to be reconciled"
    rm -rf "$home" "$report_file" "$probe_list" "$before_meta" "$after_meta"
    return 1
  fi

  if [[ -n "$protected_audit" ]]; then
    assert_d1_protected_access_audit "$protected_audit" "apply-${d1_sentinel_scenario}" false || return 1
  fi

  assert_role_contract "$report_file" || return 1

  rm -rf "$home" "$report_file" "$probe_list" "$before_meta" "$after_meta"
  return 0
}

snapshot_qwen_kimi_state() {
  local trusted_root="$1"
  local output_file="$2"
  python3 - "$trusted_root" "$output_file" <<'PY'
import hashlib
import hashlib
import json
import os
import stat
import sys

trusted_root, output_file = sys.argv[1:]
O_DIRECTORY = getattr(os, "O_DIRECTORY", 0)
O_NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
relatives = [".qwen", ".qwen/agents", ".config", ".config/kimi", ".config/kimi/agents"]

def digest_fd(fd):
    digest = hashlib.sha256()
    for name in sorted(os.listdir(fd)):
        child_st = os.stat(name, dir_fd=fd, follow_symlinks=False)
        mode = stat.S_IMODE(child_st.st_mode)
        if stat.S_ISREG(child_st.st_mode):
            child_fd = os.open(name, os.O_RDONLY | O_NOFOLLOW, dir_fd=fd)
            try:
                child_digest = hashlib.sha256()
                while True:
                    block = os.read(child_fd, 1024 * 1024)
                    if not block:
                        break
                    child_digest.update(block)
            finally:
                os.close(child_fd)
            kind = "file"
            value = child_digest.hexdigest()
        elif stat.S_ISDIR(child_st.st_mode):
            child_fd = os.open(name, os.O_RDONLY | O_DIRECTORY | O_NOFOLLOW, dir_fd=fd)
            try:
                value = digest_fd(child_fd)
            finally:
                os.close(child_fd)
            kind = "directory"
        elif stat.S_ISLNK(child_st.st_mode):
            kind = "symlink"
            value = hashlib.sha256(os.readlink(name, dir_fd=fd).encode("utf-8", "surrogateescape")).hexdigest()
        else:
            kind = "special"
            value = hashlib.sha256(f"special|{mode:o}|{child_st.st_size}".encode("ascii")).hexdigest()
        digest.update(f"{kind}|{name}|{mode:o}|{child_st.st_size}|{value}\n".encode("utf-8"))
    return digest.hexdigest()

root_fd = os.open(trusted_root, os.O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
result = {}
try:
    for relative in relatives:
        parts = relative.split("/")
        current_fd = os.dup(root_fd)
        try:
            absent = False
            for part in parts[:-1]:
                try:
                    part_st = os.stat(part, dir_fd=current_fd, follow_symlinks=False)
                except FileNotFoundError:
                    absent = True
                    break
                if stat.S_ISLNK(part_st.st_mode) or not stat.S_ISDIR(part_st.st_mode):
                    result[relative] = {"exists": True, "type": "unsafe-parent", "mode": format(stat.S_IMODE(part_st.st_mode), "o"), "size": part_st.st_size, "digest": hashlib.sha256(b"unsafe-parent").hexdigest()}
                    absent = True
                    break
                next_fd = os.open(part, os.O_RDONLY | O_DIRECTORY | O_NOFOLLOW, dir_fd=current_fd)
                os.close(current_fd)
                current_fd = next_fd
            if absent:
                result.setdefault(relative, {"exists": False, "type": "absent", "mode": "-", "size": 0, "digest": hashlib.sha256(b"absent").hexdigest()})
                continue
            try:
                item_st = os.stat(parts[-1], dir_fd=current_fd, follow_symlinks=False)
            except FileNotFoundError:
                result[relative] = {"exists": False, "type": "absent", "mode": "-", "size": 0, "digest": hashlib.sha256(b"absent").hexdigest()}
                continue
            mode = stat.S_IMODE(item_st.st_mode)
            if stat.S_ISDIR(item_st.st_mode):
                item_fd = os.open(parts[-1], os.O_RDONLY | O_DIRECTORY | O_NOFOLLOW, dir_fd=current_fd)
                try:
                    item_digest = digest_fd(item_fd)
                finally:
                    os.close(item_fd)
                kind = "directory"
            elif stat.S_ISREG(item_st.st_mode):
                item_fd = os.open(parts[-1], os.O_RDONLY | O_NOFOLLOW, dir_fd=current_fd)
                try:
                    h = hashlib.sha256()
                    while True:
                        block = os.read(item_fd, 1024 * 1024)
                        if not block:
                            break
                        h.update(block)
                    item_digest = h.hexdigest()
                finally:
                    os.close(item_fd)
                kind = "file"
            elif stat.S_ISLNK(item_st.st_mode):
                kind = "symlink"
                item_digest = hashlib.sha256(os.readlink(parts[-1], dir_fd=current_fd).encode("utf-8", "surrogateescape")).hexdigest()
            else:
                kind = "special"
                item_digest = hashlib.sha256(f"special|{mode:o}|{item_st.st_size}".encode("ascii")).hexdigest()
            result[relative] = {"exists": True, "type": kind, "mode": format(mode, "o"), "size": item_st.st_size, "digest": item_digest}
        finally:
            os.close(current_fd)
finally:
    os.close(root_fd)
with open(output_file, "w", encoding="utf-8") as fp:
    json.dump(result, fp, separators=(",", ":"), sort_keys=True)
PY
}

print_qwen_kimi_diagnostic() {
  local report_file="$1"
  local command_rc="$2"
  local before_file="$3"
  local after_file="$4"
  python3 - "$report_file" "$command_rc" "$before_file" "$after_file" >&2 <<'PY'
import json
import sys

report = json.load(open(sys.argv[1], encoding="utf-8"))
before = json.load(open(sys.argv[3], encoding="utf-8"))
after = json.load(open(sys.argv[4], encoding="utf-8"))
failure = report.get("failure", {})
manifest = report.get("manifest", {})
result = report.get("result", {})
rollback = report.get("rollback", {})
changes = {"added": [], "modified": [], "deleted": []}
for relative in sorted(set(before) | set(after)):
    if not before.get(relative, {}).get("exists") and after.get(relative, {}).get("exists"):
        changes["added"].append(relative)
    elif before.get(relative, {}).get("exists") and not after.get(relative, {}).get("exists"):
        changes["deleted"].append(relative)
    elif before.get(relative) != after.get(relative):
        changes["modified"].append(relative)
print("QWEN_KIMI_DIAGNOSTIC=" + json.dumps({
    "rc": int(sys.argv[2]),
    "stage": failure.get("stage"),
    "reason": failure.get("reason"),
    "operation": failure.get("operation"),
    "transactionCount": manifest.get("transactionCount"),
    "backupCount": result.get("backupCount"),
    "rollback": {
        "performed": rollback.get("performed"),
        "attempted": rollback.get("attempted"),
        "restored": rollback.get("restored"),
        "restoreFailures": len(rollback.get("restoreFailures", [])) if isinstance(rollback.get("restoreFailures"), list) else None,
    },
    "targets": after,
    "changes": changes,
}, separators=(",", ":"), sort_keys=True))
PY
}

case_missing_qwen_kimi_targets() {
  local case_root result_root raw_report clean_report stderr_file before_state after_state command_rc
  case_root="$(fixture_case_home)"
  result_root="$(mktemp -d "$FIXTURE_ROOT/qwen-kimi-result.XXXXXX")"
  chmod 700 "$result_root"
  local source_root_dir
  local manifest_path
  local evidence_root="$case_root/.codex/supervisor-runtime-evidence"
  local evidence_signers="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/allowed_signers"
  local evidence_ledger="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/owner-only-ledger.jsonl"
  source_root_dir="$(fixture_source_copy "$case_root")"
  manifest_path="$(fixture_manifest_path "$case_root")"

  prepare_installed_manifest_targets "$case_root" "$case_root" "$manifest_path"
  clear_qwen_kimi_targets "$case_root"

  read -r action signature allowed_signers < <(build_auth_bundle "$case_root/bundle" aicc-supervisor-authorization supervisor-approver "$case_root/action.json" "$manifest_path" "$evidence_signers" "isolated-test" "$case_root" "$case_root")

  raw_report="$result_root/raw.json"
  clean_report="$result_root/report.json"
  stderr_file="$result_root/stderr.log"
  before_state="$result_root/before.json"
  after_state="$result_root/after.json"
  snapshot_qwen_kimi_state "$case_root" "$before_state"

  if HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" --home "$case_root" --test-mode --test-mode-root "$case_root" --apply --manifest "$manifest_path" --source-root "$source_root_dir" --project "$case_root" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$raw_report" 2>"$stderr_file"; then
    command_rc=0
  else
    command_rc=$?
  fi
  snapshot_qwen_kimi_state "$case_root" "$after_state"
  if ! read_isolated_sync_report "$result_root" "$raw_report" "$clean_report"; then
    echo "FAIL: qwen/kimi apply did not emit one isolated sync report"
    return 1
  fi
  print_qwen_kimi_diagnostic "$clean_report" "$command_rc" "$before_state" "$after_state"
  if [[ "$command_rc" != "0" ]]; then
    return 1
  fi

  python3 -c '
import json
import os
import stat
import sys

flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
fd = os.open(sys.argv[1], flags)
try:
    metadata = os.fstat(fd)
    if not stat.S_ISREG(metadata.st_mode):
        raise SystemExit(1)
    chunks = []
    while True:
        chunk = os.read(fd, 65536)
        if not chunk:
            break
        chunks.append(chunk)
finally:
    os.close(fd)
state = json.loads(b"".join(chunks).decode("utf-8"))
expected = {
    ".qwen": "directory",
    ".qwen/agents": "directory",
    ".config": "directory",
    ".config/kimi": "directory",
    ".config/kimi/agents": "directory",
}
for relative, expected_type in expected.items():
    item = state.get(relative, {})
    if item.get("exists") is not True or item.get("type") != expected_type:
        raise SystemExit(1)
    if item.get("mode") != "700" or not item.get("digest"):
        raise SystemExit(1)
' "$after_state" || {
    echo "FAIL: qwen/kimi descriptor state does not match created target contract"
    return 1
  }

  rm -rf "$case_root" "$result_root"
  return 0
}

case_missing_qwen_or_kimi_source_is_blocked() {
  local missing_source="$1"
  local home report
  home="$(fixture_case_home)"
  local manifest_path
  local report_file
  local source_root_dir="$home/source"
  local evidence_root="$home/.codex/supervisor-runtime-evidence"
  local evidence_signers="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/allowed_signers"
  local evidence_ledger="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/owner-only-ledger.jsonl"
  source_root_dir="$(fixture_source_copy "$home")"
  manifest_path="$(fixture_manifest_path "$home")"
  rm -rf "$source_root_dir/$missing_source"

  read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" aicc-supervisor-authorization supervisor-approver "$home/action.json" "$manifest_path" "$evidence_signers" "isolated-test" "$home" "$home")

  report_file="$(mktemp)"
  if HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$manifest_path" --source-root "$source_root_dir" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report_file"; then
    echo "FAIL: missing ${missing_source} source should be BLOCK"
    rm -rf "$home" "$report_file"
    return 1
  fi

  rm -rf "$home" "$report_file"
  return 0
}

case_stage_copy_failure_records_reason_and_operation() {
  local home report
  home="$(fixture_case_home)"
  local manifest_path
  local evidence_root="$home/.codex/supervisor-runtime-evidence"
  local evidence_signers="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/allowed_signers"
  local evidence_ledger="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/owner-only-ledger.jsonl"
  local src_root
  local action signature allowed_signers
  local report_file
  local report_json
  local failure_operation failure_reason

  src_root="$(fixture_source_copy "$home")"
  manifest_path="$(fixture_manifest_path "$home")"
  chmod 000 "$src_root/aider/CONVENTIONS.md"

  read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" aicc-supervisor-authorization supervisor-approver "$home/action.json" "$manifest_path" "$evidence_signers" "isolated-test" "$home" "$home")
  report_file="$(mktemp)"
  report_json="$(mktemp)"

  if HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$manifest_path" --source-root "$src_root" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report_file" 2>&1; then
    chmod 600 "$src_root/aider/CONVENTIONS.md"
    rm -rf "$home" "$report_file" "$report_json"
    return 1
  fi

  if ! extract_report_json "$report_file" "$report_json"; then
    chmod 600 "$src_root/aider/CONVENTIONS.md"
    rm -rf "$home" "$report_file" "$report_json"
    return 1
  fi

  if [[ "$(json_get "$report_json" result.status)" != "failed" ]]; then
    echo "FAIL: stage-copy mutation should fail"
    chmod 600 "$src_root/aider/CONVENTIONS.md"
    rm -rf "$home" "$report_file" "$report_json"
    return 1
  fi
  failure_operation="$(json_get "$report_json" failure.operation)"
  failure_reason="$(json_get "$report_json" failure.reason)"
  if [[ "$failure_operation" != "stage-copy" || -z "$failure_reason" ]]; then
    echo "FAIL: stage-copy failure operation/reason missing (operation=$failure_operation reason=$failure_reason)"
    chmod 600 "$src_root/aider/CONVENTIONS.md"
    rm -rf "$home" "$report_file" "$report_json"
    return 1
  fi

  chmod 600 "$src_root/aider/CONVENTIONS.md"
  rm -rf "$home" "$report_file" "$report_json"
  return 0
}

case_target_backup_failure_records_reason_and_operation() {
  local home report
  home="$(fixture_case_home)"
  local manifest_path
  local evidence_root="$home/.codex/supervisor-runtime-evidence"
  local evidence_signers="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/allowed_signers"
  local evidence_ledger="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/owner-only-ledger.jsonl"
  local src_root
  local action signature allowed_signers
  local report_file
  local report_json
  local failure_operation failure_reason
  local qwen_target
  local qwen_parent

  src_root="$(fixture_source_copy "$home")"
  manifest_path="$(fixture_manifest_path "$home")"
  prepare_installed_manifest_targets "$home" "$home" "$manifest_path"
  qwen_target="$(resolve_manifest_path "$(jq -r '.tools[] | select(.installTool=="qwen") | .targets[0].targetPath // empty' "$manifest_path")" "$home" "$home")"
  qwen_parent="$(dirname "$qwen_target")"
  chmod a-w "$qwen_parent"

  read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" aicc-supervisor-authorization supervisor-approver "$home/action.json" "$manifest_path" "$evidence_signers" "isolated-test" "$home" "$home")
  report_file="$(mktemp)"
  report_json="$(mktemp)"

  if HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$manifest_path" --source-root "$src_root" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report_file" 2>&1; then
    chmod u+w "$qwen_parent"
    rm -rf "$home" "$report_file" "$report_json"
    return 1
  fi

  if ! extract_report_json "$report_file" "$report_json"; then
    chmod u+w "$qwen_parent"
    rm -rf "$home" "$report_file" "$report_json"
    return 1
  fi

  if [[ "$(json_get "$report_json" result.status)" != "failed" ]]; then
    echo "FAIL: target-backup mutation should fail"
    chmod u+w "$qwen_parent"
    rm -rf "$home" "$report_file" "$report_json"
    return 1
  fi
  failure_operation="$(json_get "$report_json" failure.operation)"
  failure_reason="$(json_get "$report_json" failure.reason)"
  if [[ "$failure_operation" != "target-backup" || -z "$failure_reason" ]]; then
    echo "FAIL: target-backup failure operation/reason missing (operation=$failure_operation reason=$failure_reason)"
    chmod u+w "$qwen_parent"
    rm -rf "$home" "$report_file" "$report_json"
    return 1
  fi

  chmod u+w "$qwen_parent"
  rm -rf "$home" "$report_file" "$report_json"
  return 0
}

snapshot_replay_ledger() {
  local trusted_root="$1"
  local ledger_relative="$2"
  local output_file="$3"
  python3 - "$trusted_root" "$ledger_relative" "$output_file" <<'PY'
import hashlib
import json
import os
import stat
import sys

trusted_root, relative, output_file = sys.argv[1:]
nofollow = getattr(os, "O_NOFOLLOW", 0)
cloexec = getattr(os, "O_CLOEXEC", 0)
root_fd = os.open(trusted_root, os.O_RDONLY | os.O_DIRECTORY | nofollow | cloexec)
current_fd = root_fd
opened = []
state = {"exists": False, "inode": 0, "mode": "-", "size": 0, "digest": hashlib.sha256(b"absent").hexdigest(), "entryCount": 0}
try:
    parts = relative.split("/")
    if not parts or any(part in ("", ".", "..") for part in parts):
        raise SystemExit(1)
    try:
        for part in parts[:-1]:
            next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | nofollow | cloexec, dir_fd=current_fd)
            opened.append(next_fd)
            current_fd = next_fd
        ledger_fd = os.open(parts[-1], os.O_RDONLY | nofollow | cloexec, dir_fd=current_fd)
    except FileNotFoundError:
        ledger_fd = None
    if ledger_fd is not None:
        opened.append(ledger_fd)
        before = os.fstat(ledger_fd)
        if not stat.S_ISREG(before.st_mode):
            raise SystemExit(1)
        chunks = []
        while True:
            chunk = os.read(ledger_fd, 65536)
            if not chunk:
                break
            chunks.append(chunk)
        after = os.fstat(ledger_fd)
        if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns):
            raise SystemExit(1)
        payload = b"".join(chunks)
        state = {
            "exists": True,
            "inode": before.st_ino,
            "mode": format(stat.S_IMODE(before.st_mode), "o"),
            "size": before.st_size,
            "digest": hashlib.sha256(payload).hexdigest(),
            "entryCount": len(payload.splitlines()),
        }
finally:
    for fd in reversed(opened):
        os.close(fd)
    os.close(root_fd)
with open(output_file, "x", encoding="utf-8") as handle:
    json.dump(state, handle, separators=(",", ":"), sort_keys=True)
PY
}

snapshot_replay_targets() {
  local trusted_root="$1"
  local manifest_path="$2"
  local output_file="$3"
  local probe_list
  local absolute_snapshot
  probe_list="$(mktemp)"
  absolute_snapshot="$(mktemp)"
  collect_probe_paths "$trusted_root" "$trusted_root" "$probe_list" "$manifest_path"
  snapshot_paths_with_digest "$probe_list" "$absolute_snapshot"
  python3 - "$trusted_root" "$absolute_snapshot" "$output_file" <<'PY'
import json
import os
import sys

trusted_root, input_file, output_file = sys.argv[1:]
root = os.path.realpath(trusted_root)
with open(input_file, encoding="utf-8") as handle:
    source = json.load(handle)
result = {}
for absolute, value in source.items():
    relative = os.path.relpath(absolute, root)
    if relative == ".." or relative.startswith("../") or os.path.isabs(relative):
        raise SystemExit(1)
    result[relative] = value
with open(output_file, "x", encoding="utf-8") as handle:
    json.dump(result, handle, separators=(",", ":"), sort_keys=True)
PY
  rm -f "$probe_list" "$absolute_snapshot"
}

print_replay_diagnostic() {
  local first_report="$1" second_report="$2" first_rc="$3" second_rc="$4"
  local ledger_before="$5" ledger_first="$6" ledger_second="$7"
  local targets_first="$8" targets_second="$9" first_stderr="${10}" second_stderr="${11}"
  python3 - "$first_report" "$second_report" "$first_rc" "$second_rc" "$ledger_before" "$ledger_first" "$ledger_second" "$targets_first" "$targets_second" "$first_stderr" "$second_stderr" <<'PY'
import hashlib
import json
import os
import sys

first_report, second_report, first_rc, second_rc, ledger_before, ledger_first, ledger_second, targets_first, targets_second, first_stderr, second_stderr = sys.argv[1:]
def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)
def report(path, rc):
    value = load(path)
    failure = value.get("failure") or {}
    rollback = value.get("rollback") or {}
    security = value.get("supervisorAuthorization") or value.get("security") or {}
    manifest = value.get("manifest") or {}
    result = value.get("result") or {}
    return {
        "rc": int(rc),
        "status": result.get("status"),
        "stage": failure.get("stage"),
        "reason": failure.get("reason"),
        "operation": failure.get("operation"),
        "securityReason": security.get("reason"),
        "transactionCount": manifest.get("transactionCount"),
        "backupCount": result.get("backupCount"),
        "rollback": {key: rollback.get(key) for key in ("performed", "attempted", "restored", "restoreFailures")},
    }
def stderr_summary(path):
    data = open(path, "rb").read()
    return {"size": len(data), "lineCount": len(data.splitlines()), "digest": hashlib.sha256(data).hexdigest()}
first_targets = load(targets_first)
second_targets = load(targets_second)
output = {
    "first": report(first_report, first_rc),
    "second": report(second_report, second_rc),
    "ledger": {"before": load(ledger_before), "afterFirst": load(ledger_first), "afterSecond": load(ledger_second)},
    "targets": {"entryCount": len(first_targets), "unchangedAfterReplay": first_targets == second_targets},
    "stderr": {"first": stderr_summary(first_stderr), "second": stderr_summary(second_stderr)},
}
print("LEDGER_REPLAY_DIAGNOSTIC=" + json.dumps(output, separators=(",", ":"), sort_keys=True), file=sys.stderr)
PY
}

case_replay_rejected() {
  local case_root result_root manifest_path evidence_root evidence_signers evidence_ledger src_root
  local raw_first raw_second clean_first clean_second stderr_first stderr_second
  local ledger_before ledger_first ledger_second targets_first targets_second first_rc second_rc
  local poison_ledger poison_report poison_report_json poison_before poison_after
  case_root="$(fixture_case_home)"
  result_root="$(mktemp -d "$FIXTURE_ROOT/ledger-replay-result.XXXXXX")"
  chmod 700 "$result_root"
  manifest_path="$(fixture_manifest_path "$case_root")"
  evidence_root="$case_root/.codex/supervisor-runtime-evidence"
  evidence_signers="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/allowed_signers"
  evidence_ledger="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/owner-only-ledger.jsonl"
  src_root="$(fixture_source_copy "$case_root")"
  prepare_installed_manifest_targets "$case_root" "$case_root" "$manifest_path"
  clear_qwen_kimi_targets "$case_root"
  IFS=' ' read -r action signature allowed_signers < <(build_auth_bundle "$case_root/bundle" aicc-supervisor-authorization supervisor-approver "$case_root/action.json" "$manifest_path" "$evidence_signers" "isolated-test" "$case_root" "$case_root")

  raw_first="$result_root/first-raw.json"
  raw_second="$result_root/second-raw.json"
  clean_first="$result_root/first-report.json"
  clean_second="$result_root/second-report.json"
  stderr_first="$result_root/first-stderr.log"
  stderr_second="$result_root/second-stderr.log"
  ledger_before="$result_root/ledger-before.json"
  ledger_first="$result_root/ledger-after-first.json"
  ledger_second="$result_root/ledger-after-second.json"
  targets_first="$result_root/targets-after-first.json"
  targets_second="$result_root/targets-after-second.json"

  snapshot_replay_ledger "$case_root" ".codex/supervisor-authority/owner-only-ledger.jsonl" "$ledger_before"
  if HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" --home "$case_root" --test-mode --test-mode-root "$case_root" --apply --manifest "$manifest_path" --source-root "$src_root" --project "$case_root" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$raw_first" 2>"$stderr_first"; then
    first_rc=0
  else
    first_rc=$?
  fi
  snapshot_replay_ledger "$case_root" ".codex/supervisor-authority/owner-only-ledger.jsonl" "$ledger_first"
  snapshot_replay_targets "$case_root" "$manifest_path" "$targets_first"
  read_isolated_sync_report "$result_root" "$raw_first" "$clean_first" || return 1
  if [[ "$first_rc" != "0" ]]; then
    cp "$clean_first" "$clean_second"
    cp "$stderr_first" "$stderr_second"
    cp "$ledger_first" "$ledger_second"
    cp "$targets_first" "$targets_second"
    print_replay_diagnostic "$clean_first" "$clean_second" "$first_rc" "$first_rc" "$ledger_before" "$ledger_first" "$ledger_second" "$targets_first" "$targets_second" "$stderr_first" "$stderr_second"
    return 1
  fi

  if HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" --home "$case_root" --test-mode --test-mode-root "$case_root" --apply --manifest "$manifest_path" --source-root "$src_root" --project "$case_root" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$raw_second" 2>"$stderr_second"; then
    second_rc=0
  else
    second_rc=$?
  fi
  snapshot_replay_ledger "$case_root" ".codex/supervisor-authority/owner-only-ledger.jsonl" "$ledger_second"
  snapshot_replay_targets "$case_root" "$manifest_path" "$targets_second"
  read_isolated_sync_report "$result_root" "$raw_second" "$clean_second" || return 1
  print_replay_diagnostic "$clean_first" "$clean_second" "$first_rc" "$second_rc" "$ledger_before" "$ledger_first" "$ledger_second" "$targets_first" "$targets_second" "$stderr_first" "$stderr_second"

  python3 - "$clean_first" "$clean_second" "$ledger_before" "$ledger_first" "$ledger_second" "$targets_first" "$targets_second" "$first_rc" "$second_rc" <<'PY' || return 1
import json
import sys

first_report, second_report, before_path, first_path, second_path, first_targets_path, second_targets_path, first_rc, second_rc = sys.argv[1:]
load = lambda path: json.load(open(path, encoding="utf-8"))
first = load(first_report)
second = load(second_report)
before = load(before_path)
after_first = load(first_path)
after_second = load(second_path)
if int(first_rc) != 0 or (first.get("result") or {}).get("status") != "passed":
    raise SystemExit(1)
if int(second_rc) == 0 or (second.get("result") or {}).get("status") != "failed":
    raise SystemExit(1)
if (first.get("manifest") or {}).get("transactionCount") != 18 or (second.get("manifest") or {}).get("transactionCount") != 18:
    raise SystemExit(1)
if (first.get("result") or {}).get("backupCount") != 18 or (second.get("result") or {}).get("backupCount") != 0:
    raise SystemExit(1)
security = second.get("supervisorAuthorization") or second.get("security") or {}
failure = second.get("failure") or {}
if security.get("reason") != "action replay detected" and failure.get("reason") != "action replay detected":
    raise SystemExit(1)
if before.get("exists") or not after_first.get("exists") or after_first.get("entryCount") != 1:
    raise SystemExit(1)
for key in ("exists", "inode", "mode", "size", "digest", "entryCount"):
    if after_first.get(key) != after_second.get(key):
        raise SystemExit(1)
if load(first_targets_path) != load(second_targets_path):
    raise SystemExit(1)
PY

  poison_ledger="$case_root/.codex/supervisor-authority/poison-ledger.jsonl"
  poison_report="$result_root/poison-raw.json"
  poison_report_json="$result_root/poison-report.json"
  printf '%s\n' 'invalid ledger entry without fields' > "$poison_ledger"
  poison_before="$(file_hash "$poison_ledger")"
  if HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" --home "$case_root" --test-mode --test-mode-root "$case_root" --apply --manifest "$manifest_path" --source-root "$src_root" --project "$case_root" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$poison_ledger" >"$poison_report" 2>/dev/null; then
    return 1
  fi
  read_isolated_sync_report "$result_root" "$poison_report" "$poison_report_json" || return 1
  poison_after="$(file_hash "$poison_ledger")"
  [[ "$poison_before" == "$poison_after" ]] || return 1

  rm -rf "$case_root" "$result_root"
  return 0
}

case_ledger_intermediate_race() {
  local case_root result_root manifest_path source_root evidence_root authority_root nested_root replacement_root
  local action signature allowed_signers ledger raw_report clean_report stderr_file targets_before targets_after command_rc
  local authority_before authority_after evidence_before evidence_after
  case_root="$(fixture_case_home)"
  result_root="$(mktemp -d "$FIXTURE_ROOT/ledger-race-result.XXXXXX")" || return 1
  chmod 700 "$result_root" || return 1
  manifest_path="$(fixture_manifest_path "$case_root")"
  source_root="$(fixture_source_copy "$case_root")" || return 1
  prepare_installed_manifest_targets "$case_root" "$case_root" "$manifest_path" || return 1
  evidence_root="$case_root/.codex/supervisor-runtime-evidence"
  authority_root="$case_root/.codex/supervisor-authority"
  nested_root="$authority_root/nested"
  replacement_root="$authority_root/.ledger-intermediate-replacement"
  ensure_fixture_security_roots "$case_root" || return 1
  python3 - "$authority_root" <<'PY' || return 1
import os
import stat
import sys

root_fd = None
opened = []
try:
    flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0)
    root_fd = os.open(sys.argv[1], flags)
    root_st = os.fstat(root_fd)
    if not stat.S_ISDIR(root_st.st_mode) or root_st.st_uid != os.getuid() or stat.S_IMODE(root_st.st_mode) != 0o700:
        raise SystemExit(1)
    for leaf in ("nested", ".ledger-intermediate-replacement"):
        os.mkdir(leaf, 0o700, dir_fd=root_fd)
        before = os.stat(leaf, dir_fd=root_fd, follow_symlinks=False)
        child = os.open(leaf, flags, dir_fd=root_fd)
        opened.append(child)
        after = os.fstat(child)
        if (
            not stat.S_ISDIR(before.st_mode)
            or before.st_uid != os.getuid()
            or stat.S_IMODE(before.st_mode) != 0o700
            or (before.st_dev, before.st_ino, before.st_uid, stat.S_IMODE(before.st_mode))
            != (after.st_dev, after.st_ino, after.st_uid, stat.S_IMODE(after.st_mode))
        ):
            raise SystemExit(1)
finally:
    for fd in reversed(opened):
        os.close(fd)
    if root_fd is not None:
        os.close(root_fd)
PY
  IFS=' ' read -r action signature allowed_signers < <(build_auth_bundle "$case_root/bundle" aicc-supervisor-authorization supervisor-approver "$case_root/action.json" "$manifest_path" "$authority_root/allowed_signers" "isolated-test" "$case_root" "$case_root")
  [[ -f "$action" && -f "$signature" && -f "$allowed_signers" ]] || return 1
  ledger="$nested_root/owner-only-ledger.jsonl"
  raw_report="$result_root/raw.json"
  clean_report="$result_root/report.json"
  stderr_file="$result_root/stderr.log"
  targets_before="$result_root/targets-before.json"
  targets_after="$result_root/targets-after.json"
  authority_before="$result_root/authority-before.json"
  authority_after="$result_root/authority-after.json"
  evidence_before="$result_root/evidence-before.json"
  evidence_after="$result_root/evidence-after.json"
  snapshot_replay_ledger "$case_root" ".codex/supervisor-authority/nested/owner-only-ledger.jsonl" "$authority_before" || return 1
  snapshot_replay_ledger "$case_root" ".codex/supervisor-runtime-evidence/owner-only-ledger.jsonl" "$evidence_before" || return 1
  snapshot_replay_targets "$case_root" "$manifest_path" "$targets_before"
  if AGENCY_TEST_LEDGER_RACE_STAGE=ledger-intermediate-after-stat-before-open AGENCY_TEST_LEDGER_RACE_LEAF=nested HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" --home "$case_root" --test-mode --test-mode-root "$case_root" --apply --manifest "$manifest_path" --source-root "$source_root" --project "$case_root" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$ledger" >"$raw_report" 2>"$stderr_file"; then
    command_rc=0
  else
    command_rc=$?
  fi
  snapshot_replay_ledger "$case_root" ".codex/supervisor-authority/nested/owner-only-ledger.jsonl" "$authority_after" || return 1
  snapshot_replay_ledger "$case_root" ".codex/supervisor-runtime-evidence/owner-only-ledger.jsonl" "$evidence_after" || return 1
  snapshot_replay_targets "$case_root" "$manifest_path" "$targets_after"
  read_isolated_sync_report "$result_root" "$raw_report" "$clean_report" || return 1
  [[ "$command_rc" != 0 ]] || return 1
  python3 - "$clean_report" "$targets_before" "$targets_after" "$authority_before" "$authority_after" "$evidence_before" "$evidence_after" "$stderr_file" "$case_root/.codex/supervisor-authority/.ledger-intermediate-old/owner-only-ledger.jsonl" <<'PY' || return 1
import hashlib
import json
import os
import sys

report_path, before_path, after_path, authority_before_path, authority_after_path, evidence_before_path, evidence_after_path, stderr_path, old_ledger = sys.argv[1:]
report = json.load(open(report_path, encoding="utf-8"))
failure = report.get("failure") or {}
security = report.get("security") or report.get("supervisorAuthorization") or {}
result = report.get("result") or {}
rollback = report.get("rollback") or {}
load = lambda path: json.load(open(path, encoding="utf-8"))
targets_before = load(before_path)
targets_after = load(after_path)
authority_before = load(authority_before_path)
authority_after = load(authority_after_path)
evidence_before = load(evidence_before_path)
evidence_after = load(evidence_after_path)
stderr_bytes = open(stderr_path, "rb").read()
prefix = "LEDGER_INTERMEDIATE_RACE_HANDSHAKE "
matches = [line for line in stderr_bytes.decode("utf-8", "replace").splitlines() if line.startswith(prefix)]
expected_keys = {
    "requested",
    "authorized",
    "traversalReached",
    "preStatTaken",
    "replacementPerformed",
    "childOpened",
    "identityMismatchDetected",
    "blockedBeforeMutation",
}
if len(matches) != 1:
    raise SystemExit(1)
fields = dict(item.split("=", 1) for item in matches[0][len(prefix):].split(" "))
if set(fields) != expected_keys or any(value != "true" for value in fields.values()):
    raise SystemExit(1)
diagnostic = {
    "actual": {
        "stage": failure.get("stage"),
        "reason": failure.get("reason"),
        "operation": failure.get("operation"),
        "backupCount": result.get("backupCount"),
        "rollback": {key: rollback.get(key) for key in ("performed", "attempted", "restored", "restoreFailures")},
    },
    "handshake": {key: fields[key] == "true" for key in sorted(expected_keys)},
    "ledger": {
        "authorityBefore": authority_before,
        "authorityAfter": authority_after,
        "evidenceBefore": evidence_before,
        "evidenceAfter": evidence_after,
    },
    "targetsChanged": targets_before != targets_after,
    "stderr": {"size": len(stderr_bytes), "lineCount": len(stderr_bytes.splitlines()), "digest": hashlib.sha256(stderr_bytes).hexdigest()},
}
print("LEDGER_INTERMEDIATE_RACE_DIAGNOSTIC=" + json.dumps(diagnostic, separators=(",", ":"), sort_keys=True), file=sys.stderr)
if report.get("schema") != "agency-agents.local-sync-report/v1" or (report.get("result") or {}).get("status") != "failed":
    raise SystemExit(1)
if failure.get("stage") != "authorization-validation" or failure.get("reason") != "authorization validation failed" or failure.get("operation") != "authorization-validation":
    raise SystemExit(1)
if security.get("reason") != "ledger write failed":
    raise SystemExit(1)
if result.get("backupCount") != 0 or rollback.get("performed") is not False or rollback.get("attempted") != 0 or rollback.get("restored") != 0:
    raise SystemExit(1)
if targets_before != targets_after or authority_before != authority_after or evidence_before != evidence_after:
    raise SystemExit(1)
if authority_after.get("exists") or evidence_after.get("exists") or os.path.lexists(old_ledger):
    raise SystemExit(1)
PY
  rm -rf "$case_root" "$result_root"
  return 0
}

case_ledger_root_layout_negative() {
  local mutation="$1"
  local case_root result_root manifest_path source_root evidence_root authority_root
  local action signature allowed_signers signer_arg ledger_arg raw_report clean_report stderr_file targets_before targets_after command_rc
  local authority_before authority_after evidence_before evidence_after
  case_root="$(fixture_case_home)"
  result_root="$(mktemp -d "$FIXTURE_ROOT/ledger-layout-negative.XXXXXX")" || return 1
  chmod 700 "$result_root" || return 1
  manifest_path="$(fixture_manifest_path "$case_root")"
  source_root="$(fixture_source_copy "$case_root")" || return 1
  prepare_installed_manifest_targets "$case_root" "$case_root" "$manifest_path" || return 1
  evidence_root="$case_root/.codex/supervisor-runtime-evidence"
  authority_root="$case_root/.codex/supervisor-authority"
  mkdir -p "$evidence_root"
  chmod 700 "$case_root/.codex" "$evidence_root"
  IFS=' ' read -r action signature allowed_signers < <(build_auth_bundle "$case_root/bundle" aicc-supervisor-authorization supervisor-approver "$case_root/action.json" "$manifest_path" "$authority_root/allowed_signers" "isolated-test" "$case_root" "$case_root")
  [[ -f "$action" && -f "$signature" && -f "$allowed_signers" ]] || return 1
  signer_arg="$allowed_signers"
  ledger_arg="$authority_root/owner-only-ledger.jsonl"
  case "$mutation" in
    ledger-in-evidence)
      ledger_arg="$evidence_root/owner-only-ledger.jsonl"
      ;;
    evidence-authority-colocate)
      ;;
    signer-outside-authority)
      signer_arg="$case_root/escaped-allowed-signers"
      cp "$allowed_signers" "$signer_arg"
      chmod 600 "$signer_arg"
      ;;
    *) return 1 ;;
  esac
  raw_report="$result_root/raw.json"
  clean_report="$result_root/report.json"
  stderr_file="$result_root/stderr.log"
  targets_before="$result_root/targets-before.json"
  targets_after="$result_root/targets-after.json"
  authority_before="$result_root/authority-before.json"
  authority_after="$result_root/authority-after.json"
  evidence_before="$result_root/evidence-before.json"
  evidence_after="$result_root/evidence-after.json"
  snapshot_replay_ledger "$case_root" ".codex/supervisor-authority/owner-only-ledger.jsonl" "$authority_before" || return 1
  snapshot_replay_ledger "$case_root" ".codex/supervisor-runtime-evidence/owner-only-ledger.jsonl" "$evidence_before" || return 1
  snapshot_replay_targets "$case_root" "$manifest_path" "$targets_before"
  if [[ "$mutation" == evidence-authority-colocate ]]; then
    if AGENCY_TEST_EVIDENCE_ROOT_MODE=authority-colocate HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" --home "$case_root" --test-mode --test-mode-root "$case_root" --apply --manifest "$manifest_path" --source-root "$source_root" --project "$case_root" --action-file "$action" --signature-file "$signature" --allowed-signers "$signer_arg" --ledger "$ledger_arg" >"$raw_report" 2>"$stderr_file"; then
      command_rc=0
    else
      command_rc=$?
    fi
  else
    if AGENCY_TEST_LEDGER_LAYOUT_DIAGNOSTIC="$(if [[ "$mutation" == ledger-in-evidence ]]; then printf '%s' ledger-in-evidence-v1; fi)" HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" --home "$case_root" --test-mode --test-mode-root "$case_root" --apply --manifest "$manifest_path" --source-root "$source_root" --project "$case_root" --action-file "$action" --signature-file "$signature" --allowed-signers "$signer_arg" --ledger "$ledger_arg" >"$raw_report" 2>"$stderr_file"; then
      command_rc=0
    else
      command_rc=$?
    fi
  fi
  snapshot_replay_ledger "$case_root" ".codex/supervisor-authority/owner-only-ledger.jsonl" "$authority_after" || return 1
  snapshot_replay_ledger "$case_root" ".codex/supervisor-runtime-evidence/owner-only-ledger.jsonl" "$evidence_after" || return 1
  snapshot_replay_targets "$case_root" "$manifest_path" "$targets_after"
  read_isolated_sync_report "$result_root" "$raw_report" "$clean_report" || return 1
  [[ "$command_rc" != 0 ]] || return 1
  python3 - "$clean_report" "$targets_before" "$targets_after" "$authority_before" "$authority_after" "$evidence_before" "$evidence_after" "$stderr_file" "$command_rc" "$mutation" <<'PY' || return 1
import hashlib
import json
import sys

report_path, before_path, after_path, authority_before_path, authority_after_path, evidence_before_path, evidence_after_path, stderr_path, command_rc, mutation = sys.argv[1:]
report = json.load(open(report_path, encoding="utf-8"))
result = report.get("result") or {}
rollback = report.get("rollback") or {}
security = report.get("security") or report.get("supervisorAuthorization") or {}
failure = report.get("failure") or {}
load = lambda path: json.load(open(path, encoding="utf-8"))
targets_before = load(before_path)
targets_after = load(after_path)
authority_before = load(authority_before_path)
authority_after = load(authority_after_path)
evidence_before = load(evidence_before_path)
evidence_after = load(evidence_after_path)
stderr_bytes = open(stderr_path, "rb").read()
stderr_text = stderr_bytes.decode("utf-8", "replace")
handshake = {
    "overrideRequested": False,
    "overridePreservedAcrossLauncher": False,
    "layoutValidatorReached": False,
    "invalidLocationDetected": False,
}
prefix = "LEDGER_LAYOUT_HANDSHAKE "
matches = [line for line in stderr_text.splitlines() if line.startswith(prefix)]
if mutation == "ledger-in-evidence":
    if len(matches) != 1:
        raise SystemExit(1)
    fields = dict(item.split("=", 1) for item in matches[0][len(prefix):].split(" "))
    if set(fields) != set(handshake) or any(value not in ("true", "false") for value in fields.values()):
        raise SystemExit(1)
    handshake = {key: fields[key] == "true" for key in handshake}
    if not all(handshake.values()):
        raise SystemExit(1)
diagnostic = {
    "actual": {
        "rc": int(command_rc),
        "stage": failure.get("stage"),
        "reason": failure.get("reason"),
        "operation": failure.get("operation"),
        "backupCount": result.get("backupCount"),
        "rollback": {key: rollback.get(key) for key in ("performed", "attempted", "restored", "restoreFailures")},
    },
    "ledger": {
        "authorityBefore": authority_before,
        "authorityAfter": authority_after,
        "evidenceBefore": evidence_before,
        "evidenceAfter": evidence_after,
    },
    "targets": {"changed": targets_before != targets_after, "entryCount": len(targets_before)},
    "handshake": handshake,
    "stderr": {"size": len(stderr_bytes), "lineCount": len(stderr_bytes.splitlines()), "digest": hashlib.sha256(stderr_bytes).hexdigest()},
}
print("LEDGER_LAYOUT_DIAGNOSTIC=" + json.dumps(diagnostic, separators=(",", ":"), sort_keys=True), file=sys.stderr)
if report.get("schema") != "agency-agents.local-sync-report/v1" or result.get("status") != "failed":
    raise SystemExit(1)
if security.get("reason") != "isolated test security root layout invalid":
    raise SystemExit(1)
if failure.get("stage") != "authorization-validation" or failure.get("reason") != "authorization validation failed" or failure.get("operation") != "authorization-validation":
    raise SystemExit(1)
if result.get("backupCount") != 0 or rollback.get("performed") is not False or rollback.get("attempted") != 0 or rollback.get("restored") != 0:
    raise SystemExit(1)
if targets_before != targets_after:
    raise SystemExit(1)
if authority_before != authority_after or evidence_before != evidence_after or authority_after.get("exists") or evidence_after.get("exists"):
    raise SystemExit(1)
PY
  rm -rf "$case_root" "$result_root"
  return 0
}

case_bad_namespace_or_principal() {
  local ns="$1"
  local principal="$2"

  local home report
  home="$(fixture_case_home)"
  local manifest_path
  local evidence_root="$home/.codex/supervisor-runtime-evidence"
  local evidence_signers="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/allowed_signers"
  local evidence_ledger="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/owner-only-ledger.jsonl"
  local src_root="$home/source"
  report="$(mktemp)"
  manifest_path="$(fixture_manifest_path "$home")"

  src_root="$(fixture_source_copy "$home")"
  read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" "$ns" "$principal" "$home/action.json" "$manifest_path" "$evidence_signers" "isolated-test" "$home" "$home")

  if HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$manifest_path" --source-root "$src_root" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report"; then
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
  local home report report_json owner_target owner_before_meta owner_before_digest owner_after_meta owner_after_digest
  local manifest_path src_root source_digest plan_file owner_tool owner_label owner_source owner_manifest_target owner_kind owner_mode owner_create owner_source_path owner_root owner_relative selected_owner action signature allowed_signers auth_path
  home="$(fixture_case_home)"
  local manifest_path
  local evidence_root="$home/.codex/supervisor-runtime-evidence"
  local evidence_signers="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/allowed_signers"
  local evidence_ledger="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/owner-only-ledger.jsonl"
  report="$(mktemp)"
  manifest_path="$(fixture_manifest_path "$home")"
  src_root="$(fixture_source_copy "$home")"
  prepare_installed_manifest_targets "$home" "$home" "$manifest_path"

  AGENCY269_NO_CLI=1 source "$SYNC_SCRIPT"
  TEST_MODE=true
  TEST_MODE_ROOT="$home"
  HOME_OVERRIDE="$home"
  PROJECT_ROOT="$home"
  exec 9<"$home"
  if ! IFS=$'\t' read -r TEST_MODE_BOUND_DEV TEST_MODE_BOUND_INO < <(python3 - "$home" <<'PY'
import os
import stat
import sys

path = sys.argv[1]
fd = 9
st = os.fstat(fd)
path_st = os.stat(path, follow_symlinks=False)
if (
    not stat.S_ISDIR(st.st_mode)
    or st.st_uid != os.getuid()
    or stat.S_IMODE(st.st_mode) != 0o700
    or (st.st_dev, st.st_ino) != (path_st.st_dev, path_st.st_ino)
):
    raise SystemExit(1)
print(f"{st.st_dev}\t{st.st_ino}")
PY
  ); then
    echo 'FAIL: owner symlink fixture cannot bind isolated test root'
    rm -rf "$home" "$report"
    return 1
  fi
  TEST_MODE_ROOT_FD=9
  TEST_MODE_ROOT_BOUND_MARKER=v1
  AGENCY_TEST_MODE_ROOT_BOUND_PATH="$home"
  AGENCY_TEST_MODE_ROOT_BOUND_DEV="$TEST_MODE_BOUND_DEV"
  AGENCY_TEST_MODE_ROOT_BOUND_INO="$TEST_MODE_BOUND_INO"
  if ! load_canonical_role_profile; then
    echo 'FAIL: owner symlink fixture cannot load canonical role profile'
    rm -rf "$home" "$report"
    return 1
  fi
  source_digest="$(compute_manifest_source_root_digest "$src_root")" || {
    echo 'FAIL: owner symlink fixture cannot hash source root'
    rm -rf "$home" "$report"
    return 1
  }
  source_digest="$(jq -r '.digest' <<<"$source_digest")" || {
    rm -rf "$home" "$report"
    return 1
  }
  selected_owner=""
  while IFS=$'\t' read -r owner_tool owner_label owner_source owner_manifest_target owner_kind owner_create owner_mode; do
    [[ "$owner_kind" == "directory" && "$owner_create" == "false" && "$owner_tool" != "openclaw" ]] || continue
    owner_source_path="$src_root/$owner_source"
    plan_file="$(mktemp "$home/owner-plan.XXXXXX")" || break
    if ! build_owner_plan "$owner_source_path" "$owner_mode" "$owner_tool" "$owner_label" 0 "$source_digest" '[]' "$plan_file"; then
      rm -f "$plan_file"
      continue
    fi
    owner_relative="$(awk -F $'\t' '$2 != "__whole_file__" { print $2; exit }' "$plan_file")"
    rm -f "$plan_file"
    [[ -n "$owner_relative" ]] || continue
    owner_root="$(resolve_manifest_path "$owner_manifest_target" "$home" "$home")"
    case "${owner_root}/${owner_relative}" in
      "$home/.openclaw/agents/main"|"$home/.openclaw/agents/main"/*) continue ;;
    esac
    selected_owner=1
    break
  done < <(jq -r '.tools[] as $t | ($t.targets // [])[] | [($t.installTool // $t.name // ""),(.label // .targetPath // ""),($t.sourceDir // $t.name // ""),.targetPath,(.kind // "directory"),((.createIfMissing // $t.createIfMissing // false) | tostring),(.ownerMode // "")] | @tsv' "$manifest_path")
  if [[ "$selected_owner" != "1" || -z "${owner_root:-}" || -z "${owner_relative:-}" ]]; then
    echo 'FAIL: owner symlink fixture found no nonprotected manifest owner'
    rm -rf "$home" "$report"
    return 1
  fi
  exec 9<&-

  mkdir -p "$home/owner-external"
  owner_target="$home/owner-external/kept.txt"
  printf 'owner symlink sentinel\n' > "$owner_target"
  owner_before_meta="$(stat -f '%i|%p|%z|%m' "$owner_target")"
  owner_before_digest="$(shasum -a 256 "$owner_target" | awk '{print $1}')"
  rm -rf "${owner_root}/${owner_relative}"
  ln -s "$home/owner-external" "${owner_root}/${owner_relative}"

  if ! IFS=' ' read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" aicc-supervisor-authorization supervisor-approver "$home/action.json" "$manifest_path" "$evidence_signers" "isolated-test" "$home" "$home"); then
    echo 'FAIL: owner symlink fixture cannot read auth bundle'
    rm -rf "$home" "$report"
    return 1
  fi
  if [[ -z "$action" || -z "$signature" || -z "$allowed_signers" || "$action" == "$signature" || "$action" == "$allowed_signers" || "$signature" == "$allowed_signers" ]]; then
    echo 'FAIL: owner symlink fixture auth bundle paths are not distinct'
    rm -rf "$home" "$report"
    return 1
  fi
  for auth_path in "$action" "$signature" "$allowed_signers"; do
    if [[ "$auth_path" != "$home"/* || -L "$auth_path" || ! -f "$auth_path" ]]; then
      echo 'FAIL: owner symlink fixture auth bundle path is not an isolated regular file'
      rm -rf "$home" "$report"
      return 1
    fi
  done

  if HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$manifest_path" --source-root "$src_root" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report"; then
    rm -rf "$home" "$report"
    return 1
  fi
  report_json="$(mktemp)"
  if ! extract_report_json "$report" "$report_json"; then
    echo "FAIL: owner symlink block missing JSON report"
    rm -rf "$home" "$report" "$report_json"
    return 1
  fi
  if [[ "$(json_get "$report_json" result.status)" != "failed" ]] || [[ -z "$(json_get "$report_json" failure.stage)" ]] || [[ "$(json_get "$report_json" failure.reason)" != *"owner symlink blocked"* ]] || [[ "$(json_get "$report_json" failure.operation)" != "owner-path-validation" ]] || [[ "$(json_get "$report_json" failure.tool)" != "$owner_tool" ]] || [[ -z "$(json_get "$report_json" failure.id)" ]] || [[ "$(json_get "$report_json" result.backupCount)" != "0" ]]; then
    printf 'EXPECTED owner BLOCK: result.status=failed stage=<nonempty> reason~owner symlink blocked operation=owner-path-validation tool=%s id=<nonempty> target=<nonempty> backupCount=0 transactionCount=<not-asserted>\n' "$owner_tool" >&2
    printf 'ACTUAL owner BLOCK: result.status=%s stage=%s reason=%s operation=%s tool=%s id=%s target=%s backupCount=%s transactionCount=%s\n' "$(json_get "$report_json" result.status)" "$(json_get "$report_json" failure.stage)" "$(json_get "$report_json" failure.reason)" "$(json_get "$report_json" failure.operation)" "$(json_get "$report_json" failure.tool)" "$(json_get "$report_json" failure.id)" "$(json_get "$report_json" failure.target)" "$(json_get "$report_json" result.backupCount)" "$(json_get "$report_json" manifest.transactionCount)" >&2
    echo "FAIL: owner symlink block JSON failure contract mismatch"
    rm -rf "$home" "$report" "$report_json"
    return 1
  fi
  if [[ ! -L "${owner_root}/${owner_relative}" ]] || [[ "$(readlink "${owner_root}/${owner_relative}")" != "$home/owner-external" ]]; then
    echo "FAIL: owner symlink was modified"
    rm -rf "$home" "$report" "$report_json"
    return 1
  fi
  owner_after_meta="$(stat -f '%i|%p|%z|%m' "$owner_target")"
  owner_after_digest="$(shasum -a 256 "$owner_target" | awk '{print $1}')"
  if [[ "$owner_before_meta" != "$owner_after_meta" ]] || [[ "$owner_before_digest" != "$owner_after_digest" ]]; then
    echo "FAIL: owner symlink target changed"
    rm -rf "$home" "$report" "$report_json"
    return 1
  fi
  rm -f "$report_json"

  rm -rf "$home/.openclaw"
  mkdir -p "$home/.qwen"
  rm -rf "$home/.qwen"
  mkdir -p "$home/.qwen-alt"
  ln -sfn "$home/.qwen-alt" "$home/.qwen"
  if HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$manifest_path" --source-root "$src_root" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report"; then
    rm -rf "$home" "$report"
    return 1
  fi

  rm -rf "$home" "$report"
  return 0
}

case_rollback_on_failure() {
  local home report
  home="$(fixture_case_home)"
  local manifest_path
  local evidence_root="$home/.codex/supervisor-runtime-evidence"
  local evidence_signers="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/allowed_signers"
  local evidence_ledger="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/owner-only-ledger.jsonl"
  local src_root="$home/source"
  local report_file report_clean
  local rollback_performed rollback_attempted rollback_restored failure_tool failure_id failure_stage failure_target failure_reason failure_operation
  local rollback_len backup_count
  local probe_paths before_state after_state
  local rollback_state_report frozen_owner_target frozen_owner_id frozen_owner_rel pre_digest pre_mode pre_size owner_evidence
  local rollback_state_report_rc=0
  local cleanup_entries=0 cleanup_rc=0 case_stderr_file case_stderr_safe=''
  local protected_audit=''
  local d1_sentinel_scenario="${SYNC_D1_SENTINEL_SCENARIO:-legacy}"
  local d1_roots_before d1_roots_after
  CASE_CLEANUP_ENTRIES=0
  report_file="$(mktemp "$home/fault-report.raw.XXXXXX")"
  report_clean="$(mktemp "$home/fault-report.clean.XXXXXX")"
  probe_paths="$(mktemp "$home/fault-probes.XXXXXX")"
  before_state="$(mktemp "$home/fault-before.XXXXXX")"
  after_state="$(mktemp "$home/fault-after.XXXXXX")"
  case_stderr_file="$(mktemp "$home/fault-stderr.XXXXXX")"

  manifest_path="$(fixture_manifest_path "$home")"
  src_root="$(fixture_source_copy "$home")"
  if ! reorder_post_mutation_fault_manifest "$manifest_path"; then
    echo 'FAIL: unable to build post-mutation fault manifest fixture'
    return 1
  fi
  clear_qwen_kimi_targets "$home"
  prepare_installed_manifest_targets "$home" "$home" "$manifest_path"
  d1_roots_before="$(mktemp)" || return 1
  d1_roots_after="$(mktemp)" || return 1
  setup_d1_openclaw_sentinels "$home" agents-baseline || return 1
  freeze_d1_manifest_target_roots "$home" "$home" "$manifest_path" "$d1_roots_before" || return 1
  setup_d1_openclaw_sentinels "$home" "$d1_sentinel_scenario" || return 1
  freeze_d1_manifest_target_roots "$home" "$home" "$manifest_path" "$d1_roots_after" || return 1
  assert_d1_manifest_target_roots_preserved "$d1_roots_before" "$d1_roots_after" "$d1_sentinel_scenario" || return 1
  if [[ "${SYNC_D1_PROTECTED_AUDIT:-}" == "1" ]]; then
    protected_audit="$home/.d1-protected-access-audit"
    : > "$protected_audit"
    chmod 600 "$protected_audit"
  fi
  frozen_owner_target="$(resolve_manifest_path "$(jq -r '.tools[] | select(.installTool == "aider") | .targets[0].targetPath' "$manifest_path")" "$home" "$home")"
  frozen_owner_id='aider:${PROJECT}/CONVENTIONS.md'
  frozen_owner_rel='__whole_file__'
  IFS=$'\t' read -r pre_digest pre_mode pre_size < <(python3 - "$frozen_owner_target" <<'PY'
import hashlib
import os
import stat
import sys

path = sys.argv[1]
parts = [part for part in path.split('/') if part]
fd = os.open('/', os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0))
try:
    for part in parts[:-1]:
        st = os.stat(part, dir_fd=fd, follow_symlinks=False)
        if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode): raise SystemExit(1)
        next_fd = os.open(part, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0) | getattr(os, 'O_NOFOLLOW', 0), dir_fd=fd)
        os.close(fd); fd = next_fd
    st = os.stat(parts[-1], dir_fd=fd, follow_symlinks=False)
    if not stat.S_ISREG(st.st_mode): raise SystemExit(1)
    file_fd = os.open(parts[-1], os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0), dir_fd=fd)
    try:
        digest = hashlib.sha256()
        while True:
            block = os.read(file_fd, 1024 * 1024)
            if not block: break
            digest.update(block)
        print(f"{digest.hexdigest()}\t{stat.S_IMODE(st.st_mode):o}\t{st.st_size}")
    finally:
        os.close(file_fd)
finally:
    os.close(fd)
PY
)
  build_d1_probe_list "$home" "$home" "$manifest_path" "$d1_sentinel_scenario" "$probe_paths" || return 1
  sort -u "$probe_paths" -o "$probe_paths"
  if ! snapshot_paths_descriptor_no_follow "$home" "$probe_paths" "$before_state"; then
    echo 'FAIL: unable to capture independent descriptor before snapshot'
    return 1
  fi

  read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" aicc-supervisor-authorization supervisor-approver "$home/action.json" "$manifest_path" "$evidence_signers" "isolated-test" "$home" "$home")

  local fault_rc=0
  if AGENCY_TEST_FAULT_STAGE=post-owner-install AGENCY_TEST_FAULT_TARGET=kimi SYNC_PROTECTED_ACCESS_AUDIT_FILE="$protected_audit" SYNC_PROTECTED_ACCESS_AUDIT="${SYNC_D1_PROTECTED_AUDIT:-}" HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --test-mode --test-mode-root "$home" --apply --manifest "$manifest_path" --source-root "$src_root" --project "$home" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$report_file" 2>"$case_stderr_file"; then
    fault_rc=0
  else
    fault_rc=$?
  fi
  if [[ "$fault_rc" == "0" ]]; then
    echo "FAIL: command unexpectedly succeeded (inject failed or not hit)"
    rm -rf "$home" "$report_file"
    return 1
  fi

  if [[ ! -s "$report_file" ]]; then
    echo "FAIL: rollback report missing"
    rm -rf "$home" "$report_file"
    return 1
  fi

  if ! read_isolated_sync_report "$home" "$report_file" "$report_clean"; then
    echo "FAIL: rollback stdout is not one local sync report JSON object"
    rm -rf "$home" "$report_file" "$report_clean" "$probe_paths" "$before_state" "$after_state"
    return 1
  fi
  printf 'REPORT_COUNT=1\n'

  if [[ "$(json_get "$report_clean" result.status)" != "failed" ]]; then
    echo "FAIL: failure case status not failed"
    rm -rf "$home" "$report_file"
    return 1
  fi

  rollback_performed="$(json_get "$report_clean" rollback.performed)"
  if [[ "$rollback_performed" != "true" && "$rollback_performed" != "True" ]]; then
    python3 - "$report_clean" >&2 <<'PY'
import json
import sys

report = json.load(open(sys.argv[1], encoding="utf-8"))
failure = report.get("failure", {})
rollback = report.get("rollback", {})
entries = rollback.get("entries", [])
print("ROLLBACK_FAULT_DIAGNOSTIC=" + json.dumps({
    "failure": {key: failure.get(key, "") for key in ("stage", "tool", "id", "reason", "operation")},
    "rollback": {
        "performed": rollback.get("performed"),
        "attempted": rollback.get("attempted"),
        "restored": rollback.get("restored"),
        "restoreFailures": len(rollback.get("restoreFailures", [])),
        "journalEntries": len(entries),
        "journalTools": sorted({entry.get("tool", "") for entry in entries}),
    },
}, separators=(",", ":"), sort_keys=True))
PY
    echo "FAIL: rollback flag false"
    rm -rf "$home" "$report_file" "$report_clean" "$probe_paths" "$before_state" "$after_state"
    return 1
  fi

  if ! snapshot_paths_descriptor_no_follow "$home" "$probe_paths" "$after_state"; then
    echo 'FAIL: unable to capture independent descriptor after snapshot'
    return 1
  fi

  rollback_attempted="$(json_get "$report_clean" rollback.attempted)"
  rollback_restored="$(json_get "$report_clean" rollback.restored)"
  backup_count="$(json_get "$report_clean" result.backupCount)"
  rollback_len="$(python3 -c 'import json,sys; fp=open(sys.argv[1], "r", encoding="utf-8"); r=json.load(fp); fp.close(); print(len(r.get("rollback", {}).get("entries", [])))' "$report_clean")"
  owner_evidence="$(python3 - "$report_clean" "$frozen_owner_id" "$frozen_owner_rel" "$pre_digest" "$pre_mode" "$pre_size" <<'PY'
import json
import sys

report = json.load(open(sys.argv[1], encoding="utf-8"))
target_id, owner_rel, pre_digest, pre_mode, pre_size = sys.argv[2:]
matches = [entry for entry in report.get("rollback", {}).get("entries", []) if entry.get("id") == target_id and entry.get("ownerRelative") == owner_rel]
if len(matches) != 1:
    raise SystemExit(1)
entry = matches[0]
expected = entry.get("expected", {})
staged = entry.get("staged", {})
if not entry.get("hasBackup") or entry.get("kind") != "file" or expected != {"digest": pre_digest, "mode": pre_mode, "size": int(pre_size)}:
    raise SystemExit(1)
print(json.dumps({
    "targetId": target_id,
    "ownerRel": owner_rel,
    "wasExisting": True,
    "backup": {"type": "file", **expected},
    "staged": {"type": "file", **staged},
    "rollbackVerifier": {"type": "file", **expected, "countedRestored": True},
}, separators=(",", ":"), sort_keys=True))
PY
)" || {
    echo 'FAIL: single owner journal evidence mismatch'
    return 1
  }
  printf 'SINGLE_OWNER_ROLLBACK_EVIDENCE=%s\n' "$owner_evidence" >&2

  if [[ "$rollback_len" != "$rollback_attempted" || "$rollback_len" != "$rollback_restored" || "$rollback_len" != "$backup_count" ]]; then
    echo "FAIL: rollback counts unexpected attempted=$rollback_attempted restored=$rollback_restored backupCount=$backup_count entries=$rollback_len"
    rm -rf "$home" "$report_file" "$probe_paths" "$before_state" "$after_state"
    return 1
  fi
  if [[ "$rollback_attempted" -le 1 ]]; then
    echo "FAIL: rollback should include prior entries (attempted=$rollback_attempted)"
    rm -rf "$home" "$report_file"
    return 1
  fi

  failure_tool="$(json_get "$report_clean" failure.tool)"
  failure_id="$(json_get "$report_clean" failure.id)"
  failure_stage="$(json_get "$report_clean" failure.stage)"
  failure_target="$(json_get "$report_clean" failure.target)"
  failure_reason="$(json_get "$report_clean" failure.reason)"
  failure_operation="$(json_get "$report_clean" failure.operation)"
  if [[ "$failure_tool" != "kimi" || -z "$failure_id" || -z "$failure_stage" || -z "$failure_target" ]]; then
    echo "FAIL: rollback failure context missing or not kimi (tool=$failure_tool id=$failure_id stage=$failure_stage)"
    rm -rf "$home" "$report_file"
    return 1
  fi
  if [[ -z "$failure_reason" || -z "$failure_operation" ]]; then
    echo "FAIL: rollback failure reason/operation missing (reason=$failure_reason operation=$failure_operation)"
    rm -rf "$home" "$report_file"
    return 1
  fi

  has_kimi_entry="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1], "r", encoding="utf-8")); print("1" if any(entry.get("tool") == "kimi" for entry in r.get("rollback", {}).get("entries", [])) else "0")' "$report_clean")"
  if [[ "$has_kimi_entry" != "1" ]]; then
    echo "FAIL: rollback journal missing kimi entry"
    rm -rf "$home" "$report_file"
    return 1
  fi

  has_failure_target="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1], "r", encoding="utf-8")); entries=r.get("rollback", {}).get("entries", []); failure_target=r.get("failure", {}).get("target", ""); print("1" if any((entry.get("tool") == "kimi" and entry.get("target") == failure_target) or (entry.get("tool") == "kimi" and r.get("failure", {}).get("tool") == "kimi") for entry in entries) else "0")' "$report_clean")"
  if [[ "$has_failure_target" != "1" ]]; then
    echo "FAIL: failure target not represented in rollback journal"
    rm -rf "$home" "$report_file" "$probe_paths" "$before_state" "$after_state"
    return 1
  fi

  rollback_state_report="$(mktemp "$home/rollback-state.XXXXXX")"
  rollback_state_report_rc=0
  python3 - "$before_state" "$after_state" "$report_clean" "$frozen_owner_id" "$frozen_owner_rel" "$pre_digest" "$pre_mode" "$pre_size" > "$rollback_state_report" <<'PY'
import json
import os
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fp:
  before = json.load(fp)
with open(sys.argv[2], "r", encoding="utf-8") as fp:
  after = json.load(fp)
with open(sys.argv[3], "r", encoding="utf-8") as fp:
  report = json.load(fp)
frozen_id, frozen_rel, pre_digest, pre_mode, pre_size = sys.argv[4:]

failure = report.get("failure", {})
manifest = report.get("manifest", {})
result = report.get("result", {})
rollback = report.get("rollback", {})
entries = rollback.get("entries", [])
backup_targets = set()
bad = []

def mismatch(code, entry=None, expected=None, actual=None):
  item = {"code": code}
  if entry is not None:
    item.update({
      "id": entry.get("id", ""),
      "ownerRelative": entry.get("ownerRelative", ""),
      "kind": entry.get("kind", ""),
    })
  if expected is not None:
    item["expected"] = expected
  if actual is not None:
    item["actual"] = actual
  bad.append(item)

def stable_restore_failures(items):
  stable = []
  for item in items if isinstance(items, list) else []:
    stable.append({key: item.get(key) for key in ("index", "code", "operation", "relative", "message") if key in item})
  return stable

if report.get("schema") != "agency-agents.local-sync-report/v1":
  mismatch("schema-mismatch")
if result.get("status") != "failed":
  mismatch("decision-not-failed")
if failure.get("stage") != "fault-injection":
  mismatch("failure-stage-mismatch")
if failure.get("reason") != "injected post-owner-install failure":
  mismatch("failure-reason-mismatch")
if failure.get("operation") != "test-fault-seam":
  mismatch("failure-operation-mismatch")
if manifest.get("transactionCount") != 18:
  mismatch("transaction-count-mismatch", expected=18, actual=manifest.get("transactionCount"))
if not entries:
  mismatch("no-mutated-journal-entry")
if rollback.get("performed") is not True:
  mismatch("rollback-not-performed")
if rollback.get("attempted") != len(entries):
  mismatch("attempted-journal-mismatch", expected=len(entries), actual=rollback.get("attempted"))
if rollback.get("restored") != len(entries):
  mismatch("restored-verification-mismatch", expected=len(entries), actual=rollback.get("restored"))
if rollback.get("restoreFailures") != []:
  mismatch("restore-failures-present", expected=[], actual=stable_restore_failures(rollback.get("restoreFailures")))

aider_matches = [entry for entry in entries if entry.get("id") == frozen_id and entry.get("ownerRelative") == frozen_rel]
if len(aider_matches) != 1:
  mismatch("aider-journal-entry-count", expected=1, actual=len(aider_matches))
aider_entry = aider_matches[0] if len(aider_matches) == 1 else {}
aider_expected = {"digest": pre_digest, "mode": pre_mode, "size": int(pre_size)}
if aider_entry and (not aider_entry.get("hasBackup") or aider_entry.get("expected") != aider_expected):
  mismatch("aider-pre-state-metadata-mismatch", aider_entry, aider_expected, aider_entry.get("expected"))

kimi_entries = [entry for entry in entries if entry.get("tool") == "kimi"]
if not kimi_entries:
  mismatch("kimi-journal-entry-missing")
if failure.get("tool") != "kimi":
  mismatch("failure-tool-not-kimi")
for entry in entries:
  target = entry.get("target", "")
  has_backup = entry.get("hasBackup", False)
  before_target = before.get(target, {})
  after_target = after.get(target, {})
  if has_backup:
    if not before_target.get("exists", False):
      mismatch("existing-owner-missing-before", entry)
      continue
    if before_target != after_target:
      mismatch("existing-owner-state-mismatch", entry, before_target, after_target)
  else:
    if after_target.get("exists", False):
      mismatch("new-owner-not-removed", entry, {"exists": False}, after_target)
  backup_targets.add(target)

for path, original_state in before.items():
  if path in backup_targets:
    continue
  if original_state != after.get(path, {}):
    mismatch("non-owner-or-created-parent-state-mismatch", expected=original_state, actual=after.get(path, {}))

single_object = {
  "id": aider_entry.get("id", frozen_id),
  "ownerRelative": aider_entry.get("ownerRelative", frozen_rel),
  "kind": aider_entry.get("kind", "file"),
  "expected": aider_entry.get("expected", aider_expected),
  "staged": aider_entry.get("staged", {}),
}
summary = {
  "decision": result.get("status"),
  "stage": failure.get("stage"),
  "reason": failure.get("reason"),
  "operation": failure.get("operation"),
  "transactionCount": manifest.get("transactionCount"),
  "journalEntries": len(entries),
  "performed": rollback.get("performed"),
  "attempted": rollback.get("attempted"),
  "restored": rollback.get("restored"),
  "restoreFailures": stable_restore_failures(rollback.get("restoreFailures")),
  "singleObject": single_object,
  "mismatches": bad,
}
print(json.dumps(summary, separators=(",", ":"), sort_keys=True))
raise SystemExit(1 if bad else 0)
PY
  rollback_state_report_rc=$?
  local rollback_state_summary
  rollback_state_summary="$(read_isolated_json_object_no_follow "$home" "$rollback_state_report")" || {
    echo "FAIL: rollback state diagnostic is not an isolated regular JSON object"
    rm -rf "$home"
    return 1
  }
  printf 'ROLLBACK_STATE_DIAGNOSTIC=%s\n' "$rollback_state_summary" >&2
  if [[ "$rollback_state_report_rc" -ne 0 ]]; then
    echo "FAIL: rollback journal/state contract check failed"
    rm -rf "$home" "$report_file" "$report_clean" "$probe_paths" "$before_state" "$after_state" "$rollback_state_report"
    return 1
  fi

  assert_d1_sentinel_snapshot "$before_state" "$after_state" "$home" "$d1_sentinel_scenario" rollback || return 1

  case_stderr_safe="$(awk 'NF && $0 != "ok" { print }' "$case_stderr_file")"
  if [[ -n "$protected_audit" ]]; then
    assert_d1_protected_access_audit "$protected_audit" "rollback-${d1_sentinel_scenario}" false || return 1
  fi
  cleanup_entries=8
  CASE_CLEANUP_ENTRIES="$cleanup_entries"
  harness_marker case-body-complete 0 "$cleanup_entries"
  harness_marker cleanup-start 0 "$cleanup_entries"
  rm -rf "$home" "$report_file" "$report_clean" || cleanup_rc=$?
  rm -rf "$probe_paths" "$before_state" "$after_state" "$rollback_state_report" "$case_stderr_file" || cleanup_rc=$?
  harness_marker cleanup-end "$cleanup_rc" "$cleanup_entries"
  if [[ -n "$case_stderr_safe" ]]; then
    printf '%s\n' "$case_stderr_safe" >&2
  fi
  if [[ "$cleanup_rc" != "0" ]]; then
    harness_marker case-function-return "$cleanup_rc" "$cleanup_entries"
    CASE_FUNCTION_RETURN_MARKED=true
    return "$cleanup_rc"
  fi
  harness_marker case-function-return 0 "$cleanup_entries"
  CASE_FUNCTION_RETURN_MARKED=true
  return 0
}

task_post_mutation_fault_fixture_selfcheck() {
  local fixture_dir source_copy manifest_path production_sha_before production_sha_after isolated_sha

  build_isolated_fixture || return 1
  fixture_dir="$(fixture_case_home)"
  manifest_path="$(fixture_manifest_path "$fixture_dir")"
  production_sha_before="$(shasum -a 256 "$CANONICAL_REPO_MANIFEST" | awk '{print $1}')"
  source_copy="$(fixture_source_copy "$fixture_dir")"
  [[ -d "$source_copy" && -f "$manifest_path" ]] || { echo 'FAIL: isolated manifest was not created before transform'; return 1; }
  reorder_post_mutation_fault_manifest "$manifest_path" || { echo 'FAIL: isolated fault manifest transform contract failed'; return 1; }
  isolated_sha="$(shasum -a 256 "$manifest_path" | awk '{print $1}')"
  production_sha_after="$(shasum -a 256 "$CANONICAL_REPO_MANIFEST" | awk '{print $1}')"
  if [[ "$isolated_sha" != "$FAULT_FIXTURE_MANIFEST_SHA" || "$production_sha_before" != "$production_sha_after" ]]; then
    echo 'FAIL: fault fixture SHA contract failed'
    return 1
  fi
  echo 'POST_MUTATION_FAULT_FIXTURE_SELFTEST=PASS'
}

if [[ "${SYNC_FAULT_FIXTURE_SELFTEST:-}" == "1" ]]; then
  task_post_mutation_fault_fixture_selfcheck
  exit $?
fi

task_fault_seam_authorization_selfcheck() {
  local raw_task_root task_root
  raw_task_root="$(mktemp -d /tmp/agency-fault-seam.XXXXXX)" || return 1
  task_root="$(physical_root "$raw_task_root")" || return 1
  trap "rm -rf -- '$task_root' '$FIXTURE_ROOT'" EXIT
  source "$SYNC_SCRIPT"
  TEST_MODE=true
  HAS_TEST_MODE_ROOT=true
  TEST_MODE_ROOT="$task_root"
  HOME_OVERRIDE="$task_root"
  PROJECT_ROOT="$task_root"
  exec 8<"$task_root"
  TEST_MODE_ROOT_FD=8

  TEST_FAULT_STAGE=post-owner-install
  TEST_FAULT_TARGET=kimi
  validate_test_fault_seam || { echo 'FAIL: allowlisted test fault seam was rejected'; return 1; }
  [[ "$TEST_FAULT_SEAM_ENABLED" == true ]] || { echo 'FAIL: allowlisted test fault seam was not enabled'; return 1; }

  TEST_MODE=false
  TEST_FAULT_STAGE=post-owner-install
  TEST_FAULT_TARGET=kimi
  if validate_test_fault_seam; then echo 'FAIL: non-test fault seam was accepted'; return 1; fi
  TEST_MODE=true
  TEST_FAULT_STAGE=pre-owner-install
  TEST_FAULT_TARGET=kimi
  if validate_test_fault_seam; then echo 'FAIL: unknown fault stage was accepted'; return 1; fi
  TEST_FAULT_STAGE=post-owner-install
  TEST_FAULT_TARGET="$task_root/kimi"
  if validate_test_fault_seam; then echo 'FAIL: path-like fault target was accepted'; return 1; fi
  TEST_FAULT_STAGE=post-owner-install
  TEST_FAULT_TARGET='kimi,zcode'
  if validate_test_fault_seam; then echo 'FAIL: multi-value fault target was accepted'; return 1; fi
  echo 'FAULT_SEAM_AUTHORIZATION_SELFTEST=PASS'
}

task_auth_descriptor_selfcheck() {
  local raw_task_root task_root bundle_dir action signature signers ledger dry_ledger key action_sha replaced_sha result code replay_rc ledger_before ledger_after standard_verify_rc
  raw_task_root="$(mktemp -d /tmp/agency-auth-descriptor.XXXXXX)" || return 1
  task_root="$(physical_root "$raw_task_root")" || return 1
  chmod 700 "$task_root"
  exec 9<"$task_root" || return 1
  trap "rm -rf -- '$task_root' '$FIXTURE_ROOT'" EXIT
  source "$SYNC_SCRIPT"

  bundle_dir="$task_root/bundle"
  mkdir -p "$bundle_dir" "$task_root/evidence"
  chmod 700 "$bundle_dir" "$task_root/evidence"
  action="$bundle_dir/action.json"
  signature="$bundle_dir/action.json.sig"
  signers="$bundle_dir/allowed_signers"
  ledger="$task_root/evidence/owner-only-ledger.jsonl"
  dry_ledger="$task_root/evidence/dry-run-ledger.jsonl"
  key="$bundle_dir/key"
  printf '%s\n' '{"kind":"descriptor-selftest"}' > "$action"
  ssh-keygen -t ed25519 -N '' -f "$key" >/dev/null 2>&1 || return 1
  printf 'supervisor-approver %s\n' "$(cat "${key}.pub")" > "$signers"
  ssh-keygen -Y sign -f "$key" -n aicc-supervisor-authorization -I supervisor-approver "$action" >/dev/null 2>&1 || return 1
  chmod 600 "$action" "$signature" "$signers"

  set +e
  ssh-keygen -Y verify -f "$signers" -I supervisor-approver -n aicc-supervisor-authorization -s "$signature" < "$action" >/dev/null 2>&1
  standard_verify_rc=$?
  set -e
  [[ "$standard_verify_rc" -eq 0 ]] || { echo 'FAIL: standard authorization signature verification failed'; return 1; }
  result="$(auth_descriptor_snapshot "$action" "$signature" "$signers" supervisor-approver aicc-supervisor-authorization true "$task_root" 9)" || return 1
  code="$(jq -r '.code // ""' <<< "$result")"
  action_sha="$(jq -r '.auth_sha // ""' <<< "$result")"
  if [[ "$code" != ok || ! "$action_sha" =~ ^[a-f0-9]{64}$ ]]; then
    jq -cn --arg code "$code" --argjson standard "$standard_verify_rc" --argjson ssh_exit "$(jq -r '.ssh_exit // -1' <<< "$result")" --arg classification "$(jq -r '.classification // ""' <<< "$result")" --argjson signers_offset "$(jq -r '.signers_offset // -1' <<< "$result")" --argjson signature_offset "$(jq -r '.signature_offset // -1' <<< "$result")" --argjson signers_size "$(jq -r '.signers_size // -1' <<< "$result")" --argjson signature_size "$(jq -r '.signature_size // -1' <<< "$result")" --argjson message_length "$(jq -r '.message_length // -1' <<< "$result")" --argjson message_ends_newline "$(jq -r '.message_ends_newline // false' <<< "$result")" '{standardVerifyRc:$standard,fdVerifyRc:$ssh_exit,classification:$classification,signersOffset:$signers_offset,signatureOffset:$signature_offset,signersSize:$signers_size,signatureSize:$signature_size,messageLength:$message_length,messageEndsNewline:$message_ends_newline,passFds:true,devFdBinding:true,principalNamespaceMatch:true}' >&2
    echo 'FAIL: ordinary authorization descriptor snapshot failed'
    return 1
  fi

  ln -s "$action" "$bundle_dir/action-link"
  result="$(auth_descriptor_snapshot "$bundle_dir/action-link" "$signature" "$signers" supervisor-approver aicc-supervisor-authorization true "$task_root" 9)"
  [[ "$(jq -r '.code // ""' <<< "$result")" == auth-descriptor-unsafe ]] || { echo 'FAIL: authorization symlink was accepted'; return 1; }
  mkfifo "$bundle_dir/signature-fifo"
  result="$(auth_descriptor_snapshot "$action" "$bundle_dir/signature-fifo" "$signers" supervisor-approver aicc-supervisor-authorization true "$task_root" 9)"
  [[ "$(jq -r '.code // ""' <<< "$result")" == auth-descriptor-unsafe ]] || { echo 'FAIL: signature special file was accepted'; return 1; }
  ln -s "$signers" "$bundle_dir/signers-link"
  result="$(auth_descriptor_snapshot "$action" "$signature" "$bundle_dir/signers-link" supervisor-approver aicc-supervisor-authorization true "$task_root" 9)"
  [[ "$(jq -r '.code // ""' <<< "$result")" == auth-descriptor-unsafe ]] || { echo 'FAIL: allowed_signers symlink was accepted'; return 1; }

  : > "$ledger"
  chmod 600 "$ledger"
  ledger_before="$(file_hash "$ledger")"
  printf '%s\n' 'invalid detached signature' > "$bundle_dir/invalid.sig"
  chmod 600 "$bundle_dir/invalid.sig"
  result="$(auth_descriptor_snapshot "$action" "$bundle_dir/invalid.sig" "$signers" supervisor-approver aicc-supervisor-authorization true "$task_root" 9)"
  ledger_after="$(file_hash "$ledger")"
  if [[ "$(jq -r '.code // ""' <<< "$result")" != signature-invalid || "$ledger_before" != "$ledger_after" ]]; then
    echo 'FAIL: invalid signature changed ledger or was accepted'
    return 1
  fi

  result="$(auth_descriptor_snapshot "$action" "$signature" "$signers" supervisor-approver aicc-supervisor-authorization true "$task_root" 9)"
  append_ledger_entry "$ledger" "$action_sha" supervisor-approver aicc-supervisor-authorization entry-sha manifest-sha "$(jq -r '.allowed_signers_digest' <<< "$result")" "$task_root/evidence" || { echo 'FAIL: valid action was not consumed once'; return 1; }
  ledger_before="$(file_hash "$ledger")"
  set +e
  append_ledger_entry "$ledger" "$action_sha" supervisor-approver aicc-supervisor-authorization entry-sha manifest-sha "$(jq -r '.allowed_signers_digest' <<< "$result")" "$task_root/evidence"
  replay_rc=$?
  set -e
  ledger_after="$(file_hash "$ledger")"
  if [[ "$replay_rc" != 2 || "$ledger_before" != "$ledger_after" ]]; then
    echo 'FAIL: replay contract was not single-use byte-stable'
    return 1
  fi
  ln -s "$ledger" "$task_root/evidence/ledger-link"
  set +e
  append_ledger_entry "$task_root/evidence/ledger-link" deadbeef supervisor-approver aicc-supervisor-authorization entry-sha manifest-sha deadbeef "$task_root/evidence"
  replay_rc=$?
  set -e
  [[ "$replay_rc" != 0 ]] || { echo 'FAIL: ledger symlink was accepted'; return 1; }

  DRY_RUN=true
  LEDGER_FILE="$dry_ledger"
  verify_authorization || { echo 'FAIL: dry-run authorization did not skip'; return 1; }
  [[ ! -e "$dry_ledger" && ! -L "$dry_ledger" ]] || { echo 'FAIL: dry-run created ledger'; return 1; }
  DRY_RUN=false

  cp "$action" "$bundle_dir/race-action.json"
  cp "$signature" "$bundle_dir/race-action.json.sig"
  cp "$signers" "$bundle_dir/race-signers"
  printf '%s\n' '{"replacement":"not-authorized"}' > "$bundle_dir/.auth-replacement-source"
  chmod 600 "$bundle_dir/race-action.json" "$bundle_dir/race-action.json.sig" "$bundle_dir/race-signers" "$bundle_dir/.auth-replacement-source"
  AUTH_DESCRIPTOR_TEST_RACE_PATH="$bundle_dir/race-action.json"
  AUTH_DESCRIPTOR_TEST_RACE_REPLACEMENT="$bundle_dir/.auth-replacement-source"
  AUTH_DESCRIPTOR_TEST_RACE_STAGE=after-auth-snapshot
  ledger_before="$(file_hash "$ledger")"
  result="$(auth_descriptor_snapshot "$AUTH_DESCRIPTOR_TEST_RACE_PATH" "$bundle_dir/race-action.json.sig" "$bundle_dir/race-signers" supervisor-approver aicc-supervisor-authorization true "$task_root" 9)"
  replaced_sha="$(file_hash "$AUTH_DESCRIPTOR_TEST_RACE_PATH")"
  ledger_after="$(file_hash "$ledger")"
  if [[ "$(jq -r '.code // ""' <<< "$result")" != auth-descriptor-path-replaced || "$replaced_sha" == "$action_sha" || "$ledger_before" != "$ledger_after" ]]; then
    echo 'FAIL: test-only auth path replacement was not fail-closed and ledger-stable'
    return 1
  fi
  result="$(auth_descriptor_snapshot "$AUTH_DESCRIPTOR_TEST_RACE_PATH" "$bundle_dir/race-action.json.sig" "$bundle_dir/race-signers" supervisor-approver aicc-supervisor-authorization false "$task_root")"
  [[ "$(jq -r '.code // ""' <<< "$result")" == auth-race-seam-blocked ]] || { echo 'FAIL: non-test auth race seam was reachable'; return 1; }
  AUTH_DESCRIPTOR_TEST_RACE_PATH=''
  AUTH_DESCRIPTOR_TEST_RACE_REPLACEMENT=''
  AUTH_DESCRIPTOR_TEST_RACE_STAGE=''
  echo 'AUTH_DESCRIPTOR_SELFTEST=PASS'
}

task_ledger_unsafe_selfcheck() {
  local raw_task_root task_root evidence baseline before after rc
  raw_task_root="$(mktemp -d /tmp/agency-ledger-unsafe.XXXXXX)" || return 1
  task_root="$(physical_root "$raw_task_root")" || return 1
  chmod 700 "$task_root"
  exec 9<"$task_root" || return 1
  trap "rm -rf -- '$task_root' '$FIXTURE_ROOT'" EXIT
  source "$SYNC_SCRIPT"
  evidence="$task_root/evidence"
  mkdir -p "$evidence"
  chmod 700 "$evidence"
  ledger_state() {
    python3 - "$1" <<'PY'
import hashlib, json, os, stat, sys
path = sys.argv[1]
try:
    value = os.lstat(path)
except FileNotFoundError:
    print('{"kind":"absent"}')
    raise SystemExit(0)
if stat.S_ISREG(value.st_mode):
    with open(path, 'rb') as handle:
        digest = hashlib.sha256(handle.read()).hexdigest()
    print(json.dumps({"kind":"regular","inode":value.st_ino,"mtimeNs":value.st_mtime_ns,"size":value.st_size,"digest":digest}, separators=(',', ':')))
else:
    print(json.dumps({"kind":"special","mode":stat.S_IFMT(value.st_mode)}, separators=(',', ':')))
PY
  }
  baseline="$evidence/ledger"
  printf '%s\n' 'seed|supervisor-approver|aicc-supervisor-authorization|entry|manifest|signers|0' > "$baseline"
  chmod 600 "$baseline"
  before="$(ledger_state "$baseline")"
  ln -s ledger "$evidence/ledger-link"
  set +e
  append_ledger_entry "$evidence/ledger-link" deadbeef supervisor-approver aicc-supervisor-authorization entry manifest signers "$evidence"
  rc=$?
  set -e
  after="$(ledger_state "$baseline")"
  [[ "$rc" == 4 && "$before" == "$after" ]] || { echo 'FAIL: ledger symlink mutated existing ledger'; return 1; }

  mkfifo "$evidence/ledger-fifo"
  set +e
  append_ledger_entry "$evidence/ledger-fifo" deadbeef supervisor-approver aicc-supervisor-authorization entry manifest signers "$evidence"
  rc=$?
  set -e
  [[ "$rc" == 4 && -p "$evidence/ledger-fifo" ]] || { echo 'FAIL: ledger special file was not fail-closed'; return 1; }

  chmod 644 "$baseline"
  before="$(ledger_state "$baseline")"
  set +e
  append_ledger_entry "$baseline" deadbeef supervisor-approver aicc-supervisor-authorization entry manifest signers "$evidence"
  rc=$?
  set -e
  after="$(ledger_state "$baseline")"
  [[ "$rc" == 4 && "$before" == "$after" ]] || { echo 'FAIL: ledger mode rejection mutated bytes or metadata'; return 1; }
  chmod 600 "$baseline"

  printf '%s\n' 'malformed' > "$evidence/malformed"
  chmod 600 "$evidence/malformed"
  before="$(ledger_state "$evidence/malformed")"
  set +e
  append_ledger_entry "$evidence/malformed" deadbeef supervisor-approver aicc-supervisor-authorization entry manifest signers "$evidence"
  rc=$?
  set -e
  after="$(ledger_state "$evidence/malformed")"
  [[ "$rc" == 3 && "$before" == "$after" ]] || { echo 'FAIL: malformed ledger was not byte-stable'; return 1; }

  set +e
  append_ledger_entry "$evidence/missing/ledger" deadbeef supervisor-approver aicc-supervisor-authorization entry manifest signers "$evidence"
  rc=$?
  set -e
  [[ "$rc" == 4 && ! -e "$evidence/missing" && ! -L "$evidence/missing" ]] || { echo 'FAIL: missing ledger parent was created or accepted'; return 1; }

  mkdir "$evidence/parent-target"
  ln -s parent-target "$evidence/parent-link"
  set +e
  append_ledger_entry "$evidence/parent-link/ledger" deadbeef supervisor-approver aicc-supervisor-authorization entry manifest signers "$evidence"
  rc=$?
  set -e
  [[ "$rc" == 4 && ! -e "$evidence/parent-target/ledger" ]] || { echo 'FAIL: ledger parent replacement was followed'; return 1; }
  echo 'LEDGER_UNSAFE_SELFTEST=PASS'
}

task_auth_path_replacement_selfcheck() {
  local raw_task_root task_root bundle action signature signers key replacement ledger before after result action_sha replacement_sha helper_rc error_code ledger_existed digest_changed
  raw_task_root="$(mktemp -d /tmp/agency-auth-replacement.XXXXXX)" || return 1
  task_root="$(physical_root "$raw_task_root")" || return 1
  chmod 700 "$task_root"
  exec 9<"$task_root" || return 1
  trap "rm -rf -- '$task_root' '$FIXTURE_ROOT'" EXIT
  source "$SYNC_SCRIPT"
  bundle="$task_root/bundle"
  mkdir -p "$bundle" "$task_root/evidence"
  chmod 700 "$bundle" "$task_root/evidence"
  action="$bundle/action.json"
  signature="$bundle/action.json.sig"
  signers="$bundle/allowed_signers"
  key="$bundle/key"
  ledger="$task_root/evidence/ledger"
  printf '%s\n' '{"kind":"descriptor-path-replacement"}' > "$action"
  ssh-keygen -t ed25519 -N '' -f "$key" >/dev/null 2>&1 || return 1
  printf 'supervisor-approver %s\n' "$(cat "${key}.pub")" > "$signers"
  ssh-keygen -Y sign -f "$key" -n aicc-supervisor-authorization -I supervisor-approver "$action" >/dev/null 2>&1 || return 1
  chmod 600 "$action" "$signature" "$signers"
  action_sha="$(file_hash "$action")"
  cp "$action" "$bundle/race-action.json"
  cp "$signature" "$bundle/race-action.json.sig"
  cp "$signers" "$bundle/race-signers"
  printf '%s\n' '{"replacement":"not-authorized"}' > "$bundle/.auth-replacement-source"
  chmod 600 "$bundle/race-action.json" "$bundle/race-action.json.sig" "$bundle/race-signers" "$bundle/.auth-replacement-source"
  : > "$ledger"
  chmod 600 "$ledger"
  before="$(file_hash "$ledger")"
  AUTH_DESCRIPTOR_TEST_RACE_PATH="$bundle/race-action.json"
  AUTH_DESCRIPTOR_TEST_RACE_REPLACEMENT="$bundle/.auth-replacement-source"
  AUTH_DESCRIPTOR_TEST_RACE_STAGE=after-auth-snapshot
  set +e
  result="$(auth_descriptor_snapshot "$AUTH_DESCRIPTOR_TEST_RACE_PATH" "$bundle/race-action.json.sig" "$bundle/race-signers" supervisor-approver aicc-supervisor-authorization true "$task_root" 9)"
  helper_rc=$?
  set -e
  after="$(file_hash "$ledger")"
  replacement_sha="$(file_hash "$AUTH_DESCRIPTOR_TEST_RACE_PATH")"
  error_code="$(jq -r '.code // ""' <<< "$result")"
  ledger_existed=false
  [[ -e "$ledger" && ! -L "$ledger" ]] && ledger_existed=true
  digest_changed=false
  [[ "$before" != "$after" ]] && digest_changed=true
  AUTH_DESCRIPTOR_TEST_RACE_PATH=''
  AUTH_DESCRIPTOR_TEST_RACE_REPLACEMENT=''
  AUTH_DESCRIPTOR_TEST_RACE_STAGE=''
  [[ "$error_code" == auth-descriptor-path-replaced && "$action_sha" != "$replacement_sha" && "$before" == "$after" ]] || { printf 'AUTH_PATH_REPLACEMENT_DIAGNOSTIC code=%s helperRc=%s ledgerExisted=%s ledgerDigestChanged=%s actionStable=%s signatureStable=%s signersStable=%s\n' "$error_code" "$helper_rc" "$ledger_existed" "$digest_changed" "$(jq -r '.action_stable // true' <<< "$result")" "$(jq -r '.signature_stable // true' <<< "$result")" "$(jq -r '.signers_stable // true' <<< "$result")" >&2; echo 'FAIL: auth path replacement was not rejected without ledger mutation'; return 1; }
  echo 'AUTH_PATH_REPLACEMENT_SELFTEST=PASS'
}

if [[ "${SYNC_AUTH_PATH_REPLACEMENT_SELFTEST:-}" == "1" ]]; then
  task_auth_path_replacement_selfcheck
  exit $?
fi

if [[ "${SYNC_LEDGER_UNSAFE_SELFTEST:-}" == "1" ]]; then
  task_ledger_unsafe_selfcheck
  exit $?
fi

if [[ "${SYNC_AUTH_DESCRIPTOR_SELFTEST:-}" == "1" ]]; then
  task_auth_descriptor_selfcheck
  exit $?
fi

if [[ "${SYNC_FAULT_SEAM_AUTH_SELFTEST:-}" == "1" ]]; then
  task_fault_seam_authorization_selfcheck
  exit $?
fi

task_fault_seam_control_flow_selfcheck() {
  local fault_rc=0
  local handle_marker=unreached
  local report_marker=unreached

  source "$SYNC_SCRIPT"
  TEST_FAULT_SEAM_ENABLED=true
  TEST_FAULT_TARGET=kimi
  invoke_test_fault_seam post-owner-install kimi || fault_rc=$?
  if [[ "$fault_rc" == "86" ]]; then
    handle_marker=reached
  fi
  report_marker=reached
  if [[ "$fault_rc" != "86" || "$handle_marker" != reached || "$report_marker" != reached ]]; then
    printf 'FAULT_SEAM_CONTROL_MISMATCH fault_rc=%s handle=%s report=%s\n' "$fault_rc" "$handle_marker" "$report_marker" >&2
    return 1
  fi
  echo 'FAULT_SEAM_CONTROL_FLOW_SELFTEST=PASS'
}

if [[ "${SYNC_FAULT_SEAM_CONTROL_SELFTEST:-}" == "1" ]]; then
  task_fault_seam_control_flow_selfcheck
  exit $?
fi

task_single_object_rollback_selfcheck() {
  local fixture_dir source_copy plan_file stage_root journal created target backup has_backup tool target_id journal_index owner_rel kind
  local pre_digest pre_mode pre_size expected_digest expected_mode expected_size staged_digest staged_mode staged_size parsed_line restore_rc=0 verify_rc=0 evidence

  build_isolated_fixture || return 1
  fixture_dir="$(fixture_case_home)"
  source_copy="$(fixture_source_copy "$fixture_dir")"
  source "$SYNC_SCRIPT"
  TEST_MODE=true
  TEST_MODE_ROOT="$fixture_dir"
  HOME_OVERRIDE="$fixture_dir"
  PROJECT_ROOT="$fixture_dir"
  load_canonical_role_profile || return 1
  plan_file="$(mktemp "$fixture_dir/single-owner-plan.XXXXXX")" || return 1
  stage_root="$fixture_dir/single-owner-stage"
  journal="$(mktemp "$fixture_dir/single-owner-journal.XXXXXX")" || return 1
  created="$(mktemp "$fixture_dir/single-owner-created.XXXXXX")" || return 1
  build_owner_plan "$source_copy/aider/CONVENTIONS.md" whole-file aider 'aider:${PROJECT}/CONVENTIONS.md' 0 single-object-digest '[]' "$plan_file" || return 1
  stage_owner_plan "$source_copy/aider/CONVENTIONS.md" "$plan_file" "$stage_root" || return 1
  target="$fixture_dir/project/CONVENTIONS.md"
  mkdir -p "$fixture_dir/project"
  printf 'single owner pre-state\n' > "$target"
  chmod 640 "$target"
  IFS=$'\t' read -r pre_digest pre_mode pre_size < <(python3 - "$target" <<'PY'
import hashlib
import os
import stat
import sys

path = sys.argv[1]
parent, name = os.path.split(path)
parent_fd = os.open(parent, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0) | getattr(os, 'O_NOFOLLOW', 0))
try:
    st = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    if not stat.S_ISREG(st.st_mode): raise SystemExit(1)
    fd = os.open(name, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0), dir_fd=parent_fd)
    try:
        digest = hashlib.sha256()
        while True:
            block = os.read(fd, 1024 * 1024)
            if not block: break
            digest.update(block)
        print(f"{digest.hexdigest()}\t{stat.S_IMODE(st.st_mode):o}\t{st.st_size}")
    finally:
        os.close(fd)
finally:
    os.close(parent_fd)
PY
)
  install_owner_plan "$stage_root" "$plan_file" "$target" file false "$journal" "$created" 'aider:${PROJECT}/CONVENTIONS.md' 0 aider || return 1
  parsed_line="$(head -n 1 "$journal")"
  parsed_line="${parsed_line//$'\t'/$'\034'}"
  IFS=$'\034' read -r journal_index target backup has_backup tool target_id journal_index owner_rel kind expected_digest expected_mode expected_size staged_digest staged_mode staged_size <<< "$parsed_line"
  if [[ "$target_id" != 'aider:${PROJECT}/CONVENTIONS.md' || "$owner_rel" != '__whole_file__' || "$kind" != file || "$has_backup" != 1 || "$expected_digest" != "$pre_digest" || "$expected_mode" != "$pre_mode" || "$expected_size" != "$pre_size" ]]; then
    printf 'SINGLE_OWNER_JOURNAL_MISMATCH target_id=%s owner_rel=%s kind=%s was_existing=%s pre_digest=%s expected_digest=%s staged_digest=%s\n' "$target_id" "$owner_rel" "$kind" "$has_backup" "$pre_digest" "$expected_digest" "$staged_digest" >&2
    return 1
  fi
  verify_rollback_owner "$backup" present file "$pre_digest" "$pre_mode" "$pre_size" || { echo 'FAIL: single owner backup metadata mismatch'; return 1; }
  ENTRY_TOTAL=1
  ENTRY_STATUS=(pending)
  ROLLBACK_RESTORE_FAILURES='[]'
  restore_from_journal "$journal" || restore_rc=$?
  verify_rollback_owner "$target" present file "$pre_digest" "$pre_mode" "$pre_size" || verify_rc=$?
  if [[ "$restore_rc" != 0 || "$verify_rc" != 0 || "$RUN_ROLLBACK_RESTORED" != 1 || "$ROLLBACK_RESTORE_FAILURES" != '[]' ]]; then
    printf 'SINGLE_OWNER_RESTORE_MISMATCH target_id=%s owner_rel=%s expected_digest=%s restore_rc=%s verify_rc=%s restored=%s restoreFailures=%s\n' "$target_id" "$owner_rel" "$pre_digest" "$restore_rc" "$verify_rc" "$RUN_ROLLBACK_RESTORED" "$ROLLBACK_RESTORE_FAILURES" >&2
    return 1
  fi
  evidence="$(jq -cn --arg targetId "$target_id" --arg ownerRel "$owner_rel" --arg preDigest "$pre_digest" --arg preMode "$pre_mode" --argjson preSize "$pre_size" --arg stagedDigest "$staged_digest" --arg stagedMode "$staged_mode" --argjson stagedSize "$staged_size" '{targetId:$targetId,ownerRel:$ownerRel,pre:{type:"file",mode:$preMode,size:$preSize,digest:$preDigest},backup:{type:"file",mode:$preMode,size:$preSize,digest:$preDigest},staged:{type:"file",mode:$stagedMode,size:$stagedSize,digest:$stagedDigest},rollbackVerifier:{actual:{type:"file",mode:$preMode,size:$preSize,digest:$preDigest},countedRestored:true}}')"
  printf 'SINGLE_OWNER_ROLLBACK_EVIDENCE=%s\n' "$evidence" >&2
  echo 'SINGLE_OBJECT_ROLLBACK_SELFTEST=PASS'
}

if [[ "${SYNC_SINGLE_OBJECT_ROLLBACK_SELFTEST:-}" == "1" ]]; then
  task_single_object_rollback_selfcheck
  exit $?
fi

task_a_owner_plan_selfcheck() {
  local task_root source_copy source_digest plan_one plan_two whole_plan first_owner
  task_root="$(mktemp -d "${TMPDIR:-/tmp}/agency-owner-plan.XXXXXX")" || return 1
  trap "rm -rf -- '$task_root' '$FIXTURE_ROOT'" EXIT

  if ! jq -e '[.tools[].targets[] | .ownerMode] | length == 18 and all(.[]; . == "source-top-level" or . == "whole-file")' "$MANIFEST_PATH" >/dev/null; then
    echo 'FAIL: manifest ownerMode contract is not exactly 18 supported modes'
    return 1
  fi

  if ! build_isolated_fixture; then
    echo 'FAIL: unable to build isolated owner-plan fixture'
    return 1
  fi
  source_copy="$(fixture_source_copy "$task_root")" || return 1

  source "$SYNC_SCRIPT"
  TEST_MODE=true
  TEST_MODE_ROOT="$task_root"
  exec 9<"$task_root" || return 1
  TEST_MODE_ROOT_FD=9
  TEST_MODE_ROOT_BOUND_MARKER=v1
  HOME_OVERRIDE="$task_root"
  PROJECT_OVERRIDE="$task_root"
  if ! load_canonical_role_profile; then
    echo 'FAIL: unable to load canonical role profile for owner plan'
    return 1
  fi

  source_digest="task-a-isolated-source-digest"
  plan_one="$(mktemp "$task_root/plan-one.XXXXXX")" || return 1
  plan_two="$(mktemp "$task_root/plan-two.XXXXXX")" || return 1
  whole_plan="$(mktemp "$task_root/whole-plan.XXXXXX")" || return 1

  if ! build_owner_plan "$source_copy/openclaw" "source-top-level" "openclaw" "task-a:openclaw" 0 "$source_digest" '[]' "$plan_one"; then
    echo "FAIL: source-top-level owner plan BLOCK: ${OWNER_PLAN_FAILURE_REASON:-unknown}"
    return 1
  fi
  if [[ "$(wc -l < "$plan_one" | tr -d ' ')" != "269" ]] || ! LC_ALL=C sort -c -t $'\t' -k3,3 "$plan_one" || [[ "$(cut -f3 "$plan_one" | LC_ALL=C sort -u | wc -l | tr -d ' ')" != "269" ]]; then
    echo 'FAIL: source-top-level owner plan is not a sorted canonical 269-entry plan'
    return 1
  fi
  if ! build_owner_plan "$source_copy/openclaw" "source-top-level" "openclaw" "task-a:openclaw" 0 "$source_digest" '[]' "$plan_two" || ! cmp -s "$plan_one" "$plan_two"; then
    echo 'FAIL: source-top-level owner plan is not deterministic'
    return 1
  fi
  if ! build_owner_plan "$source_copy/aider/CONVENTIONS.md" "whole-file" "aider" "task-a:aider" 1 "$source_digest" '[]' "$whole_plan" || [[ "$(wc -l < "$whole_plan" | tr -d ' ')" != "1" ]] || ! awk -F $'\t' 'NR == 1 { exit !($2 == "__whole_file__" && $3 == "__whole_file__" && $4 == "file") }' "$whole_plan"; then
    echo 'FAIL: whole-file owner plan contract mismatch'
    return 1
  fi

  first_owner="$(awk -F $'\t' 'NR == 1 { print $2 }' "$plan_one")"
  if build_owner_plan "$source_copy/openclaw" "source-top-level" "openclaw" "task-a:openclaw" 0 "$source_digest" "[\"${first_owner}\"]" "$(mktemp "$task_root/protected.XXXXXX")"; then
    echo 'FAIL: protected lexical overlap was accepted'
    return 1
  fi
  mkdir -p "$task_root/unsafe-symlink" "$task_root/unsafe-special"
  ln -s "$source_copy/openclaw/$first_owner" "$task_root/unsafe-symlink/$first_owner"
  if build_owner_plan "$task_root/unsafe-symlink" "source-top-level" "openclaw" "task-a:unsafe" 2 "$source_digest" '[]' "$(mktemp "$task_root/symlink.XXXXXX")"; then
    echo 'FAIL: source symlink was accepted'
    return 1
  fi
  mkfifo "$task_root/unsafe-special/fifo"
  if build_owner_plan "$task_root/unsafe-special" "source-top-level" "openclaw" "task-a:special" 3 "$source_digest" '[]' "$(mktemp "$task_root/special.XXXXXX")"; then
    echo 'FAIL: source special file was accepted'
    return 1
  fi
  if build_owner_plan "$source_copy/openclaw" "unknown-mode" "openclaw" "task-a:unknown" 4 "$source_digest" '[]' "$(mktemp "$task_root/unknown.XXXXXX")"; then
    echo 'FAIL: unknown ownerMode was accepted'
    return 1
  fi
  echo 'TASK_A_OWNER_PLAN_SELFTEST=PASS'
}

if [[ "${SYNC_TASK_A_SELFTEST:-}" == "1" ]]; then
  task_a_owner_plan_selfcheck
  exit $?
fi

task_b_stage_selfcheck() {
  local task_root raw_task_root source_copy plan_top plan_top_check plan_whole stage_parent stage_top stage_whole
  raw_task_root="$(mktemp -d /tmp/agency-owner-stage.XXXXXX)" || return 1
  task_root="$(physical_root "$raw_task_root")" || return 1
  export TMPDIR="$task_root"
  trap "rm -rf -- '$task_root' '$FIXTURE_ROOT'" EXIT

  if ! build_isolated_fixture; then
    echo 'FAIL: unable to build isolated staging fixture'
    return 1
  fi
  source_copy="$(fixture_source_copy "$task_root")" || return 1
  source "$SYNC_SCRIPT"
  TEST_MODE=true
  TEST_MODE_ROOT="$task_root"
  exec 9<"$task_root" || return 1
  TEST_MODE_ROOT_FD=9
  HOME_OVERRIDE="$task_root"
  PROJECT_OVERRIDE="$task_root"
  load_canonical_role_profile || return 1

  plan_top="$(mktemp "$task_root/plan-top.XXXXXX")" || return 1
  plan_top_check="$(mktemp "$task_root/plan-top-check.XXXXXX")" || return 1
  plan_whole="$(mktemp "$task_root/plan-whole.XXXXXX")" || return 1
  if ! build_owner_plan "$source_copy/openclaw" source-top-level openclaw task-b:openclaw 0 task-b-source-digest '[]' "$plan_top"; then
    echo "FAIL: Task B source plan BLOCK: ${OWNER_PLAN_FAILURE_REASON:-unknown}"
    return 1
  fi
  if ! build_owner_plan "$source_copy/aider/CONVENTIONS.md" whole-file aider task-b:aider 1 task-b-source-digest '[]' "$plan_whole"; then
    echo "FAIL: Task B whole-file plan BLOCK: ${OWNER_PLAN_FAILURE_REASON:-unknown}"
    return 1
  fi

  stage_parent="$task_root/stage-parent"
  mkdir -p "$stage_parent"
  stage_top="$stage_parent/stage-top"
  stage_whole="$stage_parent/stage-whole"
  if ! stage_owner_plan "$source_copy/openclaw" "$plan_top" "$stage_top"; then
    echo "FAIL: source-top-level staging BLOCK: ${OWNER_STAGE_FAILURE_REASON:-unknown}"
    return 1
  fi
  if ! build_owner_plan "$stage_top" source-top-level openclaw task-b:staged 0 task-b-stage-digest '[]' "$plan_top_check" || ! diff -u <(cut -f1-6 "$plan_top") <(cut -f1-6 "$plan_top_check") >/dev/null; then
    echo 'FAIL: staged directory owners do not preserve plan digest/mode or contain extra entries'
    return 1
  fi
  if ! stage_owner_plan "$source_copy/aider/CONVENTIONS.md" "$plan_whole" "$stage_whole"; then
    echo "FAIL: whole-file staging BLOCK: ${OWNER_STAGE_FAILURE_REASON:-unknown}"
    return 1
  fi
  if [[ ! -f "$stage_whole/__whole_file__" ]] || ! cmp -s "$source_copy/aider/CONVENTIONS.md" "$stage_whole/__whole_file__" || [[ "$(stat -f '%Lp' "$source_copy/aider/CONVENTIONS.md")" != "$(stat -f '%Lp' "$stage_whole/__whole_file__")" ]]; then
    echo 'FAIL: staged whole-file content or mode mismatch'
    return 1
  fi

  mkdir -p "$stage_parent/preexisting"
  if stage_owner_plan "$source_copy/openclaw" "$plan_top" "$stage_parent/preexisting" >/dev/null 2>&1; then
    echo 'FAIL: pre-existing stage root was accepted'
    return 1
  fi
  ln -s "$stage_parent" "$stage_parent/stage-symlink"
  if stage_owner_plan "$source_copy/openclaw" "$plan_top" "$stage_parent/stage-symlink" >/dev/null 2>&1; then
    echo 'FAIL: stage symlink was accepted'
    return 1
  fi
  mkfifo "$stage_parent/stage-special"
  if stage_owner_plan "$source_copy/openclaw" "$plan_top" "$stage_parent/stage-special" >/dev/null 2>&1; then
    echo 'FAIL: stage special-file collision was accepted'
    return 1
  fi
  echo 'TASK_B_DESCRIPTOR_STAGE_SELFTEST=PASS'
}

if [[ "${SYNC_TASK_B_SELFTEST:-}" == "1" ]]; then
  task_b_stage_selfcheck
  exit $?
fi

task_c1_created_root_contract_selfcheck() {
  local preexisting="${1:-false}"
  local raw_task_root task_root source_copy plan_top plan_one stage_qwen stage_kimi journal created first_owner qwen_target kimi_target qwen_backup kimi_backup expected_mode
  raw_task_root="$(mktemp -d /tmp/agency-owner-created-root.XXXXXX)" || return 1
  task_root="$(physical_root "$raw_task_root")" || return 1
  export TMPDIR="$task_root"
  trap "rm -rf -- '$task_root' '$FIXTURE_ROOT'" EXIT
  build_isolated_fixture || return 1
  source_copy="$(fixture_source_copy "$task_root")" || return 1
  source "$SYNC_SCRIPT"
  TEST_MODE=true
  TEST_MODE_ROOT="$task_root"
  exec 9<"$task_root" || return 1
  TEST_MODE_ROOT_FD=9
  HOME_OVERRIDE="$task_root"
  PROJECT_OVERRIDE="$task_root"
  load_canonical_role_profile || return 1

  plan_top="$(mktemp "$task_root/plan-top.XXXXXX")" || return 1
  plan_one="$(mktemp "$task_root/plan-one.XXXXXX")" || return 1
  build_owner_plan "$source_copy/openclaw" source-top-level openclaw task-c1:root-plan 0 task-c1-digest '[]' "$plan_top" || return 1
  head -n 1 "$plan_top" >"$plan_one"
  first_owner="$(awk -F $'\t' 'NR == 1 { print $2 }' "$plan_one")"
  stage_qwen="$task_root/stage-qwen"
  stage_kimi="$task_root/stage-kimi"
  stage_owner_plan "$source_copy/openclaw" "$plan_one" "$stage_qwen" || return 1
  stage_owner_plan "$source_copy/openclaw" "$plan_one" "$stage_kimi" || return 1
  journal="$(mktemp "$task_root/journal.XXXXXX")" || return 1
  created="$(mktemp "$task_root/created.XXXXXX")" || return 1
  qwen_target="$task_root/qwen-root/.qwen/agents"
  kimi_target="$task_root/kimi-root/.config/kimi/agents"
  if [[ "$preexisting" == "true" ]]; then
    mkdir -p "$qwen_target" "$kimi_target"
    expected_mode=preexisting
  else
    expected_mode=created
  fi

  install_owner_plan "$stage_qwen" "$plan_one" "$qwen_target" directory true "$journal" "$created" task-c1:qwen 2 qwen || return 1
  qwen_backup="$OWNER_INSTALL_BACKUP_DIR"
  install_owner_plan "$stage_kimi" "$plan_one" "$kimi_target" directory true "$journal" "$created" task-c1:kimi 3 kimi || return 1
  kimi_backup="$OWNER_INSTALL_BACKUP_DIR"

  if ! python3 - "$created" "$task_root" "$expected_mode" <<'PY'
import json
import sys

journal, test_root, mode = sys.argv[1:]
entries = []
for order, raw in enumerate(open(journal, encoding="utf-8"), 1):
    fields = raw.rstrip("\n").split("\t")
    if len(fields) != 4:
        entries.append({"order": order, "targetId": "<invalid>", "kind": "<invalid>", "trustedRoot": "invalid", "relative": "<invalid>"})
        continue
    target_id, kind, root, relative = fields
    entries.append({"order": order, "targetId": target_id, "kind": kind, "trustedRoot": "test-home" if root == test_root else "unexpected", "relative": relative})
expected = [] if mode == "preexisting" else [
    {"order": 1, "targetId": "task-c1:qwen", "kind": "parent-dir", "trustedRoot": "test-home", "relative": "qwen-root"},
    {"order": 2, "targetId": "task-c1:qwen", "kind": "parent-dir", "trustedRoot": "test-home", "relative": "qwen-root/.qwen"},
    {"order": 3, "targetId": "task-c1:qwen", "kind": "created-target-root", "trustedRoot": "test-home", "relative": "qwen-root/.qwen/agents"},
    {"order": 4, "targetId": "task-c1:kimi", "kind": "parent-dir", "trustedRoot": "test-home", "relative": "kimi-root"},
    {"order": 5, "targetId": "task-c1:kimi", "kind": "parent-dir", "trustedRoot": "test-home", "relative": "kimi-root/.config"},
    {"order": 6, "targetId": "task-c1:kimi", "kind": "parent-dir", "trustedRoot": "test-home", "relative": "kimi-root/.config/kimi"},
    {"order": 7, "targetId": "task-c1:kimi", "kind": "created-target-root", "trustedRoot": "test-home", "relative": "kimi-root/.config/kimi/agents"},
]
if entries != expected or len({(entry["trustedRoot"], entry["relative"]) for entry in entries}) != len(entries):
    print("C1_CREATED_ROOT_ACTUAL=" + json.dumps(entries, separators=(",", ":"), sort_keys=True), file=sys.stderr)
    print("C1_CREATED_ROOT_EXPECTED=" + json.dumps(expected, separators=(",", ":"), sort_keys=True), file=sys.stderr)
    raise SystemExit(1)
PY
  then
    return 1
  fi

  ENTRY_TOTAL=4
  ENTRY_STATUS=(pending pending pending pending)
  restore_from_journal "$journal" || return 1
  [[ ! -e "$qwen_backup" ]] || descriptor_no_follow_remove "$qwen_backup" 0 || return 1
  [[ ! -e "$kimi_backup" ]] || descriptor_no_follow_remove "$kimi_backup" 0 || return 1
  cleanup_created_dirs "$created" || return 1
  if [[ -e "$qwen_target/$first_owner" || -L "$qwen_target/$first_owner" || -e "$kimi_target/$first_owner" || -L "$kimi_target/$first_owner" ]]; then
    echo 'FAIL: created-root contrast owner rollback incomplete'
    return 1
  fi
  if [[ "$preexisting" == "true" ]]; then
    if [[ ! -d "$qwen_target" || ! -d "$kimi_target" ]]; then
      echo 'FAIL: preexisting target root was removed'
      return 1
    fi
    echo 'TASK_C1_PREEXISTING_ROOT_SELFTEST=PASS'
  else
    if [[ -e "$task_root/qwen-root" || -L "$task_root/qwen-root" || -e "$task_root/kimi-root" || -L "$task_root/kimi-root" ]]; then
      echo 'FAIL: transaction-created target root or parent was retained'
      return 1
    fi
    echo 'TASK_C1_CREATED_ROOT_SELFTEST=PASS'
  fi
}

if [[ "${SYNC_TASK_C1_CREATED_ROOT_SELFTEST:-}" == "1" ]]; then
  task_c1_created_root_contract_selfcheck false
  exit $?
fi

if [[ "${SYNC_TASK_C1_PREEXISTING_ROOT_SELFTEST:-}" == "1" ]]; then
  task_c1_created_root_contract_selfcheck true
  exit $?
fi

task_c1_owner_install_selfcheck() {
  local task_root raw_task_root source_copy plan_top plan_one plan_whole stage_top stage_qwen stage_kimi stage_whole stage_multi stage_false stage_symlink stage_whole_created journal created first_owner first_digest first_mode whole_digest whole_mode whole_size target_root qwen_target kimi_target whole_target multi_target false_target symlink_target whole_created_target
  raw_task_root="$(mktemp -d /tmp/agency-owner-install.XXXXXX)" || return 1
  task_root="$(physical_root "$raw_task_root")" || return 1
  export TMPDIR="$task_root"
  trap "rm -rf -- '$task_root' '$FIXTURE_ROOT'" EXIT
  build_isolated_fixture || return 1
  source_copy="$(fixture_source_copy "$task_root")" || return 1
  source "$SYNC_SCRIPT"
  TEST_MODE=true
  TEST_MODE_ROOT="$task_root"
  exec 9<"$task_root" || return 1
  TEST_MODE_ROOT_FD=9
  HOME_OVERRIDE="$task_root"
  PROJECT_OVERRIDE="$task_root"
  load_canonical_role_profile || return 1

  plan_top="$(mktemp "$task_root/plan-top.XXXXXX")" || return 1
  plan_one="$(mktemp "$task_root/plan-one.XXXXXX")" || return 1
  plan_whole="$(mktemp "$task_root/plan-whole.XXXXXX")" || return 1
  build_owner_plan "$source_copy/openclaw" source-top-level openclaw task-c1:openclaw 0 task-c1-digest '[]' "$plan_top" || return 1
  head -n 1 "$plan_top" > "$plan_one"
  build_owner_plan "$source_copy/aider/CONVENTIONS.md" whole-file aider task-c1:aider 1 task-c1-digest '[]' "$plan_whole" || return 1
  first_owner="$(awk -F $'\t' 'NR == 1 { print $2 }' "$plan_one")"
  first_digest="$(awk -F $'\t' 'NR == 1 { print $5 }' "$plan_one")"
  first_mode="$(awk -F $'\t' 'NR == 1 { print $6 }' "$plan_one")"
  whole_digest="$(awk -F $'\t' 'NR == 1 { print $5 }' "$plan_whole")"
  whole_mode="$(awk -F $'\t' 'NR == 1 { print $6 }' "$plan_whole")"
  whole_size="$(stat -f '%z' "$source_copy/aider/CONVENTIONS.md")"
  stage_top="$task_root/stage-top"
  stage_qwen="$task_root/stage-qwen"
  stage_kimi="$task_root/stage-kimi"
  stage_whole="$task_root/stage-whole"
  stage_multi="$task_root/stage-multi"
  stage_false="$task_root/stage-false"
  stage_symlink="$task_root/stage-symlink"
  stage_whole_created="$task_root/stage-whole-created"
  stage_owner_plan "$source_copy/openclaw" "$plan_top" "$stage_top" || return 1
  stage_owner_plan "$source_copy/openclaw" "$plan_top" "$stage_qwen" || return 1
  stage_owner_plan "$source_copy/openclaw" "$plan_top" "$stage_kimi" || return 1
  stage_owner_plan "$source_copy/aider/CONVENTIONS.md" "$plan_whole" "$stage_whole" || return 1
  stage_owner_plan "$source_copy/openclaw" "$plan_one" "$stage_multi" || return 1
  stage_owner_plan "$source_copy/openclaw" "$plan_one" "$stage_false" || return 1
  stage_owner_plan "$source_copy/openclaw" "$plan_one" "$stage_symlink" || return 1
  stage_owner_plan "$source_copy/aider/CONVENTIONS.md" "$plan_whole" "$stage_whole_created" || return 1
  if [[ ! -d "$stage_top/$first_owner" ]]; then
    echo 'FAIL: Task B stage does not contain planned owner'
    return 1
  fi
  journal="$(mktemp "$task_root/journal.XXXXXX")" || return 1
  created="$(mktemp "$task_root/created.XXXXXX")" || return 1

  target_root="$task_root/target/agents"
  mkdir -p "$target_root/$first_owner" "$target_root/owner-outside-dir" "$task_root/sentinel"
  printf 'old owner\n' > "$target_root/$first_owner/old.txt"
  printf 'keep file\n' > "$target_root/owner-outside-file"
  printf 'keep link\n' > "$task_root/sentinel/kept.txt"
  ln -s "$task_root/sentinel" "$target_root/owner-outside-link"
  local keep_before
  keep_before="$(stat -f '%i|%p|%z|%m' "$target_root/owner-outside-file")|$(shasum -a 256 "$target_root/owner-outside-file" | awk '{print $1}')|$(readlink "$target_root/owner-outside-link")"
  if ! install_owner_plan "$stage_top" "$plan_one" "$target_root" directory false "$journal" "$created" task-c1:openclaw 0 openclaw; then
    echo "FAIL: existing/absent owner install BLOCK: ${OWNER_INSTALL_FAILURE_REASON:-unknown}"
    return 1
  fi
  if [[ -e "$target_root/$first_owner/old.txt" ]] || [[ ! -d "$target_root/$first_owner" ]]; then
    echo 'FAIL: existing owner was not atomically replaced'
    return 1
  fi
  if [[ "$keep_before" != "$(stat -f '%i|%p|%z|%m' "$target_root/owner-outside-file")|$(shasum -a 256 "$target_root/owner-outside-file" | awk '{print $1}')|$(readlink "$target_root/owner-outside-link")" ]] || [[ ! -d "$target_root/owner-outside-dir" ]]; then
    echo 'FAIL: owner-external sentinel changed'
    return 1
  fi

  qwen_target="$task_root/qwen-root/.qwen/agents"
  kimi_target="$task_root/kimi-root/.config/kimi/agents"
  install_owner_plan "$stage_qwen" "$plan_one" "$qwen_target" directory true "$journal" "$created" task-c1:qwen 2 qwen || return 1
  install_owner_plan "$stage_kimi" "$plan_one" "$kimi_target" directory true "$journal" "$created" task-c1:kimi 3 kimi || return 1
  if [[ ! -d "$qwen_target/$first_owner" || ! -d "$kimi_target/$first_owner" ]]; then
    echo 'FAIL: missing qwen/kimi parents were not descriptor-created'
    return 1
  fi
  if ! python3 - "$created" "$task_root" <<'PY'
import json
import sys

journal, test_root = sys.argv[1:]
entries = []
for order, raw in enumerate(open(journal, encoding="utf-8"), 1):
    fields = raw.rstrip("\n").split("\t")
    if len(fields) == 4:
        target_id, kind, root, relative = fields
        entries.append({"order": order, "targetId": target_id, "kind": kind, "trustedRoot": "test-home" if root == test_root else "unexpected", "relative": relative})
    else:
        entries.append({"order": order, "targetId": "<invalid>", "kind": "<invalid>", "trustedRoot": "invalid", "relative": "<invalid>"})
expected = [
    {"order": 1, "targetId": "task-c1:qwen", "kind": "parent-dir", "trustedRoot": "test-home", "relative": "qwen-root"},
    {"order": 2, "targetId": "task-c1:qwen", "kind": "parent-dir", "trustedRoot": "test-home", "relative": "qwen-root/.qwen"},
    {"order": 3, "targetId": "task-c1:qwen", "kind": "created-target-root", "trustedRoot": "test-home", "relative": "qwen-root/.qwen/agents"},
    {"order": 4, "targetId": "task-c1:kimi", "kind": "parent-dir", "trustedRoot": "test-home", "relative": "kimi-root"},
    {"order": 5, "targetId": "task-c1:kimi", "kind": "parent-dir", "trustedRoot": "test-home", "relative": "kimi-root/.config"},
    {"order": 6, "targetId": "task-c1:kimi", "kind": "parent-dir", "trustedRoot": "test-home", "relative": "kimi-root/.config/kimi"},
    {"order": 7, "targetId": "task-c1:kimi", "kind": "created-target-root", "trustedRoot": "test-home", "relative": "kimi-root/.config/kimi/agents"},
]
if entries != expected or len({(entry["trustedRoot"], entry["relative"]) for entry in entries}) != len(entries):
    print("C1_CREATED_DIR_JOURNAL=" + json.dumps(entries, separators=(",", ":"), sort_keys=True), file=sys.stderr)
    print("C1_CREATED_DIR_EXPECTED=" + json.dumps(expected, separators=(",", ":"), sort_keys=True), file=sys.stderr)
    raise SystemExit(1)
PY
  then
    echo 'FAIL: multi-level created-directory journal is incomplete'
    return 1
  fi

  multi_target="$task_root/multi-root/a/b/agents"
  install_owner_plan "$stage_multi" "$plan_one" "$multi_target" directory true "$journal" "$created" task-c1:multi 4 openclaw || return 1
  if [[ ! -d "$multi_target/$first_owner" ]]; then
    echo 'FAIL: nested target parents were not descriptor-created'
    return 1
  fi
  false_target="$task_root/false-root/a/b/agents"
  if install_owner_plan "$stage_false" "$plan_one" "$false_target" directory false "$journal" "$created" task-c1:false 5 openclaw >/dev/null 2>&1; then
    echo 'FAIL: createIfMissing=false accepted missing parent'
    return 1
  fi
  mkdir -p "$task_root/symlink-root/sentinel"
  ln -s "$task_root/symlink-root/sentinel" "$task_root/symlink-root/.config"
  symlink_target="$task_root/symlink-root/.config/kimi/agents"
  if install_owner_plan "$stage_symlink" "$plan_one" "$symlink_target" directory true "$journal" "$created" task-c1:symlink-parent 6 openclaw >/dev/null 2>&1; then
    echo 'FAIL: symlink intermediate target component was accepted'
    return 1
  fi
  whole_created_target="$task_root/whole-created/project/CONVENTIONS.md"
  install_owner_plan "$stage_whole_created" "$plan_whole" "$whole_created_target" file true "$journal" "$created" task-c1:whole-created 7 aider || return 1
  if ! cmp -s "$source_copy/aider/CONVENTIONS.md" "$whole_created_target"; then
    echo 'FAIL: whole-file parent creation did not preserve source content'
    return 1
  fi

  whole_target="$task_root/project/CONVENTIONS.md"
  mkdir -p "$(dirname "$whole_target")"
  printf 'old whole file\n' > "$whole_target"
  install_owner_plan "$stage_whole" "$plan_whole" "$whole_target" file false "$journal" "$created" task-c1:aider 8 aider || return 1
  if ! cmp -s "$source_copy/aider/CONVENTIONS.md" "$whole_target"; then
    echo 'FAIL: whole-file owner was not installed'
    return 1
  fi
  if ! python3 - "$journal" "$first_owner" "$first_digest" "$first_mode" "$whole_digest" "$whole_mode" "$whole_size" <<'PY'
import hashlib
import json
import os
import stat
import sys

journal, owner, owner_digest, owner_mode, whole_digest, whole_mode, whole_size = sys.argv[1:]
names = ["schema", "targetIndex", "targetPath", "targetId", "tool", "ownerRelative", "ownerKind", "originalState", "backupReference", "originalType", "originalMode", "originalSize", "originalDigest", "stagedType", "stagedMode", "stagedSize", "stagedDigest"]

def digest_path(path, kind):
    st = os.lstat(path)
    if stat.S_ISLNK(st.st_mode):
        raise SystemExit(1)
    if kind == "file":
        with open(path, "rb") as fp:
            digest = hashlib.sha256(fp.read()).hexdigest()
        return {"type": "file", "mode": format(stat.S_IMODE(st.st_mode), "o"), "size": st.st_size, "digest": digest}
    digest = hashlib.sha256()
    for child in sorted(os.listdir(path)):
        child_path = os.path.join(path, child)
        child_kind = "directory" if os.path.isdir(child_path) and not os.path.islink(child_path) else "file"
        meta = digest_path(child_path, child_kind)
        child_row_terminator = b"\\n"
        if child_row_terminator != bytes((0x5c, 0x6e)) or child_row_terminator == bytes((0x0a,)):
            raise SystemExit("owner journal child-row terminator contract mismatch")
        digest.update(f"{child_kind}|{child}|{meta['mode']}|{meta['digest']}\\n".encode())
    return {"type": "directory", "mode": format(stat.S_IMODE(st.st_mode), "o"), "size": 0, "digest": digest.hexdigest()}

rows = []
for raw in open(journal, encoding="utf-8"):
    fields = raw.rstrip("\n").split("\t")
    rows.append(fields)
actual = []
valid = True
for fields in rows:
    field_states = [{"name": name, "empty": index >= len(fields) or fields[index] == ""} for index, name in enumerate(names)]
    if len(fields) != 17:
        valid = False
        actual.append({"fieldCount": len(fields), "fieldStates": field_states})
        continue
    values = dict(zip(names, fields))
    original = {"type": values["originalType"], "mode": values["originalMode"], "size": values["originalSize"], "digest": values["originalDigest"]}
    staged = {"type": values["stagedType"], "mode": values["stagedMode"], "size": values["stagedSize"], "digest": values["stagedDigest"]}
    original_metadata_verified = True
    backup_observed = None
    if values["originalState"] == "existing":
        if values["backupReference"] == "-":
            valid = False
            original_metadata_verified = False
        else:
            backup_observed = {key: str(value) for key, value in digest_path(values["backupReference"], values["ownerKind"]).items()}
            original_metadata_verified = original == backup_observed
            valid = valid and original_metadata_verified
    else:
        original_metadata_verified = values["backupReference"] == "-" and original == {"type": "absent", "mode": "-", "size": "-", "digest": "-"}
        valid = valid and original_metadata_verified
    actual.append({
        "fieldCount": len(fields), "fieldStates": field_states, "targetId": values["targetId"],
        "ownerRelative": values["ownerRelative"], "kind": values["ownerKind"], "originalState": values["originalState"],
        "backupReference": "present" if values["backupReference"] != "-" else "absent", "backupObserved": backup_observed, "originalMetadataVerified": original_metadata_verified, "original": original, "staged": staged,
    })

expected_specs = [
    ("task-c1:openclaw", owner, "directory", "existing", owner_digest, owner_mode, None),
    ("task-c1:qwen", owner, "directory", "created", owner_digest, owner_mode, None),
    ("task-c1:kimi", owner, "directory", "created", owner_digest, owner_mode, None),
    ("task-c1:multi", owner, "directory", "created", owner_digest, owner_mode, None),
    ("task-c1:whole-created", "__whole_file__", "file", "created", whole_digest, whole_mode, whole_size),
    ("task-c1:aider", "__whole_file__", "file", "existing", whole_digest, whole_mode, whole_size),
]
expected = []
for target_id, relative, kind, state, digest, mode, size in expected_specs:
    expected.append({"targetId": target_id, "ownerRelative": relative, "kind": kind, "originalState": state, "backupReference": "present" if state == "existing" else "absent", "staged": {"type": kind, "mode": mode, "size": str(0 if kind == "directory" else size), "digest": digest}})

actual_contract = [{key: row[key] for key in ("targetId", "ownerRelative", "kind", "originalState", "backupReference", "staged")} for row in actual if "targetId" in row]
print("C1_OWNER_JOURNAL_ACTUAL=" + json.dumps({"entryCount": len(actual), "entries": actual}, separators=(",", ":"), sort_keys=True), file=sys.stderr)
print("C1_OWNER_JOURNAL_EXPECTED=" + json.dumps({"entryCount": len(expected), "entries": expected}, separators=(",", ":"), sort_keys=True), file=sys.stderr)
if not valid or actual_contract != expected or len({(row.get("targetId"), row.get("ownerRelative"), row.get("kind")) for row in actual}) != len(actual):
    raise SystemExit(1)
PY
  then
    echo 'FAIL: owner journal is incomplete'
    return 1
  fi
  if [[ "${SYNC_TASK_C1_OWNER_JOURNAL_SELFTEST:-}" == "1" ]]; then
    echo 'TASK_C1_OWNER_JOURNAL_SELFTEST=PASS'
    return 0
  fi
  rm -rf "$target_root/$first_owner"
  ln -s "$task_root/sentinel" "$target_root/$first_owner"
  if install_owner_plan "$stage_top" "$plan_one" "$target_root" directory false "$journal" "$created" task-c1:symlink 5 openclaw >/dev/null 2>&1; then
    echo 'FAIL: owner symlink was accepted for install'
    return 1
  fi
  OWNER_PLAN_FILES=()
  ENTRY_TOTAL=1
  ENTRY_STATUS=(pending)
  ENTRY_TARGETS=("$target_root")
  ENTRY_KINDS=(directory)
  ENTRY_CREATE_IF_MISSING=(false)
  ENTRY_TOOLS=(openclaw)
  ENTRY_IDS=(task-c1:preflight)
  OWNER_PLAN_FILES[0]="$plan_one"
  local preflight_state preflight_code preflight_idx preflight_rel preflight_reason
  preflight_state="$(mktemp "$task_root/preflight.XXXXXX")" || return 1
  if preflight_owner_targets "$preflight_state"; then
    echo 'FAIL: owner preflight accepted owner symlink'
    return 1
  fi
  IFS=$'\t' read -r preflight_code preflight_idx preflight_rel preflight_reason < "$preflight_state"
  set_preflight_failure "owner-preflight" "$target_root/$preflight_rel" openclaw task-c1:preflight "$preflight_reason" owner-path-validation
  if [[ "$preflight_code" != "E_OWNER_SYMLINK" || "$preflight_idx" != "0" || "$preflight_rel" != "$first_owner" || -z "$RUN_FAILURE_STAGE" || -z "$RUN_FAILURE_REASON" || -z "$RUN_FAILURE_OPERATION" || -z "$RUN_FAILURE_TOOL" || -z "$RUN_FAILURE_ID" || -z "$RUN_FAILURE_TARGET" ]]; then
    echo 'FAIL: owner preflight structured mapping is incomplete'
    return 1
  fi
  echo 'TASK_C1_OWNER_INSTALL_SELFTEST=PASS'
}

if [[ "${SYNC_TASK_C1_SELFTEST:-}" == "1" || "${SYNC_TASK_C1_OWNER_JOURNAL_SELFTEST:-}" == "1" ]]; then
  task_c1_owner_install_selfcheck
  exit $?
fi

task_c2_new_owner_rollback_case() {
  local task_root="$1"
  local journal="$2"
  local new_owner_rel="new-owner"
  local new_target="$task_root/target/$new_owner_rel"
  local new_owner_target_path="$new_target"
  local new_digest new_mode new_size new_restore_rc new_descriptor_state journal_owner_rel

  printf 'new owner\n' > "$new_target"
  new_digest="$(shasum -a 256 "$new_target" | awk '{print $1}')"
  new_mode="$(stat -f '%Lp' "$new_target")"
  new_size="$(stat -f '%z' "$new_target")"
  printf 'owner-journal/v1\t0\t%s\ttask-c2:new\trollback-tool\t%s\tfile\tcreated\t-\tabsent\t-\t-\t-\tfile\t%s\t%s\t%s\n' "$new_owner_target_path" "$new_owner_rel" "$new_mode" "$new_size" "$new_digest" > "$journal"
  journal_owner_rel="$(awk -F '\t' 'NR == 1 { print $6 }' "$journal")"
  ENTRY_STATUS=(pending)
  set +e
  restore_from_journal "$journal"
  new_restore_rc=$?
  set -e
  new_descriptor_state="$(python3 - "$new_owner_target_path" <<'PY'
import os
import stat
import sys

path = sys.argv[1]
parts = [part for part in path.split('/') if part]
fd = os.open('/', os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0))
try:
    for part in parts[:-1]:
        try:
            before = os.stat(part, dir_fd=fd, follow_symlinks=False)
        except FileNotFoundError:
            print('absent-parent')
            raise SystemExit(0)
        if stat.S_ISLNK(before.st_mode):
            print('unsafe-parent-symlink')
            raise SystemExit(0)
        if not stat.S_ISDIR(before.st_mode):
            print('unsafe-parent-special')
            raise SystemExit(0)
        next_fd = os.open(part, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0) | getattr(os, 'O_NOFOLLOW', 0), dir_fd=fd)
        os.close(fd)
        fd = next_fd
    try:
        final = os.stat(parts[-1], dir_fd=fd, follow_symlinks=False)
    except FileNotFoundError:
        print('absent')
    else:
        if stat.S_ISLNK(final.st_mode):
            print('present-symlink')
        elif stat.S_ISREG(final.st_mode) or stat.S_ISDIR(final.st_mode):
            print('present')
        else:
            print('present-special')
finally:
    os.close(fd)
PY
)"
  if [[ "$new_restore_rc" != "0" || "$RUN_ROLLBACK_RESTORED" != "1" || "$new_descriptor_state" != "absent" ]]; then
    printf 'C2_NEW_OWNER_MISMATCH frozen_path=%s journal_owner_rel=%s descriptor_existence=%s restore_rc=%s restored=%s restoreFailures=%s\n' "$new_owner_target_path" "$journal_owner_rel" "$new_descriptor_state" "$new_restore_rc" "$RUN_ROLLBACK_RESTORED" "$ROLLBACK_RESTORE_FAILURES" >&2
    echo 'FAIL: new owner rollback deletion was not verified' >&2
    return 1
  fi
}

task_c2_new_owner_rollback_selfcheck() {
  local raw_task_root task_root journal
  raw_task_root="$(mktemp -d /tmp/agency-owner-rollback-new.XXXXXX)" || return 1
  task_root="$(physical_root "$raw_task_root")" || return 1
  trap "rm -rf -- '$task_root' '$FIXTURE_ROOT'" EXIT
  source "$SYNC_SCRIPT"
  ENTRY_TOTAL=1
  ENTRY_STATUS=(pending)
  journal="$task_root/rollback.tsv"
  : > "$journal"
  mkdir -p "$task_root/target" "$task_root/backup"
  task_c2_new_owner_rollback_case "$task_root" "$journal" || return 1
  echo 'TASK_C2_NEW_OWNER_ROLLBACK_SELFTEST=PASS'
}

if [[ "${SYNC_TASK_C2_NEW_OWNER_SELFTEST:-}" == "1" ]]; then
  task_c2_new_owner_rollback_selfcheck
  exit $?
fi

c2_descriptor_existence() {
  python3 - "$1" <<'PY'
import os
import stat
import sys

path = sys.argv[1]
parts = [part for part in path.split('/') if part]
fd = os.open('/', os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0))
try:
    for part in parts[:-1]:
        try:
            before = os.stat(part, dir_fd=fd, follow_symlinks=False)
        except FileNotFoundError:
            print('absent-parent')
            raise SystemExit(0)
        if stat.S_ISLNK(before.st_mode):
            print('unsafe-parent-symlink')
            raise SystemExit(0)
        if not stat.S_ISDIR(before.st_mode):
            print('unsafe-parent-special')
            raise SystemExit(0)
        next_fd = os.open(part, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0) | getattr(os, 'O_NOFOLLOW', 0), dir_fd=fd)
        os.close(fd)
        fd = next_fd
    try:
        final = os.stat(parts[-1], dir_fd=fd, follow_symlinks=False)
    except FileNotFoundError:
        print('absent')
    else:
        if stat.S_ISLNK(final.st_mode):
            print('present-symlink')
        elif stat.S_ISREG(final.st_mode) or stat.S_ISDIR(final.st_mode):
            print('present')
        else:
            print('present-special')
finally:
    os.close(fd)
PY
}

task_c2_created_parent_cleanup_case() {
  local task_root="$1"
  local created="$2"
  local child_rel="created-parent/child"
  local parent_rel="created-parent"
  local child_path="$task_root/$child_rel"
  local parent_path="$task_root/$parent_rel"
  local cleanup_rc child_state parent_state frozen_journal cleanup_order

  mkdir -p "$child_path"
  printf '%s\t%s\t%s\t%s\n%s\t%s\t%s\t%s\n' 'task-c2:created' 'parent-dir' "$task_root" "$child_rel" 'task-c2:created' 'parent-dir' "$task_root" "$parent_rel" > "$created"
  frozen_journal="$(tr '\n' ',' < "$created" | sed 's/,$//')"
  cleanup_order="$(reverse_journal_lines "$created" | tr '\n' ',' | sed 's/,$//')"
  ROLLBACK_RESTORE_FAILURES='[]'
  set +e
  cleanup_created_dirs "$created"
  cleanup_rc=$?
  set -e
  child_state="$(c2_descriptor_existence "$child_path")"
  parent_state="$(c2_descriptor_existence "$parent_path")"
  if [[ "$cleanup_rc" != "0" || ( "$child_state" != "absent" && "$child_state" != "absent-parent" ) || "$parent_state" != "absent" ]]; then
    printf 'C2_CREATED_PARENT_MISMATCH frozen_journal=%s cleanup_order=%s child_rmdir_result=%s parent_rmdir_result=%s cleanup_rc=%s restoreFailures=%s\n' "$frozen_journal" "$cleanup_order" "$child_state" "$parent_state" "$cleanup_rc" "$ROLLBACK_RESTORE_FAILURES" >&2
    echo 'FAIL: created parent cleanup did not complete' >&2
    return 1
  fi
}

task_c2_created_parent_cleanup_selfcheck() {
  local raw_task_root task_root created
  raw_task_root="$(mktemp -d /tmp/agency-owner-rollback-created.XXXXXX)" || return 1
  task_root="$(physical_root "$raw_task_root")" || return 1
  trap "rm -rf -- '$task_root' '$FIXTURE_ROOT'" EXIT
  source "$SYNC_SCRIPT"
  HOME_OVERRIDE="$task_root"
  PROJECT_ROOT="$task_root/project"
  created="$task_root/created.tsv"
  : > "$created"
  task_c2_created_parent_cleanup_case "$task_root" "$created" || return 1
  echo 'TASK_C2_CREATED_PARENT_CLEANUP_SELFTEST=PASS'
}

if [[ "${SYNC_TASK_C2_CREATED_PARENT_SELFTEST:-}" == "1" ]]; then
  task_c2_created_parent_cleanup_selfcheck
  exit $?
fi

task_c2_created_dir_cleanup_failure_selfcheck() {
  local raw_task_root task_root created stuck_rel='stuck-parent' cleanup_rc failure_summary
  raw_task_root="$(mktemp -d /tmp/agency-owner-rollback-stuck.XXXXXX)" || return 1
  task_root="$(physical_root "$raw_task_root")" || return 1
  trap "rm -rf -- '$task_root' '$FIXTURE_ROOT'" EXIT
  source "$SYNC_SCRIPT"
  HOME_OVERRIDE="$task_root"
  PROJECT_ROOT="$task_root/project"
  created="$task_root/created.tsv"
  mkdir -p "$task_root/$stuck_rel/child"
  printf '%s\t%s\t%s\t%s\n' 'task-c2:stuck' 'parent-dir' "$task_root" "$stuck_rel" > "$created"
  ROLLBACK_RESTORE_FAILURES='[]'
  RUN_ROLLBACK_RESTORED=0
  set +e
  cleanup_created_dirs "$created"
  cleanup_rc=$?
  set -e
  failure_summary="$(python3 - "$ROLLBACK_RESTORE_FAILURES" "$task_root" "$stuck_rel" "$cleanup_rc" "$RUN_ROLLBACK_RESTORED" <<'PY'
import json
import sys

failures = json.loads(sys.argv[1])
root, relative, cleanup_rc, restored = sys.argv[2:]
expected = {
    "index": "-1",
    "target": root + "/" + relative,
    "code": "E_CREATED_DIR_NOT_EMPTY",
    "operation": "created-dir-cleanup",
    "relative": relative,
    "message": "created directory is not empty",
}
if cleanup_rc != "1" or restored != "0" or failures != [expected]:
    print(json.dumps({
        "expected": {**expected, "cleanup_rc": "1", "restored": "0"},
        "actual": {
            "cleanup_rc": cleanup_rc,
            "restored": restored,
            "restoreFailures": [{k: value for k, value in item.items() if k != "target"} for item in failures],
        },
    }, separators=(",", ":"), sort_keys=True))
    raise SystemExit(1)
print(json.dumps({
    "code": expected["code"],
    "operation": expected["operation"],
    "relative": expected["relative"],
    "restoreFailuresIncrement": 1,
    "restored": 0,
}, separators=(",", ":"), sort_keys=True))
PY
)" || {
    printf 'C2_CREATED_DIR_FAILURE_MISMATCH %s\n' "$failure_summary" >&2
    echo 'FAIL: created directory cleanup failure was not structurally recorded' >&2
    return 1
  }
  printf 'C2_CREATED_DIR_FAILURE=%s\n' "$failure_summary" >&2
  echo 'TASK_C2_CREATED_DIR_CLEANUP_FAILURE_SELFTEST=PASS'
}

if [[ "${SYNC_TASK_C2_CREATED_DIR_FAILURE_SELFTEST:-}" == "1" ]]; then
  task_c2_created_dir_cleanup_failure_selfcheck
  exit $?
fi

task_c2_rollback_selfcheck() {
  local raw_task_root task_root journal created target existing_target_path backup digest mode size bad_target bad_backup good_digest good_mode good_size stuck existing_restore_rc cleanup_rc
  raw_task_root="$(mktemp -d /tmp/agency-owner-rollback.XXXXXX)" || return 1
  task_root="$(physical_root "$raw_task_root")" || return 1
  trap "rm -rf -- '$task_root' '$FIXTURE_ROOT'" EXIT
  source "$SYNC_SCRIPT"
  HOME_OVERRIDE="$task_root"
  PROJECT_ROOT="$task_root/project"
  ENTRY_TOTAL=1
  ENTRY_STATUS=(pending)
  journal="$task_root/rollback.tsv"
  created="$task_root/created.tsv"
  : > "$journal"
  : > "$created"
  mkdir -p "$task_root/target" "$task_root/backup"

  target="$task_root/target/existing-owner"
  existing_target_path="$target"
  backup="$task_root/backup/existing-owner"
  printf 'restored owner\n' > "$backup"
  chmod 640 "$backup"
  digest="$(shasum -a 256 "$backup" | awk '{print $1}')"
  mode="$(stat -f '%Lp' "$backup")"
  size="$(stat -f '%z' "$backup")"
  printf 'mutated owner\n' > "$target"
  printf 'owner-journal/v1\t0\t%s\ttask-c2:existing\trollback-tool\texisting-owner\tfile\texisting\t%s\tfile\t%s\t%s\t%s\tfile\t%s\t%s\t%s\n' "$target" "$backup" "$mode" "$size" "$digest" "$mode" "$size" "$digest" > "$journal"
  set +e
  restore_from_journal "$journal"
  existing_restore_rc=$?
  set -e
  if [[ "$existing_restore_rc" != "0" || "$RUN_ROLLBACK_RESTORED" != "1" ]] || ! cmp -s "$existing_target_path" <(printf 'restored owner\n'); then
    local actual_exists=false actual_type=absent actual_mode='' actual_size='' actual_digest=''
    if [[ -L "$existing_target_path" ]]; then
      actual_exists=true
      actual_type=symlink
    elif [[ -f "$existing_target_path" ]]; then
      actual_exists=true
      actual_type=file
      actual_mode="$(stat -f '%Lp' "$existing_target_path")"
      actual_size="$(stat -f '%z' "$existing_target_path")"
      actual_digest="$(shasum -a 256 "$existing_target_path" | awk '{print $1}')"
    elif [[ -d "$existing_target_path" ]]; then
      actual_exists=true
      actual_type=directory
      actual_mode="$(stat -f '%Lp' "$existing_target_path")"
      actual_size=0
    fi
    printf 'C2_EXISTING_MISMATCH expected={exists:true,type:file,mode:%s,size:%s,digest:%s} actual={exists:%s,type:%s,mode:%s,size:%s,digest:%s} restore_rc=%s restored=%s restoreFailures=%s\n' "$mode" "$size" "$digest" "$actual_exists" "$actual_type" "$actual_mode" "$actual_size" "$actual_digest" "$existing_restore_rc" "$RUN_ROLLBACK_RESTORED" "$ROLLBACK_RESTORE_FAILURES" >&2
    echo 'FAIL: existing owner rollback was not descriptor-verified'
    return 1
  fi

  task_c2_new_owner_rollback_case "$task_root" "$journal" || return 1

  bad_target="$task_root/target/bad-owner"
  bad_backup="$task_root/backup/bad-owner"
  printf 'expected owner\n' > "$task_root/expected-owner"
  good_digest="$(shasum -a 256 "$task_root/expected-owner" | awk '{print $1}')"
  good_mode="$(stat -f '%Lp' "$task_root/expected-owner")"
  good_size="$(stat -f '%z' "$task_root/expected-owner")"
  printf 'wrong owner\n' > "$bad_backup"
  printf 'mutated owner\n' > "$bad_target"
  printf 'owner-journal/v1\t0\t%s\ttask-c2:verify\trollback-tool\tbad-owner\tfile\texisting\t%s\tfile\t%s\t%s\t%s\tfile\t%s\t%s\t%s\n' "$bad_target" "$bad_backup" "$good_mode" "$good_size" "$good_digest" "$good_mode" "$good_size" "$good_digest" > "$journal"
  ENTRY_STATUS=(pending)
  if restore_from_journal "$journal" || [[ "$RUN_ROLLBACK_RESTORED" != "0" ]] || [[ "$ROLLBACK_RESTORE_FAILURES" != *"digest/mode/size mismatch"* ]]; then
    echo 'FAIL: rollback verification failure was misreported as restored'
    return 1
  fi

  task_c2_created_parent_cleanup_case "$task_root" "$created" || return 1

  stuck="$task_root/stuck-parent"
  mkdir -p "$stuck/child"
  printf '%s\t%s\t%s\t%s\n' 'task-c2:stuck' 'parent-dir' "$task_root" 'stuck-parent' > "$created"
  ROLLBACK_RESTORE_FAILURES='[]'
  RUN_ROLLBACK_RESTORED=0
  set +e
  cleanup_created_dirs "$created"
  cleanup_rc=$?
  set -e
  if ! python3 - "$ROLLBACK_RESTORE_FAILURES" "$task_root" 'stuck-parent' "$cleanup_rc" "$RUN_ROLLBACK_RESTORED" <<'PY'
import json
import sys

failures = json.loads(sys.argv[1])
root, relative, cleanup_rc, restored = sys.argv[2:]
expected = [{
    "index": "-1",
    "target": root + "/" + relative,
    "code": "E_CREATED_DIR_NOT_EMPTY",
    "operation": "created-dir-cleanup",
    "relative": relative,
    "message": "created directory is not empty",
}]
raise SystemExit(0 if cleanup_rc == "1" and restored == "0" and failures == expected else 1)
PY
  then
    echo 'FAIL: created directory cleanup failure was not structurally recorded'
    return 1
  fi
  echo 'TASK_C2_ROLLBACK_SELFTEST=PASS'
}

task_c2_existing_owner_selfcheck() {
  local raw_task_root task_root journal target backup digest mode size restore_rc
  raw_task_root="$(mktemp -d /tmp/agency-owner-rollback-existing.XXXXXX)" || return 1
  task_root="$(physical_root "$raw_task_root")" || return 1
  trap "rm -rf -- '$task_root' '$FIXTURE_ROOT'" EXIT
  source "$SYNC_SCRIPT"
  ENTRY_TOTAL=1
  ENTRY_STATUS=(pending)
  journal="$task_root/rollback.tsv"
  mkdir -p "$task_root/target" "$task_root/backup"
  target="$task_root/target/existing-owner"
  backup="$task_root/backup/existing-owner"
  printf 'restored owner\n' > "$backup"
  chmod 640 "$backup"
  digest="$(shasum -a 256 "$backup" | awk '{print $1}')"
  mode="$(stat -f '%Lp' "$backup")"
  size="$(stat -f '%z' "$backup")"
  printf 'mutated owner\n' > "$target"
  printf 'owner-journal/v1\t0\t%s\ttask-c2:existing\trollback-tool\texisting-owner\tfile\texisting\t%s\tfile\t%s\t%s\t%s\tfile\t%s\t%s\t%s\n' "$target" "$backup" "$mode" "$size" "$digest" "$mode" "$size" "$digest" > "$journal"
  set +e
  restore_from_journal "$journal"
  restore_rc=$?
  set -e
  if [[ "$restore_rc" != "0" || "$RUN_ROLLBACK_RESTORED" != "1" ]]; then
    python3 - "$target" "$digest" "$mode" "$size" "$ROLLBACK_RESTORE_FAILURES" >&2 <<'PY'
import hashlib
import json
import os
import stat
import sys

target, expected_digest, expected_mode, expected_size, failures = sys.argv[1:]
actual = {"exists": False, "type": "absent", "mode": None, "size": None, "digest": None}
try:
    st = os.lstat(target)
    actual["exists"] = True
    if stat.S_ISLNK(st.st_mode):
        actual["type"] = "symlink"
    elif stat.S_ISREG(st.st_mode):
        actual["type"] = "file"
        actual["mode"] = format(stat.S_IMODE(st.st_mode), "o")
        actual["size"] = st.st_size
        with open(target, "rb") as fp:
            actual["digest"] = hashlib.sha256(fp.read()).hexdigest()
    elif stat.S_ISDIR(st.st_mode):
        actual["type"] = "directory"
        actual["mode"] = format(stat.S_IMODE(st.st_mode), "o")
        actual["size"] = 0
    else:
        actual["type"] = "special"
except FileNotFoundError:
    pass
print(json.dumps({
    "C2_EXISTING_MISMATCH": {
        "expected": {"exists": True, "type": "file", "mode": expected_mode, "size": int(expected_size), "digest": expected_digest},
        "actual": actual,
        "restored": os.environ.get("RUN_ROLLBACK_RESTORED", "unknown"),
        "restoreFailures": json.loads(failures),
    }}, separators=(",", ":"), sort_keys=True))
PY
    echo 'FAIL: existing owner rollback was not descriptor-verified'
    return 1
  fi
  echo 'TASK_C2_EXISTING_OWNER_SELFTEST=PASS'
}

if [[ "${SYNC_TASK_C2_EXISTING_SELFTEST:-}" == "1" ]]; then
  task_c2_existing_owner_selfcheck
  exit $?
fi

if [[ "${SYNC_TASK_C2_SELFTEST:-}" == "1" ]]; then
  task_c2_rollback_selfcheck
  exit $?
fi

task_apply_control_flow_selfcheck() {
  local raw_task_root task_root source_copy source_digest plan_file first_owner target_root apply_rc caller_marker
  raw_task_root="$(mktemp -d /tmp/agency-apply-control.XXXXXX)" || return 1
  task_root="$(physical_root "$raw_task_root")" || return 1
  export TMPDIR="$task_root"
  trap "rm -rf -- '$task_root' '$FIXTURE_ROOT'" EXIT
  build_isolated_fixture || return 1
  source_copy="$CANONICAL_SOURCE"
  source "$SYNC_SCRIPT"
  TEST_MODE=true
  TEST_MODE_ROOT="$task_root"
  HOME_OVERRIDE="$task_root"
  PROJECT_ROOT="$task_root"
  load_canonical_role_profile || return 1
  source_digest="$(compute_manifest_source_root_digest "$source_copy")" || return 1
  source_digest="$(jq -r '.digest' <<<"$source_digest")" || return 1
  plan_file="$(mktemp "$task_root/owner-plan.XXXXXX")" || return 1
  build_owner_plan "$source_copy/openclaw" source-top-level openclaw control-flow:openclaw 0 "$source_digest" '[]' "$plan_file" || return 1
  first_owner="$(awk -F $'\t' 'NR == 1 { print $2 }' "$plan_file")"
  [[ -n "$first_owner" ]] || return 1
  target_root="$task_root/target/agents"
  mkdir -p "$target_root" "$task_root/sentinel"
  printf 'control-flow sentinel\n' > "$task_root/sentinel/kept.txt"
  ln -s "$task_root/sentinel" "$target_root/$first_owner"

  ENTRY_TOTAL=1
  ENTRY_STATUS=(pending)
  ENTRY_SOURCES=("$source_copy/openclaw")
  ENTRY_OWNER_MODES=(source-top-level)
  ENTRY_TOOLS=(openclaw)
  ENTRY_IDS=(control-flow:openclaw)
  ENTRY_TARGETS=("$target_root")
  ENTRY_KINDS=(directory)
  ENTRY_CREATE_IF_MISSING=(false)
  ENTRY_TX_IDS=(control-flow:tx-0)
  MANIFEST_SOURCE_ROOT_DIGEST="$source_digest"
  RUN_FAILURE_STAGE=-1
  RUN_FAILURE_TARGET=''
  RUN_FAILURE_TOOL=''
  RUN_FAILURE_ID=''
  RUN_FAILURE_REASON=''
  RUN_FAILURE_OPERATION=''

  set +e
  run_apply_with_rollback
  apply_rc=$?
  caller_marker=after-owner-preflight
  set -e
  if [[ "$apply_rc" == "0" || "$caller_marker" != after-owner-preflight || "$RUN_BACKUP_COUNT" != "0" || "$RUN_FAILURE_STAGE" != owner-preflight || "$RUN_FAILURE_OPERATION" != owner-path-validation || "$RUN_FAILURE_REASON" != *"owner symlink blocked"* || "$RUN_FAILURE_TOOL" != openclaw || "$RUN_FAILURE_ID" != control-flow:openclaw || -z "$RUN_FAILURE_TARGET" ]]; then
    printf 'FAIL: apply control-flow failure mapping rc=%s marker=%s stage=%s reason=%s operation=%s tool=%s id=%s target=%s backup=%s\n' "$apply_rc" "$caller_marker" "$RUN_FAILURE_STAGE" "$RUN_FAILURE_REASON" "$RUN_FAILURE_OPERATION" "$RUN_FAILURE_TOOL" "$RUN_FAILURE_ID" "$RUN_FAILURE_TARGET" "$RUN_BACKUP_COUNT"
    return 1
  fi
  echo 'APPLY_CONTROL_FLOW_SELFTEST=PASS'
}

if [[ "${SYNC_APPLY_CONTROL_FLOW_SELFTEST:-}" == "1" ]]; then
  task_apply_control_flow_selfcheck
  exit $?
fi

source_owner_plan_gate() {
  local task_root plan_file tool label source_dir kind owner_mode source_path source_digest target_path count
  task_root="$(physical_root "$(mktemp -d /tmp/agency-source-owner-plan.XXXXXX)")" || return 1
  trap "rm -rf -- '$task_root'" EXIT
  source "$SYNC_SCRIPT"
  TEST_MODE=false
  if ! load_canonical_role_profile; then
    echo 'FAIL: source owner-plan gate cannot load canonical role profile'
    return 1
  fi
  source_digest="$(compute_manifest_source_root_digest "$SOURCE_ROOT")" || return 1
  source_digest="$(jq -r '.digest' <<<"$source_digest")" || return 1
  while IFS=$'\t' read -r tool label source_dir target_path kind owner_mode; do
    source_path="${SOURCE_ROOT}/${source_dir}"
    if [[ "$kind" == "file" ]]; then
      source_path="${source_path}/$(basename "$target_path")"
    fi
    plan_file="$(mktemp "$task_root/${tool}-${label}.XXXXXX")" || return 1
    if ! build_owner_plan "$source_path" "$owner_mode" "$tool" "$label" 0 "$source_digest" '[]' "$plan_file"; then
      echo "FAIL: source owner-plan BLOCK tool=${tool} id=${label} reason=${OWNER_PLAN_FAILURE_REASON:-unknown}"
      return 1
    fi
    if [[ "$owner_mode" == "source-top-level" ]]; then
      count="$(cut -f3 "$plan_file" | LC_ALL=C sort -u | wc -l | tr -d ' ')"
      if [[ "$count" != "269" ]] || [[ "$(wc -l < "$plan_file" | tr -d ' ')" != "269" ]]; then
        echo "FAIL: source owner-plan canonical contract tool=${tool} id=${label}"
        return 1
      fi
    elif [[ "$(wc -l < "$plan_file" | tr -d ' ')" != "1" ]] || ! awk -F $'\t' 'NR == 1 { exit !($2 == "__whole_file__" && $3 == "__whole_file__" && $4 == "file") }' "$plan_file"; then
      echo "FAIL: source owner-plan whole-file contract tool=${tool} id=${label}"
      return 1
    fi
  done < <(jq -r '.tools[] as $t | ($t.targets // [])[] | [($t.installTool // $t.name // ""),(.label // .targetPath // ""),($t.sourceDir // $t.name // ""),.targetPath,(.kind // "directory"),(.ownerMode // "")] | @tsv' "$MANIFEST_PATH")
  echo 'SOURCE_OWNER_PLAN_GATE=PASS'
}

task_digest_walker_selfcheck() {
  local task_root source_root plan depth_root entries_root bytes_root
  task_root="$(physical_root "$(mktemp -d /tmp/agency-digest-walker.XXXXXX)")" || return 1
  trap "rm -rf -- '$task_root'" EXIT
  source "$SYNC_SCRIPT"
  TEST_MODE=true
  TEST_MODE_ROOT="$task_root"
  TEST_MODE_ROOT_FD=9
  TEST_MODE_ROOT_BOUND_MARKER=v1
  exec 9<"$task_root" || return 1
  load_canonical_role_profile || return 1
  source_root="$task_root/source"
  mkdir "$source_root" || return 1
  plan="$task_root/plan.tsv"

  depth_root="$source_root/depth"
  mkdir "$depth_root" || return 1
  for (( depth=0; depth<65; depth++ )); do
    depth_root="$depth_root/d$depth"
    mkdir "$depth_root" || return 1
  done
  if build_owner_plan "$source_root" source-top-level antigravity digest-depth 0 digest-depth '[]' "$plan"; then
    echo 'FAIL: digest depth limit was not enforced'
    return 1
  fi

  entries_root="$source_root/entries"
  mkdir "$entries_root" || return 1
  for (( depth=0; depth<10001; depth++ )); do
    : > "$entries_root/entry-$depth"
  done
  if build_owner_plan "$entries_root" source-top-level antigravity digest-entries 1 digest-entries '[]' "$plan"; then
    echo 'FAIL: digest entry limit was not enforced'
    return 1
  fi

  bytes_root="$source_root/bytes"
  mkdir "$bytes_root" || return 1
  truncate -s 268435457 "$bytes_root/blob" || return 1
  if build_owner_plan "$bytes_root" source-top-level antigravity digest-bytes 2 digest-bytes '[]' "$plan"; then
    echo 'FAIL: digest byte limit was not enforced'
    return 1
  fi
  echo 'DIGEST_WALKER_SELFTEST=PASS'
}

if [[ "${SYNC_DIGEST_WALKER_SELFTEST:-}" == "1" ]]; then
  task_digest_walker_selfcheck
  exit $?
fi

setup_d1_openclaw_sentinels() {
  local home="$1"
  local scenario="$2"
  python3 - "$home" "$scenario" <<'PY'
import os
import stat
import sys

home, scenario = sys.argv[1:]
if scenario not in ("agents-baseline", "main-symlink", "auth-special", "legacy"):
    raise SystemExit(1)
O_DIRECTORY = getattr(os, "O_DIRECTORY", 0)
O_NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
dir_flags = os.O_RDONLY | O_DIRECTORY | O_NOFOLLOW

def open_dir(parent_fd, name, create=False, require_private=False):
    try:
        before = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        if not create:
            raise
        os.mkdir(name, 0o700, dir_fd=parent_fd)
        before = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    if stat.S_ISLNK(before.st_mode) or not stat.S_ISDIR(before.st_mode):
        raise RuntimeError("fixture directory unsafe")
    if require_private and (before.st_uid != os.getuid() or stat.S_IMODE(before.st_mode) != 0o700):
        raise RuntimeError("fixture directory owner or mode unsafe")
    fd = os.open(name, dir_flags, dir_fd=parent_fd)
    after = os.fstat(fd)
    if (before.st_dev, before.st_ino) != (after.st_dev, after.st_ino):
        os.close(fd)
        raise RuntimeError("fixture directory identity changed")
    return fd

def require_absent_leaf(parent_fd, name):
    try:
        st = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        return
    if stat.S_ISDIR(st.st_mode):
        raise RuntimeError("fixed fixture leaf unexpectedly directory")
    os.unlink(name, dir_fd=parent_fd)

def create_fixed_auth_fifo(agent_dir_fd):
    leaf = "auth-profiles.json"
    cwd_fd = os.open(".", dir_flags)
    try:
        os.fchdir(agent_dir_fd)
        os.mkfifo(leaf, 0o600)
        created = os.lstat(leaf)
        if not stat.S_ISFIFO(created.st_mode):
            raise RuntimeError("fixed auth leaf is not FIFO")
        if created.st_uid != os.getuid() or stat.S_IMODE(created.st_mode) != 0o600:
            raise RuntimeError("fixed auth FIFO owner or mode unsafe")
    finally:
        os.fchdir(cwd_fd)
        os.close(cwd_fd)

root_fd = os.open(home, dir_flags)
fds = [root_fd]
try:
    openclaw_fd = open_dir(root_fd, ".openclaw")
    fds.append(openclaw_fd)
    agents_fd = open_dir(openclaw_fd, "agents", create=True, require_private=True)
    fds.append(agents_fd)
    if scenario == "agents-baseline":
        raise SystemExit(0)
    if scenario in ("main-symlink", "legacy"):
        protected_fd = open_dir(root_fd, ".openclaw-protected-main", create=True)
        fds.append(protected_fd)
        if scenario == "legacy":
            protected_agent_fd = open_dir(protected_fd, "agent", create=True)
            fds.append(protected_agent_fd)
            require_absent_leaf(protected_agent_fd, "auth-profiles.json")
            create_fixed_auth_fifo(protected_agent_fd)
        require_absent_leaf(agents_fd, "main")
        os.symlink(home + "/.openclaw-protected-main", "main", dir_fd=agents_fd)
    else:
        main_fd = open_dir(agents_fd, "main", create=True)
        fds.append(main_fd)
        agent_fd = open_dir(main_fd, "agent", create=True)
        fds.append(agent_fd)
        require_absent_leaf(agent_fd, "auth-profiles.json")
        create_fixed_auth_fifo(agent_fd)
    require_absent_leaf(agents_fd, "custom-owner-sentinel")
    custom_fd = os.open("custom-owner-sentinel", os.O_WRONLY | os.O_CREAT | os.O_EXCL | O_NOFOLLOW, 0o640, dir_fd=agents_fd)
    try:
        os.write(custom_fd, b"custom owner sentinel\n")
        os.fsync(custom_fd)
    finally:
        os.close(custom_fd)
finally:
    for fd in reversed(fds):
        os.close(fd)
PY
}

freeze_d1_manifest_target_roots() {
  local home="$1"
  local project="$2"
  local manifest_path="$3"
  local output="$4"
  local paths
  paths="$(mktemp)" || return 1
  while IFS= read -r template; do
    resolve_manifest_path "$template" "$home" "$project" >>"$paths"
  done < <(jq -r '.tools[].targets[] | select(.createIfMissing == false) | .targetPath' "$manifest_path")
  printf '%s\n' "$home/.openclaw/agents" >>"$paths"
  python3 - "$home" "$paths" "$output" <<'PY'
import json
import os
import stat
import sys

home, paths_file, output = sys.argv[1:]
O_DIRECTORY = getattr(os, "O_DIRECTORY", 0)
O_NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
flags = os.O_RDONLY | O_DIRECTORY | O_NOFOLLOW
root_fd = os.open(home, flags)
state = {}
try:
    for absolute in sorted({line.rstrip("\n") for line in open(paths_file, encoding="utf-8") if line.rstrip("\n")}):
        relative = os.path.relpath(os.path.normpath(absolute), os.path.normpath(home))
        if relative == ".." or relative.startswith("../") or os.path.isabs(relative):
            raise RuntimeError("manifest target root escaped fixture")
        parts = relative.split("/")
        fd = os.dup(root_fd)
        try:
            for part in parts[:-1]:
                st = os.stat(part, dir_fd=fd, follow_symlinks=False)
                if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode):
                    raise RuntimeError("manifest target intermediate unsafe")
                next_fd = os.open(part, flags, dir_fd=fd)
                os.close(fd)
                fd = next_fd
            st = os.stat(parts[-1], dir_fd=fd, follow_symlinks=False)
            kind = "directory" if stat.S_ISDIR(st.st_mode) else "file" if stat.S_ISREG(st.st_mode) else "unsafe"
            if kind == "unsafe" or stat.S_ISLNK(st.st_mode):
                raise RuntimeError("manifest target root unsafe")
            state[relative] = {"inode": st.st_ino, "type": kind, "mode": format(stat.S_IMODE(st.st_mode), "o")}
        finally:
            os.close(fd)
finally:
    os.close(root_fd)
with open(output, "w", encoding="utf-8") as handle:
    json.dump(state, handle, separators=(",", ":"), sort_keys=True)
PY
  local rc=$?
  rm -f "$paths"
  return "$rc"
}

assert_d1_manifest_target_roots_preserved() {
  local before="$1"
  local after="$2"
  local scenario="$3"
  python3 - "$before" "$after" "$scenario" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle: before = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle: after = json.load(handle)
if not before or before != after:
    raise SystemExit(1)
PY
}

case_d1_fixture_preservation() {
  local scenario home manifest before after source_copy manifest_sha target_count
  for scenario in main-symlink auth-special; do
    home="$(fixture_case_home)"
    if [[ ! -d "$home" || -L "$home" || "$(stat -f '%Lp' "$home")" != "700" ]]; then
      echo 'FAIL: D1 fixture root is not an isolated mode-0700 directory' >&2
      return 1
    fi
    source_copy="$(fixture_source_copy "$home")" || {
      echo 'FAIL: D1 fixture source copy failed' >&2
      return 1
    }
    if [[ ! -d "$source_copy" || -L "$source_copy" ]]; then
      echo 'FAIL: D1 fixture source copy is unsafe' >&2
      return 1
    fi
    manifest="$(fixture_manifest_path "$home")"
    if [[ ! -f "$manifest" || -L "$manifest" ]]; then
      echo 'FAIL: D1 isolated manifest is missing or unsafe' >&2
      return 1
    fi
    manifest_sha="$(shasum -a 256 "$manifest" | awk '{print $1}')" || return 1
    target_count="$(jq '[.tools[].targets[]] | length' "$manifest")" || return 1
    if [[ ! "$manifest_sha" =~ ^[0-9a-f]{64}$ || "$target_count" != "18" ]]; then
      echo 'FAIL: D1 isolated manifest digest or target count invalid' >&2
      return 1
    fi
    prepare_installed_manifest_targets "$home" "$home" "$manifest" || return 1
    before="$(mktemp)" || return 1
    after="$(mktemp)" || return 1
    setup_d1_openclaw_sentinels "$home" agents-baseline || return 1
    freeze_d1_manifest_target_roots "$home" "$home" "$manifest" "$before" || return 1
    setup_d1_openclaw_sentinels "$home" "$scenario" || return 1
    freeze_d1_manifest_target_roots "$home" "$home" "$manifest" "$after" || return 1
    assert_d1_manifest_target_roots_preserved "$before" "$after" "$scenario" || return 1
    rm -rf "$home" "$before" "$after"
  done
  echo 'D1_FIXTURE_PRESERVATION=PASS'
}

case_d1_fifo_helper() {
  local root list output
  root="$(mktemp -d /tmp/agency-d1-fifo.XXXXXX)" || return 1
  chmod 700 "$root" || return 1
  mkdir "$root/.openclaw" || return 1
  chmod 700 "$root/.openclaw" || return 1
  setup_d1_openclaw_sentinels "$root" agents-baseline || return 1
  setup_d1_openclaw_sentinels "$root" auth-special || return 1
  list="$(mktemp)" || return 1
  output="$(mktemp)" || return 1
  printf '%s\n' "$root/.openclaw/agents/main/agent/auth-profiles.json" >"$list"
  snapshot_paths_descriptor_no_follow "$root" "$list" "$output" || return 1
  if ! python3 - "$output" "$root/.openclaw/agents/main/agent/auth-profiles.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle).get(sys.argv[2], {})
expected = value.get("exists") is True and value.get("type") == "other" and value.get("mode") == "600" and isinstance(value.get("inode"), int) and isinstance(value.get("digest"), str)
raise SystemExit(0 if expected else 1)
PY
  then
    echo 'FAIL: fixed auth FIFO descriptor verification mismatch' >&2
    return 1
  fi
  rm -rf "$root" "$list" "$output"
  echo 'D1_FIFO_HELPER=PASS'
}

build_d1_probe_list() {
  local home="$1"
  local project="$2"
  local manifest_path="$3"
  local scenario="$4"
  local output="$5"
  local filtered
  filtered="$(mktemp)" || return 1
  collect_probe_paths "$home" "$project" "$output" "$manifest_path"
  python3 - "$output" "$filtered" "$home" "$scenario" <<'PY'
import sys

source, output, home, scenario = sys.argv[1:]
nested_auth = home + "/.openclaw/agents/main/agent/auth-profiles.json"
with open(source, encoding="utf-8") as handle:
    paths = {line.rstrip("\n") for line in handle if line.rstrip("\n")}
if scenario in ("main-symlink", "legacy"):
    paths.discard(nested_auth)
paths.add(home + "/.openclaw/agents/main")
paths.add(home + "/.openclaw/agents/custom-owner-sentinel")
if scenario == "auth-special":
    paths.add(nested_auth)
elif scenario == "legacy":
    paths.add(home + "/.openclaw-protected-main/agent/auth-profiles.json")
with open(output, "w", encoding="utf-8") as handle:
    for path in sorted(paths):
        handle.write(path + "\n")
PY
  mv -f "$filtered" "$output"
}

assert_d1_sentinel_snapshot() {
  local before="$1"
  local after="$2"
  local home="$3"
  local scenario="$4"
  local context="$5"
  python3 - "$before" "$after" "$home" "$scenario" "$context" <<'PY'
import json
import sys

before_path, after_path, home, scenario, context = sys.argv[1:]
with open(before_path, encoding="utf-8") as handle:
    before = json.load(handle)
with open(after_path, encoding="utf-8") as handle:
    after = json.load(handle)
custom = home + "/.openclaw/agents/custom-owner-sentinel"
if scenario == "main-symlink":
    expected = {home + "/.openclaw/agents/main": "symlink", custom: "file"}
elif scenario == "auth-special":
    expected = {
        home + "/.openclaw/agents/main": "directory",
        home + "/.openclaw/agents/main/agent/auth-profiles.json": "other",
        custom: "file",
    }
elif scenario == "legacy":
    expected = {
        home + "/.openclaw/agents/main": "symlink",
        home + "/.openclaw-protected-main/agent/auth-profiles.json": "other",
        custom: "file",
    }
else:
    raise SystemExit(1)
for path, expected_type in expected.items():
    original = before.get(path)
    final = after.get(path)
    if not isinstance(original, dict) or not original.get("exists") or original.get("type") != expected_type:
        raise SystemExit(1)
    if any(key not in original for key in ("inode", "mode", "size", "digest")):
        raise SystemExit(1)
    if final != original:
        raise SystemExit(1)
PY
}

assert_d1_protected_access_audit() {
  local audit_file="$1"
  local context="$2"
  local expected_requested="${3:-false}"
  local expected_rel_enum="${4:-}"
  local audit_json
  if [[ ! -f "$audit_file" || -L "$audit_file" ]]; then
    echo "FAIL: D1 ${context} protected access audit missing or unsafe"
    return 1
  fi
audit_json="$(python3 - "$audit_file" "$expected_requested" "$expected_rel_enum" <<'PY'
import json
import os
import stat
import sys

path = sys.argv[1]
expected_requested = sys.argv[2] == "true"
expected_rel_enum = sys.argv[3]
st = os.lstat(path)
if not stat.S_ISREG(st.st_mode):
    raise SystemExit(1)
with open(path, "r", encoding="utf-8") as fp:
    rows = [json.loads(line) for line in fp if line.strip()]
protected = {"main", "main/agent/auth-profiles.json"}
owner_rows = [row for row in rows if row.get("event") == "owner-access"]
handshakes = [row for row in rows if row.get("event") == "d1-injection-handshake"]
hits = [row.get("relative") for row in owner_rows if row.get("relative") in protected or any(str(row.get("relative", "")).startswith(item + "/") for item in protected)]
if len(handshakes) != 1:
    raise SystemExit(1)
handshake = handshakes[0]
expected = {
    "injectionRequested": expected_requested,
    "injectionAuthorized": expected_requested,
    "injectionReachedOwnerPlanBoundary": True,
    "injectionHit": expected_requested,
    "requestedRelAllowlisted": expected_requested,
}
for key, value in expected.items():
    if key not in handshake or type(handshake[key]) is not bool or handshake[key] is not value:
        raise SystemExit(1)
if not isinstance(hits, list) or any(not isinstance(item, str) for item in hits):
    raise SystemExit(1)
summary = {key: handshake[key] for key in expected}
summary["protectedHits"] = hits
print(json.dumps(summary, separators=(",", ":"), sort_keys=True))
if expected_requested:
    expected_hit = {"main": "main", "auth-profile": "main/agent/auth-profiles.json"}.get(expected_rel_enum)
    raise SystemExit(0 if expected_hit and hits == [expected_hit] else 1)
raise SystemExit(1 if hits or not owner_rows else 0)
PY
)" || {
    echo "FAIL: D1 ${context} protected access audit contains protected relative path"
    return 1
  }
  printf 'D1_PROTECTED_ACCESS_AUDIT_%s=%s\n' "$context" "$audit_json" >&2
}

case_d1_owner_access_injection_handshake() {
  local scenario="${1:-main-symlink}"
  local relative_enum="${2:-main}"
  SYNC_D1_PROTECTED_AUDIT=1 SYNC_D1_SENTINEL_SCENARIO="$scenario" SYNC_D1_INJECT_REL_ENUM="$relative_enum" case_apply_success_and_protections
}

case_snapshot_diff_paths_arity() {
  local helper_rc=0
  if snapshot_diff_paths before after; then
    helper_rc=0
  else
    helper_rc=$?
  fi
  if [[ "$helper_rc" != "64" ]]; then
    printf 'FAIL: snapshot_diff_paths arity rc expected=64 actual=%s\n' "$helper_rc" >&2
    return 1
  fi
  echo 'SNAPSHOT_DIFF_PATHS_ARITY_SELFTEST=PASS'
  return 0
}

case_d1_openclaw_protected_owner_preservation() {
  local rc scenario relative_enum
  for scenario in main-symlink auth-special; do
    if [[ "$scenario" == main-symlink ]]; then relative_enum=main; else relative_enum=auth-profile; fi
    case_d1_owner_access_injection_handshake "$scenario" "$relative_enum"
    rc=$?
    [[ "$rc" -eq 0 ]] || return "$rc"
    SYNC_D1_PROTECTED_AUDIT=1 SYNC_D1_SENTINEL_SCENARIO="$scenario" case_apply_success_and_protections
    rc=$?
    [[ "$rc" -eq 0 ]] || return "$rc"
    SYNC_D1_PROTECTED_AUDIT=1 SYNC_D1_SENTINEL_SCENARIO="$scenario" case_rollback_on_failure
    rc=$?
    [[ "$rc" -eq 0 ]] || return "$rc"
    printf 'D1_SCENARIO_%s=PASS\n' "$scenario"
  done
  echo 'SYNC_D1_OPENCLAW_PROTECTED_SELFTEST=PASS'
}

assert_single_sync_report_stdout() {
  local stdout_file="$1"
  python3 - "$stdout_file" <<'PY'
import json
import sys

raw = open(sys.argv[1], "rb").read()
try:
    value = json.loads(raw)
except (UnicodeDecodeError, json.JSONDecodeError):
    print("SYNC_STDOUT_DIAGNOSTIC=" + json.dumps({"byteCount": len(raw), "lineCount": len(raw.splitlines())}, separators=(",", ":")), file=sys.stderr)
    raise SystemExit(1)
if not isinstance(value, dict) or value.get("schema") != "agency-agents.local-sync-report/v1":
    print("SYNC_STDOUT_DIAGNOSTIC=" + json.dumps({"byteCount": len(raw), "lineCount": len(raw.splitlines()), "valueType": type(value).__name__}, separators=(",", ":")), file=sys.stderr)
    raise SystemExit(1)
PY
}

print_d2_cli_diagnostic() {
  local stdout_file="$1"
  local rc="$2"
  python3 - "$stdout_file" "$rc" >&2 <<'PY'
import json
import sys

raw = open(sys.argv[1], "rb").read()
summary = {"rc": int(sys.argv[2]), "stdoutJsonValueCount": 0}
try:
    value = json.loads(raw)
    summary["stdoutJsonValueCount"] = 1
except (UnicodeDecodeError, json.JSONDecodeError):
    value = None
if isinstance(value, dict):
    failure = value.get("failure", {})
    for field in ("stage", "reason", "operation"):
        item = failure.get(field)
        summary[field] = item
        summary[field + "Type"] = type(item).__name__
print("D2_CLI_DIAGNOSTIC=" + json.dumps(summary, separators=(",", ":"), sort_keys=True))
PY
}

case_d2_stdout_machine_contract() {
  local home stdout stderr rc ledger evidence
  home="$(fixture_case_home)"
  ledger="$home/d2-ledger"
  evidence="$home/d2-evidence"
  for mode in help unknown; do
    stdout="$(mktemp "$home/d2-${mode}-stdout.XXXXXX")"
    stderr="$(mktemp "$home/d2-${mode}-stderr.XXXXXX")"
    if [[ "$mode" == help ]]; then
      HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --help >"$stdout" 2>"$stderr"
      rc=$?
      [[ "$rc" == 0 ]] || { echo "FAIL: D2 help rc=$rc"; rm -rf "$home"; return 1; }
      print_d2_cli_diagnostic "$stdout" "$rc"
      [[ "$(python3 - "$stdout" <<'PY'
import json, sys
r=json.load(open(sys.argv[1], encoding="utf-8"))
f=r.get("failure", {})
print("1" if r.get("result", {}).get("status") == "passed" and f.get("stage") == "cli-help" and f.get("reason") == "help-requested" and f.get("operation") == "argument-validation" and all(isinstance(f.get(key), str) for key in ("stage", "reason", "operation")) else "0")
PY
)" == 1 ]] || { echo 'FAIL: D2 help report semantics changed'; rm -rf "$home"; return 1; }
    else
      if HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --not-a-governed-option >"$stdout" 2>"$stderr"; then rc=0; else rc=$?; fi
      [[ "$rc" != 0 ]] || { echo 'FAIL: D2 unknown option unexpectedly succeeded'; rm -rf "$home"; return 1; }
      print_d2_cli_diagnostic "$stdout" "$rc"
      [[ "$(python3 - "$stdout" <<'PY'
import json, sys
r=json.load(open(sys.argv[1], encoding="utf-8"))
f=r.get("failure", {})
print("1" if r.get("result", {}).get("status") == "failed" and f.get("stage") == "cli-argument-validation" and f.get("reason") == "unknown-option" and f.get("operation") == "argument-validation" and all(isinstance(f.get(key), str) for key in ("stage", "reason", "operation")) else "0")
PY
)" == 1 ]] || { echo 'FAIL: D2 unknown-option report semantics changed'; rm -rf "$home"; return 1; }
    fi
    if ! assert_single_sync_report_stdout "$stdout"; then
      echo "FAIL: D2 ${mode} stdout is not exactly one fixed sync report"
      rm -rf "$home"
      return 1
    fi
  done
  [[ ! -e "$ledger" && ! -e "$evidence" ]] || { echo 'FAIL: D2 help/unknown created ledger or runtime evidence'; rm -rf "$home"; return 1; }
  rm -rf "$home"
  echo 'SYNC_D2_STDOUT_SELFTEST=PASS'
}

prepare_test_root_descriptor_fixture() {
  local root="$1"
  local source_root manifest_path
  mkdir -p "$root" || return 1
  chmod 700 "$root" || return 1
  source_root="$(fixture_source_copy "$root")" || return 1
  manifest_path="$(fixture_manifest_path "$root")" || return 1
  prepare_installed_manifest_targets "$root" "$root" "$manifest_path" || return 1
  printf '%s\n%s\n' "$source_root" "$manifest_path"
}

run_test_root_descriptor_probe() {
  local root="$1"
  local source_root="$2"
  local manifest_path="$3"
  local stdout_file="$4"
  local stderr_file="$5"
  local race_stage="${6:-}"
  local launcher_race_stage=""
  local action=""
  local signature=""
  local allowed_signers=""
  local ledger=""
  case "$race_stage" in
    before-bind|after-bind) launcher_race_stage="$race_stage" ;;
  esac
  TEST_ROOT_PROBE_RC=0
  if [[ "$race_stage" == before-bind || "$race_stage" == after-bind ]]; then
    if AGENCY_TEST_ROOT_RACE_AUTH=isolated-test AGENCY_TEST_ROOT_RACE_STAGE="$launcher_race_stage" HOME="$root" PROJECT="$root" "$SYNC_SCRIPT" --dry-run --home "$root" --test-mode --test-mode-root "$root" --manifest "$manifest_path" --source-root "$source_root" --project "$root" >"$stdout_file" 2>"$stderr_file"; then
      TEST_ROOT_PROBE_RC=0
    else
      TEST_ROOT_PROBE_RC=$?
    fi
  elif [[ "$race_stage" == before-owner-plan || "$race_stage" == before-aider-owner-plan || "$race_stage" == before-windsurf-owner-plan ]]; then
    IFS=' ' read -r action signature allowed_signers < <(build_auth_bundle "$root/bundle" aicc-supervisor-authorization supervisor-approver "$root/action.json" "$manifest_path" "$root/.codex/supervisor-authority/allowed_signers" "isolated-test" "$root" "$root")
    ledger="$root/.codex/supervisor-authority/owner-only-ledger.jsonl"
    if AGENCY_TEST_ROOT_BOUND_REPLACE_STAGE="$race_stage" HOME="$root" PROJECT="$root" "$SYNC_SCRIPT" --apply --home "$root" --test-mode --test-mode-root "$root" --manifest "$manifest_path" --source-root "$source_root" --project "$root" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$ledger" >"$stdout_file" 2>"$stderr_file"; then
      TEST_ROOT_PROBE_RC=0
    else
      TEST_ROOT_PROBE_RC=$?
    fi
  elif [[ -n "$race_stage" ]]; then
    if AGENCY_TEST_ROOT_BOUND_REPLACE_STAGE="$race_stage" HOME="$root" PROJECT="$root" "$SYNC_SCRIPT" --dry-run --home "$root" --test-mode --test-mode-root "$root" --manifest "$manifest_path" --source-root "$source_root" --project "$root" >"$stdout_file" 2>"$stderr_file"; then
      TEST_ROOT_PROBE_RC=0
    else
      TEST_ROOT_PROBE_RC=$?
    fi
  else
    if HOME="$root" PROJECT="$root" "$SYNC_SCRIPT" --dry-run --home "$root" --test-mode --test-mode-root "$root" --manifest "$manifest_path" --source-root "$source_root" --project "$root" >"$stdout_file" 2>"$stderr_file"; then
      TEST_ROOT_PROBE_RC=0
    else
      TEST_ROOT_PROBE_RC=$?
    fi
  fi
}

assert_test_root_descriptor_report() {
  local report_file="$1"
  local expected_status="$2"
  local expected_rc_kind="$3"
  assert_raw_sync_report_json "$report_file" || return 1
  python3 - "$report_file" "$expected_status" "$expected_rc_kind" "$TEST_ROOT_PROBE_RC" <<'PY'
import json
import sys

report_path, expected_status, expected_rc_kind, actual_rc = sys.argv[1:]
with open(report_path, encoding="utf-8") as fp:
    raw_report = fp.read()
try:
    report = json.loads(raw_report)
except json.JSONDecodeError:
    print("TEST_ROOT_REPORT_DIAGNOSTIC=" + json.dumps({"lineCount": len(raw_report.splitlines()), "byteCount": len(raw_report.encode("utf-8"))}, separators=(",", ":")), file=sys.stderr)
    raise
failure = report.get("failure") or {}
result = report.get("result") or {}
if report.get("schema") != "agency-agents.local-sync-report/v1":
    raise SystemExit(1)
if result.get("status") != expected_status:
    raise SystemExit(1)
if expected_rc_kind == "zero":
    if int(actual_rc) != 0:
        raise SystemExit(1)
else:
    if int(actual_rc) == 0:
        raise SystemExit(1)
    if not failure.get("stage") or not failure.get("reason") or not failure.get("operation"):
        raise SystemExit(1)
PY
}

test_root_sentinel_metadata() {
  python3 - "$1" <<'PY'
import hashlib
import json
import os
import stat
import sys

path = sys.argv[1]
st = os.lstat(path)
if not stat.S_ISREG(st.st_mode):
    raise SystemExit(1)
with open(path, "rb") as fp:
    digest = hashlib.sha256(fp.read()).hexdigest()
print(json.dumps({
    "inode": st.st_ino,
    "type": "file",
    "mode": format(stat.S_IMODE(st.st_mode), "o"),
    "size": st.st_size,
    "mtimeNs": st.st_mtime_ns,
    "digest": digest,
}, separators=(",", ":"), sort_keys=True))
PY
}

case_test_root_descriptor_binding() {
  local scenario_root valid_root fixture_pair source_root manifest_path stdout_file stderr_file
  local final_parent final_real final_link final_pair final_source final_manifest
  local parent_real parent_link parent_child parent_pair parent_source parent_manifest
  local special_root wrong_mode_root wrong_pair wrong_source wrong_manifest
  local race_parent race_root replacement_root race_pair race_source race_manifest race_stage
  local sentinel_before sentinel_after sentinel_after_path failures=0 subcases=0

  scenario_root="$(fixture_case_home)"
  chmod 700 "$scenario_root" || return 1

  valid_root="$scenario_root/valid-root"
  fixture_pair="$(prepare_test_root_descriptor_fixture "$valid_root")" || return 1
  source_root="${fixture_pair%%$'\n'*}"
  manifest_path="${fixture_pair#*$'\n'}"
  stdout_file="$scenario_root/valid.stdout"
  stderr_file="$scenario_root/valid.stderr"
  run_test_root_descriptor_probe "$valid_root" "$source_root" "$manifest_path" "$stdout_file" "$stderr_file"
  subcases=$((subcases + 1))
  assert_test_root_descriptor_report "$stdout_file" passed zero || failures=$((failures + 1))

  final_parent="$scenario_root/final-symlink-parent"
  final_real="$final_parent/real-root"
  mkdir -p "$final_parent"
  chmod 700 "$final_parent"
  final_pair="$(prepare_test_root_descriptor_fixture "$final_real")" || return 1
  final_source="${final_pair%%$'\n'*}"
  final_manifest="${final_pair#*$'\n'}"
  final_link="$final_parent/root-link"
  ln -s "$final_real" "$final_link"
  run_test_root_descriptor_probe "$final_link" "${final_source/#$final_real/$final_link}" "${final_manifest/#$final_real/$final_link}" "$scenario_root/final-symlink.stdout" "$scenario_root/final-symlink.stderr"
  subcases=$((subcases + 1))
  assert_test_root_descriptor_report "$scenario_root/final-symlink.stdout" failed nonzero || failures=$((failures + 1))

  parent_real="$scenario_root/parent-symlink-real"
  parent_child="$parent_real/child-root"
  mkdir -p "$parent_real"
  chmod 700 "$parent_real"
  parent_pair="$(prepare_test_root_descriptor_fixture "$parent_child")" || return 1
  parent_source="${parent_pair%%$'\n'*}"
  parent_manifest="${parent_pair#*$'\n'}"
  parent_link="$scenario_root/parent-link"
  ln -s "$parent_real" "$parent_link"
  run_test_root_descriptor_probe "$parent_link/child-root" "${parent_source/#$parent_real/$parent_link}" "${parent_manifest/#$parent_real/$parent_link}" "$scenario_root/parent-symlink.stdout" "$scenario_root/parent-symlink.stderr"
  subcases=$((subcases + 1))
  assert_test_root_descriptor_report "$scenario_root/parent-symlink.stdout" failed nonzero || failures=$((failures + 1))

  special_root="$scenario_root/special-root"
  mkfifo "$special_root"
  run_test_root_descriptor_probe "$special_root" "$source_root" "$manifest_path" "$scenario_root/special.stdout" "$scenario_root/special.stderr"
  subcases=$((subcases + 1))
  assert_test_root_descriptor_report "$scenario_root/special.stdout" failed nonzero || failures=$((failures + 1))

  wrong_mode_root="$scenario_root/wrong-mode-root"
  wrong_pair="$(prepare_test_root_descriptor_fixture "$wrong_mode_root")" || return 1
  wrong_source="${wrong_pair%%$'\n'*}"
  wrong_manifest="${wrong_pair#*$'\n'}"
  chmod 755 "$wrong_mode_root"
  run_test_root_descriptor_probe "$wrong_mode_root" "$wrong_source" "$wrong_manifest" "$scenario_root/wrong-mode.stdout" "$scenario_root/wrong-mode.stderr"
  subcases=$((subcases + 1))
  assert_test_root_descriptor_report "$scenario_root/wrong-mode.stdout" failed nonzero || failures=$((failures + 1))
  printf '%s\n' 'TEST_ROOT_WRONG_OWNER=SKIP current UID cannot safely construct a foreign-owned root'

  for race_stage in before-bind after-bind; do
    race_parent="$scenario_root/race-$race_stage"
    race_root="$race_parent/bound-root"
    replacement_root="$race_parent/.agency-test-root-replacement"
    mkdir -p "$race_parent" "$replacement_root"
    chmod 700 "$race_parent" "$replacement_root"
    race_pair="$(prepare_test_root_descriptor_fixture "$race_root")" || return 1
    race_source="${race_pair%%$'\n'*}"
    race_manifest="${race_pair#*$'\n'}"
    printf '%s\n' 'replacement sentinel' > "$replacement_root/sentinel.bin"
    chmod 600 "$replacement_root/sentinel.bin"
    sentinel_before="$(test_root_sentinel_metadata "$replacement_root/sentinel.bin")" || return 1
    run_test_root_descriptor_probe "$race_root" "$race_source" "$race_manifest" "$scenario_root/race-$race_stage.stdout" "$scenario_root/race-$race_stage.stderr" "$race_stage"
    subcases=$((subcases + 1))
    assert_test_root_descriptor_report "$scenario_root/race-$race_stage.stdout" failed nonzero || failures=$((failures + 1))
    if [[ -f "$replacement_root/sentinel.bin" ]]; then
      sentinel_after_path="$replacement_root/sentinel.bin"
    else
      sentinel_after_path="$race_root/sentinel.bin"
    fi
    sentinel_after="$(test_root_sentinel_metadata "$sentinel_after_path")" || return 1
    [[ "$sentinel_before" == "$sentinel_after" ]] || failures=$((failures + 1))
  done

  subcases=$((subcases + 1))
  if grep -F 'exec 9<"$TEST_MODE_ROOT"' "$SYNC_SCRIPT" >/dev/null; then
    failures=$((failures + 1))
  fi

  printf 'TEST_ROOT_DESCRIPTOR_SUBCASES=%s FAILURES=%s\n' "$subcases" "$failures"
  [[ "$failures" -eq 0 ]]
}

case_directory_role_metadata_race() {
  local scenario_root race_parent race_root replacement_root pair source_root manifest_path stdout_file stderr_file
  local action signature allowed_signers ledger report sentinel_before sentinel_after sibling_trap sibling_before sibling_after rc
  scenario_root="$(fixture_case_home)" || return 1
  race_parent="$scenario_root/directory-metadata-race"
  race_root="$race_parent/bound-root"
  replacement_root="$race_parent/.agency-test-root-replacement"
  sibling_trap="$race_parent/sibling-trap"
  mkdir -p "$race_parent" "$replacement_root" || return 1
  chmod 700 "$race_parent" "$replacement_root" || return 1
  pair="$(prepare_test_root_descriptor_fixture "$race_root")" || return 1
  ensure_fixture_codex_root "$race_root" || return 1
  source_root="${pair%%$'\n'*}"
  manifest_path="${pair#*$'\n'}"
  mkdir -p "$replacement_root/repo/local-deployment" || return 1
  cp "$manifest_path" "$replacement_root/repo/local-deployment/frozen-action-manifest.json" || return 1
  chmod 600 "$replacement_root/repo/local-deployment/frozen-action-manifest.json" || return 1
  printf 'directory metadata replacement sentinel\n' >"$replacement_root/sentinel.bin" || return 1
  chmod 600 "$replacement_root/sentinel.bin" || return 1
  printf 'directory metadata sibling trap\n' >"$sibling_trap" || return 1
  chmod 600 "$sibling_trap" || return 1
  sentinel_before="$(test_root_sentinel_metadata "$replacement_root/sentinel.bin")" || return 1
  sibling_before="$(test_root_sentinel_metadata "$sibling_trap")" || return 1
  stdout_file="$scenario_root/directory-metadata.stdout"
  stderr_file="$scenario_root/directory-metadata.stderr"
  report="$race_root/.codex/supervisor-runtime-evidence/directory-metadata-report.json"
  ledger="$race_root/.codex/supervisor-authority/owner-only-ledger.jsonl"
  IFS=' ' read -r action signature allowed_signers < <(build_auth_bundle "$race_root/bundle" aicc-supervisor-authorization supervisor-approver "$race_root/action.json" "$manifest_path" "$race_root/.codex/supervisor-authority/allowed_signers" "isolated-test" "$race_root" "$race_root") || return 1
  if AGENCY_TEST_ROOT_BOUND_REPLACE_STAGE=before-directory-role-metadata HOME="$race_root" PROJECT="$race_root" "$SYNC_SCRIPT" --home "$race_root" --project "$race_root" --test-mode --test-mode-root "$race_root" --apply --manifest "$manifest_path" --source-root "$source_root" --json-report "$report" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$ledger" >"$stdout_file" 2>"$stderr_file"; then
    rc=0
  else
    rc=$?
  fi
  assert_raw_sync_report_json "$stdout_file" || return 1
  [[ "$rc" != 0 ]] || return 1
  [[ "$(json_get "$stdout_file" result.status)" == failed ]] || return 1
  [[ "$(json_get "$stdout_file" failure.stage)" == manifest-validation ]] || return 1
  [[ "$(json_get "$stdout_file" failure.operation)" == manifest-validation ]] || return 1
  [[ "$(json_get "$stdout_file" failure.reason)" == "directory source validation failed" ]] || return 1
  if [[ -f "$replacement_root/sentinel.bin" ]]; then
    sentinel_after="$(test_root_sentinel_metadata "$replacement_root/sentinel.bin")" || return 1
  else
    sentinel_after="$(test_root_sentinel_metadata "$race_root/sentinel.bin")" || return 1
  fi
  if [[ -f "$sibling_trap" ]]; then
    sibling_after="$(test_root_sentinel_metadata "$sibling_trap")" || return 1
  else
    return 1
  fi
  [[ "$sentinel_before" == "$sentinel_after" ]] || return 1
  [[ "$sibling_before" == "$sibling_after" ]] || return 1
  [[ ! -e "$ledger" ]] || return 1
  rm -rf "$scenario_root"
  printf 'DIRECTORY_ROLE_METADATA_RACE=PASS\n'
}

case_test_root_descriptor_race() {
  local race_stage="$1"
  local scenario_root race_parent race_root replacement_root race_pair race_source race_manifest
  local stdout_file stderr_file sentinel_before sentinel_after sentinel_after_path
  scenario_root="$(fixture_case_home)"
  chmod 700 "$scenario_root" || return 1
  race_parent="$scenario_root/race-$race_stage"
  race_root="$race_parent/bound-root"
  replacement_root="$race_parent/.agency-test-root-replacement"
  mkdir -p "$race_parent" "$replacement_root" || return 1
  chmod 700 "$race_parent" "$replacement_root" || return 1
  race_pair="$(prepare_test_root_descriptor_fixture "$race_root")" || return 1
  race_source="${race_pair%%$'\n'*}"
  race_manifest="${race_pair#*$'\n'}"
  printf '%s\n' 'replacement sentinel' > "$replacement_root/sentinel.bin"
  chmod 600 "$replacement_root/sentinel.bin"
  sentinel_before="$(test_root_sentinel_metadata "$replacement_root/sentinel.bin")" || return 1
  stdout_file="$scenario_root/race.stdout"
  stderr_file="$scenario_root/race.stderr"
  run_test_root_descriptor_probe "$race_root" "$race_source" "$race_manifest" "$stdout_file" "$stderr_file" "$race_stage"
  if ! assert_test_root_descriptor_report "$stdout_file" failed nonzero; then
    return 1
  fi
  if [[ -f "$replacement_root/sentinel.bin" ]]; then
    sentinel_after_path="$replacement_root/sentinel.bin"
  else
    sentinel_after_path="$race_root/sentinel.bin"
  fi
  sentinel_after="$(test_root_sentinel_metadata "$sentinel_after_path")" || return 1
  [[ "$sentinel_before" == "$sentinel_after" ]] || return 1
  return 0
}

case_role_set_file_sha_negative() {
  local mutation="$1"
  local expected_reason="$2"
  local case_root result_root source_root manifest_path manifest_tmp
  local evidence_root evidence_signers evidence_ledger action signature allowed_signers
  local raw_report clean_report stderr_file before_state after_state audit_path command_rc
  case_root="$(fixture_case_home)"
  result_root="$(mktemp -d "$FIXTURE_ROOT/role-set-file-sha-result.XXXXXX")" || return 1
  chmod 700 "$result_root"
  source_root="$(fixture_source_copy "$case_root")"
  manifest_path="$(fixture_manifest_path "$case_root")"
  prepare_installed_manifest_targets "$case_root" "$case_root" "$manifest_path"
  manifest_tmp="$(mktemp "$case_root/manifest-role-set-sha.XXXXXX")" || return 1
  case "$mutation" in
    missing) jq 'del(.roleSetFileSha256)' "$manifest_path" >"$manifest_tmp" ;;
    malformed) jq '.roleSetFileSha256 = "NOT-LOWERCASE-SHA256"' "$manifest_path" >"$manifest_tmp" ;;
    drift) jq '.roleSetFileSha256 = "0000000000000000000000000000000000000000000000000000000000000000"' "$manifest_path" >"$manifest_tmp" ;;
    *) return 1 ;;
  esac
  jq -e . "$manifest_tmp" >/dev/null || return 1
  mv -f "$manifest_tmp" "$manifest_path"

  evidence_root="$case_root/.codex/supervisor-runtime-evidence"
  evidence_signers="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/allowed_signers"
  evidence_ledger="${evidence_root%/supervisor-runtime-evidence}/supervisor-authority/owner-only-ledger.jsonl"
  IFS=' ' read -r action signature allowed_signers < <(build_auth_bundle "$case_root/bundle" aicc-supervisor-authorization supervisor-approver "$case_root/action.json" "$manifest_path" "$evidence_signers" "isolated-test" "$case_root" "$case_root")
  [[ -f "$action" && -f "$signature" && -f "$allowed_signers" ]] || return 1
  chmod 700 "$case_root" "$result_root" "$case_root/bundle" "$case_root/.codex" "$case_root/.codex/supervisor-authority" "$evidence_root"
  for isolated_root in "$case_root" "$result_root" "$case_root/bundle" "$case_root/.codex" "$case_root/.codex/supervisor-authority" "$evidence_root"; do
    [[ -d "$isolated_root" && ! -L "$isolated_root" && "$(stat -f '%Lp' "$isolated_root")" == "700" ]] || return 1
  done

  raw_report="$result_root/raw.json"
  clean_report="$result_root/report.json"
  stderr_file="$result_root/stderr.log"
  before_state="$result_root/before.json"
  after_state="$result_root/after.json"
  audit_path="$case_root/test-audit-output"
  snapshot_dry_run_roots "$before_state" "$case_root" "$evidence_root" "$audit_path"
  if HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" --home "$case_root" --test-mode --test-mode-root "$case_root" --apply --manifest "$manifest_path" --source-root "$source_root" --project "$case_root" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$evidence_ledger" >"$raw_report" 2>"$stderr_file"; then
    command_rc=0
  else
    command_rc=$?
  fi
  snapshot_dry_run_roots "$after_state" "$case_root" "$evidence_root" "$audit_path"
  read_isolated_sync_report "$result_root" "$raw_report" "$clean_report" || return 1
  if [[ "${SYNC_ROLESET_DIAGNOSTIC:-}" == "1" ]]; then
    python3 - "$result_root" "$expected_reason" "$command_rc" "$evidence_ledger" <<'PY' >&2 || return 1
import hashlib
import json
import os
import stat
import sys

root, expected_reason, command_rc, ledger_path = sys.argv[1:]
root_fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0))
try:
    root_stat = os.fstat(root_fd)
    if not stat.S_ISDIR(root_stat.st_mode) or stat.S_IMODE(root_stat.st_mode) != 0o700:
        raise SystemExit("unsafe-diagnostic-root")
    payloads = {}
    metadata = {}
    for leaf in ("raw.json", "report.json", "before.json", "after.json", "stderr.log"):
        fd = os.open(leaf, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0), dir_fd=root_fd)
        try:
            item_stat = os.fstat(fd)
            if not stat.S_ISREG(item_stat.st_mode):
                raise SystemExit("unsafe-diagnostic-leaf")
            chunks = []
            while True:
                block = os.read(fd, 65536)
                if not block:
                    break
                chunks.append(block)
            data = b"".join(chunks)
            payloads[leaf] = data
            metadata[leaf] = {
                "mode": format(stat.S_IMODE(item_stat.st_mode), "o"),
                "size": item_stat.st_size,
                "sha256": hashlib.sha256(data).hexdigest(),
            }
        finally:
            os.close(fd)
finally:
    os.close(root_fd)

raw_text = payloads["raw.json"].decode("utf-8", "replace")
decoder = json.JSONDecoder()
values = []
offset = 0
while offset < len(raw_text):
    while offset < len(raw_text) and raw_text[offset].isspace():
        offset += 1
    if offset >= len(raw_text):
        break
    try:
        value, end = decoder.raw_decode(raw_text, offset)
    except json.JSONDecodeError:
        offset += 1
        continue
    values.append(value)
    offset = end

report = json.loads(payloads["report.json"])
before = json.loads(payloads["before.json"])
after = json.loads(payloads["after.json"])
failure = report.get("failure") or {}
result = report.get("result") or {}
rollback = report.get("rollback") or {}
actual = {
    "rc": int(command_rc),
    "status": result.get("status"),
    "stage": failure.get("stage"),
    "reason": failure.get("reason"),
    "operation": failure.get("operation"),
    "backupCount": result.get("backupCount"),
    "rollback": {
        "performed": rollback.get("performed"),
        "attempted": rollback.get("attempted"),
        "restored": rollback.get("restored"),
        "restoreFailures": rollback.get("restoreFailures"),
    },
}
expected = {
    "rcNonzero": True,
    "status": "failed",
    "stage": "manifest-validation",
    "reason": expected_reason,
    "operation": "manifest-validation",
    "backupCount": 0,
    "rollback": {"performed": False, "attempted": 0, "restored": 0},
}
failure_point = "none"
if report.get("schema") != "agency-agents.local-sync-report/v1":
    failure_point = "report-schema"
elif actual["rc"] == 0:
    failure_point = "production-rc"
elif actual["status"] != expected["status"] or actual["backupCount"] != expected["backupCount"]:
    failure_point = "result-contract"
elif any(actual[key] != expected[key] for key in ("stage", "reason", "operation")):
    failure_point = "failure-contract"
elif any(actual["rollback"].get(key) != expected["rollback"][key] for key in expected["rollback"]):
    failure_point = "rollback-contract"
elif before != after:
    failure_point = "root-state-changed"
elif os.path.lexists(ledger_path):
    failure_point = "ledger-created"

changed_roots = sorted(key for key in set(before) | set(after) if before.get(key) != after.get(key))
print("ROLE_SET_SHA_DIAGNOSTIC=" + json.dumps({
    "actual": actual,
    "expected": expected,
    "failurePoint": failure_point,
    "changedRootCategories": changed_roots,
    "rawJsonValueCount": len(values),
    "rawReportObjectCount": sum(isinstance(value, dict) and value.get("schema") == "agency-agents.local-sync-report/v1" for value in values),
    "files": metadata,
    "stderrLineCount": len(payloads["stderr.log"].splitlines()),
    "stderrSha256": hashlib.sha256(payloads["stderr.log"]).hexdigest(),
    "ledgerExists": os.path.lexists(ledger_path),
    "stateCategories": {
        "keySignature": "case-root",
        "ledger": "case-root",
        "evidence": "case-root",
        "authHelperOutput": "case-process",
        "selector": "case-process",
        "resultLeaf": "case-root",
        "canonicalFixtureSource": "shared-read-only",
    },
}, separators=(",", ":"), sort_keys=True))
PY
  fi
  [[ "$command_rc" != "0" ]] || return 1
  python3 - "$clean_report" "$expected_reason" <<'PY' || return 1
import json
import sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
failure = report.get("failure") or {}
result = report.get("result") or {}
rollback = report.get("rollback") or {}
if report.get("schema") != "agency-agents.local-sync-report/v1":
    raise SystemExit(1)
if result.get("status") != "failed" or result.get("backupCount") != 0:
    raise SystemExit(1)
if failure.get("stage") != "manifest-validation" or failure.get("operation") != "manifest-validation" or failure.get("reason") != sys.argv[2]:
    raise SystemExit(1)
if rollback.get("performed") is not False or rollback.get("attempted") != 0 or rollback.get("restored") != 0:
    raise SystemExit(1)
PY
  diff_dry_run_roots "$before_state" "$after_state" >/dev/null || return 1
  [[ ! -e "$evidence_ledger" ]] || return 1
  rm -rf "$case_root" "$result_root"
  return 0
}

case_cli_missing_option_values() {
  local case_root result_root before_state after_state audit_path evidence_root option stdout_file stderr_file command_rc index
  local -a value_options=(
    --home --project --test-mode-root --manifest --source-root --json-report
    --action-file --auth-bytes --signature-file --auth-signature --principal
    --namespace --allowed-signers --ledger
  )
  case_root="$(fixture_case_home)"
  result_root="$(mktemp -d "$FIXTURE_ROOT/cli-missing-value-result.XXXXXX")" || return 1
  chmod 700 "$result_root"
  before_state="$result_root/before.json"
  after_state="$result_root/after.json"
  audit_path="$case_root/test-audit-output"
  evidence_root="$case_root/.codex/supervisor-runtime-evidence"
  snapshot_dry_run_roots "$before_state" "$case_root" "$evidence_root" "$audit_path"
  index=0
  for option in "${value_options[@]}"; do
    stdout_file="$result_root/stdout-$index.json"
    stderr_file="$result_root/stderr-$index.log"
    if HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" "$option" >"$stdout_file" 2>"$stderr_file"; then
      command_rc=0
    else
      command_rc=$?
    fi
    [[ "$command_rc" != "0" ]] || return 1
    assert_single_sync_report_stdout "$stdout_file" || return 1
    python3 - "$stdout_file" <<'PY' || return 1
import json
import sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
failure = report.get("failure") or {}
if report.get("schema") != "agency-agents.local-sync-report/v1" or (report.get("result") or {}).get("status") != "failed":
    raise SystemExit(1)
expected = {"stage": "cli-argument-validation", "operation": "argument-validation", "reason": "missing-option-value"}
if any(failure.get(key) != value or not isinstance(failure.get(key), str) for key, value in expected.items()):
    raise SystemExit(1)
PY
    index=$((index + 1))
  done
  snapshot_dry_run_roots "$after_state" "$case_root" "$evidence_root" "$audit_path"
  diff_dry_run_roots "$before_state" "$after_state" >/dev/null || return 1
  [[ ! -e "$evidence_root" ]] || return 1
  rm -rf "$case_root" "$result_root"
  printf 'CLI_MISSING_VALUE_CASES=%s\n' "${#value_options[@]}"
  return 0
}

case_production_scope_overrides() {
  local case_root result_root before_state after_state stdout_file stderr_file command_rc
  case_root="$(fixture_case_home)" || return 1
  result_root="$(mktemp -d "$FIXTURE_ROOT/production-scope-result.XXXXXX")" || return 1
  chmod 700 "$result_root"
  before_state="$result_root/before.json"
  after_state="$result_root/after.json"
  snapshot_dry_run_roots "$before_state" "$case_root" "$case_root/runtime-evidence" "$case_root/audit"
  for selector in home project both; do
    stdout_file="$result_root/$selector.stdout"
    stderr_file="$result_root/$selector.stderr"
    if [[ "$selector" == home ]]; then
      if HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" --dry-run --home "$case_root" >"$stdout_file" 2>"$stderr_file"; then command_rc=0; else command_rc=$?; fi
    elif [[ "$selector" == project ]]; then
      if HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" --dry-run --project "$case_root" >"$stdout_file" 2>"$stderr_file"; then command_rc=0; else command_rc=$?; fi
    else
      if HOME="$case_root" PROJECT="$case_root" "$SYNC_SCRIPT" --dry-run --home "$case_root" --project "$case_root" >"$stdout_file" 2>"$stderr_file"; then command_rc=0; else command_rc=$?; fi
    fi
    [[ "$command_rc" != 0 ]] || return 1
    assert_single_sync_report_stdout "$stdout_file" || return 1
    python3 - "$stdout_file" <<'PY' || return 1
import json
import sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
failure = report.get("failure") or {}
if report.get("schema") != "agency-agents.local-sync-report/v1":
    raise SystemExit(1)
if (report.get("result") or {}).get("status") != "failed":
    raise SystemExit(1)
expected = {
    "stage": "execution-context-validation",
    "reason": "production target override blocked",
    "operation": "execution-context-validation",
}
if any(failure.get(key) != value for key, value in expected.items()):
    raise SystemExit(1)
PY
  done
  snapshot_dry_run_roots "$after_state" "$case_root" "$case_root/runtime-evidence" "$case_root/audit"
  diff_dry_run_roots "$before_state" "$after_state" >/dev/null || return 1
  rm -rf "$case_root" "$result_root"
  printf 'PRODUCTION_SCOPE_OVERRIDE_CASES=3\n'
  return 0
}

case_test_root_downstream_race() {
  grep -q 'replace_test_root_at_stage' "$SYNC_SCRIPT" || return 1
  grep -q 'verify_test_root_identity_now' "$SYNC_SCRIPT" || return 1
  case_test_root_descriptor_race after-bind
}

case_descriptor_boundary_contract() {
  if grep -q 'rm -rf' "$SYNC_SCRIPT"; then
    echo 'FAIL: production transaction cleanup still uses rm -rf' >&2
    return 1
  fi
  if grep -q '^[[:space:]]*bind_temp_root()' "$SYNC_SCRIPT" || grep -q 'cd -- "\$raw_root"' "$SYNC_SCRIPT"; then
    echo 'FAIL: dead pathname transaction bind fallback remains' >&2
    return 1
  fi
  grep -q 'write_report_descriptor' "$SYNC_SCRIPT" || return 1
  grep -q 'O_EXCL' "$SYNC_SCRIPT" || return 1
  grep -q 'verify_test_root_identity_now' "$SYNC_SCRIPT" || return 1
  grep -q 'auth_descriptor_snapshot.*TEST_MODE_ROOT_FD' "$SYNC_SCRIPT" || return 1
  if grep -q 'printf.*JSON_REPORT' "$SYNC_SCRIPT"; then
    echo 'FAIL: production report still uses pathname redirection' >&2
    return 1
  fi
  printf 'EVIDENCE_AND_CLEANUP_DESCRIPTOR_CONTRACT=PASS\n'
  return 0
}

read_binder_rc74_reason() {
  local stderr_file="$1"
  python3 - "$stderr_file" <<'PY'
import sys

path = sys.argv[1]
report_values = {
    'report-parent', 'report-parent-race', 'report-leaf', 'report-leaf-type',
    'report-boundary', 'report-components', 'report-fd-collision',
    'report-leaf-existing-or-io',
    'report-close-socket-raw', 'report-close-socket-reserved',
    'report-close-report-parent', 'report-close-report-leaf',
    'report-close-transaction-parent', 'report-close-evidence-parent',
    'report-close-work', 'report-close-backup', 'report-close-entry',
    'report-close-parent-channel', 'report-close-child-channel',
}
binder_values = {
    'rc74-unclassified',
    'close-socket-raw', 'close-socket-reserved',
    'close-report-parent', 'close-report-leaf',
    'close-transaction-parent', 'close-evidence-parent',
    'close-work', 'close-backup', 'close-entry',
    'close-parent-channel', 'close-child-channel',
    'report-report-parent', 'report-report-parent-race',
    'report-report-leaf', 'report-report-leaf-type',
    'report-report-boundary', 'report-report-components',
    'report-report-fd-collision', 'report-leaf-existing-or-io',
    'python-reason-missing-shell-rc74',
    'close-report-parent', 'close-report-leaf',
    'close-transaction-parent', 'close-evidence-parent',
    'report-boundary', 'report-parent-race', 'report-leaf-existing',
    'report-leaf-type', 'report-fd-collision', 'report-components',
    'report-parent', 'raw-rc74-without-python-reason',
}
prefixes = (b'POST_AUTH_REPORT_BIND_FAILURE=', b'POST_AUTH_BINDER_RC74_REASON=')
hits = []
with open(path, 'rb') as stream:
    for raw in stream:
        if any(prefix in raw for prefix in prefixes):
            if not raw.endswith(b'\n') or raw.count(b'\n') != 1:
                print('malformed-line')
                raise SystemExit(0)
            line = raw[:-1].decode('ascii')
            key, value = line.split('=', 1)
            if key == 'POST_AUTH_REPORT_BIND_FAILURE':
                allowed = report_values
            elif key == 'POST_AUTH_BINDER_RC74_REASON':
                allowed = binder_values
            else:
                print('unknown-enum')
                raise SystemExit(0)
            if value not in allowed:
                print('unknown-enum')
                raise SystemExit(0)
            hits.append(value)
if len(hits) == 0:
    print('count-zero')
elif len(hits) > 1:
    print('count-multiple')
elif hits[0] == 'python-reason-missing-shell-rc74':
    print('python-reason-missing-shell-rc74')
else:
    print(hits[0])
PY
}

read_post_auth_stage_last() {
  local stderr_file="$1"
  python3 - "$stderr_file" <<'PY'
import sys

allowed = {
    'binder-enter', 'fd20-ready', 'report-prebind-start', 'report-prebind-ok',
    'fork-ok', 'child-early-enter', 'child-proof-ok', 'child-descriptor-table-ok',
    'child-consume-ack', 'child-origin-ok', 'child-report-adopted', 'writer-enter',
}
hits = []
with open(sys.argv[1], 'rb') as stream:
    for raw in stream:
        if b'POST_AUTH_STAGE=' not in raw:
            continue
        if not raw.startswith(b'POST_AUTH_STAGE=') or not raw.endswith(b'\n') or raw.count(b'\n') != 1:
            print('malformed')
            raise SystemExit(1)
        try:
            value = raw[:-1].split(b'=', 1)[1].decode('ascii')
        except (IndexError, UnicodeDecodeError):
            print('malformed')
            raise SystemExit(1)
        if value not in allowed:
            print('unknown')
            raise SystemExit(1)
        hits.append(value)
print(hits[-1] if hits else 'count-zero')
PY
}

emit_post_auth_stage_last() {
  local stderr_file="$1" stage_last="count-zero"
  stage_last="$(read_post_auth_stage_last "$stderr_file")" || stage_last="count-zero"
  printf 'POST_AUTH_STAGE_LAST=%s\n' "$stage_last" >&2
}

emit_focused_case_diagnostic() {
  local stdout_file="$1" stderr_file="$2" command_rc="$3"
  python3 - "$stdout_file" "$stderr_file" "$command_rc" <<'PY' >&2
import json
import os
import re
import stat
import sys

STAGES = {
    'authorization-validation', 'evidence-validation',
    'execution-context-validation', 'manifest-validation',
    'report-path-validation', 'test-root-validation',
    'transaction-cleanup', 'transaction-origin-validation',
    'transaction-root-validation',
}
OPERATIONS = {
    'authorization-validation', 'evidence-validation',
    'execution-context-validation', 'manifest-validation',
    'report-path-validation', 'test-root-binding',
    'transaction-cleanup', 'transaction-origin',
    'transaction-root-validation',
}
REASONS = {
    'authorization validation failed': 'authorization-validation-failed',
    'evidence report write failed': 'evidence-report-write-failed',
    'post-auth-origin-attestation-failed': 'post-auth-origin-attestation-failed',
    'production target override blocked': 'production-target-override-blocked',
    'report path validation failed': 'report-path-validation-failed',
    'transaction cleanup failed': 'transaction-cleanup-failed',
    'transaction root binding failed': 'transaction-root-binding-failed',
    'trusted descriptor bootstrap failed': 'trusted-descriptor-bootstrap-failed',
}
STAGE_VALUES = {
    'binder-enter', 'fd20-ready', 'report-prebind-start', 'report-prebind-ok',
    'fork-ok', 'child-early-enter', 'child-proof-ok',
    'child-descriptor-table-ok', 'child-consume-ack', 'child-origin-ok',
    'child-report-adopted', 'writer-enter',
}
BINDER_VALUES = {
    'rc74-unclassified',
    'close-socket-raw', 'close-socket-reserved',
    'close-report-parent', 'close-report-leaf',
    'close-transaction-parent', 'close-evidence-parent',
    'close-work', 'close-backup', 'close-entry',
    'close-parent-channel', 'close-child-channel',
    'report-report-parent', 'report-report-parent-race',
    'report-report-leaf', 'report-report-leaf-type',
    'report-report-boundary', 'report-report-components',
    'report-report-fd-collision', 'report-leaf-existing-or-io',
    'python-reason-missing-shell-rc74',
    'report-boundary', 'report-parent-race', 'report-leaf-existing',
    'report-leaf-type', 'report-fd-collision', 'report-components',
    'report-parent', 'raw-rc74-without-python-reason',
    'report-close-socket-raw', 'report-close-socket-reserved',
    'report-close-report-parent', 'report-close-report-leaf',
    'report-close-transaction-parent', 'report-close-evidence-parent',
    'report-close-work', 'report-close-backup', 'report-close-entry',
    'report-close-parent-channel', 'report-close-child-channel',
}
WRITER_VALUES = {
    ('OK', '0'): 'OK-0',
    ('REPORT_PATH_VALIDATION_FAILED', '74'): 'REPORT_PATH_VALIDATION_FAILED-74',
    ('EVIDENCE_WRITE_FAILED', '75'): 'EVIDENCE_WRITE_FAILED-75',
}
def read_regular_nofollow(path):
    flags = os.O_RDONLY
    if hasattr(os, 'O_NOFOLLOW'):
        flags |= os.O_NOFOLLOW
    fd = os.open(path, flags)
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode):
            raise ValueError('not-regular')
        chunks = []
        while True:
            block = os.read(fd, 65536)
            if not block:
                return b''.join(chunks)
            chunks.append(block)
    finally:
        os.close(fd)


def decode_json_stream(raw):
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError:
        return [], True
    decoder = json.JSONDecoder()
    values = []
    offset = 0
    malformed = False
    while True:
        while offset < len(text) and text[offset].isspace():
            offset += 1
        if offset == len(text):
            break
        try:
            value, offset = decoder.raw_decode(text, offset)
        except json.JSONDecodeError:
            malformed = True
            break
        values.append(value)
    return values, malformed


def exact_lines(raw, prefix):
    hits = []
    malformed = False
    for line in raw.splitlines(keepends=True):
        if prefix not in line:
            continue
        if not line.startswith(prefix) or not line.endswith(b'\n') or line.count(b'\n') != 1:
            malformed = True
            continue
        try:
            hits.append(line[:-1].split(b'=', 1)[1].decode('ascii'))
        except (IndexError, UnicodeDecodeError):
            malformed = True
    return hits, malformed


def one_allowlisted(hits, malformed, allowed):
    if malformed or len(hits) > 1:
        return 'invalid'
    if not hits:
        return 'none'
    return hits[0] if hits[0] in allowed else 'invalid'


def writer_result(raw):
    prefix = b'REPORT_WRITER_RESULT='
    hits = []
    malformed = False
    for line in raw.splitlines(keepends=True):
        if prefix not in line:
            continue
        if not line.startswith(prefix) or not line.endswith(b'\n') or line.count(b'\n') != 1:
            malformed = True
            continue
        try:
            body = line[:-1].decode('ascii')
            result_part, rc_part = body.split(' RC=', 1)
            result = result_part.split('=', 1)[1]
            hits.append((result, rc_part))
        except (IndexError, UnicodeDecodeError, ValueError):
            malformed = True
    if malformed or len(hits) > 1:
        return 'invalid'
    if not hits:
        return 'none'
    return WRITER_VALUES.get(hits[0], 'invalid')


def safe_rc(value):
    try:
        parsed = int(value, 10)
    except (TypeError, ValueError):
        return 'invalid'
    return str(parsed) if 0 <= parsed <= 255 else 'invalid'


rc_value = safe_rc(sys.argv[3] if len(sys.argv) > 3 else '')
json_count = 0
status_value = 'none'
stage_value = 'none'
operation_value = 'none'
reason_value = 'none'
post_auth_stage = 'none'
binder_reason = 'none'
writer_value = 'none'
leaf_race = 'none'
writer_python = 'none'
writer_shell = 'none'
try:
    stdout_raw = read_regular_nofollow(sys.argv[1])
    stderr_raw = read_regular_nofollow(sys.argv[2])
    values, malformed_json = decode_json_stream(stdout_raw)
    json_count = len(values)
    if malformed_json:
        status_value = stage_value = operation_value = reason_value = 'invalid'
    elif len(values) == 1 and isinstance(values[0], dict):
        report = values[0]
        result = report.get('result')
        failure = report.get('failure')
        raw_status = result.get('status') if isinstance(result, dict) else None
        raw_stage = failure.get('stage') if isinstance(failure, dict) else None
        raw_operation = failure.get('operation') if isinstance(failure, dict) else None
        raw_reason = failure.get('reason') if isinstance(failure, dict) else None
        status_value = raw_status if raw_status in {'passed', 'failed'} else ('none' if raw_status is None else 'invalid')
        stage_value = raw_stage if raw_stage in STAGES else ('none' if raw_stage is None else 'invalid')
        operation_value = raw_operation if raw_operation in OPERATIONS else ('none' if raw_operation is None else 'invalid')
        reason_value = REASONS.get(raw_reason, 'none' if raw_reason is None else 'invalid')
    elif values:
        status_value = stage_value = operation_value = reason_value = 'invalid'

    stage_hits, stage_malformed = exact_lines(stderr_raw, b'POST_AUTH_STAGE=')
    if stage_malformed or any(value not in STAGE_VALUES for value in stage_hits):
        post_auth_stage = 'invalid'
    elif stage_hits:
        post_auth_stage = stage_hits[-1]
    else:
        post_auth_stage = 'none'

    binder_hits = []
    binder_malformed = False
    for prefix in (b'POST_AUTH_BINDER_RC74_REASON=', b'POST_AUTH_REPORT_BIND_FAILURE='):
        hits, malformed = exact_lines(stderr_raw, prefix)
        binder_hits.extend(hits)
        binder_malformed = binder_malformed or malformed
    binder_reason = one_allowlisted(binder_hits, binder_malformed, BINDER_VALUES)
    writer_value = writer_result(stderr_raw)

    race_hits, race_malformed = exact_lines(stderr_raw, b'REPORT_LEAF_RACE_HIT=')
    if not race_malformed and race_hits and all(value == 'after-report-leaf-prebind' for value in race_hits):
        leaf_race = 'hit'
    python_lines = [line.decode('ascii', 'strict') for line in stderr_raw.splitlines()
                    if line.startswith(b'REPORT_WRITER_PYTHON ')]
    shell_lines = [line.decode('ascii', 'strict') for line in stderr_raw.splitlines()
                   if line.startswith(b'REPORT_WRITER_SHELL ')]
    python_pattern = re.compile(r'^REPORT_WRITER_PYTHON phase=(leaf-mutation|leaf-open|leaf-identity|prebound-write|checked-close) exception=(FileNotFoundError|FileExistsError|OSError|ReportPathValidationError|EvidenceWriteError|UnexpectedError) rc=(74|75)$')
    shell_pattern = re.compile(r'^REPORT_WRITER_SHELL raw_rc=([0-9]+) mapped_rc=(74|75) class=(REPORT_PATH_VALIDATION_FAILED|EVIDENCE_WRITE_FAILED)$')
    if len(python_lines) == 1 and python_pattern.fullmatch(python_lines[0]):
        writer_python = python_lines[0].split(' ', 1)[1].replace(' ', ',')
    elif python_lines:
        writer_python = 'invalid'
    if len(shell_lines) == 1 and shell_pattern.fullmatch(shell_lines[0]):
        writer_shell = shell_lines[0].split(' ', 1)[1].replace(' ', ',')
    elif shell_lines:
        writer_shell = 'invalid'
except Exception:
    json_count = 0
    status_value = stage_value = operation_value = reason_value = 'invalid'
    post_auth_stage = binder_reason = writer_value = 'invalid'
    leaf_race = 'none'
    writer_python = writer_shell = 'invalid'

print(
    'FOCUSED_DIAGNOSTIC '
    f'rc={rc_value} json_count={json_count} status={status_value} '
    f'stage={stage_value} operation={operation_value} reason={reason_value} '
    f'post_auth_stage={post_auth_stage} binder_reason={binder_reason} '
    f'writer_result={writer_value} leaf_race={leaf_race} '
    f'writer_python={writer_python} writer_shell={writer_shell}'
)
PY
}

case_custom_report_descriptor_security() {
  local mode
  for mode in prefix-collision parent-symlink existing-leaf parent-replacement leaf-replacement; do
    SYNC_TEST_JSON_REPORT_MODE="$mode" case_apply_success_and_protections || return 1
  done
}

case_descriptor_admission_contract() {
  local script="$SYNC_SCRIPT"
  local home_fn evidence_fn bootstrap_fn cleanup_fn
  home_fn="$(sed -n '/^canonical_trust_home()/,/^}/p' "$script")" || return 1
  evidence_fn="$(sed -n '/^ensure_production_evidence_root()/,/^}/p' "$script")" || return 1
  bootstrap_fn="$(sed -n '/^bootstrap_descriptor_table()/,/^canonical_trust_home()/p' "$script")" || return 1
  cleanup_fn="$(sed -n '/^  cleanup_tmp_roots()/,/^  }/p' "$script")" || return 1
  [[ "$home_fn" != *'${HOME}'* && "$home_fn" != *'realpath'* && "$home_fn" != *'pwd -P'* ]] || return 1
  [[ "$evidence_fn" != *'os.open("/"'* && "$evidence_fn" != *"os.open('/'"* ]] || return 1
  [[ "$bootstrap_fn" != *'DESCRIPTOR_TRANSACTION_PARENT_FD=19'* &&
     "$bootstrap_fn" != *'DESCRIPTOR_EVIDENCE_FD=20'* &&
     "$bootstrap_fn" != *'DESCRIPTOR_REPORT_PARENT_FD=21'* ]] || return 1
  [[ "$cleanup_fn" != *'eval '* && "$cleanup_fn" != *'2>/dev/null'* ]] || return 1
  printf 'DESCRIPTOR_ADMISSION_CONTRACT=PASS\n'
}

case_active_descriptor_call_graph_contract() {
  local script="$SYNC_SCRIPT"
  python3 - "$script" <<'PY'
import re
import sys

script = open(sys.argv[1], encoding='utf-8').read()
active = (
    'stage_owner_plan', 'install_owner_plan',
    'descriptor_no_follow_rename', 'descriptor_no_follow_remove',
    'restore_from_journal', 'verify_rollback_owner',
    'cleanup_created_dirs', 'run_apply_with_rollback',
    'rollback_deferred_transaction',
)
for name in active:
    match = re.search(r'^' + re.escape(name) + r'\(\) \{.*?^\}', script, re.M | re.S)
    if not match:
        raise SystemExit('active helper missing: ' + name)
    block = match.group(0)
    if re.search(r'os\.open\(\s*["\']/["\']', block):
        raise SystemExit('active root reopen: ' + name)
    if re.search(r'except\s+OSError\s*:\s*(?:#.*\n\s*)?pass', block):
        raise SystemExit('active close swallowed: ' + name)
stage = re.search(r'^stage_owner_plan\(\) \{.*?^\}', script, re.M | re.S).group(0)
install = re.search(r'^install_owner_plan\(\) \{.*?^\}', script, re.M | re.S).group(0)
if 'os.dup(12)' not in stage or 'os.dup(12)' not in install:
    raise SystemExit('work anchor not explicit')
if 'os.dup(17)' not in install or 'os.dup(18)' not in install:
    raise SystemExit('target anchors not explicit')

def shell_context_without_python_heredocs(text):
    result = []
    in_python = False
    for line in text.splitlines(True):
        if in_python:
            if line.strip() == 'PY':
                in_python = False
            continue
        if re.search(r"<<-?['\"]?PY['\"]?\s*$", line):
            in_python = True
            continue
        result.append(line)
    return ''.join(result)

shell_script = shell_context_without_python_heredocs(script)
dead_helpers = ('stage_entry', 'descriptor_no_follow_copy', 'descriptor_no_follow_mkdir')
for helper in dead_helpers:
    if re.search(r'^' + re.escape(helper) + r'\(\)[ \t]*\{', shell_script, re.M):
        raise SystemExit('dead helper definition remains: ' + helper)
    shell_calls = re.findall(r'^\s*' + re.escape(helper) + r'\s+', shell_script, re.M)
    if shell_calls:
        raise SystemExit('dead helper has production shell caller: ' + forbidden)
if 'run_descriptor_copy_selftest' in script or 'AGENCY_DESCRIPTOR_COPY_SELFTEST' in script:
    raise SystemExit('descriptor copy selftest dispatch remains')

stage_python_match = re.search(r"stage_owner_plan\(\) \{.*?<<['\"]PY['\"]\n(.*?)^PY$", script, re.M | re.S)
if not stage_python_match:
    raise SystemExit('stage Python block missing')
stage_python = stage_python_match.group(1)
if not re.search(r'^def\s+descriptor_no_follow_copy\s*\(', stage_python, re.M):
    raise SystemExit('stage recursive copy definition missing')
if not re.search(r'^\s*descriptor_no_follow_copy\(source_fd,\s*child,\s*dest_fd,\s*child\)', stage_python, re.M):
    raise SystemExit('stage recursive copy call missing')
if not re.search(r'^\s*descriptor_no_follow_copy\(source_parent_fd,\s*source_name,\s*stage_fd,\s*relative\)', stage_python, re.M):
    raise SystemExit('stage whole-file copy call missing')
if not re.search(r'^\s*descriptor_no_follow_copy\(source_root_fd,\s*relative,\s*stage_fd,\s*relative\)', stage_python, re.M):
    raise SystemExit('stage directory copy call missing')
if 'close_checked' not in stage_python or 'source_parent_fd' not in stage_python or 'dest_parent_fd' not in stage_python:
    raise SystemExit('stage recursive copy descriptor contract missing')
PY
  printf 'ACTIVE_DESCRIPTOR_CALL_GRAPH_CONTRACT=PASS\n'
}

case_active_descriptor_close_failure() {
  local script="$SYNC_SCRIPT"
  python3 - "$script" <<'PY'
import sys
text = open(sys.argv[1], encoding='utf-8').read()
required = ('owner-stage-parent-close', 'rollback-target-parent-close',
            'E_DESCRIPTOR_CLOSE', 'verify_test_root_identity_now',
            'owner stage failed', 'rollback restoration failed',
            'RC_DESCRIPTOR_CLOSE_FAILED',
            'RC_PRIMARY_WITH_SECONDARY_CLOSE_FAILED')
for value in required:
    if value not in text:
        raise SystemExit('close-failure contract missing: ' + value)
PY
  if ! grep -Eq 'case_apply_success|owner-stage-parent-close' "$script" || ! grep -Eq 'case_rollback_fault|rollback-target-parent-close' "$script"; then
    printf 'TRANSACTION_ASSERT_FAIL=fixture\n'
    return 1
  fi
  if ! grep -Eq 'close_checked\([^)]*owner-stage|close_checked\([^)]*owner-install|close_checked\([^)]*rollback' "$script"; then
    printf 'TRANSACTION_ASSERT_FAIL=close\n'
    return 1
  fi
  printf 'ACTIVE_DESCRIPTOR_CLOSE_FAILURE=PASS\n'
}

case_forged_transaction_markers() {
  case_transaction_root_binding_security || return 1
  printf 'FORGED_POST_AUTH_DESCRIPTORS=PASS\n'
  return 0
}

case_launcher_origin_proof_admission() {
  local variant home source_root manifest_path action signature allowed_signers txn_root work backup work_leaf backup_leaf report unrelated sentinel before after status root_dev root_ino
  for variant in self-consistent report-fd-unrelated; do
    home="$(fixture_case_home)" || return 1
    source_root="$(fixture_source_copy "$home")" || return 1
    manifest_path="$(fixture_manifest_path "$home")" || return 1
    prepare_installed_manifest_targets "$home" "$home" "$manifest_path" || return 1
    IFS=" " read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" aicc-supervisor-authorization supervisor-approver "$home/action.json" "$manifest_path" "$home/.codex/supervisor-authority/allowed_signers" "isolated-test" "$home" "$home") || return 1
    sentinel="$home/origin-attacker-sentinel"
    printf 'origin attacker sentinel\n' >"$sentinel"
    chmod 600 "$sentinel"
    before="$home/origin-before.json"
    after="$home/origin-after.json"
    printf '%s\n' "$sentinel" >"$home/origin-list"
    descriptor_snapshot_exact "$home" "$home/origin-list" "$before" || return 1
    if [[ "$variant" == self-consistent || "$variant" == report-fd-unrelated ]]; then
      txn_root="$home"
      work="$txn_root/.agency-test-transaction-work"
      backup="$txn_root/.agency-test-transaction-backup"
      work_leaf="$(basename "$work")"
      backup_leaf="$(basename "$backup")"
      mkdir "$work" "$backup" || return 1
      chmod 700 "$work" "$backup" || return 1
      report="$home/.codex/supervisor-runtime-evidence/origin-report"
      : >"$report"
      chmod 600 "$report"
      if [[ "$variant" == report-fd-unrelated ]]; then
        unrelated="$home/unrelated-report-fd"
        : >"$unrelated"
        chmod 600 "$unrelated"
      else
        unrelated="$report"
      fi
    fi
    set +e
    if [[ "$variant" == marker-only ]]; then
      AGENCY_TXN_ROOT_BOUND=v1 HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --project "$home" --test-mode --test-mode-root "$home" --apply --manifest "$manifest_path" --source-root "$source_root" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$home/.codex/supervisor-authority/owner-only-ledger.jsonl" >"$home/origin-report" 2>"$home/origin-stderr"
    elif [[ "$variant" == fd12-13-regular ]]; then
      printf 'not a directory\n' >"$home/forged-work"
      printf 'not a directory\n' >"$home/forged-backup"
      chmod 600 "$home/forged-work" "$home/forged-backup"
      (
        exec 12<"$home/forged-work"
        exec 13<"$home/forged-backup"
        AGENCY_TXN_ROOT_BOUND=v1 AGENCY_TXN_WORK_ROOT="$home/forged-work" AGENCY_TXN_BACKUP_ROOT="$home/forged-backup" HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --project "$home" --test-mode --test-mode-root "$home" --apply --manifest "$manifest_path" --source-root "$source_root" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$home/.codex/supervisor-authority/owner-only-ledger.jsonl" >"$home/origin-report" 2>"$home/origin-stderr"
      )
    else
      report_dev="$(stat -f '%d' "$unrelated")"
      report_ino="$(stat -f '%i' "$unrelated")"
      root_dev="$(stat -f '%d' "$home")"
      root_ino="$(stat -f '%i' "$home")"
      (
        exec 9<"$home"
        exec 10<"$SYNC_SCRIPT"
        exec 11<"$SYNC_SCRIPT"
        exec 12<"$work"
        exec 13<"$backup"
        exec 14<>"$unrelated"
        TEST_MODE_ROOT_FD=9 AGENCY_TEST_MODE_ROOT_BOUND=v1 AGENCY_TEST_MODE_ROOT_BOUND_PATH="$home" AGENCY_TEST_MODE_ROOT_BOUND_DEV="$root_dev" AGENCY_TEST_MODE_ROOT_BOUND_INO="$root_ino" AGENCY_ENTRY_FD_BOUND=11 AGENCY_ENTRY_SCRIPT_DIR="$(dirname "$SYNC_SCRIPT")" AGENCY_TXN_ROOT_BOUND=v1 AGENCY_TXN_WORK_ROOT="$work" AGENCY_TXN_BACKUP_ROOT="$backup" AGENCY_TXN_WORK_LEAF="$work_leaf" AGENCY_TXN_BACKUP_LEAF="$backup_leaf" AGENCY_REPORT_FD_BOUND=v1 AGENCY_REPORT_FD=14 AGENCY_REPORT_DEV="$report_dev" AGENCY_REPORT_INO="$report_ino" AGENCY_JSON_REPORT="$report" HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" --home "$home" --project "$home" --test-mode --test-mode-root "$home" --apply --manifest "$manifest_path" --source-root "$source_root" --json-report "$report" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$home/.codex/supervisor-authority/owner-only-ledger.jsonl" >"$home/origin-report.stdout" 2>"$home/origin-stderr"
      )
    fi
    status=$?
    set -e
    if [[ "$variant" == marker-only || "$variant" == fd12-13-regular ]]; then
      report="$home/origin-report"
    else
      report="$home/origin-report.stdout"
    fi
    assert_raw_sync_report_json "$report" || return 1
    [[ "$status" != 0 ]] || return 1
    [[ "$(json_get "$report" result.status)" == failed ]] || return 1
    if [[ "$variant" == marker-only || "$variant" == fd12-13-regular ]]; then
      [[ "$(json_get "$report" failure.stage)" == report-path-validation ]] || return 1
      [[ "$(json_get "$report" failure.operation)" == report-path-validation ]] || return 1
    else
      [[ "$(json_get "$report" failure.stage)" == transaction-origin-validation ]] || return 1
      [[ "$(json_get "$report" failure.operation)" == transaction-origin-validation ]] || return 1
      [[ "$(json_get "$report" failure.reason)" == "transaction launcher origin proof failed" ]] || return 1
    fi
    descriptor_snapshot_exact "$home" "$home/origin-list" "$after" || return 1
    diff -u "$before" "$after" >/dev/null || return 1
    [[ ! -e "$home/.codex/supervisor-authority/owner-only-ledger.jsonl" ]] || return 1
    rm -rf "$home"
  done
  printf 'LAUNCHER_ORIGIN_PROOF_ADMISSION=PASS\n'
}

case_transaction_root_binding_security() {
  local home txn_parent replacement source_root manifest_path action signature allowed_signers ledger snapshot_fd
  local report stdout_file stderr_file status before_attacker_state report_sentinel state_list before_state after_state
  home="$(fixture_case_home)"
  snapshot_fd=200
        if ! python3 - <<'PY'
import errno
import os
try:
    os.fstat(200)
except OSError as exc:
    raise SystemExit(0 if exc.errno == errno.EBADF else 2)
raise SystemExit(1)
PY
        then
            return 1
        fi
  exec 200<"$home"
  export SYNC_SNAPSHOT_FD="$snapshot_fd"
  txn_parent="$home/.agency-test-transaction"
  replacement="$home/.agency-test-transaction-replacement"
  mkdir -p "$txn_parent" "$replacement"
  chmod 700 "$txn_parent" "$replacement"
  printf 'transaction replacement sentinel\n' > "$replacement/sentinel"
  chmod 600 "$replacement/sentinel"
  before_attacker_state="$(python3 - "$home" <<'PY'
import hashlib
import json
import os
import stat
import sys

path = '.agency-test-transaction-replacement'
parts = []
parent = os.dup(int(os.environ['SYNC_SNAPSHOT_FD']))
opened = [parent]
try:
    for part in parts:
        before = os.stat(part, dir_fd=parent, follow_symlinks=False)
        if stat.S_ISLNK(before.st_mode) or not stat.S_ISDIR(before.st_mode):
            raise SystemExit(1)
        child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        after = os.fstat(child)
        if (before.st_dev, before.st_ino, before.st_uid, stat.S_IMODE(before.st_mode), before.st_nlink) != (after.st_dev, after.st_ino, after.st_uid, stat.S_IMODE(after.st_mode), after.st_nlink):
            os.close(child)
            raise SystemExit(1)
        if parent != opened[0]:
            os.close(parent)
        parent = child
        opened.append(child)
    replacement_fd = os.open('.agency-test-transaction-replacement', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
    try:
        directory = os.fstat(replacement_fd)
        sentinel_fd = os.open('sentinel', os.O_RDONLY | os.O_NOFOLLOW, dir_fd=replacement_fd)
    except BaseException:
        os.close(replacement_fd)
        raise
    try:
        sentinel = os.fstat(sentinel_fd)
        digest = hashlib.sha256()
        while True:
            block = os.read(sentinel_fd, 65536)
            if not block:
                break
            digest.update(block)
    finally:
        os.close(sentinel_fd)
        os.close(replacement_fd)
    digest = digest.hexdigest()
finally:
    for fd in reversed(opened):
        try:
            os.close(fd)
        except OSError:
            pass
print(json.dumps({
    "directory": [directory.st_dev, directory.st_ino, stat.S_IFMT(directory.st_mode), stat.S_IMODE(directory.st_mode), directory.st_nlink, directory.st_size, directory.st_mtime_ns],
    "sentinel": [sentinel.st_dev, sentinel.st_ino, stat.S_IFMT(sentinel.st_mode), stat.S_IMODE(sentinel.st_mode), sentinel.st_nlink, sentinel.st_size, sentinel.st_mtime_ns, digest],
}, separators=(",", ":"), sort_keys=True))
PY
  )" || return 1
  source_root="$(fixture_source_copy "$home")"
  manifest_path="$(fixture_manifest_path "$home")"
  prepare_installed_manifest_targets "$home" "$home" "$manifest_path" || return 1
  IFS=' ' read -r action signature allowed_signers < <(build_auth_bundle "$home/bundle" aicc-supervisor-authorization supervisor-approver "$home/action.json" "$manifest_path" "$home/.codex/supervisor-authority/allowed_signers" "isolated-test" "$home" "$home")
  ledger="$home/.codex/supervisor-authority/owner-only-ledger.jsonl"
  report="$home/.codex/supervisor-runtime-evidence/transaction-race-report.json"
  stdout_file="$home/transaction-race-stdout"
  stderr_file="$home/transaction-race-stderr"
  report_sentinel="$home/.codex/supervisor-runtime-evidence/transaction-race-report-sentinel"
  printf '%s\n' 'independent report sentinel' >"$report_sentinel"
  chmod 600 "$report_sentinel"
  state_list="$home/transaction-race-state-list"
  before_state="$home/transaction-race-state-before"
  after_state="$home/transaction-race-state-after"
  printf '%s\n' "$action" "$signature" "$allowed_signers" "$ledger" "$report_sentinel" >"$state_list"
  snapshot_paths_descriptor_no_follow "$home" "$state_list" "$before_state" || return 1
  set +e
  TMPDIR="$txn_parent" AGENCY_TEST_TRANSACTION_ROOT_RACE=after-origin-work AGENCY_TEST_TRANSACTION_ROOT_STAGE=post-auth-before-revalidation AGENCY_TEST_REPORT_WRITER_DIAGNOSTIC=transaction-race-v1 HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" \
    --home "$home" --project "$home" --test-mode --test-mode-root "$home" --apply --manifest "$manifest_path" --source-root "$source_root" \
    --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$ledger" --json-report "$report" \
    >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  if ! emit_focused_case_diagnostic "$stdout_file" "$stderr_file" "$status"; then
    printf 'TRANSACTION_ASSERT_FAIL=stderr\n' >&2
    return 1
  fi
  local writer_receipt
  writer_receipt="$(rg '^REPORT_WRITER_RESULT=(OK|REPORT_PATH_VALIDATION_FAILED|EVIDENCE_WRITE_FAILED) RC=(0|74|75)$' "$stderr_file" | tail -1 || true)"
  if ! assert_raw_sync_report_json "$stdout_file"; then
    printf 'TRANSACTION_ASSERT_FAIL=json\n' >&2
    cat "$stdout_file" >&2 || true
    tail -20 "$stderr_file" >&2 || true
    return 1
  fi
  if [[ "$status" == 0 || "$(json_get "$stdout_file" result.status)" != failed ]]; then
    printf 'TRANSACTION_ASSERT_FAIL=command-rc\n' >&2
    printf 'transaction-status=%s\n' "$status" >&2
    cat "$stdout_file" >&2
    return 1
  fi
  local actual_status actual_stage actual_operation actual_reason
  if ! actual_status="$(json_get "$stdout_file" result.status)"; then
    printf 'TRANSACTION_ASSERT_FAIL=json\n' >&2
    return 1
  fi
  if ! actual_stage="$(json_get "$stdout_file" failure.stage)"; then
    printf 'TRANSACTION_ASSERT_FAIL=json\n' >&2
    return 1
  fi
  if ! actual_operation="$(json_get "$stdout_file" failure.operation)"; then
    printf 'TRANSACTION_ASSERT_FAIL=json\n' >&2
    return 1
  fi
  if ! actual_reason="$(json_get "$stdout_file" failure.reason)"; then
    printf 'TRANSACTION_ASSERT_FAIL=json\n' >&2
    return 1
  fi
  if [[ -z "$writer_receipt" ]]; then
    emit_post_auth_stage_last "$stderr_file"
    local binder_reason
    if binder_reason="$(read_binder_rc74_reason "$stderr_file")"; then
      printf 'BINDER_RC74_REASON=%s\n' "$binder_reason" >&2
    else
      echo 'FAIL: missing unique allowlisted binder rc74 receipt' >&2
    fi
    printf 'TRANSACTION_ASSERT_FAIL=stderr\n' >&2
    printf 'POST_AUTH_REPORT_TUPLE status=%s stage=%s operation=%s reason=%s REPORT_WRITER_RESULT=MISSING RC=missing\n' \
      "$actual_status" "$actual_stage" "$actual_operation" "$actual_reason" >&2
    return 1
  fi
  if [[ "$actual_status" != failed || "$actual_stage" != transaction-root-validation ||
        "$actual_operation" != transaction-root-validation || "$actual_reason" != "transaction root binding failed" ]]; then
    printf 'TRANSACTION_ASSERT_FAIL=stage\n' >&2
    emit_post_auth_stage_last "$stderr_file"
    printf 'POST_AUTH_REPORT_TUPLE status=%s stage=%s operation=%s reason=%s %s\n' \
      "$actual_status" "$actual_stage" "$actual_operation" "$actual_reason" "$writer_receipt" >&2
    return 1
  fi
  if rg -q 'Traceback|FileExistsError' "$stderr_file"; then
    printf 'TRANSACTION_ASSERT_FAIL=stderr\n' >&2
    return 1
  fi
  if ! snapshot_paths_descriptor_no_follow "$home" "$state_list" "$after_state"; then
    printf 'TRANSACTION_ASSERT_FAIL=sentinel\n' >&2
    return 1
  fi
  if ! diff -u "$before_state" "$after_state" >/dev/null; then
    printf 'TRANSACTION_ASSERT_FAIL=sentinel\n' >&2
    return 1
  fi
  local report_meta
  if ! report_meta="$(descriptor_leaf_snapshot "$report")"; then
    printf 'TRANSACTION_ASSERT_FAIL=artifact-meta\n' >&2
    return 1
  fi
  IFS='|' read -r _ _ report_type report_mode report_nlink report_size _ _ <<<"$report_meta"
  if ! [[ "$report_type" == 32768 && "$report_mode" == 384 && "$report_nlink" == 1 ]]; then
    printf 'TRANSACTION_ASSERT_FAIL=artifact-meta\n' >&2
    return 1
  fi
  if ! python3 - "$stdout_file" "$writer_receipt" <<'PY'
import hashlib
import json
import os
import stat
import sys

stdout_path, writer_receipt = sys.argv[1:]
root_fd = os.dup(int(os.environ["SYNC_SNAPSHOT_FD"]))
current = root_fd
opened = []
try:
    for part in (".codex", "supervisor-runtime-evidence"):
        before = os.stat(part, dir_fd=current, follow_symlinks=False)
        if stat.S_ISLNK(before.st_mode) or not stat.S_ISDIR(before.st_mode):
            raise SystemExit(1)
        child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=current)
        after = os.fstat(child)
        if (before.st_dev, before.st_ino, stat.S_IFMT(before.st_mode), before.st_uid,
                stat.S_IMODE(before.st_mode), before.st_nlink) != (
                after.st_dev, after.st_ino, stat.S_IFMT(after.st_mode), after.st_uid,
                stat.S_IMODE(after.st_mode), after.st_nlink):
            os.close(child)
            raise SystemExit(1)
        os.close(current)
        current = child
        opened.append(child)
    leaf_fd = os.open("transaction-race-report.json", os.O_RDONLY | os.O_NOFOLLOW, dir_fd=current)
    try:
        leaf = os.fstat(leaf_fd)
        if (not stat.S_ISREG(leaf.st_mode) or leaf.st_uid != os.getuid() or
                stat.S_IMODE(leaf.st_mode) != 0o600 or leaf.st_nlink != 1):
            raise SystemExit(1)
        chunks = []
        while True:
            block = os.read(leaf_fd, 65536)
            if not block:
                break
            chunks.append(block)
        artifact = b"".join(chunks)
    finally:
        os.close(leaf_fd)
    with open(stdout_path, "rb") as handle:
        stdout_payload = handle.read()
    def tuple_summary(raw):
        try:
            obj = json.loads(raw.rstrip(b"\n"))
            failure = obj.get("failure", {})
            return (str(obj.get("result", {}).get("status", "")),
                    str(failure.get("stage", "")),
                    str(failure.get("operation", "")),
                    str(failure.get("reason", "")))
        except Exception:
            return ("<invalid>", "<invalid>", "<invalid>", "<invalid>")

    def report_diff(kind):
        limit = min(len(artifact), len(stdout_payload))
        offset = next((i for i in range(limit) if artifact[i] != stdout_payload[i]), limit)
        print("POST_AUTH_REPORT_BYTE_DIFF kind=%s artifact_len=%d stdout_len=%d "
              "artifact_sha256=%s stdout_sha256=%s first_diff_offset=%d "
              "artifact_status=%s artifact_stage=%s artifact_operation=%s artifact_reason=%s "
              "stdout_status=%s stdout_stage=%s stdout_operation=%s stdout_reason=%s "
              "writer_result=%s" % (
                  kind, len(artifact), len(stdout_payload),
                  hashlib.sha256(artifact).hexdigest(), hashlib.sha256(stdout_payload).hexdigest(),
                  offset, *tuple_summary(artifact), *tuple_summary(stdout_payload), writer_receipt), file=sys.stderr)
        raise SystemExit(1)

    if writer_receipt != "REPORT_WRITER_RESULT=OK RC=0":
        report_diff("writer-class")
    if artifact != stdout_payload:
        report_diff("raw")
    if (artifact.count(b"\n") != 1 or stdout_payload.count(b"\n") != 1 or
            not artifact.endswith(b"\n") or not stdout_payload.endswith(b"\n")):
        report_diff("newline")
    try:
        artifact_json = json.loads(artifact[:-1])
        stdout_json = json.loads(stdout_payload[:-1])
    except Exception:
        report_diff("json")
    if artifact_json != stdout_json:
        report_diff("semantic")
finally:
    for fd in reversed(opened):
        try:
            os.close(fd)
        except OSError:
            pass
    if current == root_fd:
        try:
            os.close(root_fd)
        except OSError:
            pass
PY
  then
    printf 'TRANSACTION_ASSERT_FAIL=artifact-bytes\n' >&2
    return 1
  fi
  if ! python3 - "$home" "$before_attacker_state" <<'PY'
import hashlib
import json
import os
import stat
import sys

root, expected_raw = sys.argv[1:]
expected = json.loads(expected_raw)
parts = []
if any(part in ('', '.', '..') or '/' in part for part in parts):
    print('TRANSACTION_ATTACKER_ASSERT_FAIL=unsafe-components', file=sys.stderr)
    raise SystemExit(1)
parent = os.dup(int(os.environ['SYNC_SNAPSHOT_FD']))
opened = [parent]
try:
    current = parent
    for part in parts:
        before = os.stat(part, dir_fd=current, follow_symlinks=False)
        if stat.S_ISLNK(before.st_mode) or not stat.S_ISDIR(before.st_mode):
            print('TRANSACTION_ATTACKER_ASSERT_FAIL=ancestor-unsafe', file=sys.stderr)
            raise SystemExit(1)
        child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=current)
        after = os.fstat(child)
        if (before.st_dev, before.st_ino, before.st_uid, stat.S_IMODE(before.st_mode)) != (after.st_dev, after.st_ino, after.st_uid, stat.S_IMODE(after.st_mode)):
            print('TRANSACTION_ATTACKER_ASSERT_FAIL=ancestor-identity', file=sys.stderr)
            raise SystemExit(1)
        if current != parent:
            os.close(current)
        current = child
        opened.append(child)
    fixed = '.agency-test-transaction-replacement'
    try:
        os.stat(fixed, dir_fd=current, follow_symlinks=False)
    except FileNotFoundError:
        pass
    else:
        print('TRANSACTION_ATTACKER_ASSERT_FAIL=replacement-present', file=sys.stderr)
        raise SystemExit(1)
    attacker = []
    old_work = []
    candidate_count = 0
    for name in sorted(os.listdir(current)):
        st = os.stat(name, dir_fd=current, follow_symlinks=False)
        if stat.S_ISLNK(st.st_mode):
            continue
        if name.startswith('.agency-work-') and stat.S_ISDIR(st.st_mode):
            candidate_count += 1
            if name.endswith('.old'):
                old_work.append((name, st))
                continue
            child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=current)
            try:
                sent = os.stat('sentinel', dir_fd=child, follow_symlinks=False)
                if stat.S_ISREG(sent.st_mode):
                    fd = os.open('sentinel', os.O_RDONLY | os.O_NOFOLLOW, dir_fd=child)
                    try:
                        digest = hashlib.sha256()
                        while True:
                            block = os.read(fd, 65536)
                            if not block:
                                break
                            digest.update(block)
                    finally:
                        os.close(fd)
                    if digest.hexdigest() == expected['sentinel'][-1]:
                        attacker.append((name, st, sent))
            finally:
                os.close(child)
    if len(attacker) != 1:
        print('TRANSACTION_ATTACKER_ASSERT_FAIL=%s' % (
            'attacker-no-candidate' if candidate_count == 0 else
            'attacker-sentinel-mismatch'), file=sys.stderr)
        raise SystemExit(1)
    if len(old_work) != 1:
        print('TRANSACTION_ATTACKER_ASSERT_FAIL=old-count', file=sys.stderr)
        raise SystemExit(1)
    _, attacker_st, attacker_sentinel = attacker[0]
    expected_dir = expected['directory']
    expected_sent = expected['sentinel']
    if [attacker_st.st_dev, attacker_st.st_ino, stat.S_IFMT(attacker_st.st_mode), stat.S_IMODE(attacker_st.st_mode), attacker_st.st_nlink, attacker_st.st_size, attacker_st.st_mtime_ns] != expected_dir:
        print('TRANSACTION_ATTACKER_ASSERT_FAIL=attacker-identity', file=sys.stderr)
        raise SystemExit(1)
    if [attacker_sentinel.st_dev, attacker_sentinel.st_ino, stat.S_IFMT(attacker_sentinel.st_mode), stat.S_IMODE(attacker_sentinel.st_mode), attacker_sentinel.st_nlink, attacker_sentinel.st_size, attacker_sentinel.st_mtime_ns, expected_sent[-1]] != expected_sent:
        print('TRANSACTION_ATTACKER_ASSERT_FAIL=attacker-sentinel', file=sys.stderr)
        raise SystemExit(1)
finally:
    for fd in reversed(opened):
        try:
            os.close(fd)
        except OSError:
            pass
PY
  then
    printf 'TRANSACTION_ASSERT_FAIL=attacker\n' >&2
    return 1
  fi
  if ! rm -rf "$home"; then
    printf 'TRANSACTION_ASSERT_FAIL=cleanup\n' >&2
    return 1
  fi
  printf 'TRANSACTION_ROOT_BINDING_SECURITY=PASS\n'
  return 0
}

case_evidence_seam_isolation() {
  local root evidence replacement before after rc temp_parent
  temp_parent="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || printf '/tmp')"
  root="$(mktemp -d "${temp_parent%/}/agency-evidence-seam.XXXXXX")" || return 1
  root="$(physical_root "$root")" || return 1
  chmod 700 "$root"
  evidence="$root"
  replacement="$root/replacement"
  mkdir "$replacement"
  chmod 700 "$replacement"
  printf 'protected evidence sentinel\n' >"$evidence/sentinel"
  printf 'replacement sentinel\n' >"$replacement/sentinel"
  chmod 600 "$evidence/sentinel" "$replacement/sentinel"
  before="$(stat -f '%i|%p|%z|%m' "$evidence/sentinel")"
  set +e
  AGENCY_TEST_EVIDENCE_RACE_STAGE=after-stat-before-open \
  AGENCY_TEST_EVIDENCE_RACE_AUTH=isolated-production-root-v1 \
    /bin/bash -c 'source "$1"; ensure_production_evidence_root "$2" "$3" false "" ""' _ "$SYNC_SCRIPT" "$evidence" "$(dirname "$root")"
  rc=$?
  set -e
  [[ "$rc" != 0 ]] || return 1
  after="$(stat -f '%i|%p|%z|%m' "$evidence/sentinel")"
  [[ "$before" == "$after" ]] || return 1
  [[ ! -e "$evidence/.agency-test-evidence-old" && ! -e "$evidence/.agency-test-evidence-replacement" ]] || return 1
  rm -rf "$root"
  printf 'EVIDENCE_SEAM_PRODUCTION_UNREACHABLE=PASS\n'
  return 0
}

descriptor_snapshot_exact() {
  if [[ "$#" -ne 3 ]]; then
    echo 'FAIL: exact descriptor snapshot requires trusted root, path list, and output' >&2
    return 64
  fi
  local trusted_root="$1"
  local list="$2"
  local out="$3"
  python3 - "$trusted_root" "$list" "$out" <<'PY'
import hashlib
import json
import os
import stat
import sys

root, list_path, output = sys.argv[1:]
O_DIRECTORY = getattr(os, "O_DIRECTORY", 0)
O_NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
root_flags = os.O_RDONLY | O_DIRECTORY | O_NOFOLLOW
leaf_flags = os.O_RDONLY | O_NOFOLLOW

def kind(mode):
    if stat.S_ISREG(mode):
        return "file"
    if stat.S_ISDIR(mode):
        return "directory"
    if stat.S_ISLNK(mode):
        return "symlink"
    return "special"

def digest_opened(fd, opened):
    if kind(opened.st_mode) != "file":
        return hashlib.sha256(kind(opened.st_mode).encode("ascii")).hexdigest()
    digest = hashlib.sha256()
    while True:
        block = os.read(fd, 1024 * 1024)
        if not block:
            break
        digest.update(block)
    return digest.hexdigest()

def capture(root_fd, absolute):
    if not absolute.startswith("/"):
        raise RuntimeError("snapshot path must be absolute")
    normalized_root = os.path.normpath(root)
    normalized = os.path.normpath(absolute)
    relative = os.path.relpath(normalized, normalized_root)
    if relative == ".." or relative.startswith("../") or os.path.isabs(relative):
        raise RuntimeError("snapshot escaped trusted root")
    parts = [] if relative == "." else relative.split("/")
    if any(not part or part in (".", "..") or "/" in part for part in parts):
        raise RuntimeError("unsafe snapshot component")
    current = os.dup(root_fd)
    try:
        for part in parts[:-1]:
            before = os.stat(part, dir_fd=current, follow_symlinks=False)
            if stat.S_ISLNK(before.st_mode) or not stat.S_ISDIR(before.st_mode):
                raise RuntimeError("unsafe snapshot intermediate")
            child = os.open(part, root_flags, dir_fd=current)
            after = os.fstat(child)
            if (before.st_dev, before.st_ino, before.st_uid, stat.S_IMODE(before.st_mode), before.st_nlink) != (
                    after.st_dev, after.st_ino, after.st_uid, stat.S_IMODE(after.st_mode), after.st_nlink):
                os.close(child)
                raise RuntimeError("snapshot intermediate identity changed")
            os.close(current)
            current = child
        if not parts:
            st = os.fstat(current)
            return {"exists": True, "dev": st.st_dev, "inode": st.st_ino, "type": "directory",
                    "mode": format(stat.S_IMODE(st.st_mode), "o"), "nlink": st.st_nlink,
                    "size": st.st_size, "mtimeNs": st.st_mtime_ns, "digest": "root"}
        name = parts[-1]
        try:
            st = os.stat(name, dir_fd=current, follow_symlinks=False)
        except FileNotFoundError:
            return {"exists": False}
        item = {"exists": True, "dev": st.st_dev, "inode": st.st_ino, "type": kind(st.st_mode),
                "mode": format(stat.S_IMODE(st.st_mode), "o"), "nlink": st.st_nlink,
                "size": st.st_size, "mtimeNs": st.st_mtime_ns}
        if item["type"] == "symlink":
            item["digest"] = hashlib.sha256(os.readlink(name, dir_fd=current).encode("utf-8", "surrogateescape")).hexdigest()
            return item
        if item["type"] == "file":
            fd = os.open(name, leaf_flags, dir_fd=current)
            try:
                opened = os.fstat(fd)
                if (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns) != (
                        st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns):
                    raise RuntimeError("snapshot leaf identity changed")
                item["digest"] = digest_opened(fd, opened)
                final = os.fstat(fd)
                if (final.st_dev, final.st_ino, final.st_size, final.st_mtime_ns, final.st_nlink) != (
                        opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns, opened.st_nlink):
                    raise RuntimeError("snapshot leaf changed during read")
            finally:
                os.close(fd)
            return item
        item["digest"] = hashlib.sha256(item["type"].encode("ascii")).hexdigest()
        return item
    finally:
        os.close(current)

root_fd = os.open(root, root_flags)
try:
    root_st = os.fstat(root_fd)
    if not stat.S_ISDIR(root_st.st_mode) or root_st.st_uid != os.getuid() or stat.S_IMODE(root_st.st_mode) != 0o700:
        raise RuntimeError("unsafe snapshot root")
    paths = [line.rstrip("\n") for line in open(list_path, encoding="utf-8") if line.rstrip("\n")]
    state = {path: capture(root_fd, path) for path in paths}
finally:
    os.close(root_fd)
with open(output, "w", encoding="utf-8") as handle:
    json.dump(state, handle, separators=(",", ":"), sort_keys=True)
PY
}

descriptor_leaf_snapshot() {
  local path="$1"
  python3 - "$path" <<'PY'
import hashlib
import os
import stat
import sys

path = sys.argv[1]
parts = [part for part in path.split('/') if part]
if not path.startswith('/') or not parts or any(part in ('', '.', '..') or '/' in part for part in parts):
    raise SystemExit(1)
parent = os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
opened = [parent]
try:
    current = parent
    for part in parts[:-1]:
        before = os.stat(part, dir_fd=current, follow_symlinks=False)
        if stat.S_ISLNK(before.st_mode) or not stat.S_ISDIR(before.st_mode):
            raise SystemExit(1)
        child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=current)
        after = os.fstat(child)
        if (before.st_dev, before.st_ino, before.st_uid, stat.S_IMODE(before.st_mode)) != (after.st_dev, after.st_ino, after.st_uid, stat.S_IMODE(after.st_mode)):
            raise SystemExit(1)
        if current != parent:
            os.close(current)
        current = child
        opened.append(child)
    fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW, dir_fd=current)
    try:
        st = os.fstat(fd)
        digest = hashlib.sha256()
        while True:
            block = os.read(fd, 65536)
            if not block:
                break
            digest.update(block)
        print(f'{st.st_dev}|{st.st_ino}|{stat.S_IFMT(st.st_mode)}|{stat.S_IMODE(st.st_mode)}|{st.st_nlink}|{st.st_size}|{st.st_mtime_ns}|{digest.hexdigest()}')
    finally:
        os.close(fd)
finally:
    for fd in reversed(opened):
        try:
            os.close(fd)
        except OSError:
            pass
PY
}

focused_case_fail() {
  printf 'FOCUSED_ASSERT_FAIL=%s\n' "$1" >&2
  return 1
}

case_evidence_ancestry_security() {
  local root attack report stdout_file stderr_file status manifest_file source_root action signature allowed_signers ledger
  local evidence_root replacement_root report_sentinel report_sentinel_after before_snapshot after_snapshot sentinel_before sentinel_after replacement_before replacement_after hook_stage
  local action_before action_after signature_before signature_after signers_before signers_after
  local target_before target_after temp_parent focused_tuple
  manifest_file="$MANIFEST_PATH"
  temp_parent="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || printf '/tmp')"
  for scenario in unsafe-mode ancestor-symlink replacement-race; do
    root="$(fixture_case_home)" || focused_case_fail fixture-setup
    root="$(physical_root "$root")" || focused_case_fail fixture-setup
    source_root="$(fixture_source_copy "$root")" || focused_case_fail fixture-setup
    manifest_file="$(fixture_manifest_path "$root")" || focused_case_fail fixture-setup
    prepare_installed_manifest_targets "$root" "$root" "$manifest_file" || focused_case_fail fixture-setup
    IFS=' ' read -r action signature allowed_signers < <(build_auth_bundle "$root/bundle" aicc-supervisor-authorization supervisor-approver "$root/action.json" "$manifest_file" "$root/.codex/supervisor-authority/allowed_signers" "isolated-test" "$root" "$root") || focused_case_fail fixture-setup
    evidence_root="$root/.codex/supervisor-runtime-evidence"
    [[ -d "$evidence_root" ]] || focused_case_fail fixture-setup
    chmod 700 "$evidence_root" || focused_case_fail fixture-setup
    action_before="$(descriptor_leaf_snapshot "$action")" || focused_case_fail fixture-setup
    signature_before="$(descriptor_leaf_snapshot "$signature")" || focused_case_fail fixture-setup
    signers_before="$(descriptor_leaf_snapshot "$root/.codex/supervisor-authority/allowed_signers")" || focused_case_fail fixture-setup
    attack="$root/attack"
    mkdir "$attack" || focused_case_fail fixture-setup
    chmod 700 "$attack" || focused_case_fail fixture-setup
    printf 'evidence ancestry sentinel\n' > "$attack/sentinel"
    chmod 600 "$attack/sentinel" || focused_case_fail fixture-setup
    before_snapshot="$(descriptor_leaf_snapshot "$attack/sentinel")" || focused_case_fail fixture-setup
    mkdir "$evidence_root/custom-parent" || focused_case_fail fixture-setup
    chmod 700 "$evidence_root/custom-parent" || focused_case_fail fixture-setup
    report_sentinel="$evidence_root/ancestry-report-sentinel"
    report_sentinel_after="$report_sentinel"
    printf '%s\n' 'report sentinel' >"$report_sentinel"
    chmod 600 "$report_sentinel" || focused_case_fail fixture-setup
    sentinel_before="$(descriptor_leaf_snapshot "$report_sentinel")" || focused_case_fail fixture-setup
    if [[ "$scenario" == unsafe-mode ]]; then
      hook_stage=before-evidence-ancestry-unsafe
    elif [[ "$scenario" == ancestor-symlink ]]; then
      hook_stage=before-evidence-ancestry-symlink
    else
      hook_stage=before-evidence-ancestry-replacement
      replacement_root="$evidence_root/.agency-test-evidence-replacement"
      mkdir "$replacement_root" || focused_case_fail fixture-setup
      chmod 700 "$replacement_root" || focused_case_fail fixture-setup
      printf 'replacement sentinel\n' > "$replacement_root/sentinel"
      chmod 600 "$replacement_root/sentinel" || focused_case_fail fixture-setup
      replacement_before="$(descriptor_leaf_snapshot "$replacement_root/sentinel")" || focused_case_fail fixture-setup
      report_sentinel_after="$report_sentinel"
    fi
        report="$evidence_root/custom-parent/ancestry-report.json"
    ledger="$root/.codex/supervisor-authority/owner-only-ledger.jsonl"
    stdout_file="$root/ancestry.stdout"
    stderr_file="$root/ancestry.stderr"
    target_before="$root/ancestry-target-before"
    target_after="$root/ancestry-target-after"
    snapshot_replay_targets "$root" "$manifest_file" "$target_before" || return 1
    set +e
    if [[ "$scenario" == replacement-race ]]; then
      AGENCY_TEST_EVIDENCE_RACE_STAGE=before-evidence-ancestry-replacement \
      AGENCY_TEST_EVIDENCE_RACE_AUTH=isolated-production-root-v1 \
      HOME="$root" PROJECT="$root" "$SYNC_SCRIPT" --home "$root" --project "$root" --test-mode --test-mode-root "$root" --apply --manifest "$manifest_file" --source-root "$source_root" --json-report "$report" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$ledger" >"$stdout_file" 2>"$stderr_file"
    elif [[ "$scenario" == unsafe-mode ]]; then
      AGENCY_TEST_EVIDENCE_RACE_STAGE=before-evidence-ancestry-unsafe \
      AGENCY_TEST_EVIDENCE_RACE_AUTH=isolated-production-root-v1 \
      HOME="$root" PROJECT="$root" "$SYNC_SCRIPT" --home "$root" --project "$root" --test-mode --test-mode-root "$root" --apply --manifest "$manifest_file" --source-root "$source_root" --json-report "$report" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$ledger" >"$stdout_file" 2>"$stderr_file"
    elif [[ "$scenario" == ancestor-symlink ]]; then
      AGENCY_TEST_EVIDENCE_RACE_STAGE=before-evidence-ancestry-symlink \
      AGENCY_TEST_EVIDENCE_RACE_AUTH=isolated-production-root-v1 \
      HOME="$root" PROJECT="$root" "$SYNC_SCRIPT" --home "$root" --project "$root" --test-mode --test-mode-root "$root" --apply --manifest "$manifest_file" --source-root "$source_root" --json-report "$report" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$ledger" >"$stdout_file" 2>"$stderr_file"
    else
      HOME="$root" PROJECT="$root" "$SYNC_SCRIPT" --home "$root" --project "$root" --test-mode --test-mode-root "$root" --apply --manifest "$manifest_file" --source-root "$source_root" --json-report "$report" --action-file "$action" --signature-file "$signature" --allowed-signers "$allowed_signers" --ledger "$ledger" >"$stdout_file" 2>"$stderr_file"
    fi
    status=$?
    set -e
    assert_raw_sync_report_json "$stdout_file" || focused_case_fail json
    grep -Fx "EVIDENCE_ANCESTRY_HOOK_HIT=$hook_stage" "$stderr_file" >/dev/null || focused_case_fail hook
    focused_tuple="$(python3 - "$stdout_file" "$status" <<'PY'
import json
import re
import sys

report_path, command_rc = sys.argv[1:]
with open(report_path, encoding="utf-8") as handle:
    raw = handle.read()
lines = [line for line in raw.splitlines() if line.strip()]
if len(lines) != 1:
    raise SystemExit(1)
report = json.loads(lines[0])
failure = report.get("failure") or {}
result = report.get("result") or {}

def enum(value):
    value = str(value or "")
    return value.lower() if re.fullmatch(r"[A-Za-z0-9_-]{1,64}", value) else "unknown"

reason_map = {
    "evidence root validation failed": "evidence-root-validation-failed",
    "report path validation failed": "report-path-validation-failed",
    "transaction root binding failed": "transaction-root-binding-failed",
    "authorization validation failed": "authorization-validation-failed",
    "post-auth-origin-attestation-failed": "post-auth-origin-attestation-failed",
}
reason = reason_map.get(str(failure.get("reason") or ""), "unknown")
print("%s\t%s\t%s\t%s\t%s\t%s" % (
    int(command_rc), len(lines), enum(result.get("status")),
    enum(failure.get("stage")), enum(failure.get("operation")), reason
))
PY
    )" || focused_case_fail json
    IFS=$'\t' read -r tuple_rc tuple_count tuple_status tuple_stage tuple_operation tuple_reason <<<"$focused_tuple"
    printf 'FOCUSED_TUPLE rc=%s json_count=%s status=%s stage=%s operation=%s reason=%s\n' \
      "$tuple_rc" "$tuple_count" "$tuple_status" "$tuple_stage" "$tuple_operation" "$tuple_reason" >&2
    [[ "$status" != 0 ]] || focused_case_fail command-rc
    [[ "$(json_get "$stdout_file" result.status)" == failed ]] || focused_case_fail status
    if [[ "$scenario" == replacement-race ]]; then
      [[ "$(json_get "$stdout_file" failure.stage)" == evidence-validation ]] || focused_case_fail stage
      [[ "$(json_get "$stdout_file" failure.operation)" == evidence-validation ]] || focused_case_fail operation
      [[ "$(json_get "$stdout_file" failure.reason)" == "evidence root validation failed" ]] || focused_case_fail reason
    else
      [[ "$(json_get "$stdout_file" failure.stage)" == evidence-validation ]] || focused_case_fail stage
      [[ "$(json_get "$stdout_file" failure.operation)" == evidence-validation ]] || focused_case_fail operation
      [[ "$(json_get "$stdout_file" failure.reason)" == "evidence root validation failed" ]] || focused_case_fail reason
    fi
    after_snapshot="$(descriptor_leaf_snapshot "$attack/sentinel")" || focused_case_fail attacker
    [[ "$before_snapshot" == "$after_snapshot" ]] || focused_case_fail attacker
    if [[ "$scenario" == replacement-race ]]; then
      replacement_after="$(descriptor_leaf_snapshot "$evidence_root/custom-parent/sentinel")" || focused_case_fail replacement
      [[ "$replacement_before" == "$replacement_after" ]] || focused_case_fail replacement
    fi
    sentinel_after="$(descriptor_leaf_snapshot "$report_sentinel_after")" || focused_case_fail sentinel
    [[ "$sentinel_before" == "$sentinel_after" ]] || focused_case_fail sentinel
    action_after="$(descriptor_leaf_snapshot "$action")" || focused_case_fail authorization
    signature_after="$(descriptor_leaf_snapshot "$signature")" || focused_case_fail authorization
    signers_after="$(descriptor_leaf_snapshot "$root/.codex/supervisor-authority/allowed_signers")" || focused_case_fail authorization
    [[ "$action_before" == "$action_after" && "$signature_before" == "$signature_after" && "$signers_before" == "$signers_after" ]] || focused_case_fail authorization
    snapshot_replay_targets "$root" "$manifest_file" "$target_after" || focused_case_fail target
    diff -u "$target_before" "$target_after" >/dev/null || focused_case_fail target
    [[ ! -e "$ledger" ]] || focused_case_fail ledger
    [[ ! -e "$report" ]] || focused_case_fail artifact
    rm -rf "$root" || focused_case_fail cleanup
  done
  printf 'EVIDENCE_ANCESTRY_SECURITY=PASS\n'
  return 0
}

task_security_root_fixture_selfcheck() {
  local selftest_root positive_root wrong_mode_root
  selftest_root="$(mktemp -d "${TMPDIR:-/tmp}/agency-security-root-selftest.XXXXXX")" || return 1
  chmod 700 "$selftest_root" || return 1
  positive_root="$selftest_root/positive"
  wrong_mode_root="$selftest_root/wrong-mode"
  mkdir "$positive_root" "$wrong_mode_root" || return 1
  chmod 700 "$positive_root" "$wrong_mode_root" || return 1

  if ! ensure_fixture_security_roots "$positive_root"; then
    printf '%s\n' 'FAIL: positive security-root fixture creation failed' >&2
    rm -rf "$selftest_root"
    printf 'TOTAL=1\nPASS=0\nFAIL=1\nRC=1\n'
    return 1
  fi
  if ! ensure_fixture_security_roots "$positive_root"; then
    printf '%s\n' 'FAIL: positive security-root fixture revalidation failed' >&2
    rm -rf "$selftest_root"
    printf 'TOTAL=1\nPASS=0\nFAIL=1\nRC=1\n'
    return 1
  fi
  if ! python3 - "$positive_root" <<'PY'
import os
import stat
import sys

root = sys.argv[1]
flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0)
fds = []
try:
    root_fd = os.open(root, flags)
    fds.append(root_fd)
    codex_fd = os.open(".codex", flags, dir_fd=root_fd)
    fds.append(codex_fd)
    authority_fd = os.open("supervisor-authority", flags, dir_fd=codex_fd)
    fds.append(authority_fd)
    evidence_fd = os.open("supervisor-runtime-evidence", flags, dir_fd=codex_fd)
    fds.append(evidence_fd)
    stats = [os.fstat(fd) for fd in fds]
    if any(not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) != 0o700 for st in stats):
        raise SystemExit(1)
    if (stats[2].st_dev, stats[2].st_ino) == (stats[3].st_dev, stats[3].st_ino):
        raise SystemExit(1)
finally:
    for fd in reversed(fds):
        os.close(fd)
PY
  then
    printf '%s\n' 'FAIL: positive security-root fixture metadata mismatch' >&2
    rm -rf "$selftest_root"
    printf 'TOTAL=1\nPASS=0\nFAIL=1\nRC=1\n'
    return 1
  fi

  mkdir "$wrong_mode_root/.codex" || return 1
  chmod 700 "$wrong_mode_root/.codex" || return 1
  mkdir "$wrong_mode_root/.codex/supervisor-authority" "$wrong_mode_root/.codex/supervisor-runtime-evidence" || return 1
  chmod 755 "$wrong_mode_root/.codex/supervisor-authority" || return 1
  chmod 700 "$wrong_mode_root/.codex/supervisor-runtime-evidence" || return 1
  if ensure_fixture_security_roots "$wrong_mode_root" >/dev/null 2>&1; then
    printf '%s\n' 'FAIL: wrong-mode authority root was accepted' >&2
    rm -rf "$selftest_root"
    printf 'TOTAL=1\nPASS=0\nFAIL=1\nRC=1\n'
    return 1
  fi
  if [[ "$(stat -f '%Lp' "$wrong_mode_root/.codex/supervisor-authority")" != "755" ]]; then
    printf '%s\n' 'FAIL: wrong-mode authority root was silently changed' >&2
    rm -rf "$selftest_root"
    printf 'TOTAL=1\nPASS=0\nFAIL=1\nRC=1\n'
    return 1
  fi
  if [[ -e "$wrong_mode_root/.codex/supervisor-authority/owner-only-ledger.jsonl" ]]; then
    printf '%s\n' 'FAIL: wrong-mode fixture created ledger state' >&2
    rm -rf "$selftest_root"
    printf 'TOTAL=1\nPASS=0\nFAIL=1\nRC=1\n'
    return 1
  fi

  rm -rf "$selftest_root"
  printf 'TOTAL=1\nPASS=1\nFAIL=0\nRC=0\n'
  return 0
}

task_codex_root_init_selfcheck() {
  local selftest_root positive_root wrong_mode_root
  selftest_root="$(mktemp -d "${TMPDIR:-/tmp}/agency-codex-root-selftest.XXXXXX")" || return 1
  chmod 700 "$selftest_root" || return 1
  positive_root="$selftest_root/positive"
  wrong_mode_root="$selftest_root/wrong-mode"
  mkdir "$positive_root" "$wrong_mode_root" || return 1
  chmod 700 "$positive_root" "$wrong_mode_root" || return 1

  if ! ensure_fixture_codex_root "$positive_root"; then
    printf '%s\n' 'FAIL: positive .codex initialization failed' >&2
    rm -rf "$selftest_root"
    printf 'TOTAL=1\nPASS=0\nFAIL=1\nRC=1\n'
    return 1
  fi
  if ! ensure_fixture_codex_root "$positive_root"; then
    printf '%s\n' 'FAIL: existing valid .codex revalidation failed' >&2
    rm -rf "$selftest_root"
    printf 'TOTAL=1\nPASS=0\nFAIL=1\nRC=1\n'
    return 1
  fi
  if ! python3 - "$positive_root" <<'PY'
import os
import stat
import sys

root_fd = None
codex_fd = None
try:
    flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0)
    root_fd = os.open(sys.argv[1], flags)
    codex_fd = os.open(".codex", flags, dir_fd=root_fd)
    st = os.fstat(codex_fd)
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) != 0o700:
        raise SystemExit(1)
finally:
    for fd in (codex_fd, root_fd):
        if fd is not None:
            os.close(fd)
PY
  then
    printf '%s\n' 'FAIL: initialized .codex metadata mismatch' >&2
    rm -rf "$selftest_root"
    printf 'TOTAL=1\nPASS=0\nFAIL=1\nRC=1\n'
    return 1
  fi

  mkdir "$wrong_mode_root/.codex" || return 1
  chmod 755 "$wrong_mode_root/.codex" || return 1
  if ensure_fixture_codex_root "$wrong_mode_root" >/dev/null 2>&1; then
    printf '%s\n' 'FAIL: wrong-mode .codex was accepted' >&2
    rm -rf "$selftest_root"
    printf 'TOTAL=1\nPASS=0\nFAIL=1\nRC=1\n'
    return 1
  fi
  if [[ "$(stat -f '%Lp' "$wrong_mode_root/.codex")" != "755" ]]; then
    printf '%s\n' 'FAIL: wrong-mode .codex was silently changed' >&2
    rm -rf "$selftest_root"
    printf 'TOTAL=1\nPASS=0\nFAIL=1\nRC=1\n'
    return 1
  fi

  rm -rf "$selftest_root"
  printf 'TOTAL=1\nPASS=1\nFAIL=0\nRC=0\n'
  return 0
}

if [[ "${SYNC_CODEX_ROOT_INIT_SELFTEST:-}" == "1" ]]; then
  task_codex_root_init_selfcheck
  exit $?
fi

if [[ "${SYNC_SECURITY_ROOT_FIXTURE_SELFTEST:-}" == "1" ]]; then
  task_security_root_fixture_selfcheck
  exit $?
fi

if [[ "${SYNC_SOURCE_OWNER_PLAN_GATE:-}" == "1" ]]; then
  source_owner_plan_gate
  exit $?
fi

if ! build_isolated_fixture; then
  echo 'FAIL: failed to build test fixture'
  exit 1
fi

trap 'rm -rf "$FIXTURE_ROOT"' EXIT

if [[ -n "${SYNC_TEST_CASE:-}" ]]; then
  case_test_root_entry_failure() {
    local scenario="$1"
    local home report sentinel manifest_path source_root before_meta before_digest after_meta after_digest status
    local entry_dir entry_file entry_sentinel_dir launcher_pid ready_seen
    home="$(fixture_case_home)"
    manifest_path="$(fixture_manifest_path "$home")"
    source_root="$(fixture_source_copy "$home")"
    report="$home/entry-failure-report"
    sentinel="$home/entry-failure-sentinel"
    printf 'entry failure sentinel\n' >"$sentinel"
    entry_dir="$home/entry-fixture/components"
    entry_file="$entry_dir/entry.sh"
    entry_sentinel_dir="$home/entry-fixture/sentinel-dir"
    mkdir -p "$entry_dir" "$entry_sentinel_dir"
    chmod 700 "$home/entry-fixture" "$entry_dir" "$entry_sentinel_dir"
    printf '#!/bin/sh\nexit 0\n' >"$entry_file"
    chmod 600 "$entry_file"
    case "$scenario" in
      entry-component-unsafe)
        unlink "$entry_file"
        rmdir "$entry_dir"
        ln -s "$entry_sentinel_dir" "$entry_dir"
        ;;
      entry-leaf-unsafe)
        unlink "$entry_file"
        ln -s "$sentinel" "$entry_file"
        ;;
      entry-special)
        unlink "$entry_file"
        mkfifo "$entry_file"
        ;;
      entry-open-failed)
        unlink "$entry_file"
        ;;
    esac
    before_meta="$(stat -f '%i|%p|%z|%m' "$sentinel")"
    before_digest="$(shasum -a 256 "$sentinel" | awk '{print $1}')"
    set +e
    if [[ "$scenario" == "entry-race" ]]; then
      AGENCY_TEST_LAUNCHER_SCENARIO="$scenario" AGENCY_TEST_ENTRY_REL='entry-fixture/components/entry.sh' HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" \
        --home "$home" --project "$home" --test-mode --test-mode-root "$home" \
        --dry-run --manifest "$manifest_path" --source-root "$source_root" \
        >"$report" 2>"$home/entry-failure-stderr" &
      launcher_pid=$!
      ready_seen=false
      for _ in {1..1000}; do
        if [[ -e "$home/entry-fixture/.entry-ready" ]]; then
          ready_seen=true
          break
        fi
        sleep 0.01
      done
      if [[ "$ready_seen" != true ]]; then
        kill "$launcher_pid" 2>/dev/null || true
        wait "$launcher_pid" 2>/dev/null || true
        set -e
        echo 'entry race seam was not reached' >&2
        return 1
      fi
      mv "$entry_file" "$entry_file.old"
      ln -s "$sentinel" "$entry_file"
      : > "$home/entry-fixture/.entry-release"
      wait "$launcher_pid"
      status=$?
    else
      AGENCY_TEST_LAUNCHER_SCENARIO="$scenario" AGENCY_TEST_ENTRY_REL='entry-fixture/components/entry.sh' HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" \
        --home "$home" --project "$home" --test-mode --test-mode-root "$home" \
        --dry-run --manifest "$manifest_path" --source-root "$source_root" \
        >"$report" 2>"$home/entry-failure-stderr"
      status=$?
    fi
    set -e
    python3 - "$report" "$scenario" "$status" <<'PY'
import json
import sys

report_path, scenario, status_text = sys.argv[1:]
status = int(status_text)
with open(report_path, encoding="utf-8") as handle:
    lines = [line for line in handle.read().splitlines() if line]
if len(lines) != 1:
    raise SystemExit(f"entry scenario {scenario}: expected one JSON value, got {len(lines)}")
report = json.loads(lines[0])
failure = report.get("failure", {})
if (
    report.get("schema") != "agency-agents.local-sync-report/v1"
    or status == 0
    or report.get("result", {}).get("status") != "failed"
    or failure.get("stage") != "test-root-validation"
    or failure.get("operation") != "test-root-binding"
    or not failure.get("reason")
    or report.get("rollback", {}).get("attempted") != 0
):
    raise SystemExit(f"entry scenario {scenario}: structured failure mismatch")
PY
    after_meta="$(stat -f '%i|%p|%z|%m' "$sentinel")"
    after_digest="$(shasum -a 256 "$sentinel" | awk '{print $1}')"
    if [[ "$before_meta" != "$after_meta" || "$before_digest" != "$after_digest" ]]; then
      echo "entry scenario $scenario changed sentinel" >&2
      rm -rf "$home"
      return 1
    fi
    rm -rf "$home"
  }

  case_test_root_fd_collision() {
    local collision="$1"
    local home report sentinel before_meta before_digest after_meta after_digest status
    home="$(fixture_case_home)"
    report="$home/fd-collision-report"
    sentinel="$home/fd-collision-sentinel"
    printf 'fd collision sentinel\n' >"$sentinel"
    before_meta="$(stat -f '%i|%p|%z|%m' "$sentinel")"
    before_digest="$(shasum -a 256 "$sentinel" | awk '{print $1}')"
    set +e
    (
      case "$collision" in
        9) exec 9<"$sentinel" ;;
        10) exec 10<"$sentinel" ;;
        11) exec 11<"$sentinel" ;;
        9-10-11)
          exec 9<"$sentinel"
          exec 10<"$sentinel"
          exec 11<"$sentinel"
          ;;
        *) exit 2 ;;
      esac
      HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" \
        --home "$home" --project "$home" --test-mode --test-mode-root "$home" \
        --dry-run --manifest "$(fixture_manifest_path "$home")" --source-root "$(fixture_source_copy "$home")" \
        >"$report" 2>"$home/fd-collision-stderr"
    )
    status=$?
    set -e
    python3 - "$report" "$collision" "$status" <<'PY'
import json
import sys

report_path, collision, status_text = sys.argv[1:]
status = int(status_text)
with open(report_path, encoding="utf-8") as handle:
    lines = [line for line in handle.read().splitlines() if line]
if len(lines) != 1:
    raise SystemExit(f"fd collision {collision}: expected one JSON value, got {len(lines)}")
report = json.loads(lines[0])
if report.get("schema") != "agency-agents.local-sync-report/v1":
    raise SystemExit(f"fd collision {collision}: schema mismatch")
if status == 0 or report.get("result", {}).get("status") != "failed":
    raise SystemExit(f"fd collision {collision}: status/report mismatch")
failure = report.get("failure", {})
if (
    failure.get("stage") != "test-root-validation"
    or failure.get("operation") != "test-root-binding"
    or not failure.get("reason")
    or report.get("rollback", {}).get("attempted") != 0
):
    raise SystemExit(f"fd collision {collision}: structured failure mismatch")
PY
    after_meta="$(stat -f '%i|%p|%z|%m' "$sentinel")"
    after_digest="$(shasum -a 256 "$sentinel" | awk '{print $1}')"
    if [[ "$before_meta" != "$after_meta" || "$before_digest" != "$after_digest" ]]; then
      echo "fd collision $collision changed sentinel" >&2
      rm -rf "$home"
      return 1
    fi
    rm -rf "$home"
  }

  case_trust_home_system_resolver() {
    case_production_scope_overrides
    local code=$?
    [[ "$code" == 0 ]] || return "$code"
    python3 - "$SYNC_SCRIPT" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()

def active_block(name):
    match = re.search(r"(?ms)^" + re.escape(name) + r"\(\)\s*\{.*?(?=^[A-Za-z_][A-Za-z0-9_]*\(\)\s*\{|\Z)", text)
    if not match:
        raise SystemExit(f"missing active function: {name}")
    return match.group(0)

canonical = active_block("canonical_trust_home")
bootstrap = active_block("bootstrap_descriptor_table")
active = canonical + "\n" + bootstrap
forbidden = re.compile(r'os\.environ\.get\(["\']HOME["\']\)|realpath\(|pwd\s+-P|cd\s+[^\n]*&&\s*pwd')
synthetic_bad = 'canonical_trust_home() {\n  os.environ.get("HOME")\n}\n'
if not forbidden.search(synthetic_bad):
    raise SystemExit("synthetic HOME fallback was not rejected")
diagnostic_only = "reason=production HOME fallback remains active"
if forbidden.search(diagnostic_only):
    raise SystemExit("diagnostic text was treated as active code")

semantic_patterns = (
    r'uid\s*=\s*["\']\$\(id\s+-u\)["\']',
    r'expected_uid\s*=\s*int\(sys\.argv\[1\]\)',
    r'record\s*=\s*pwd\.getpwuid\(\s*expected_uid\s*\)',
    r'record\.pw_uid\s*!=\s*expected_uid',
    r'not\s+record\.pw_dir',
    r'TRUST_HOME_UNRESOLVED',
)
if forbidden.search(active) or any(not re.search(pattern, active) for pattern in semantic_patterns):
    raise SystemExit("production trust-home active admission contract mismatch")
PY
    return 0
  }

  case_post_auth_descriptor_lifecycle() {
    case_apply_success_and_protections
  }

  case_forged_post_auth_descriptors() {
    case_forged_transaction_markers
  }

  case_post_auth_descriptor_replacement() {
    case_transaction_root_binding_security
  }

  case_fd14_direct_parent() {
    case_custom_report_descriptor_security
  }

  case_ledger_fd18_anchor() {
    case_replay_rejected
  }

  case_descriptor_close_failure() {
    local home report status
    home="$(fixture_case_home)"
    report="$home/close-failure-report"
    set +e
    AGENCY_TEST_DESCRIPTOR_CLOSE_FAILURE=true HOME="$home" PROJECT="$home" "$SYNC_SCRIPT" \
      --home "$home" --project "$home" --test-mode --test-mode-root "$home" --apply \
      --manifest "$(fixture_manifest_path "$home")" --source-root "$(fixture_source_copy "$home")" \
      >"$report" 2>"$home/close-failure-stderr"
    status=$?
    set -e
    [[ "$status" != 0 ]] || return 1
    python3 - "$report" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    lines = [line for line in handle.read().splitlines() if line]
if len(lines) != 1:
    raise SystemExit(1)
report = json.loads(lines[0])
failure = report.get('failure', {})
if report.get('result', {}).get('status') != 'failed' or failure.get('stage') != 'transaction-cleanup' or failure.get('operation') != 'transaction-cleanup':
    raise SystemExit(1)
PY
    if rg -n 'Traceback|FileNotFoundError|eval |2>/dev/null|\|\| true' "$home/close-failure-stderr" >/dev/null 2>&1; then
      return 1
    fi
    rm -rf "$home"
  }

  case_active_descriptor_bootstrap_contract() {
    case_descriptor_admission_contract
  }

  case "$SYNC_TEST_CASE" in
    test-bootstrap-descriptor-persistence)
      run_case "test bootstrap descriptors persist across exec" 0 case_apply_success_and_protections
      ;;
    public-bootstrap-descriptor-persistence)
      run_case "public bootstrap descriptors persist across exec" 0 case_apply_success_and_protections
      ;;
    public-bootstrap-fd-collision)
      run_case "public bootstrap FD collision is rejected" 0 case_active_descriptor_bootstrap_contract
      ;;
    test-bootstrap-fd-collision)
      run_case "test bootstrap FD collision is rejected" 0 case_active_descriptor_bootstrap_contract
      ;;
    forged-initial-bootstrap-origin)
      run_case "forged initial bootstrap origin is rejected" 0 case_active_descriptor_bootstrap_contract
      ;;
    entry-bootstrap-nofollow)
      run_case "entry bootstrap uses no-follow descriptors" 0 case_active_descriptor_bootstrap_contract
      ;;
    production-home-bootstrap)
      run_case "production home bootstrap is fail-closed" 0 case_trust_home_system_resolver
      ;;
    trust-home-system-resolver)
      run_case "production system trust-home resolver is fail-closed" 0 case_trust_home_system_resolver
      ;;
    post-auth-descriptor-lifecycle)
      run_case "post-auth descriptors bind before ledger consumption" 0 case_post_auth_descriptor_lifecycle
      ;;
    forged-post-auth-descriptors)
      run_case "forged post-auth descriptors are rejected" 0 case_forged_post_auth_descriptors
      ;;
    post-auth-descriptor-replacement)
      run_case "post-auth descriptor replacement is fail-closed" 0 case_post_auth_descriptor_replacement
      ;;
    fd14-direct-parent)
      run_case "FD14 remains bound to its direct report parent" 0 case_fd14_direct_parent
      ;;
    ledger-fd18-anchor)
      run_case "ledger uses the FD18 authority anchor" 0 case_ledger_fd18_anchor
      ;;
    descriptor-close-failure)
      run_case "descriptor close failure is structured" 1 case_descriptor_close_failure
      ;;
    active-descriptor-bootstrap-contract)
      run_case "active descriptor bootstrap has no pathname fallback" 0 case_active_descriptor_bootstrap_contract
      ;;
    active-descriptor-call-graph-contract)
      run_case "active descriptor call graph is anchored and fail-closed" 0 case_active_descriptor_call_graph_contract
      ;;
    active-descriptor-close-failure)
      run_case "active descriptor close failures are classified" 0 case_active_descriptor_close_failure
      ;;
    dry-run)
      run_case "dry-run outputs zero-write contract and counts" 0 case_dry_run
      ;;
    dry-run-no-security-layout)
      run_case "dry-run requires no security-root layout" 0 case_dry_run
      ;;
    dry-run-security-sentinels)
      run_case "dry-run does not access malicious security sentinels" 0 case_dry_run_malicious_security_sentinels
      ;;
    dry-run-marker-fd-pollution)
      run_case "dry-run ignores forged transaction and report FD state" 0 case_dry_run_marker_fd_pollution
      ;;
    apply-missing-security-layout)
      run_case "non-dry-run missing security layout is blocked" 0 case_apply_missing_security_layout
      ;;
    missing-role)
      run_case "missing role ID" 0 case_missing_role_id
      ;;
    wrong-role)
      run_case "wrong or unknown role ID" 0 case_wrong_or_unknown_role_id
      ;;
    duplicate-role)
      run_case "duplicate role ID" 0 case_duplicate_role_id
      ;;
    cross-role)
      run_case "cross-platform role set mismatch" 0 case_cross_platform_set_mismatch
      ;;
    aider-section)
      run_case "aider missing section" 0 case_aider_missing_section
      ;;
    windsurf-section)
      run_case "windsurf missing section" 0 case_windsurf_missing_section
      ;;
  qwen-kimi-targets)
    run_case "missing qwen/kimi targets are transactionally created" 0 case_missing_qwen_kimi_targets
    ;;
    ledger-replay)
    run_case "replay must be rejected by ledger" 0 case_replay_rejected
    ;;
    ledger-root-layout)
      run_case "ledger authority root is separate from runtime evidence" 0 case_replay_rejected
      ;;
    ledger-intermediate-race)
      run_case "ledger intermediate replacement is fail-closed" 0 case_ledger_intermediate_race
      ;;
    ledger-in-evidence)
      run_case "ledger under runtime evidence is blocked" 0 case_ledger_root_layout_negative ledger-in-evidence
      ;;
    evidence-authority-colocate)
      run_case "runtime evidence cannot colocate with authority" 0 case_ledger_root_layout_negative evidence-authority-colocate
      ;;
    signer-outside-authority)
      run_case "allowed signers outside authority is blocked" 0 case_ledger_root_layout_negative signer-outside-authority
      ;;
    role-set-file-sha-missing)
      run_case "missing roleSetFileSha256 is BLOCK" 0 case_role_set_file_sha_negative missing "roleSetFileSha256 missing"
      ;;
    role-set-file-sha-malformed)
      run_case "malformed roleSetFileSha256 is BLOCK" 0 case_role_set_file_sha_negative malformed "roleSetFileSha256 malformed"
      ;;
    role-set-file-sha-drift)
      run_case "drifted roleSetFileSha256 is BLOCK" 0 case_role_set_file_sha_negative drift "roleSetFileSha256 mismatch"
      ;;
    cli-missing-values)
      run_case "all value-taking CLI options reject missing values" 0 case_cli_missing_option_values
      ;;
    owner-symlink)
      run_case "owner symlink blocks apply" 0 case_owner_symlink_block
      ;;
    apply-success)
      run_case "apply success, role contract, qwen/kimi paths, and openclaw/auth/vibe protections" 0 case_apply_success_and_protections
      ;;
    rollback-fault)
      run_case "fault injection triggers full rollback" 0 case_rollback_on_failure
      ;;
    d1-openclaw-protected)
      run_case "D1 OpenClaw protected paths receive zero owner access" 0 case_d1_openclaw_protected_owner_preservation
      ;;
    d1-injection-handshake)
      run_case "D1 protected owner access injection handshake" 0 case_d1_owner_access_injection_handshake
      ;;
    helper-arity)
      run_case "snapshot_diff_paths rejects missing arguments without exiting harness" 0 case_snapshot_diff_paths_arity
      ;;
    descriptor-verifier)
      run_case "descriptor verifier distinguishes absent from unsafe intermediates" 0 case_descriptor_snapshot_missing_semantics
      ;;
    d1-fixture-preservation)
      run_case "D1 fixture preserves all manifest target roots" 0 case_d1_fixture_preservation
      ;;
    d1-fifo-helper)
      run_case "D1 fixed auth FIFO helper is descriptor-bound" 0 case_d1_fifo_helper
      ;;
    d2-stdout)
      run_case "D2 help and unknown option emit one machine report" 0 case_d2_stdout_machine_contract
      ;;
    test-root-descriptor)
      run_case "isolated test root is descriptor-bound without path reopen" 0 case_test_root_descriptor_binding
      ;;
    test-root-race-before)
      run_case "test root replacement before bind emits one failed report" 0 case_test_root_descriptor_race before-bind
      ;;
    test-root-race-after)
      run_case "test root replacement after bind emits one failed report" 0 case_test_root_descriptor_race after-bind
      ;;
    production-scope-overrides)
      run_case "production home/project overrides are blocked before mutation" 0 case_production_scope_overrides
      ;;
    test-root-downstream-race)
      run_case "test root replacement before auth is fail-closed" 0 case_test_root_downstream_race
      ;;
    test-root-source-snapshot-race)
      run_case "test root replacement before source snapshot is fail-closed" 0 case_test_root_descriptor_race before-source-snapshot
      ;;
    test-root-file-section-race)
      run_case "whole-file source section read is bound to FD9" 0 case_test_root_descriptor_race before-file-section-count
      ;;
    test-root-evidence-metadata-race)
      run_case "evidence metadata replacement reaches formal evidence validation" 0 case_evidence_ancestry_security
      ;;
    test-root-owner-plan-race)
      run_case "test root replacement before owner plan is fail-closed" 0 case_test_root_descriptor_race before-owner-plan
      ;;
    test-root-directory-metadata-race)
      run_case "directory role metadata is bound to FD9" 0 case_directory_role_metadata_race
      ;;
    test-root-aider-owner-plan-race)
      run_case "Aider whole-file owner plan is bound to FD9" 0 case_test_root_descriptor_race before-aider-owner-plan
      ;;
    test-root-windsurf-owner-plan-race)
      run_case "Windsurf whole-file owner plan is bound to FD9" 0 case_test_root_descriptor_race before-windsurf-owner-plan
      ;;
    test-root-entry-open-failure)
      run_case "entry open failure emits one failed JSON report" 0 case_test_root_entry_failure entry-open-failed
      ;;
    test-root-entry-component-unsafe)
      run_case "entry component unsafe emits one failed JSON report" 0 case_test_root_entry_failure entry-component-unsafe
      ;;
    test-root-entry-leaf-unsafe)
      run_case "entry leaf unsafe emits one failed JSON report" 0 case_test_root_entry_failure entry-leaf-unsafe
      ;;
    test-root-entry-special)
      run_case "entry special file emits one failed JSON report" 0 case_test_root_entry_failure entry-special
      ;;
    test-root-entry-race)
      run_case "entry stat-open race emits one failed JSON report" 0 case_test_root_entry_failure entry-race
      ;;
    test-root-reexec-failure)
      run_case "launcher execve failure emits one failed JSON report" 0 case_test_root_entry_failure reexec-failed
      ;;
    test-root-fd9-collision)
      run_case "preoccupied FD9 fails with one JSON report" 0 case_test_root_fd_collision 9
      ;;
    test-root-fd10-collision)
      run_case "preoccupied FD10 fails with one JSON report" 0 case_test_root_fd_collision 10
      ;;
    test-root-fd11-collision)
      run_case "preoccupied FD11 fails with one JSON report" 0 case_test_root_fd_collision 11
      ;;
    test-root-fd-all-collision)
      run_case "preoccupied FD9/10/11 fail with one JSON report" 0 case_test_root_fd_collision 9-10-11
      ;;
    custom-report-security)
      run_case "custom report parent is descriptor-bound" 0 case_custom_report_descriptor_security
      ;;
    transaction-root-race)
      run_case "transaction root initial bind is descriptor-bound" 0 case_transaction_root_binding_security
      ;;
    forged-transaction-markers)
      run_case "forged transaction markers fail before authorization" 0 case_forged_transaction_markers
      ;;
    launcher-origin-proof)
      run_case "launcher origin proof is fresh and single-use" 0 case_launcher_origin_proof_admission
      ;;
    descriptor-admission-contract)
      run_case "descriptor admission rejects legacy trust fallbacks" 0 case_descriptor_admission_contract
      ;;
    evidence-seam-isolation)
      run_case "production evidence replacement seam is unreachable" 0 case_evidence_seam_isolation
      ;;
    evidence-ancestry)
      run_case "production evidence ancestry is descriptor-bound" 0 case_evidence_ancestry_security
      ;;
    descriptor-boundaries)
      run_case "evidence and transaction cleanup remain descriptor-bound" 0 case_descriptor_boundary_contract
      ;;
    *)
      echo "FAIL: unknown focused sync case: ${SYNC_TEST_CASE}"
      exit 2
      ;;
  esac
  if [[ "$SYNC_TEST_CASE" == rollback-fault ]]; then
    harness_marker summary-start "$FAIL" 0
  fi
  printf 'TOTAL=%s\nPASS=%s\nFAIL=%s\n' "$TOTAL" "$PASS" "$FAIL"
  if [[ "$SYNC_TEST_CASE" == rollback-fault ]]; then
    harness_marker summary-end "$FAIL" 0
  fi
  if [[ "$FAIL" -gt 0 ]]; then
    echo 'RC=1'
    exit 1
  fi
  echo 'RC=0'
  exit 0
fi

run_case "dry-run outputs zero-write contract and counts" 0 case_dry_run
run_case "apply success, role contract, qwen/kimi paths, and openclaw/auth/vibe protections" 0 case_apply_success_and_protections
run_case "missing role ID" 0 case_missing_role_id
run_case "wrong or unknown role ID" 0 case_wrong_or_unknown_role_id
run_case "duplicate role ID" 0 case_duplicate_role_id
run_case "cross-platform role set mismatch" 0 case_cross_platform_set_mismatch
run_case "aider missing section" 0 case_aider_missing_section
run_case "windsurf missing section" 0 case_windsurf_missing_section
run_case "missing qwen/kimi targets are transactionally created" 0 case_missing_qwen_kimi_targets
run_case "missing qwen source is BLOCK" 0 case_missing_qwen_or_kimi_source_is_blocked qwen
run_case "missing kimi source is BLOCK" 0 case_missing_qwen_or_kimi_source_is_blocked kimi
run_case "replay must be rejected by ledger" 0 case_replay_rejected
run_case "wrong namespace rejected" 0 case_wrong_namespace
run_case "wrong principal rejected" 0 case_wrong_principal
run_case "owner symlink blocks apply" 0 case_owner_symlink_block
run_case "fault injection triggers full rollback" 0 case_rollback_on_failure

printf 'TOTAL=%s\nPASS=%s\nFAIL=%s\n' "$TOTAL" "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  echo 'RC=1'
  exit 1
fi
echo 'RC=0'
