#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

AGENCY269_M1_VERSION='M1-launcher-bootstrap-v1'
AGENCY269_ORIGIN_CONSUMED='0'
AGENCY269_ORIGIN_ACKED='0'
AGENCY269_ORIGIN_PROOF=''
AGENCY269_ORIGIN_CHALLENGE=''
AGENCY269_CHILD_ARGS=()
AGENCY269_REST_ARGS=()
AGENCY269_MODE=''
AGENCY269_CLI_TERMINAL=''
AGENCY269_ENTRY_PATH=''
AGENCY269_SOURCE_PATH=''
AGENCY269_PROJECT_PATH=''
AGENCY269_SYSTEM_HOME_PATH=''
AGENCY269_TEST_ROOT_PATH=''
AGENCY269_MANIFEST_PATH=''
AGENCY269_REPORT_PATH=''
AGENCY269_ACTION_PATH=''
AGENCY269_SIGNATURE_PATH=''
AGENCY269_ALLOWED_SIGNERS_PATH=''
AGENCY269_LEDGER_PATH=''
AGENCY269_ENTRY_DIGEST=''
AGENCY269_ARGV_DIGEST=''
AGENCY269_SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/$(basename "${BASH_SOURCE[0]}")"

agency269_failure_json() {
  local stage="$1" reason="$2" operation="$3" rc="$4" mode="${5:-${AGENCY269_MODE:-unknown}}"
  python3 - "$stage" "$reason" "$operation" "$rc" "$mode" <<'PY'
import json
import sys

stage, reason, operation, rc, mode = sys.argv[1:]
body = {
    "schema": "agency-agents.bootstrap-failure/v1",
    "module": "M1",
    "result": {"status": "failed", "rc": int(rc)},
    "failure": {
        "stage": stage,
        "reason": reason,
        "operation": operation,
        "rc": int(rc),
    },
    "bootstrap": {
        "phase": "initial" if stage in ("cli", "test-root-admission", "entry-admission", "descriptor-admission") else "post-auth",
        "mode": mode,
        "initial_forbidden_occupancy": [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21],
        "fixed_descriptors": {
            "FD9": "test-root",
            "FD10": "entry-execution",
            "FD11": "entry-validation",
            "FD15": "origin-channel",
            "FD16": "source",
            "FD17": "repo-project",
            "FD18": "system-home",
        },
        "transaction_logic": "owned-by-M3",
    },
    "evidence_item_ids": [
        "M1-CLI-001",
        "M1-ENTRY-001",
        "M1-FD9-001",
        "M1-FD15-001",
        "M1-ORIGIN-001",
    ],
}
print(json.dumps(body, sort_keys=True, separators=(",", ":")))
PY
}

agency269_fail() {
  local rc="$4"
  agency269_failure_json "$1" "$2" "$3" "$4" "${5:-${AGENCY269_MODE:-unknown}}"
  return "$rc"
}

agency269_hash_argv() {
  python3 - "$@" <<'PY'
import hashlib
import sys
print(hashlib.sha256(b"\0".join(x.encode("utf-8", "surrogateescape") for x in sys.argv[1:])).hexdigest())
PY
}

agency269_fd_open() {
  local fd="$1"
  python3 - "$fd" <<'PY'
import os
import sys
try:
    os.fstat(int(sys.argv[1]))
except OSError:
    raise SystemExit(1)
PY
}

agency269_assert_initial_fd_layout() {
  local fd
  for fd in 9 10 11 12 13 14 15 16 17 18 19 20 21; do
    if agency269_fd_open "$fd" >/dev/null 2>&1; then
      agency269_fail "descriptor-admission" "initial descriptor occupied" "initial-fd-occupancy" 66
      return $?
    fi
  done
}

agency269_descriptor_receipts() {
  python3 - <<'PY'
import hashlib
import json
import os
import stat

roles = {
    9: "test-root",
    10: "entry-execution",
    11: "entry-validation",
    15: "origin-channel",
    16: "source",
    17: "repo-project",
    18: "system-home",
}

def one(fd, role):
    before = os.fstat(fd)
    offset_before = "not-applicable"
    try:
        offset_before = os.lseek(fd, 0, os.SEEK_CUR)
    except OSError as exc:
        if fd in (10, 11):
            raise OSError("entry offset unavailable before pread") from exc
    digest = None
    if fd in (10, 11):
        h = hashlib.sha256()
        offset = 0
        while offset < before.st_size:
            chunk = os.pread(fd, min(1024 * 1024, before.st_size - offset), offset)
            if not chunk:
                break
            h.update(chunk)
            offset += len(chunk)
        if offset != before.st_size:
            raise OSError("entry short read")
        digest = h.hexdigest()
    after = os.fstat(fd)
    identity_before = (before.st_dev, before.st_ino, before.st_mode, before.st_uid, before.st_size, before.st_mtime_ns, before.st_ctime_ns)
    identity_after = (after.st_dev, after.st_ino, after.st_mode, after.st_uid, after.st_size, after.st_mtime_ns, after.st_ctime_ns)
    if identity_before != identity_after:
        raise OSError("descriptor identity changed")
    offset_after = "not-applicable"
    try:
        offset_after = os.lseek(fd, 0, os.SEEK_CUR)
    except OSError as exc:
        if fd in (10, 11):
            raise OSError("entry offset unavailable after pread") from exc
    if fd in (10, 11) and offset_before != offset_after:
        raise OSError("entry offset changed")
    return {
        "fd": fd,
        "role": role,
        "dev": before.st_dev,
        "ino": before.st_ino,
        "mode": format(stat.S_IMODE(before.st_mode), "04o"),
        "kind": stat.S_IFMT(before.st_mode),
        "uid": before.st_uid,
        "size": before.st_size,
        "entry_digest": digest,
        "offset_before": offset_before,
        "offset_after": offset_after,
    }

receipts = [one(fd, role) for fd, role in roles.items()]
by_fd = {item["fd"]: item for item in receipts}
if (by_fd[10]["dev"], by_fd[10]["ino"]) != (by_fd[11]["dev"], by_fd[11]["ino"]):
    raise OSError("entry descriptors do not identify the same leaf")
if by_fd[10]["entry_digest"] != by_fd[11]["entry_digest"]:
    raise OSError("entry descriptor digests differ")
if not stat.S_ISREG(os.fstat(10).st_mode) or not stat.S_ISREG(os.fstat(11).st_mode):
    raise OSError("entry descriptor is not regular")
print(json.dumps(receipts, sort_keys=True, separators=(",", ":")))
PY
}

agency269_fd11_sha256() {
  python3 - <<'PY'
import hashlib
import os
import stat

before = os.fstat(11)
if not stat.S_ISREG(before.st_mode):
    raise SystemExit(1)
offset_before = os.lseek(11, 0, os.SEEK_CUR)
digest = hashlib.sha256()
position = 0
while position < before.st_size:
    block = os.pread(11, min(1024 * 1024, before.st_size - position), position)
    if not block:
        raise SystemExit(1)
    digest.update(block)
    position += len(block)
after = os.fstat(11)
if (before.st_dev, before.st_ino, before.st_mode, before.st_uid, before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_dev, after.st_ino, after.st_mode, after.st_uid, after.st_size, after.st_mtime_ns, after.st_ctime_ns):
    raise SystemExit(1)
if os.lseek(11, 0, os.SEEK_CUR) != offset_before:
    raise SystemExit(1)
print(digest.hexdigest())
PY
}

agency269_bind_authorized_entry_sha() {
  local manifest_entry_sha="$1" authorization_entry_sha="$2" fd11_sha
  [[ "$manifest_entry_sha" =~ ^[0-9a-f]{64}$ ]] || { agency269_fail "entry-admission" "manifest entrySha256 malformed" "entry-sha-binding" 66; return $?; }
  [[ "$authorization_entry_sha" =~ ^[0-9a-f]{64}$ ]] || { agency269_fail "entry-admission" "authorization entrypoint_sha malformed" "entry-sha-binding" 66; return $?; }
  fd11_sha="$(agency269_fd11_sha256 2>/dev/null)" || { agency269_fail "entry-admission" "FD11 entry SHA unavailable" "entry-sha-binding" 66; return $?; }
  if [[ "$fd11_sha" != "$manifest_entry_sha" || "$fd11_sha" != "$authorization_entry_sha" ]]; then
    agency269_fail "entry-admission" "entry SHA binding mismatch" "entry-sha-binding" 66
    return $?
  fi
  AGENCY269_ENTRY_DIGEST="$fd11_sha"
  export AGENCY269_ENTRY_DIGEST
}

agency269_fixed_entry_exec() {
  local entry="$1" source="$2" project="$3" system_home="$4" test_root="$5" mode="$6"
  shift 6
  local rc
  set +e
  python3 - "$entry" "$source" "$project" "$system_home" "$test_root" "$mode" -- "$@" <<'PY'
import errno
import hashlib
import json
import os
import secrets
import socket
import stat
import sys

entry, source, project, system_home, test_root, mode = sys.argv[1:7]
marker = sys.argv[7]
child_args = sys.argv[8:]


def fail(stage, reason, operation, rc):
    body = {
        "schema": "agency-agents.bootstrap-failure/v1",
        "module": "M1",
        "result": {"status": "failed", "rc": rc},
        "failure": {"stage": stage, "reason": reason, "operation": operation, "rc": rc},
        "bootstrap": {
            "phase": "initial",
            "mode": mode,
            "initial_forbidden_occupancy": [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21],
            "fixed_descriptors": {"FD9": "test-root", "FD10": "entry-execution", "FD11": "entry-validation", "FD15": "origin-channel", "FD16": "source", "FD17": "repo-project", "FD18": "system-home"},
            "transaction_logic": "owned-by-M3",
        },
        "evidence_item_ids": ["M1-CLI-001", "M1-ENTRY-001", "M1-FD9-001", "M1-FD15-001", "M1-ORIGIN-001"],
    }
    print(json.dumps(body, sort_keys=True, separators=(",", ":")))
    raise SystemExit(rc)


def safe_absolute(value):
    if not value.startswith("/") or value == "/":
        raise ValueError("absolute non-root path required")
    parts = value.split("/")[1:]
    if not parts or any(not p or p in (".", "..") for p in parts):
        raise ValueError("unsafe path component")
    return parts


def open_dir(value):
    safe_absolute(value)
    fd = os.open(value, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    st = os.fstat(fd)
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) != 0o700:
        os.close(fd)
        raise ValueError("directory admission failed")
    return fd


def open_entry(value):
    parts = safe_absolute(value)
    if len(parts) < 2:
        raise ValueError("entry parent required")
    parent = value.rsplit("/", 1)[0]
    parent_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    parent_st = os.fstat(parent_fd)
    if not stat.S_ISDIR(parent_st.st_mode):
        os.close(parent_fd)
        raise ValueError("entry parent is not a directory")
    execution_fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW, dir_fd=parent_fd)
    validation_fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW, dir_fd=parent_fd)
    execution_st = os.fstat(execution_fd)
    validation_st = os.fstat(validation_fd)
    if not stat.S_ISREG(execution_st.st_mode) or not stat.S_ISREG(validation_st.st_mode) or execution_st.st_uid != os.getuid() or validation_st.st_uid != os.getuid():
        os.close(execution_fd)
        os.close(validation_fd)
        os.close(parent_fd)
        raise ValueError("entry leaf admission failed")
    if (execution_st.st_dev, execution_st.st_ino) != (validation_st.st_dev, validation_st.st_ino):
        os.close(execution_fd)
        os.close(validation_fd)
        os.close(parent_fd)
        raise ValueError("entry leaf identity mismatch")
    os.close(parent_fd)
    return execution_fd, validation_fd


