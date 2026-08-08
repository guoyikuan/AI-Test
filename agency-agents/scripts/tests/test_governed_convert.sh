#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
TEST_ROOT="$(mktemp -d)"
chmod 700 "$TEST_ROOT"
OUT="$TEST_ROOT/out"
MANIFEST="$OUT/manifest.json"
MANIFEST_BASELINE="$TEST_ROOT/manifest.baseline"
FAIL_OUT="$TEST_ROOT/fail-out"
FAIL_BIN="$TEST_ROOT/fail-bin"
SOURCE_COPY="$TEST_ROOT/source-copy"
REAL_SOURCE_BASELINE="$TEST_ROOT/real-source.before"
REAL_SOURCE_AFTER="$TEST_ROOT/real-source.after"
BAD_RENDER_STDOUT="$TEST_ROOT/bad-render.stdout"
BAD_RENDER_STDERR="$TEST_ROOT/bad-render.stderr"
BAD_CONVERT_STDOUT="$TEST_ROOT/bad-convert.stdout"
BAD_CONVERT_STDERR="$TEST_ROOT/bad-convert.stderr"
mkdir -m 700 "$OUT" "$FAIL_OUT" "$FAIL_BIN"
BAD_SOURCE=""
cleanup() {
  local status=$?
  local cleanup_status=0
  if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" ]]; then
    rm -rf -- "$TEST_ROOT" || cleanup_status=$?
  fi
  if [[ "$cleanup_status" -ne 0 ]]; then
    printf 'isolated test-root cleanup failed\n' >&2
    [[ "$status" -eq 0 ]] && status="$cleanup_status"
  fi
  exit "$status"
}
trap cleanup EXIT

snapshot_source_tree() {
  local source_root="$1" snapshot="$2"
  python3 - "$source_root" "$snapshot" <<'PY'
from hashlib import sha256
from pathlib import Path
import sys

root = Path(sys.argv[1])
output = Path(sys.argv[2])
categories = (
    "academic", "design", "engineering", "finance", "game-development",
    "gis", "healthcare", "marketing", "paid-media", "product", "project-management",
    "sales", "security", "spatial-computing", "specialized", "support", "testing",
)
records = []
for category in categories:
    category_path = root / category
    if category_path.is_symlink() or not category_path.is_dir():
        raise SystemExit(f"invalid source category: {category}")
    for path in sorted(category_path.rglob("*.md")):
        if path.is_symlink() or not path.is_file():
            raise SystemExit(f"invalid source file: {category}")
        relative = path.relative_to(root).as_posix()
        digest = sha256(path.read_bytes()).hexdigest()
        records.append((relative, digest))

records.sort()
with output.open("w", encoding="ascii", newline="\n") as handle:
    for relative, digest in records:
        handle.write(f"{relative}\t{digest}\n")
PY
}

snapshot_source_tree "$ROOT" "$REAL_SOURCE_BASELINE"
REAL_SOURCE_COUNT="$(wc -l < "$REAL_SOURCE_BASELINE" | tr -d ' ')"

./scripts/convert.sh --tool all --out "$OUT" --parallel --jobs 8
python3 scripts/governance.py manifest \
  --root "$OUT" \
  --output "$MANIFEST"
cp "$MANIFEST" "$MANIFEST_BASELINE"
python3 scripts/governance.py manifest \
  --root "$OUT" \
  --output "$MANIFEST"
cmp "$MANIFEST_BASELINE" "$MANIFEST"
python3 scripts/governance.py verify-generated \
  --repo-root . \
  --generated-root "$OUT" \
  --expected-agents 269 \
  --expected-tools 16
python3 scripts/governance.py render-governance \
  --repo-root . \
  --agent engineering/engineering-frontend-developer.md \
  >/dev/null

AGENTS_SOURCE="engineering/engineering-frontend-developer.md"
AGENT_NAME="$(python3 - "$AGENTS_SOURCE" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding='utf-8')
for line in text.splitlines():
    if line.startswith('name: '):
        print(line.split(': ', 1)[1].strip())
        break
PY
)"
AGENT_SLUG="$(python3 - "$AGENT_NAME" <<'PY'
import re,sys
name = sys.argv[1].lower()
print(re.sub(r'[^a-z0-9]+', '-', name).strip('-'))
PY
)"