def hash_entry(fd, size):
    digest = hashlib.sha256()
    offset = 0
    while offset < size:
        block = os.pread(fd, min(1024 * 1024, size - offset), offset)
        if not block:
            raise ValueError("entry short read")
        digest.update(block)
        offset += len(block)
    return digest.hexdigest()


def descriptor(fd, role, digest=None):
    st = os.fstat(fd)
    return {"fd": fd, "role": role, "dev": st.st_dev, "ino": st.st_ino, "mode": format(stat.S_IMODE(st.st_mode), "04o"), "kind": stat.S_IFMT(st.st_mode), "uid": st.st_uid, "size": st.st_size, "entry_digest": digest}

try:
    for fd in range(9, 22):
        try:
            os.fstat(fd)
        except OSError as exc:
            if exc.errno != errno.EBADF:
                fail("descriptor-admission", "initial descriptor probe failed", "initial-fd-occupancy", 66)
            continue
        fail("descriptor-admission", "initial descriptor occupied", "initial-fd-occupancy", 66)
    if marker != "--":
        fail("cli", "internal argument delimiter missing", "fixed-entry-argument-contract", 64)
    if mode == "test" and not test_root:
        fail("test-root-admission", "test root is required", "test-root-binding", 65)
    if mode != "test" and test_root:
        fail("test-root-admission", "test root supplied outside test mode", "test-root-binding", 65)

    root_fd = None
    if mode == "test":
        root_fd = open_dir(test_root)
        os.dup2(root_fd, 9)
        os.set_inheritable(9, True)
        if root_fd != 9:
            os.close(root_fd)
    entry_fd, validation_fd = open_entry(entry)
    os.dup2(entry_fd, 10)
    os.dup2(validation_fd, 11)
    os.set_inheritable(10, True)
    os.set_inheritable(11, True)
    if entry_fd not in (10, 11):
        os.close(entry_fd)
    if validation_fd not in (10, 11):
        os.close(validation_fd)

    source_fd = open_dir(source)
    project_fd = open_dir(project)
    home_fd = open_dir(system_home)
    os.dup2(source_fd, 16)
    os.dup2(project_fd, 17)
    os.dup2(home_fd, 18)
    for fd in (16, 17, 18):
        os.set_inheritable(fd, True)
    for fd in (source_fd, project_fd, home_fd):
        if fd not in (16, 17, 18):
            os.close(fd)

    origin_a, origin_b = socket.socketpair()
    os.dup2(origin_a.fileno(), 15)
    os.set_inheritable(15, True)
    os.set_inheritable(origin_b.fileno(), True)
    peer_fd = origin_b.fileno()
    execution_stat_before = os.fstat(10)
    validation_stat_before = os.fstat(11)
    if not stat.S_ISREG(execution_stat_before.st_mode) or not stat.S_ISREG(validation_stat_before.st_mode):
        fail("entry-admission", "entry descriptors are not regular", "entry-binding", 66)
    if (execution_stat_before.st_dev, execution_stat_before.st_ino) != (validation_stat_before.st_dev, validation_stat_before.st_ino):
        fail("entry-admission", "entry descriptor identity mismatch", "entry-binding", 66)
    execution_offset = os.lseek(10, 0, os.SEEK_CUR)
    validation_offset = os.lseek(11, 0, os.SEEK_CUR)
    execution_digest = hash_entry(10, execution_stat_before.st_size)
    entry_digest = hash_entry(11, validation_stat_before.st_size)
    execution_stat_after = os.fstat(10)
    validation_stat_after = os.fstat(11)
    if (execution_stat_before.st_dev, execution_stat_before.st_ino, execution_stat_before.st_mode, execution_stat_before.st_uid, execution_stat_before.st_size, execution_stat_before.st_mtime_ns, execution_stat_before.st_ctime_ns) != (execution_stat_after.st_dev, execution_stat_after.st_ino, execution_stat_after.st_mode, execution_stat_after.st_uid, execution_stat_after.st_size, execution_stat_after.st_mtime_ns, execution_stat_after.st_ctime_ns):
        fail("entry-admission", "FD10 entry identity changed during hashing", "entry-hash-pread", 66)
    if (validation_stat_before.st_dev, validation_stat_before.st_ino, validation_stat_before.st_mode, validation_stat_before.st_uid, validation_stat_before.st_size, validation_stat_before.st_mtime_ns, validation_stat_before.st_ctime_ns) != (validation_stat_after.st_dev, validation_stat_after.st_ino, validation_stat_after.st_mode, validation_stat_after.st_uid, validation_stat_after.st_size, validation_stat_after.st_mtime_ns, validation_stat_after.st_ctime_ns):
        fail("entry-admission", "FD11 entry identity changed during hashing", "entry-hash-pread", 66)
    if execution_digest != entry_digest:
        fail("entry-admission", "entry descriptor digests differ", "entry-sha-binding", 66)
    if os.lseek(10, 0, os.SEEK_CUR) != execution_offset:
        fail("entry-admission", "entry offset changed during hashing", "entry-hash-pread", 66)
    if os.lseek(11, 0, os.SEEK_CUR) != validation_offset:
        fail("entry-admission", "validation offset changed during hashing", "entry-hash-pread", 66)
    argv_digest = hashlib.sha256(b"\0".join(x.encode("utf-8", "surrogateescape") for x in child_args)).hexdigest()
    receipts = [descriptor(9, "test-root")] if mode == "test" else []
    receipts.extend([descriptor(10, "entry-execution", execution_digest), descriptor(11, "entry-validation", entry_digest), descriptor(15, "origin-channel"), descriptor(16, "source"), descriptor(17, "repo-project"), descriptor(18, "system-home")])
    challenge = {
        "schema": "agency-agents.origin-challenge/v1",
        "phase": "initial",
        "nonce": secrets.token_hex(32),
        "pid": os.getpid(),
        "argv_sha256": argv_digest,
        "entry_sha256": entry_digest,
        "descriptor_receipts": receipts,
        "single_use": True,
        "consumed": False,
    }
    env = os.environ.copy()
    env.update({
        "AGENCY269_REEXEC": "1",
        "AGENCY269_ENTRY_DIGEST": entry_digest,
        "AGENCY269_ARGV_DIGEST": argv_digest,
        "AGENCY269_ORIGIN_INITIAL": json.dumps(challenge, sort_keys=True, separators=(",", ":")),
        "AGENCY269_ORIGIN_PEER_FD": str(peer_fd),
        "AGENCY269_ENTRY_FD": "10",
        "AGENCY269_ENTRY_VALIDATION_FD": "11",
        "AGENCY269_TEST_ROOT_FD": "9" if mode == "test" else "",
        "AGENCY269_SOURCE_FD": "16",
        "AGENCY269_PROJECT_FD": "17",
        "AGENCY269_SYSTEM_HOME_FD": "18",
    })
    child = ["bash", "/dev/fd/10"] + child_args
    os.execve("/bin/bash", child, env)
except SystemExit:
    raise
except (OSError, ValueError, TypeError) as exc:
    text = str(exc)
    if "entry" in text:
        fail("entry-admission", text, "entry-binding", 66)
    if "root" in text:
        fail("test-root-admission", text, "test-root-binding", 65)
    fail("descriptor-admission", text, "fixed-descriptor-binding", 66)
PY
  rc=$?
  set -e
  return "$rc"
}

agency269_validate_initial_origin() {
  local expected_argv="$1"
  python3 - "$expected_argv" "${AGENCY269_ORIGIN_INITIAL:-}" "${AGENCY269_ENTRY_DIGEST:-}" <<'PY'
import hashlib
import json
import os
import sys

expected_argv, raw, entry_digest = sys.argv[1:]
try:
    challenge = json.loads(raw)
    if challenge.get("schema") != "agency-agents.origin-challenge/v1" or challenge.get("phase") != "initial":
        raise ValueError("initial origin schema")
    if challenge.get("single_use") is not True or challenge.get("consumed") is not False:
        raise ValueError("initial origin single-use state")
    if challenge.get("pid") != os.getpid():
        raise ValueError("origin pid mismatch")
    if challenge.get("argv_sha256") != expected_argv:
        raise ValueError("origin argv mismatch")
    if challenge.get("entry_sha256") != entry_digest:
        raise ValueError("origin entry digest mismatch")
    execution_st = os.fstat(10)
    validation_st = os.fstat(11)
    if not __import__("stat").S_ISREG(execution_st.st_mode) or not __import__("stat").S_ISREG(validation_st.st_mode):
        raise ValueError("entry descriptor invalid")
    if (execution_st.st_dev, execution_st.st_ino) != (validation_st.st_dev, validation_st.st_ino):
        raise ValueError("entry descriptor identity mismatch")
    digest = hashlib.sha256()
    position = 0
    validation_offset = os.lseek(11, 0, os.SEEK_CUR)
    while position < validation_st.st_size:
        block = os.pread(11, min(1024 * 1024, validation_st.st_size - position), position)
        if not block:
            raise ValueError("entry validation short read")
        digest.update(block)
        position += len(block)
    if os.lseek(11, 0, os.SEEK_CUR) != validation_offset or digest.hexdigest() != entry_digest:
        raise ValueError("entry validation digest mismatch")
except (ValueError, TypeError, json.JSONDecodeError, OSError) as exc:
    print(str(exc), file=sys.stderr)
    raise SystemExit(1)
PY
}

agency269_origin_write() {
  local message="$1"
  if ! agency269_fd_open 15 >/dev/null 2>&1; then
    agency269_fail "origin" "origin channel unavailable" "origin-channel-write" 67
    return $?
  fi
  if ! python3 - "$message" <<'PY'
import os
import sys
payload = sys.argv[1].encode("utf-8", "strict") + b"\n"
try:
    total = 0
    while total < len(payload):
        total += os.write(15, payload[total:])
except OSError:
    raise SystemExit(1)
PY
  then
    agency269_fail "origin" "origin channel write failed" "origin-channel-write" 67
    return $?
  fi
}

agency269_origin_challenge() {
  local phase="$1"
  case "$phase" in
    initial|post-auth) ;;
    *) agency269_fail "origin" "unsupported origin phase" "origin-challenge" 67; return $? ;;
  esac
  local receipts
  receipts="$(agency269_descriptor_receipts 2>/dev/null)" || { agency269_fail "origin" "descriptor receipt failed" "origin-descriptor-receipt" 66; return $?; }
  AGENCY269_ORIGIN_CHALLENGE="$(python3 - "$phase" "${AGENCY269_ARGV_DIGEST:-}" "${AGENCY269_ENTRY_DIGEST:-}" "$receipts" <<'PY'
import json
import os
import secrets
import sys
phase, argv_sha, entry_sha, receipts = sys.argv[1:]
body = {
    "schema": "agency-agents.origin-challenge/v1",
    "phase": phase,
    "nonce": secrets.token_hex(32),
    "pid": os.getpid(),
    "argv_sha256": argv_sha,
    "entry_sha256": entry_sha,
    "descriptor_receipts": json.loads(receipts),
    "single_use": True,
    "consumed": False,
}
print(json.dumps(body, sort_keys=True, separators=(",", ":")))
PY
)" || { agency269_fail "origin" "origin challenge construction failed" "origin-challenge" 67; return $?; }
  AGENCY269_ORIGIN_CONSUMED='0'
  AGENCY269_ORIGIN_ACKED='0'
  AGENCY269_ORIGIN_PROOF=''
  agency269_origin_write "$AGENCY269_ORIGIN_CHALLENGE"
}

agency269_origin_proof() {
  local proof="$1"
  if [[ -z "$AGENCY269_ORIGIN_CHALLENGE" ]]; then
    agency269_fail "origin" "origin challenge is absent" "origin-proof" 67
    return $?
  fi
  if [[ "$AGENCY269_ORIGIN_CONSUMED" != '0' ]]; then
    agency269_fail "origin" "origin challenge already consumed" "origin-proof" 67
    return $?
  fi
  if ! python3 - "$AGENCY269_ORIGIN_CHALLENGE" "$proof" "${AGENCY269_ENTRY_DIGEST:-}" "${AGENCY269_ARGV_DIGEST:-}" <<'PY'
import json
import os
import sys
challenge = json.loads(sys.argv[1])
proof = json.loads(sys.argv[2])
entry_sha, argv_sha = sys.argv[3:]
checks = [
    proof.get("schema") == "agency-agents.origin-proof/v1",
    proof.get("phase") == challenge.get("phase"),
    proof.get("nonce") == challenge.get("nonce"),
    proof.get("pid") == os.getpid() == challenge.get("pid"),
    proof.get("argv_sha256") == argv_sha == challenge.get("argv_sha256"),
    proof.get("entry_sha256") == entry_sha == challenge.get("entry_sha256"),
    proof.get("descriptor_receipts") == challenge.get("descriptor_receipts"),
]
if not all(checks):
    raise SystemExit(1)
PY
  then
    agency269_fail "origin" "origin proof mismatch" "origin-proof" 67
    return $?
  fi
  AGENCY269_ORIGIN_PROOF="$proof"
  agency269_origin_write "$proof"
}

agency269_origin_consume() {
  if [[ -z "$AGENCY269_ORIGIN_PROOF" ]]; then
    agency269_fail "origin" "origin proof is absent" "origin-consume" 67
    return $?
  fi
  if [[ "$AGENCY269_ORIGIN_CONSUMED" != '0' ]]; then
    agency269_fail "origin" "origin proof replay" "origin-consume" 67
    return $?
  fi
  AGENCY269_ORIGIN_CONSUMED='1'
  local receipt
  receipt="$(python3 - "${AGENCY269_ORIGIN_CHALLENGE}" <<'PY'
import json
import sys
challenge = json.loads(sys.argv[1])
challenge["consumed"] = True
challenge["consume_pid"] = __import__("os").getpid()
print(json.dumps({"schema": "agency-agents.origin-consume/v1", "phase": challenge["phase"], "nonce": challenge["nonce"], "pid": challenge["pid"], "consume_pid": challenge["consume_pid"], "entry_sha256": challenge["entry_sha256"], "single_use": True}, sort_keys=True, separators=(",", ":")))
PY
)"
  agency269_origin_write "$receipt"
}

agency269_origin_ack() {
  if [[ "$AGENCY269_ORIGIN_CONSUMED" != '1' ]]; then
    agency269_fail "origin" "origin proof is not consumed" "origin-ack" 67
    return $?
  fi
  if [[ "$AGENCY269_ORIGIN_ACKED" != '0' ]]; then
    agency269_fail "origin" "origin acknowledgement replay" "origin-ack" 67
    return $?
  fi
  AGENCY269_ORIGIN_ACKED='1'
  local ack
  ack="$(python3 - "${AGENCY269_ORIGIN_CHALLENGE}" <<'PY'
import json
import sys
c = json.loads(sys.argv[1])
print(json.dumps({"schema": "agency-agents.origin-ack/v1", "phase": c["phase"], "nonce": c["nonce"], "pid": c["pid"], "entry_sha256": c["entry_sha256"], "ack": True, "single_use": True}, sort_keys=True, separators=(",", ":")))
PY
)"
  agency269_origin_write "$ack"
}

agency269_initial_origin_challenge() { agency269_origin_challenge initial; }
agency269_post_auth_origin_challenge() { agency269_origin_challenge post-auth; }
agency269_initial_origin_proof() { agency269_origin_proof "$1"; }
agency269_post_auth_origin_proof() { agency269_origin_proof "$1"; }

agency269_fixed_entry_bootstrap() {
  if [[ "${AGENCY269_REEXEC:-0}" == '1' ]]; then
    if ! agency269_validate_initial_origin "$AGENCY269_ARGV_DIGEST"; then
      agency269_fail "entry-admission" "initial origin receipt invalid" "initial-origin-validation" 67
      return $?
    fi
    return 0
  fi
  agency269_assert_initial_fd_layout || return $?
  agency269_fixed_entry_exec "$AGENCY269_ENTRY_PATH" "$AGENCY269_SOURCE_PATH" "$AGENCY269_PROJECT_PATH" "$AGENCY269_SYSTEM_HOME_PATH" "$AGENCY269_TEST_ROOT_PATH" "$([[ "$AGENCY269_TEST_ROOT_PATH" != '' ]] && printf test || printf production)" "${AGENCY269_CHILD_ARGS[@]}"
}

agency269_dispatch_dry_run() {
  if declare -F agency269_m3_dry_run >/dev/null 2>&1; then
    agency269_m3_dry_run "${AGENCY269_REST_ARGS[@]}"
    return $?
  fi
  agency269_fail "dispatch" "M3 dry-run hook unavailable" "dry-run-dispatch" 68
}

agency269_dispatch_apply() {
  if declare -F agency269_m3_apply >/dev/null 2>&1; then
    agency269_m3_apply "${AGENCY269_REST_ARGS[@]}"
    return $?
  fi
  agency269_fail "dispatch" "M3 apply hook unavailable" "apply-dispatch" 68
}

agency269_parse_cli() {
  local value
  AGENCY269_REST_ARGS=()
  while (($#)); do
    case "$1" in
      --help|-h)
        AGENCY269_CLI_TERMINAL='help'
        agency269_cli_help
        return 0
        ;;
      --dry-run)
        [[ -z "$AGENCY269_MODE" ]] || { agency269_fail "cli" "multiple modes" "mode-selection" 64; return $?; }
        AGENCY269_MODE='dry-run'
        ;;
      --apply)
        [[ -z "$AGENCY269_MODE" ]] || { agency269_fail "cli" "multiple modes" "mode-selection" 64; return $?; }
        AGENCY269_MODE='apply'
        ;;
      --test-mode)
        AGENCY269_TEST_ROOT_PATH='__required__'
        ;;
      --entry|--source|--source-root|--project|--home|--test-mode-root|--manifest|--report|--action-file|--signature-file|--allowed-signers|--ledger)
        [[ $# -ge 2 ]] || { agency269_fail "cli" "option value missing" "option-value" 64; return $?; }
        value="$2"
        [[ "$value" != --* ]] || { agency269_fail "cli" "option value missing" "option-value" 64; return $?; }
        case "$1" in
          --entry) AGENCY269_ENTRY_PATH="$value" ;;
          --source|--source-root) AGENCY269_SOURCE_PATH="$value" ;;
          --project) AGENCY269_PROJECT_PATH="$value" ;;
          --home) AGENCY269_SYSTEM_HOME_PATH="$value" ;;
          --test-mode-root) AGENCY269_TEST_ROOT_PATH="$value" ;;
          --manifest) AGENCY269_MANIFEST_PATH="$value" ;;
          --report) AGENCY269_REPORT_PATH="$value" ;;
          --action-file) AGENCY269_ACTION_PATH="$value" ;;
          --signature-file) AGENCY269_SIGNATURE_PATH="$value" ;;
          --allowed-signers) AGENCY269_ALLOWED_SIGNERS_PATH="$value" ;;
          --ledger) AGENCY269_LEDGER_PATH="$value" ;;
        esac
        shift
        ;;
      --)
        shift
        AGENCY269_REST_ARGS=("$@")
        break
        ;;
      *)
        agency269_fail "cli" "unknown option" "option-parse" 64
        return $?
        ;;
    esac
    shift
  done
  [[ -n "$AGENCY269_MODE" ]] || { agency269_fail "cli" "mode is required" "mode-selection" 64; return $?; }
  [[ -n "$AGENCY269_ENTRY_PATH" ]] || AGENCY269_ENTRY_PATH="$AGENCY269_SCRIPT_PATH"
  [[ -n "$AGENCY269_SOURCE_PATH" ]] || { agency269_fail "cli" "source is required" "source-option" 64; return $?; }
  [[ -n "$AGENCY269_PROJECT_PATH" ]] || { agency269_fail "cli" "project is required" "project-option" 64; return $?; }
  [[ -n "$AGENCY269_SYSTEM_HOME_PATH" ]] || { agency269_fail "cli" "home option is required" "home-option" 64; return $?; }
  if [[ "$AGENCY269_TEST_ROOT_PATH" == '__required__' || -n "$AGENCY269_TEST_ROOT_PATH" ]]; then
    [[ "$AGENCY269_TEST_ROOT_PATH" != '__required__' ]] || { agency269_fail "cli" "test root value is required" "test-root-option" 64; return $?; }
  fi
  AGENCY269_ARGV_DIGEST="$(agency269_hash_argv "${AGENCY269_CHILD_ARGS[@]}")"
}

agency269_cli_help() {
  python3 - <<'PY'
import json
print(json.dumps({
    "schema": "agency-agents.bootstrap-help/v1",
    "module": "M1",
    "result": {"status": "help", "rc": 0},
    "options": ["--help", "--dry-run", "--apply", "--entry PATH", "--source-root PATH", "--project PATH", "--home PATH", "--test-mode --test-mode-root PATH", "--manifest PATH", "--report PATH", "--action-file PATH", "--signature-file PATH", "--allowed-signers PATH", "--ledger PATH"],
    "fixed_descriptors": {"FD9": "test-root", "FD10": "entry-execution", "FD11": "entry-validation", "FD15": "origin-channel", "FD16": "source", "FD17": "repo-project", "FD18": "system-home"},
    "m3_boundary": "manifest-source-transaction-logic-is-not-in-M1",
    "evidence_item_ids": ["M1-CLI-001", "M1-ENTRY-001", "M1-FD9-001", "M1-FD15-001", "M1-ORIGIN-001"],
}, sort_keys=True, separators=(",", ":")))
PY
}

agency269_cli_main() {
  local parse_rc
  AGENCY269_CHILD_ARGS=("$@")
  AGENCY269_MODE=''
  AGENCY269_CLI_TERMINAL=''
  AGENCY269_ENTRY_PATH=''
  AGENCY269_SOURCE_PATH=''
  AGENCY269_PROJECT_PATH=''
  AGENCY269_SYSTEM_HOME_PATH=''
  AGENCY269_TEST_ROOT_PATH=''
  if agency269_parse_cli "$@"; then
    parse_rc=0
  else
    parse_rc=$?
  fi
  if [[ "$parse_rc" -ne 0 ]]; then
    return "$parse_rc"
  fi
  if [[ "$AGENCY269_CLI_TERMINAL" == 'help' ]]; then
    return 0
  fi
  if [[ -z "$AGENCY269_MODE" ]]; then
    agency269_fail "cli" "mode is required" "mode-selection" 64
    return 64
  fi
  agency269_fixed_entry_bootstrap || return $?
  case "$AGENCY269_MODE" in
    dry-run) agency269_dispatch_dry_run ;;
    apply) agency269_dispatch_apply ;;
    *) agency269_fail "dispatch" "unsupported mode" "mode-dispatch" 68 ;;
  esac
}
# agency269 M2 descriptor/report/evidence module fragment.
# This file intentionally has no top-level execution. Source it or concatenate it.