EXPECTED_GOVERNANCE="$({
  python3 scripts/governance.py render-governance --repo-root . --agent "$AGENTS_SOURCE"
})"
EXPECTED_SOUL="$(awk 'BEGIN{fm=0} /^---$/ && fm<2{fm++; next} fm>=2{print}' "$AGENTS_SOURCE")"

if [[ "$AGENT_NAME" == "" ]]; then
  echo "missing test fixture name: $AGENTS_SOURCE" >&2
  exit 1
fi

ACTUAL_GOVERNANCE="$(cat "$OUT/openclaw/$AGENT_SLUG/AGENTS.md")"
ACTUAL_SOUL="$(cat "$OUT/openclaw/$AGENT_SLUG/SOUL.md")"
if [[ "$EXPECTED_GOVERNANCE" != "$ACTUAL_GOVERNANCE" ]]; then
  echo "OpenClaw AGENTS mismatch for $AGENT_SLUG" >&2
  exit 1
fi
if [[ "$EXPECTED_SOUL" != "$ACTUAL_SOUL" ]]; then
  echo "OpenClaw SOUL mismatch for $AGENT_SLUG" >&2
  exit 1
fi

assert_conversion_dependency_failure() {
  local command_name="$1"
  local command_path="$FAIL_BIN/$command_name"
  cat > "$command_path" <<'EOF'
#!/bin/sh
exit 37
EOF
  chmod +x "$command_path"
  set +e
  PATH="$FAIL_BIN:$PATH" ./scripts/convert.sh \
    --tool openclaw \
    --out "$FAIL_OUT/$command_name" \
    >/dev/null 2>&1
  local status=$?
  set -e
  rm -f "$command_path"
  if [[ "$status" -eq 0 ]]; then
    echo "Expected $command_name failure to propagate from source freeze" >&2
    exit 1
  fi
}

assert_conversion_dependency_failure find
assert_conversion_dependency_failure head
assert_conversion_dependency_failure awk

mkdir -m 700 "$SOURCE_COPY"
cp -R "$ROOT/." "$SOURCE_COPY/"
chmod -R go-rwx "$SOURCE_COPY"
BAD_SOURCE="$(mktemp "$SOURCE_COPY/engineering/.bad-openclaw-XXXX.md")"
BAD_AGENT_REL="${BAD_SOURCE#$SOURCE_COPY/}"
BAD_EXPECTED="MISMATCHED_GOVERNANCE_BINDING:$BAD_AGENT_REL"
cat > "$BAD_SOURCE" <<'EOF'
---
name: Broken OpenClaw Fixture
description: Broken openclaw fixture for fail-closed test
governance_profile: missing-governance-profile
---
Only body text.
EOF

set +e
python3 "$SOURCE_COPY/scripts/governance.py" render-governance \
  --repo-root "$SOURCE_COPY" \
  --agent "$BAD_AGENT_REL" \
  >"$BAD_RENDER_STDOUT" 2>"$BAD_RENDER_STDERR"
SET_STATUS=$?
set -e
if [[ "$SET_STATUS" -eq 0 ]]; then
  echo "Expected governance render to fail for broken source fixture" >&2
  exit 1
fi

set +e
"$SOURCE_COPY/scripts/convert.sh" --tool openclaw --out "$FAIL_OUT" \
  >"$BAD_CONVERT_STDOUT" 2>"$BAD_CONVERT_STDERR"
CONVERT_STATUS=$?
set -e
if [[ "$CONVERT_STATUS" -eq 0 ]]; then
  echo "Expected openclaw conversion failure propagation, got $CONVERT_STATUS" >&2
  exit 1
fi

if ! grep -Fq -- "$BAD_EXPECTED" "$BAD_CONVERT_STDERR" \
  && ! grep -Fq -- "$BAD_EXPECTED" "$BAD_CONVERT_STDOUT"; then
  echo "Expected exact governance binding mismatch for isolated fixture" >&2
  exit 1
fi

snapshot_source_tree "$ROOT" "$REAL_SOURCE_AFTER"
REAL_SOURCE_AFTER_COUNT="$(wc -l < "$REAL_SOURCE_AFTER" | tr -d ' ')"
if [[ "$REAL_SOURCE_COUNT" != "$REAL_SOURCE_AFTER_COUNT" ]] \
  || ! cmp -s "$REAL_SOURCE_BASELINE" "$REAL_SOURCE_AFTER"; then
  echo "Real Agency source tree changed during governed conversion test" >&2
  exit 1
fi

printf 'TOTAL=2 PASS=2 FAIL=0\n'