agency269_m2_exec() {
    local operation="${1:-protocol}"
    local config="${2:-{}}"
    "${AGENCY269_M2_PYTHON:-python3}" - "$operation" "$config" <<'PY'
import json
import os
import stat
import sys


ROLE_FDS = {
    "FD10": 10,
    "FD11": 11,
    "FD12": 12,
    "FD13": 13,
    "FD14": 14,
    "FD15": 15,
    "FD16": 16,
    "FD17": 17,
    "FD18": 18,
    "FD19": 19,
    "FD20": 20,
    "FD21": 21,
}
ROLE_KIND = {
    "FD10": "regular",
    "FD11": "regular",
    "FD12": "directory",
    "FD13": "directory",
    "FD14": "regular",
    "FD15": "socket",
    "FD16": "directory",
    "FD17": "directory",
    "FD18": "directory",
    "FD19": "directory",
    "FD20": "directory",
    "FD21": "directory",
}
SOURCE_DIRECTORY_OPEN_FLAGS = (
    os.O_RDONLY
    | getattr(os, "O_DIRECTORY", 0)
    | getattr(os, "O_NOFOLLOW", 0)
)
SOURCE_DIRECTORY_OPEN_FLAG_NAMES = ["O_RDONLY", "O_DIRECTORY", "O_NOFOLLOW"]
PRIMARY_FAILURE = 1
PRIMARY_PLUS_SECONDARY_CLOSE = 78
CLOSE_ONLY = 79
REPORT_PATH_RC = 74
EVIDENCE_WRITE_RC = 75
EVIDENCE_ROOT_RC = 76


def result(ok, rc, stage, failure=None, detail=None, close_rc=0, receipts=None, close_failures=None, primary_failure=None, primary_rc=None):
    value = {
        "ok": bool(ok),
        "rc": int(rc),
        "stage": stage,
        "failure": failure,
        "close_rc": int(close_rc),
        "secondary_close_failures": close_failures or [],
        "receipts": receipts or {},
    }
    if detail is not None:
        value["detail"] = detail
    if primary_failure is not None:
        value["primary_failure"] = primary_failure
    if primary_rc is not None:
        value["primary_rc"] = int(primary_rc)
    return value


def failure(code, stage, rc, detail=None):
    return result(False, rc, stage, [code, stage], detail=detail)


def identity(fd):
    st = os.fstat(fd)
    return {
        "dev": int(st.st_dev),
        "ino": int(st.st_ino),
        "mode": int(st.st_mode),
        "size": int(st.st_size),
        "mtime_ns": int(getattr(st, "st_mtime_ns", int(st.st_mtime * 1000000000))),
        "ctime_ns": int(getattr(st, "st_ctime_ns", int(st.st_ctime * 1000000000))),
    }


def same_identity(left, right):
    return left == right


def kind_matches(mode, expected):
    if expected == "regular":
        return stat.S_ISREG(mode)
    if expected == "directory":
        return stat.S_ISDIR(mode)
    if expected == "socket":
        return stat.S_ISSOCK(mode)
    return False


def validate_fd_roles(config, allow_missing=None):
    allow_missing = set(allow_missing or [])
    supplied = config.get("fd_roles")
    if not isinstance(supplied, dict):
        return None, failure("M2_FD_ROLE_MAP", "fd-role-map", PRIMARY_FAILURE)
    states = {}
    receipts = {}
    for role, expected_fd in ROLE_FDS.items():
        if role in allow_missing:
            continue
        value = supplied.get(role)
        if isinstance(value, bool) or not isinstance(value, int) or value != expected_fd or value <= 0:
            return None, failure("M2_FD_ROLE_NUMBER", role, PRIMARY_FAILURE)
        if value in states:
            return None, failure("M2_FD_ROLE_DUPLICATE", role, PRIMARY_FAILURE)
        try:
            rec = identity(value)
        except OSError:
            return None, failure("M2_FD_NOT_OPEN", role, PRIMARY_FAILURE)
        if not kind_matches(rec["mode"], ROLE_KIND[role]):
            return None, failure("M2_FD_ROLE_KIND", role, PRIMARY_FAILURE)
        if role == "FD16":
            if getattr(os, "O_DIRECTORY", 0) == 0 or getattr(os, "O_NOFOLLOW", 0) == 0:
                return None, failure("M2_FD_ROLE_FLAGS", role, PRIMARY_FAILURE)
            try:
                stable_rec = identity(value)
            except OSError:
                return None, failure("M2_FD_NOT_OPEN", role, PRIMARY_FAILURE)
            if not same_identity(rec, stable_rec):
                return None, failure("M2_FD_IDENTITY_UNSTABLE", role, PRIMARY_FAILURE)
            rec = stable_rec
            rec["anchor_role"] = "source-directory"
            rec["admission_flags"] = SOURCE_DIRECTORY_OPEN_FLAG_NAMES
        states[value] = "open"
        receipts[role] = rec
    return {"states": states, "receipts": receipts}, None


def validate_ancestry(config, receipts):
    ancestry = config.get("ancestry")
    if not isinstance(ancestry, list) or not ancestry:
        return failure("M2_EVIDENCE_ANCESTRY", "evidence-root", EVIDENCE_ROOT_RC)
    roles = [item.get("role") for item in ancestry if isinstance(item, dict)]
    if not roles or roles[0] != "FD20" or roles[-1] != "FD21":
        return failure("M2_EVIDENCE_ANCESTRY", "evidence-root", EVIDENCE_ROOT_RC)
    for item in ancestry:
        if not isinstance(item, dict) or item.get("role") not in receipts:
            return failure("M2_EVIDENCE_ANCESTRY", "evidence-root", EVIDENCE_ROOT_RC)
        if item.get("identity") != receipts[item["role"]]:
            return failure("M2_EVIDENCE_IDENTITY", "evidence-root", EVIDENCE_ROOT_RC)
    root = receipts.get("FD20")
    if root is None or stat.S_IMODE(root["mode"]) != 0o700:
        return failure("M2_EVIDENCE_ROOT_MODE", "evidence-root", EVIDENCE_ROOT_RC)
    return None


def open_component(parent_fd, component, flags, mode=0o600):
    if not isinstance(component, str) or not component or "/" in component or component in (".", "..") or "\x00" in component:
        raise ValueError("unsafe-component")
    no_follow = getattr(os, "O_NOFOLLOW", 0)
    return os.open(component, flags | no_follow, mode, dir_fd=parent_fd)


def traverse_components(root_fd, components, directory=True):
    retained = []
    current = root_fd
    for component in components:
        flags = SOURCE_DIRECTORY_OPEN_FLAGS if directory else os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        opened = open_component(current, component, flags)
        retained.append(opened)
        current = opened
    return current, retained


def checked_close(fd, states):
    state = states.get(fd)
    if state != "open":
        return PRIMARY_FAILURE, True
    states[fd] = "closing"
    try:
        os.close(fd)
    except OSError:
        states[fd] = "failed"
        return PRIMARY_FAILURE, True
    states[fd] = "closed"
    return 0, False


def close_all(states, primary_failed):
    close_failures = []
    for fd in sorted(states.keys(), reverse=True):
        role = next((name for name, number in ROLE_FDS.items() if number == fd), "FD_UNKNOWN")
        if states.get(fd) != "open":
            close_failures.append({
                "fd": fd,
                "role": role,
                "state": states.get(fd, "unknown"),
                "failure": ["M2_FD_CLOSE_RETRY_BLOCKED", role],
            })
            continue
        close_rc, close_failed = checked_close(fd, states)
        if close_failed:
            close_failures.append({
                "fd": fd,
                "role": role,
                "state": states.get(fd, "failed"),
                "failure": ["M2_FD_CLOSE", role],
                "close_rc": close_rc,
            })
    if primary_failed and close_failures:
        return PRIMARY_PLUS_SECONDARY_CLOSE, close_failures
    if close_failures:
        return CLOSE_ONLY, close_failures
    if primary_failed:
        return PRIMARY_FAILURE, close_failures
    return 0, close_failures


def report_leaf_name(config):
    leaf = config.get("report_leaf")
    if not isinstance(leaf, str) or not leaf or "/" in leaf or leaf in (".", "..") or "\x00" in leaf:
        return None
    return leaf


def canonical_payload(config):
    payload = config.get("payload")
    if not isinstance(payload, dict):
        raise ValueError("payload-object")
    return (json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n").encode("ascii")


def write_all(fd, data):
    view = memoryview(data)
    total = 0
    while total < len(view):
        written = os.write(fd, view[total:])
        if not isinstance(written, int) or written <= 0:
            raise OSError("short-write")
        total += written
    return total


def operation_lifecycle(config):
    allow_missing = set(config.get("allow_missing", []))
    table, error = validate_fd_roles(config, allow_missing=allow_missing)
    if error is not None:
        return error
    states = table["states"]
    receipts = table["receipts"]
    primary_error = None
    if "FD20" not in allow_missing:
        primary_error = validate_ancestry(config, receipts)
    aggregate_rc, close_failures = close_all(states, primary_error is not None)
    if primary_error is not None:
        return result(
            False,
            aggregate_rc,
            "fd-lifecycle",
            failure=primary_error["failure"],
            close_rc=aggregate_rc,
            receipts=receipts,
            close_failures=close_failures,
            primary_failure=primary_error["failure"],
            primary_rc=primary_error["rc"],
        )
    if aggregate_rc != 0:
        return result(
            False,
            aggregate_rc,
            "fd-lifecycle",
            failure=["M2_FD_CLOSE", "fd-lifecycle"],
            close_rc=aggregate_rc,
            receipts=receipts,
            close_failures=close_failures,
        )
    return result(True, 0, "fd-lifecycle", close_rc=0, receipts=receipts, close_failures=[])


def operation_close(config):
    supplied = config.get("fd_roles")
    if not isinstance(supplied, dict) or supplied.get(config.get("role")) != ROLE_FDS.get(config.get("role"), -1):
        return failure("M2_FD_ROLE_NUMBER", "checked-close", PRIMARY_FAILURE)
    fd = ROLE_FDS[config["role"]]
    try:
        identity(fd)
    except OSError:
        return failure("M2_FD_NOT_OPEN", "checked-close", PRIMARY_FAILURE)
    states = {fd: "open"}
    first, first_failed = checked_close(fd, states)
    if config.get("repeat") is True:
        return result(False, PRIMARY_PLUS_SECONDARY_CLOSE if first_failed else PRIMARY_FAILURE, "checked-close", ["M2_FD_CLOSE_RETRY_BLOCKED", "checked-close"], close_rc=first)
    if first_failed:
        return result(False, CLOSE_ONLY, "checked-close", ["M2_FD_CLOSE", "checked-close"], close_rc=first)
    return result(True, 0, "checked-close", close_rc=0)


def operation_root(config):
    table, error = validate_fd_roles(config, allow_missing={"FD14"})
    if error is not None:
        return error
    root_error = validate_ancestry(config, table["receipts"])
    if root_error is not None:
        aggregate_rc, close_failures = close_all(table["states"], True)
        return result(
            False,
            aggregate_rc,
            "evidence-root",
            failure=root_error["failure"],
            close_rc=aggregate_rc,
            receipts=table["receipts"],
            close_failures=close_failures,
            primary_failure=root_error["failure"],
            primary_rc=root_error["rc"],
        )
    states = table["states"]
    close_rc, close_failures = close_all(states, False)
    if close_rc != 0:
        return result(False, close_rc, "evidence-root", ["M2_FD_CLOSE", "evidence-root"], close_rc=close_rc, receipts=table["receipts"], close_failures=close_failures)
    return result(True, 0, "evidence-root", receipts=table["receipts"], close_failures=[])


def operation_report(config):
    table, error = validate_fd_roles(config, allow_missing={"FD14"})
    if error is not None:
        return error
    states = table["states"]
    receipts = table["receipts"]
    root_error = validate_ancestry(config, receipts)
    if root_error is not None:
        close_rc, close_failures = close_all(states, True)
        return result(False, close_rc, "evidence-root", root_error["failure"], close_rc=close_rc, receipts=receipts, close_failures=close_failures, primary_failure=root_error["failure"], primary_rc=root_error["rc"])
    leaf = report_leaf_name(config)
    if leaf is None:
        close_rc, close_failures = close_all(states, True)
        return result(False, REPORT_PATH_RC if close_rc == PRIMARY_FAILURE else close_rc, "report-path", ["M2_REPORT_PATH", "report-path"], close_rc=close_rc, receipts=receipts, close_failures=close_failures, primary_failure=["M2_REPORT_PATH", "report-path"], primary_rc=REPORT_PATH_RC)
    try:
        fd = open_component(ROLE_FDS["FD21"], leaf, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        if fd != ROLE_FDS["FD14"]:
            os.dup2(fd, ROLE_FDS["FD14"], inheritable=False)
            os.close(fd)
        fd = ROLE_FDS["FD14"]
        states[fd] = "open"
        before = identity(fd)
        payload = canonical_payload(config)
        written = write_all(fd, payload)
        if written != len(payload):
            raise OSError("short-write")
        os.fsync(fd)
        after = identity(fd)
        if not same_identity({k: before[k] for k in before if k != "size"}, {k: after[k] for k in after if k != "size"}) or after["size"] != len(payload):
            raise OSError("identity-or-size")
        receipts["FD14"] = after
        primary_failed = False
        primary_rc = 0
    except (OSError, ValueError):
        primary_failed = True
        primary_rc = REPORT_PATH_RC if "fd" not in locals() or fd not in states else EVIDENCE_WRITE_RC
    close_rc, close_failures = close_all(states, primary_failed)
    if primary_failed:
        primary_tuple = ["M2_REPORT_PATH" if primary_rc == REPORT_PATH_RC else "M2_EVIDENCE_WRITE", "report-write"]
        return result(False, close_rc if close_rc == PRIMARY_PLUS_SECONDARY_CLOSE else primary_rc, "report-write", primary_tuple, close_rc=close_rc, receipts=receipts, close_failures=close_failures, primary_failure=primary_tuple, primary_rc=primary_rc)
    if close_rc != 0:
        return result(False, close_rc, "report-close", ["M2_FD_CLOSE", "report-close"], close_rc=close_rc, receipts=receipts, close_failures=close_failures)
    return result(True, 0, "report-write", receipts=receipts, close_failures=[])


def operation_emit(config):
    artifact = config.get("artifact")
    if artifact is None:
        payload = config.get("payload")
        if not isinstance(payload, dict):
            return failure("M2_JSON_PAYLOAD", "stdout", PRIMARY_FAILURE)
        return result(True, 0, "stdout", detail=payload)
    written = operation_report(config)
    if written.get("ok"):
        return result(True, 0, "artifact-and-stdout", detail=config.get("payload"), receipts=written.get("receipts"))
    return result(False, written.get("rc", PRIMARY_FAILURE), "stdout-fallback", failure=written.get("failure"), detail={"fallback": True, "artifact_owner": True})


def main():
    operation = sys.argv[1] if len(sys.argv) > 1 else "protocol"
    try:
        config = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
        if not isinstance(config, dict):
            raise ValueError("config-object")
    except (ValueError, TypeError, json.JSONDecodeError):
        value = failure("M2_PROTOCOL", "protocol", PRIMARY_FAILURE)
        sys.stdout.write(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n")
        return PRIMARY_FAILURE
    try:
        if operation == "lifecycle":
            value = operation_lifecycle(config)
        elif operation == "checked-close":
            value = operation_close(config)
        elif operation == "evidence-root":
            value = operation_root(config)
        elif operation == "report":
            value = operation_report(config)
        elif operation == "emit":
            value = operation_emit(config)
        else:
            value = failure("M2_PROTOCOL", "protocol", PRIMARY_FAILURE)
    except (OSError, ValueError, TypeError, KeyError):
        value = failure("M2_INTERNAL_FIXED", operation, PRIMARY_FAILURE)
    sys.stdout.write(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n")
    return int(value.get("rc", PRIMARY_FAILURE))


sys.exit(main())
PY
}

agency269_m2_fd_lifecycle() {
    agency269_m2_exec lifecycle "${1:-{}}"
}

agency269_m2_checked_close() {
    agency269_m2_exec checked-close "${1:-{}}"
}

agency269_m2_validate_evidence_root() {
    agency269_m2_exec evidence-root "${1:-{}}"
}

agency269_m2_write_canonical_report() {
    agency269_m2_exec report "${1:-{}}"
}

agency269_m2_emit_single_json() {
    agency269_m2_exec emit "${1:-{}}"
}
# Agency Agents 269 recovery DAG M3.
# Validation, authorization, descriptor-bound transaction primitives.
# This include defines functions only. It performs no action when sourced.

m3_fail() {
  local stage="$1"
  local operation="$2"
  local reason="$3"
  local rc="$4"
  printf '%s\n' "M3_FAILURE stage=${stage} operation=${operation} reason=${reason} rc=${rc}" >&2
  return "$rc"
}

m3_fd_role_check() {
  local fd
  for fd in 12 13 16 17 18 19; do
    case "$fd" in
      12) : <&12 || return "$(m3_fail descriptor-admission fd12-work fd-unavailable 41; printf '%s' "$?")" ;;
      13) : <&13 || return "$(m3_fail descriptor-admission fd13-backup fd-unavailable 41; printf '%s' "$?")" ;;
      16) : <&16 || return "$(m3_fail descriptor-admission fd16-source fd-unavailable 41; printf '%s' "$?")" ;;
      17) : <&17 || return "$(m3_fail descriptor-admission fd17-project-target fd-unavailable 41; printf '%s' "$?")" ;;
      18) : <&18 || return "$(m3_fail descriptor-admission fd18-home-authority fd-unavailable 41; printf '%s' "$?")" ;;
      19) : <&19 || return "$(m3_fail descriptor-admission fd19-transaction-parent fd-unavailable 41; printf '%s' "$?")" ;;
    esac
  done
  return 0
}

m3_lexical_components() {
  local value="$1"
  [[ -n "$value" ]] || { m3_fail lexical-validation components-empty empty 42; return $?; }
  case "$value" in
    /*|*//*|*/) m3_fail lexical-validation components-unsafe component 42; return $? ;;
  esac
  local part
  local old_ifs="$IFS"
  IFS=/
  read -r -a _m3_parts <<< "$value"
  IFS="$old_ifs"
  for part in "${_m3_parts[@]}"; do
    [[ -n "$part" && "$part" != . && "$part" != .. && "$part" != */* ]] || {
      m3_fail lexical-validation component-unsafe component 42
      return $?
    }
  done
  return 0
}

m3_manifest_check() {
  local manifest="$1"
  local profiles="$2"
  python3 - "$manifest" "$profiles" <<'PY'
import hashlib
import json
import os
import sys

manifest_path, profiles_path = sys.argv[1:3]
expected_tools = ["aider", "antigravity", "claude-code", "copilot", "cursor", "gemini-cli", "hermes", "kimi", "openclaw", "opencode", "osaurus", "qwen", "vibe", "windsurf", "zcode", "github-copilot"]
expected_targets = [
    ("aider", "aider-single", "file", "${PROJECT}/CONVENTIONS.md"),
    ("antigravity", "antigravity", "directory", "${HOME}/.gemini/config/skills"),
    ("claude-code", "claude-code", "directory", "${HOME}/.claude/agents"),
    ("github-copilot", "copilot-github", "directory", "${HOME}/.github/agents"),
    ("github-copilot", "copilot-local", "directory", "${HOME}/.copilot/agents"),
    ("codex", "codex", "directory", "${HOME}/.codex/agents"),
    ("cursor", "cursor", "directory", "${PROJECT}/.cursor/rules"),
    ("gemini-cli", "gemini-cli", "directory", "${HOME}/.gemini/agents"),
    ("kimi", "kimi", "directory", "${HOME}/.config/kimi/agents"),
    ("openclaw", "openclaw", "directory", "${HOME}/.openclaw/agency-agents"),
    ("opencode", "opencode", "directory", "${PROJECT}/.opencode/agents"),
    ("osaurus", "osaurus", "directory", "${HOME}/.osaurus/skills"),
    ("qwen", "qwen", "directory", "${PROJECT}/.qwen/agents"),
    ("hermes", "hermes", "directory", "${HOME}/.hermes/plugins/agency-agents-router"),
    ("vibe", "vibe-agents", "directory", "${HOME}/.vibe/agents"),
    ("vibe", "vibe-prompts", "directory", "${HOME}/.vibe/prompts"),
    ("windsurf", "windsurf", "file", "${PROJECT}/.windsurfrules"),
    ("zcode", "zcode", "directory", "${HOME}/.zcode/agents"),
]

def block(reason):
    print("M3_FAILURE stage=manifest-validation operation=manifest-check reason=%s rc=43" % reason, file=sys.stderr)
    raise SystemExit(43)

try:
    with open(manifest_path, "rb") as fp:
        manifest_bytes = fp.read()
    with open(profiles_path, "rb") as fp:
        profile_bytes = fp.read()
    manifest = json.loads(manifest_bytes)
    profiles = json.loads(profile_bytes)
except Exception:
    block("json-unreadable")
if not isinstance(manifest, dict) or not isinstance(profiles, list):
    block("shape")
if manifest.get("sourceRoleCount") != 269 or manifest.get("roleSetCount") != 269 or manifest.get("expectedSections") != 269:
    block("role-count")
if manifest.get("roleSetFileSha256") != "ad7616f4520eb5c5727cad1f7992c4fa6ad881dcba728266ab2cdb0c55608e20":
    block("role-profile-digest")
if len(profiles) != 269 or len({p.get("role_id") for p in profiles}) != 269:
    block("role-set")
if any(not isinstance(p.get("role_id"), str) or not p.get("role_id") for p in profiles):
    block("role-id")
if any(p.get("risk_level") == "high" and p.get("allowed_write_actions") != [] for p in profiles):
    block("high-risk-write")
if [x.get("name") for x in manifest.get("tools", [])] != expected_tools:
    block("tool-order-or-set")
actual_targets = []
for tool in manifest["tools"]:
    if tool.get("sectionCount") != 269:
        block("section-count")
    for target in tool.get("targets", []):
        actual_targets.append((tool.get("name"), target.get("label"), target.get("kind"), target.get("targetPath")))
if actual_targets != expected_targets:
    block("target-order-or-set")
if len(actual_targets) != 18 or len({x[1] for x in actual_targets}) != 18:
    block("target-count")
print(json.dumps({
    "status": "passed",
    "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
    "role_profile_sha256": hashlib.sha256(profile_bytes).hexdigest(),
    "role_count": 269,
    "tool_count": 16,
    "target_count": 18,
    "expected_sections": 269,
}, sort_keys=True, separators=(",", ":")))
PY
}

m3_source_digest() {
  m3_fd_role_check || return $?
  python3 - <<'PY'
import hashlib
import json
import os
import stat
import sys

root_fd = 16

def finish_owned_closes(stage, operation, primary, owned, rollback=False):
    failures = []
    for descriptor, role in owned:
        if descriptor is None:
            continue
        try:
            os.close(descriptor)
        except OSError as exc:
            failures.append({"code":"E_DESCRIPTOR_CLOSE", "fd_role":role, "errno":exc.errno})
    if failures:
        primary_record = None if primary is None else {"type":type(primary).__name__, "code":getattr(primary, "code", None), "text":str(primary)}
        rc = 79 if primary is None else 78
        print("M3_FAILURE stage=%s operation=%s reason=E_DESCRIPTOR_CLOSE rc=%d primary=%s close_failures=%s" % (stage, operation, rc, json.dumps(primary_record, sort_keys=True, separators=(",", ":")), json.dumps(failures, sort_keys=True, separators=(",", ":"))), file=sys.stderr)
        if rollback:
            print("M3_ROLLBACK_RESTORE_FAILURE code=E_DESCRIPTOR_CLOSE details=%s" % json.dumps(failures, sort_keys=True, separators=(",", ":")), file=sys.stderr)
        raise SystemExit(rc)
    if primary is not None:
        raise primary

def bad(reason):
    print("M3_FAILURE stage=source-validation operation=source-digest reason=%s rc=44" % reason, file=sys.stderr)
    raise SystemExit(44)

def check_name(name):
    if not name or name in (".", "..") or "/" in name or "\x00" in name:
        bad("unsafe-entry")

def digest(fd, rel=""):
    try:
        names = sorted(os.listdir(fd))
    except OSError:
        bad("list-failed")
    h = hashlib.sha256()
    for name in names:
        check_name(name)
        child_rel = name if not rel else rel + "/" + name
        try:
            st_before = os.stat(name, dir_fd=fd, follow_symlinks=False)
        except OSError:
            bad("stat-failed")
        mode = stat.S_IMODE(st_before.st_mode)
        if stat.S_ISLNK(st_before.st_mode) or not (stat.S_ISREG(st_before.st_mode) or stat.S_ISDIR(st_before.st_mode)):
            bad("symlink-or-special")
        if stat.S_ISDIR(st_before.st_mode):
            h.update(("D\t%s\t%o\n" % (child_rel, mode)).encode())
            try:
                child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            except OSError:
                bad("directory-open-failed")
            primary = None
            try:
                h.update(digest(child, child_rel).digest())
                st_after = os.fstat(child)
            except BaseException as exc:
                primary = exc
            finish_owned_closes("source-validation", "source-digest", primary, [(child, "source-child-directory")])
            if (st_before.st_dev, st_before.st_ino, st_before.st_mtime_ns, st_before.st_ctime_ns) != (st_after.st_dev, st_after.st_ino, st_after.st_mtime_ns, st_after.st_ctime_ns):
                bad("directory-metadata-race")
        else:
            try:
                child = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=fd)
            except OSError:
                bad("file-open-failed")
            primary = None
            try:
                st_open = os.fstat(child)
                if not stat.S_ISREG(st_open.st_mode):
                    bad("file-type-race")
                content = bytearray()
                while True:
                    chunk = os.read(child, 1024 * 1024)
                    if not chunk:
                        break
                    content.extend(chunk)
                st_after = os.fstat(child)
            except BaseException as exc:
                primary = exc
            finish_owned_closes("source-validation", "source-digest", primary, [(child, "source-child-file")])
            if st_before.st_size != st_after.st_size or st_before.st_mtime_ns != st_after.st_mtime_ns or st_before.st_ctime_ns != st_after.st_ctime_ns:
                bad("file-metadata-race")
            file_hash = hashlib.sha256(content).hexdigest()
            h.update(("F\t%s\t%d\t%o\t%s\n" % (child_rel, len(content), stat.S_IMODE(st_before.st_mode), file_hash)).encode())
    return h

try:
    st_root = os.fstat(root_fd)
    if not stat.S_ISDIR(st_root.st_mode):
        bad("source-not-directory")
    result = digest(root_fd).hexdigest()
    st_after = os.fstat(root_fd)
    if (st_root.st_dev, st_root.st_ino, st_root.st_mtime_ns, st_root.st_ctime_ns) != (st_after.st_dev, st_after.st_ino, st_after.st_mtime_ns, st_after.st_ctime_ns):
        bad("source-root-race")
except OSError:
    bad("source-fstat-failed")
print(result)
PY
}

m3_entry_digest() {
  local components="$1"
  m3_lexical_components "$components" || return $?
  m3_fd_role_check || return $?
  python3 - "$components" <<'PY'
import hashlib
import json
import os
import stat
import sys

value = sys.argv[1]
parts = value.split("/")
fd = 16
entry = None
primary = None
close_failures = []

def close_owned(descriptor, role):
    if descriptor is None:
        return
    try:
        os.close(descriptor)
    except OSError as exc:
        close_failures.append({"code":"E_DESCRIPTOR_CLOSE", "fd_role":role, "errno":exc.errno})

try:
    for part in parts[:-1]:
        if not part or part in (".", "..") or "/" in part:
            raise ValueError("unsafe-component")
        nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
        if fd != 16:
            previous_fd = fd
            fd = nxt
            close_owned(previous_fd, "entry-parent")
            if close_failures:
                raise SystemExit(79)
        else:
            fd = nxt
    leaf = parts[-1]
    if not leaf or leaf in (".", "..") or "/" in leaf:
        raise ValueError("unsafe-leaf")
    entry = os.open(leaf, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=fd)
    st_before = os.fstat(entry)
    if not stat.S_ISREG(st_before.st_mode):
        raise ValueError("entry-not-regular")
    h = hashlib.sha256()
    while True:
        chunk = os.read(entry, 1024 * 1024)
        if not chunk:
            break
        h.update(chunk)
    st_after = os.fstat(entry)
    if (st_before.st_dev, st_before.st_ino, st_before.st_size, st_before.st_mtime_ns) != (st_after.st_dev, st_after.st_ino, st_after.st_size, st_after.st_mtime_ns):
        raise ValueError("entry-metadata-race")
    print(h.hexdigest())
except (OSError, ValueError) as exc:
    print("M3_FAILURE stage=source-validation operation=entry-digest reason=%s rc=45" % str(exc), file=sys.stderr)
    primary = SystemExit(45)
except BaseException as exc:
    primary = exc
close_owned(entry, "entry-file")
if fd != 16:
    close_owned(fd, "entry-parent-final")
if close_failures:
    rc = 79 if primary is None else 78
    primary_record = None if primary is None else {"type":type(primary).__name__, "code":getattr(primary, "code", None), "text":str(primary)}
    print("M3_FAILURE stage=source-validation operation=entry-digest reason=E_DESCRIPTOR_CLOSE rc=%d primary=%s close_failures=%s" % (rc, json.dumps(primary_record, sort_keys=True, separators=(",", ":")), json.dumps(close_failures, sort_keys=True, separators=(",", ":"))), file=sys.stderr)
    raise SystemExit(rc)
if primary is not None:
    raise primary
PY
}

m3_authorize_transaction() {
  local action_component="$1"
  local signature_component="$2"
  local signer_component="$3"
  local ledger_component="$4"
  local frozen_manifest_digest="$5"
  local entry_digest="$6"
  local source_digest="$7"
  local principal="${8:-supervisor-approver}"
  local namespace="${9:-aicc-supervisor-authorization}"
  m3_lexical_components "$action_component" || return $?
  m3_lexical_components "$signature_component" || return $?
  m3_lexical_components "$signer_component" || return $?
  m3_lexical_components "$ledger_component" || return $?
  m3_fd_role_check || return $?
  python3 - "$action_component" "$signature_component" "$signer_component" "$ledger_component" "$frozen_manifest_digest" "$entry_digest" "$source_digest" "$principal" "$namespace" <<'PY'
import fcntl
import hashlib
import json
import os
import stat
import subprocess
import sys

act_name, sig_name, signer_name, ledger_name, frozen_manifest, entry_digest, source_digest, principal, namespace = sys.argv[1:]

def finish_owned_closes(primary, owned):
    failures = []
    for descriptor, role in owned:
        if descriptor is None:
            continue
        try:
            os.close(descriptor)
        except OSError as exc:
            failures.append({"code":"E_DESCRIPTOR_CLOSE", "fd_role":role, "errno":exc.errno})
    if failures:
        rc = 79 if primary is None else 78
        primary_record = None if primary is None else {"type":type(primary).__name__, "code":getattr(primary, "code", None), "text":str(primary)}
        print("M3_FAILURE stage=authorization operation=action-signature-ledger reason=E_DESCRIPTOR_CLOSE rc=%d primary=%s close_failures=%s" % (rc, json.dumps(primary_record, sort_keys=True, separators=(",", ":")), json.dumps(failures, sort_keys=True, separators=(",", ":"))), file=sys.stderr)
        raise SystemExit(rc)
    if primary is not None:
        raise primary

def fail(reason, rc):
    print("M3_FAILURE stage=authorization operation=action-signature-ledger reason=%s rc=%d" % (reason, rc), file=sys.stderr)
    raise SystemExit(rc)

def parts(value):
    result = value.split("/")
    if any(not x or x in (".", "..") or "/" in x for x in result):
        fail("unsafe-component", 46)
    return result

def open_relative(root, value, flags, mode=0o600):
    items = parts(value)
    current = root
    owned = []
    try:
        for item in items[:-1]:
            current = os.open(item, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=current)
            owned.append(current)
        fd = os.open(items[-1], flags | os.O_NOFOLLOW, mode, dir_fd=current)
        return fd, owned
    except OSError:
        primary = SystemExit(46)
        print("M3_FAILURE stage=authorization operation=action-signature-ledger reason=descriptor-relative-open rc=46", file=sys.stderr)
        finish_owned_closes(primary, [(fd, "authorization-open-parent") for fd in reversed(owned)])

def owner_only(fd, label):
    st = os.fstat(fd)
    if st.st_uid != os.geteuid() or stat.S_IMODE(st.st_mode) & 0o077:
        fail(label + "-owner-or-mode", 47)
    if not stat.S_ISREG(st.st_mode):
        fail(label + "-not-regular", 47)

action_fd = sig_fd = signer_fd = ledger_fd = None
action_parents = []
sig_parents = []
signer_parents = []
ledger_parents = []
primary = None
try:
    action_fd, action_parents = open_relative(12, act_name, os.O_RDONLY)
    sig_fd, sig_parents = open_relative(12, sig_name, os.O_RDONLY)
    signer_fd, signer_parents = open_relative(18, signer_name, os.O_RDONLY)
    ledger_fd, ledger_parents = open_relative(18, ledger_name, os.O_RDWR | os.O_APPEND)
    owner_only(action_fd, "action")
    owner_only(sig_fd, "signature")
    owner_only(signer_fd, "allowed-signers")
    owner_only(ledger_fd, "ledger")
    action = os.read(action_fd, 64 * 1024 * 1024)
    signature = os.read(sig_fd, 64 * 1024 * 1024)
    action_digest = hashlib.sha256(action).hexdigest()
    try:
        obj = json.loads(action.decode("utf-8"))
    except Exception:
        fail("action-json", 48)
    if not isinstance(obj, dict):
        fail("action-shape", 48)
    if obj.get("namespace") != namespace or obj.get("principal") != principal:
        fail("principal-or-namespace", 48)
    if obj.get("frozen_action_digest") != frozen_manifest:
        fail("frozen-manifest-digest", 48)
    if obj.get("entry_sha256") != entry_digest or obj.get("source_root_digest") != source_digest:
        fail("entry-or-source-digest", 48)
    os.dup2(action_fd, 20)
    os.dup2(sig_fd, 21)
    os.dup2(signer_fd, 22)
    for fd in (20, 21, 22):
        os.set_inheritable(fd, True)
    verified = subprocess.run(
        ["ssh-keygen", "-Y", "verify", "-f", "/dev/fd/22", "-I", principal, "-n", namespace, "-s", "/dev/fd/21"],
        input=action,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        pass_fds=(20, 21, 22),
        check=False,
    )
    if verified.returncode != 0:
        fail("detached-signature", 49)
    fcntl.flock(ledger_fd, fcntl.LOCK_EX)
    try:
        os.lseek(ledger_fd, 0, os.SEEK_SET)
        prior = os.read(ledger_fd, 64 * 1024 * 1024)
        for line in prior.splitlines():
            try:
                row = json.loads(line.decode("utf-8"))
            except Exception:
                fail("ledger-corrupt", 50)
            if isinstance(row, dict) and row.get("action_digest") == action_digest:
                fail("single-use-replay", 51)
        record = {
            "action_digest": action_digest,
            "entry_sha256": entry_digest,
            "source_root_digest": source_digest,
            "frozen_action_digest": frozen_manifest,
            "namespace": namespace,
            "principal": principal,
        }
        encoded = (json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
        os.lseek(ledger_fd, 0, os.SEEK_END)
        os.write(ledger_fd, encoded)
        os.fsync(ledger_fd)
    finally:
        fcntl.flock(ledger_fd, fcntl.LOCK_UN)
    result = json.dumps({"status":"passed", "action_digest":action_digest, "signature_sha256":hashlib.sha256(signature).hexdigest()}, sort_keys=True, separators=(",", ":"))
except BaseException as exc:
    primary = exc
finish_owned_closes(primary, [
    (action_fd, "authorization-action"),
    (sig_fd, "authorization-signature"),
    (signer_fd, "authorization-allowed-signers"),
    (ledger_fd, "authorization-ledger"),
] + [(fd, "authorization-parent") for fd in action_parents + sig_parents + signer_parents + ledger_parents])
print(result)
PY
}

m3_tx_plan() {
  local target_role="$1"
  local target_components="$2"
  local stage_components="$3"
  local backup_components="$4"
  local source_components="$5"
  local journal_component="$6"
  [[ "${M3_DRY_RUN:-0}" == 1 ]] && return 0
  [[ "$target_role" == project || "$target_role" == home ]] || { m3_fail owner-plan target-role unknown-role 52; return $?; }
  m3_lexical_components "$target_components" || return $?
  m3_lexical_components "$stage_components" || return $?
  m3_lexical_components "$backup_components" || return $?
  m3_lexical_components "$source_components" || return $?
  m3_lexical_components "$journal_component" || return $?
  m3_fd_role_check || return $?
  python3 - "$target_role" "$target_components" "$stage_components" "$backup_components" "$source_components" "$journal_component" <<'PY'
import json, os, stat, sys
role, target, stage, backup, source, journal = sys.argv[1:]

def finish_owned_closes(primary, owned):
    failures=[]
    for descriptor, role_name in owned:
        try: os.close(descriptor)
        except OSError as exc: failures.append({"code":"E_DESCRIPTOR_CLOSE","fd_role":role_name,"errno":exc.errno})
    if failures:
        rc=79 if primary is None else 78
        primary_record=None if primary is None else {"type":type(primary).__name__,"code":getattr(primary,"code",None),"text":str(primary)}
        print("M3_FAILURE stage=owner-plan operation=journal-create reason=E_DESCRIPTOR_CLOSE rc=%d primary=%s close_failures=%s"%(rc,json.dumps(primary_record,sort_keys=True,separators=(",",":")),json.dumps(failures,sort_keys=True,separators=(",",":"))),file=sys.stderr)
        raise SystemExit(rc)
    if primary is not None: raise primary
if target.split("/")[:-1] != backup.split("/")[:-1]:
    print("M3_FAILURE stage=owner-plan operation=backup-placement reason=backup-not-target-sibling rc=53", file=sys.stderr); raise SystemExit(53)
root = 17 if role == "project" else 18
for value in (target, stage, backup, source, journal):
    if any(not x or x in (".", "..") or "/" in x for x in value.split("/")):
        print("M3_FAILURE stage=owner-plan operation=lexical-bind reason=unsafe-component rc=53", file=sys.stderr); raise SystemExit(53)
items = {"target_role":role, "target_components":target, "stage_components":stage, "backup_components":backup, "source_components":source, "target_fd":root, "journal_fd":19, "state":"planned", "created_target_dirs":[], "backup_moved":False, "installed":False}
parts=journal.split("/")
parent=19; opened=[]
primary=None
try:
    for item in parts[:-1]:
        parent=os.open(item, os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW, dir_fd=parent); opened.append(parent)
    fd=os.open(parts[-1], os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW, 0o600, dir_fd=parent)
    data=(json.dumps(items, sort_keys=True, separators=(",", ":"))+"\n").encode()
    os.write(fd,data); os.fsync(fd); os.close(fd)
    print(json.dumps({"status":"planned","target_role":role,"target_fd":root,"journal_fd":19}, sort_keys=True, separators=(",", ":")))
except OSError:
    print("M3_FAILURE stage=owner-plan operation=journal-create reason=descriptor-relative-journal-failed rc=54", file=sys.stderr); primary=SystemExit(54)
except BaseException as exc:
    primary=exc
finish_owned_closes(primary, [(fd,"owner-plan-parent") for fd in reversed(opened)])
PY
}

m3_tx_stage() {
  local journal_component="$1"
  [[ "${M3_DRY_RUN:-0}" == 1 ]] && return 0
  m3_lexical_components "$journal_component" || return $?
  m3_fd_role_check || return $?
  python3 - "$journal_component" <<'PY'
import json, os, stat, sys
journal_name=sys.argv[1]
def fail(reason,rc=55):
 print("M3_FAILURE stage=staging operation=descriptor-copy reason=%s rc=%d"%(reason,rc),file=sys.stderr); raise SystemExit(rc)
def parts(v):
 x=v.split("/")
 if any(not p or p in (".","..") or "/" in p for p in x): fail("unsafe-component")
 return x
def finish_owned_closes(primary, owned):
 failures=[]
 for descriptor,role in owned:
  if descriptor is None: continue
  try: os.close(descriptor)
  except OSError as exc: failures.append({"code":"E_DESCRIPTOR_CLOSE","fd_role":role,"errno":exc.errno})
 if failures:
  rc=79 if primary is None else 78
  primary_record=None if primary is None else {"type":type(primary).__name__,"code":getattr(primary,"code",None),"text":str(primary)}
  print("M3_FAILURE stage=staging operation=descriptor-copy reason=E_DESCRIPTOR_CLOSE rc=%d primary=%s close_failures=%s"%(rc,json.dumps(primary_record,sort_keys=True,separators=(",",":")),json.dumps(failures,sort_keys=True,separators=(",",":"))),file=sys.stderr)
  raise SystemExit(rc)
 if primary is not None: raise primary
def open_rel(root,v,flags,mode=0o600):
 cur=root; owned=[]
 for p in parts(v)[:-1]: cur=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=cur); owned.append(cur)
 return os.open(parts(v)[-1],flags|os.O_NOFOLLOW,mode,dir_fd=cur),owned
def copy_node(srcfd,dstparent,leaf):
 st=os.stat(leaf,dir_fd=srcfd,follow_symlinks=False)
 if stat.S_ISLNK(st.st_mode) or not (stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode)): fail("source-special")
 if stat.S_ISDIR(st.st_mode):
 os.mkdir(leaf,0o700,dir_fd=dstparent); out=os.open(leaf,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=dstparent); ins=os.open(leaf,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=srcfd)
  primary=None
  try:
   for name in sorted(os.listdir(ins)): copy_node(ins,out,name)
  except BaseException as exc: primary=exc
  finish_owned_closes(primary,[(ins,"stage-source-directory"),(out,"stage-output-directory")])
 else:
  inf=os.open(leaf,os.O_RDONLY|os.O_NOFOLLOW,dir_fd=srcfd); outf=os.open(leaf,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600,dir_fd=dstparent)
  primary=None
  try:
   while True:
    b=os.read(inf,1024*1024)
    if not b: break
    os.write(outf,b)
   os.fsync(outf)
  except BaseException as exc: primary=exc
  finish_owned_closes(primary,[(inf,"stage-source-file"),(outf,"stage-output-file")])

def ensure_parent(root,v):
 cur=root; created=[]
 for p in parts(v)[:-1]:
  try: nxt=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=cur)
  except FileNotFoundError:
   os.mkdir(p,0o700,dir_fd=cur); created.append(p); nxt=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=cur)
  cur=nxt
 return cur,created
fd=None; opened=[]; src=None; src_open=[]; parent=None; primary=None
try:
 fd,opened=open_rel(19,journal_name,os.O_RDWR)
 data=os.read(fd,64*1024*1024); j=json.loads(data.decode());
 if j.get("state")!="planned" or j.get("journal_fd")!=19: fail("journal-not-frozen")
 src,src_open=open_rel(16,j["source_components"],os.O_RDONLY)
 try:
  parent,created=ensure_parent(12,j["stage_components"]); copy_node(src,parent,parts(j["stage_components"])[-1])
 j["state"]="staged"; j["created_work_dirs"]=created
 os.lseek(fd,0,os.SEEK_SET); os.ftruncate(fd,0); os.write(fd,(json.dumps(j,sort_keys=True,separators=(",",":"))+"\n").encode()); os.fsync(fd)
 print(json.dumps({"status":"staged","journal_fd":19},sort_keys=True,separators=(",",":")))
except BaseException as exc: primary=exc
finish_owned_closes(primary,[(parent,"stage-parent"),(src,"stage-source"),(fd,"stage-journal")]+[(x,"stage-source-parent") for x in src_open]+[(x,"stage-journal-parent") for x in opened])
PY
}

m3_tx_install() {
  local journal_component="$1"
  [[ "${M3_DRY_RUN:-0}" == 1 ]] && return 0
  m3_lexical_components "$journal_component" || return $?
  m3_fd_role_check || return $?
  python3 - "$journal_component" <<'PY'
import json, os, stat, sys
name=sys.argv[1]
def fail(reason,rc=56):
 print("M3_FAILURE stage=install operation=owner-install reason=%s rc=%d"%(reason,rc),file=sys.stderr); raise SystemExit(rc)
def parts(v):
 x=v.split("/")
 if any(not p or p in (".","..") or "/" in p for p in x): fail("unsafe-component")
 return x
def finish_owned_closes(primary, owned):
 failures=[]
 for descriptor,role in owned:
  if descriptor is None: continue
  try: os.close(descriptor)
  except OSError as exc: failures.append({"code":"E_DESCRIPTOR_CLOSE","fd_role":role,"errno":exc.errno})
 if failures:
  rc=79 if primary is None else 78
  primary_record=None if primary is None else {"type":type(primary).__name__,"code":getattr(primary,"code",None),"text":str(primary)}
  print("M3_FAILURE stage=install operation=owner-install reason=E_DESCRIPTOR_CLOSE rc=%d primary=%s close_failures=%s"%(rc,json.dumps(primary_record,sort_keys=True,separators=(",",":")),json.dumps(failures,sort_keys=True,separators=(",",":"))),file=sys.stderr)
  raise SystemExit(rc)
 if primary is not None: raise primary
def open_rel(root,v,flags):
 cur=root; opened=[]
 for p in parts(v)[:-1]: cur=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=cur); opened.append(cur)
 return os.open(parts(v)[-1],flags|os.O_NOFOLLOW,dir_fd=cur),cur,opened
fd=None; parent=None; opened=[]; topened=[]; primary=None
try:
 fd,parent,opened=open_rel(19,name,os.O_RDWR)
 j=json.loads(os.read(fd,64*1024*1024).decode())
 if j.get("state")!="staged" or j.get("journal_fd")!=19: fail("journal-state")
 root=17 if j.get("target_role")=="project" else 18 if j.get("target_role")=="home" else 0
 if not root: fail("target-role")
 target_parent=None
 tp=parts(j["target_components"]); bp=parts(j["backup_components"]); sp=parts(j["stage_components"])
 if tp[:-1]!=bp[:-1]: fail("backup-not-sibling")
 if j.get("created_target_dirs") != []: fail("created-target-dirs-not-empty")
 cur=root
 for component_index,p in enumerate(tp[:-1]):
  try: nxt=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=cur)
  except FileNotFoundError:
   os.mkdir(p,0o700,dir_fd=cur)
   j["created_target_dirs"].append({"target_role":j["target_role"],"relative_components":tp[:component_index+1]})
   nxt=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=cur)
  topened.append(nxt); cur=nxt
 target_parent=cur
 stage_parent=12
 for p in sp[:-1]: stage_parent=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=stage_parent); topened.append(stage_parent)
 leaf=tp[-1]; backup=bp[-1]; stage_leaf=sp[-1]
 def leaf_state(parent_fd, component, label):
  try:
   result=os.stat(component,dir_fd=parent_fd,follow_symlinks=False)
  except FileNotFoundError:
   return None
  except OSError:
   fail(label+"-stat-unsafe")
  if stat.S_ISLNK(result.st_mode): fail(label+"-symlink")
  if not (stat.S_ISREG(result.st_mode) or stat.S_ISDIR(result.st_mode)): fail(label+"-special")
  return result
 if leaf_state(target_parent,backup,"backup") is not None: fail("backup-exists")
 if leaf_state(target_parent,leaf,"target") is not None:
  os.rename(leaf,backup,src_dir_fd=target_parent,dst_dir_fd=target_parent); j["backup_moved"]=True
 os.rename(stage_leaf,leaf,src_dir_fd=stage_parent,dst_dir_fd=target_parent); j["installed"]=True; j["state"]="installed"
 os.lseek(fd,0,os.SEEK_SET); os.ftruncate(fd,0); os.write(fd,(json.dumps(j,sort_keys=True,separators=(",",":"))+"\n").encode()); os.fsync(fd)
 print(json.dumps({"status":"installed","backup_fd":root,"target_fd":root,"journal_fd":19},sort_keys=True,separators=(",",":")))
except BaseException as exc: primary=exc
finish_owned_closes(primary,[(fd,"install-journal")]+[(x,"install-owned-parent") for x in topened+opened])
PY
}

m3_tx_rollback() {
  local journal_component="$1"
  [[ "${M3_DRY_RUN:-0}" == 1 ]] && return 0
  m3_lexical_components "$journal_component" || return $?
  m3_fd_role_check || return $?
  python3 - "$journal_component" <<'PY'
import json, os, stat, sys
name=sys.argv[1]
def fail(reason,rc=57):
 print("M3_FAILURE stage=rollback operation=owner-rollback reason=%s rc=%d"%(reason,rc),file=sys.stderr); raise SystemExit(rc)
def parts(v):
 x=v.split("/")
 if any(not p or p in (".","..") or "/" in p for p in x): fail("unsafe-component")
 return x
def finish_owned_closes(primary, owned):
 failures=[]
 for descriptor,role in owned:
  if descriptor is None: continue
  try: os.close(descriptor)
  except OSError as exc: failures.append({"code":"E_DESCRIPTOR_CLOSE","fd_role":role,"errno":exc.errno})
 if failures:
  rc=79 if primary is None else 78
  primary_record=None if primary is None else {"type":type(primary).__name__,"code":getattr(primary,"code",None),"text":str(primary)}
  print("M3_FAILURE stage=rollback operation=owner-rollback reason=E_DESCRIPTOR_CLOSE rc=%d primary=%s close_failures=%s"%(rc,json.dumps(primary_record,sort_keys=True,separators=(",",":")),json.dumps(failures,sort_keys=True,separators=(",",":"))),file=sys.stderr)
  print("M3_ROLLBACK_RESTORE_FAILURE code=E_DESCRIPTOR_CLOSE details=%s"%json.dumps(failures,sort_keys=True,separators=(",",":")),file=sys.stderr)
  raise SystemExit(rc)
 if primary is not None: raise primary
def remove_tree(parent,leaf):
 try: st=os.stat(leaf,dir_fd=parent,follow_symlinks=False)
 except FileNotFoundError: return
 if stat.S_ISLNK(st.st_mode): fail("rollback-symlink")
 if stat.S_ISDIR(st.st_mode):
 d=os.open(leaf,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=parent)
  primary=None
  try:
   for child in sorted(os.listdir(d)): remove_tree(d,child)
  except BaseException as exc: primary=exc
  finish_owned_closes(primary,[(d,"rollback-tree-directory")])
 os.rmdir(leaf,dir_fd=parent)
 else: os.unlink(leaf,dir_fd=parent)
def frozen_created_directories(journal, frozen_role):
 records=journal.get("created_target_dirs")
 if not isinstance(records,list): fail("created-target-dirs-shape")
 validated=[]; identities=set()
 for record in records:
  if not isinstance(record,dict) or set(record)!={"target_role","relative_components"}: fail("created-target-dir-fields")
  role=record.get("target_role"); components=record.get("relative_components")
  if role!=frozen_role or role not in ("project","home"): fail("created-target-dir-role-drift")
  if not isinstance(components,list) or not components: fail("created-target-dir-components")
  if any(not isinstance(component,str) or not component or component in (".","..") or "/" in component for component in components): fail("created-target-dir-lexical")
  identity=(role,tuple(components))
  if identity in identities: fail("created-target-dir-duplicate")
  identities.add(identity); validated.append({"target_role":role,"relative_components":components})
 return sorted(validated,key=lambda record:(-len(record["relative_components"]),tuple(record["relative_components"])))
def cleanup_created_directory(record):
 role=record["target_role"]; components=record["relative_components"]
 role_root=17 if role=="project" else 18
 current=role_root; cleanup_parents=[]; primary=None; missing=False
 try:
  for component in components[:-1]:
   try: nxt=os.open(component,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=current)
   except FileNotFoundError:
    missing=True; break
   except OSError: fail("created-directory-parent-unsafe")
   cleanup_parents.append(nxt); current=nxt
  if not missing:
   try: os.rmdir(components[-1],dir_fd=current)
   except FileNotFoundError: missing=True
   except OSError: fail("created-directory-cleanup")
 except BaseException as exc: primary=exc
 finish_owned_closes(primary,[(descriptor,"rollback-created-directory-parent") for descriptor in reversed(cleanup_parents)])
fd=19
items=parts(name); opened=[]
targets=[]; jf=None; primary=None
try:
 for p in items[:-1]: fd=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=fd); opened.append(fd)
 jf=os.open(items[-1],os.O_RDWR|os.O_NOFOLLOW,dir_fd=fd); j=json.loads(os.read(jf,64*1024*1024).decode())
 if j.get("journal_fd")!=19 or j.get("state") not in ("installed","staged","planned"): fail("journal-owner-or-state")
 frozen_target_role=j.get("target_role")
 root=17 if frozen_target_role=="project" else 18 if frozen_target_role=="home" else 0
 if not root: fail("target-role")
 tp=parts(j["target_components"]); bp=parts(j["backup_components"]); sp=parts(j["stage_components"])
 if tp[:-1]!=bp[:-1]: fail("backup-not-sibling")
 cur=root; targets=[]
 for p in tp[:-1]: cur=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=cur); targets.append(cur)
 parent=cur; leaf=tp[-1]; backup=bp[-1]
 if j.get("installed"): remove_tree(parent,leaf)
 if j.get("backup_moved"): os.rename(backup,leaf,src_dir_fd=parent,dst_dir_fd=parent)
 stage_parent=12
 for p in sp[:-1]: stage_parent=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=stage_parent); targets.append(stage_parent)
 remove_tree(stage_parent,sp[-1])
 for created_directory in frozen_created_directories(j,frozen_target_role): cleanup_created_directory(created_directory)
 j["state"]="rolled-back"; os.lseek(jf,0,os.SEEK_SET); os.ftruncate(jf,0); os.write(jf,(json.dumps(j,sort_keys=True,separators=(",",":"))+"\n").encode()); os.fsync(jf)
 print(json.dumps({"status":"rolled-back","restored":bool(j.get("backup_moved")),"journal_fd":19},sort_keys=True,separators=(",",":")))
except BaseException as exc: primary=exc
finish_owned_closes(primary,[(jf,"rollback-journal")]+[(x,"rollback-owned-parent") for x in reversed(opened+targets)])
PY
}

m3_discard_stale_markers() {
  local marker="$1"
  [[ "${M3_DRY_RUN:-0}" == 1 ]] && return 0
  case "$marker" in
    .m3-stale-marker|.m3-stage-marker|.m3-backup-marker) ;;
    *) m3_fail cleanup marker-not-allowlisted "$marker" 58; return $? ;;
  esac
  python3 - "$marker" <<'PY'
import os, stat, sys, time
marker=sys.argv[1]
removed=[]
for fd in (12,13,14):
 try: st=os.stat(marker,dir_fd=fd,follow_symlinks=False)
 except OSError: continue
 if stat.S_ISREG(st.st_mode) and st.st_uid == os.geteuid() and time.time_ns()-st.st_mtime_ns > 60*1_000_000_000:
  try: os.unlink(marker,dir_fd=fd); removed.append(fd)
  except OSError:
   print("M3_FAILURE stage=cleanup operation=discard-marker reason=unlink-failed rc=59",file=sys.stderr); raise SystemExit(59)
print("M3_MARKERS_DISCARDED=%s" % ",".join(str(x) for x in removed))
PY
}

m3_dry_run() {
  local manifest="$1"
  local profiles="$2"
  [[ "${M3_DRY_RUN:-0}" == 1 ]] || { m3_fail dry-run mode-not-enabled pure-dry-run-required 60; return $?; }
  m3_manifest_check "$manifest" "$profiles" || return $?
  m3_fd_role_check || return $?
  printf '%s\n' '{"status":"passed","dry_run":true,"writes":0,"ledger_append":false,"target_mutations":0,"marker_discard":false}'
}

m3_close_one() {
  case "$1" in
    12) exec 12>&- ;;
    13) exec 13>&- ;;
    14) exec 14>&- ;;
    16) exec 16<&- ;;
    17) exec 17<&- ;;
    18) exec 18<&- ;;
    19) exec 19<&- ;;
    *) m3_fail cleanup close-fd-unknown "$1" 61; return $? ;;
  esac
}

m3_close_aggregate() {
  local primary="$1"
  local secondary="$2"
  local primary_rc=0
  local secondary_rc=0
  m3_close_one "$primary" || primary_rc=$?
  m3_close_one "$secondary" || secondary_rc=$?
  printf '%s\n' "M3_CLOSE primary=${primary}:rc=${primary_rc} secondary=${secondary}:rc=${secondary_rc}" >&2
  if (( primary_rc != 0 )); then return "$primary_rc"; fi
  return "$secondary_rc"
}

m3_exports() {
  printf '%s\n' 'm3_fd_role_check m3_lexical_components m3_manifest_check m3_source_digest m3_entry_digest m3_authorize_transaction m3_tx_plan m3_tx_stage m3_tx_install m3_tx_rollback m3_discard_stale_markers m3_dry_run m3_close_one m3_close_aggregate'
}

agency269_cli_main "$@"
