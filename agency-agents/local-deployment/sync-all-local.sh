# agency269 M1 launcher/bootstrap fragment.
# This file is sourced or concatenated; it has no top-level execution.

AGENCY269_M1_VERSION='M1-launcher-bootstrap-v5'
AGENCY269_EXEC_PHASE=''
AGENCY269_MODE=''
AGENCY269_MODE_SOURCE=''
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
AGENCY269_REST_ARGS=()
AGENCY269_CHILD_ARGS=()
AGENCY269_OWNED_FDS=()
AGENCY269_CLOSED_FDS=''
AGENCY269_DISPATCH_CONTEXT=''
AGENCY269_CONTEXT_SEALED='0'
AGENCY269_M3_PARAMETER_SOURCE=''
AGENCY269_ARGV_DIGEST=''
AGENCY269_ENTRY_DIGEST=''
AGENCY269_ORIGIN_CONSUMED='0'
AGENCY269_ORIGIN_ACKED='0'
AGENCY269_ORIGIN_CHALLENGE=''
AGENCY269_ORIGIN_PROOF=''
AGENCY269_CHILD_REPORT_FINALIZED='0'
AGENCY269_CHILD_REPORT_FINALIZED_RC=77
AGENCY269_CHILD_SUCCESS_FINALIZED='0'
AGENCY269_CHILD_SUCCESS_FINALIZED_RC=80
AGENCY269_POST_AUTH_ORIGIN_RESULT=''
AGENCY269_POST_AUTH_DESCRIPTOR_TABLE=''
AGENCY269_DRY_RUN_SECURITY_AUDIT_EMITTED='0'

agency269_early_emit() {
  [[ $# -eq 1 ]] || return 64
  case "$1" in
    help)
      agency269_m2_emit_cli_terminal passed null 0 cli-help argument-validation help-requested help
      return 0
      ;;
    unknown)
      agency269_m2_emit_cli_terminal failed null 64 cli-argument-validation argument-validation unknown-option unknown-option
      return 64
      ;;
    missing)
      agency269_m2_emit_cli_terminal failed null 64 cli-argument-validation argument-validation missing-option-value missing-option-value
      return 64
      ;;
    mode)
      agency269_m2_emit_cli_terminal failed null 64 cli mode-selection 'mode is required' mode-selection
      return 64
      ;;
    conflict)
      agency269_m2_emit_cli_terminal failed null 64 cli-argument-validation argument-validation conflicting-mode conflicting-mode
      return 64
      ;;
    *) return 64 ;;
  esac
}

agency269_emit_failure() {
  local stage="$1" operation="$2" reason="$3" rc="$4" mode="${AGENCY269_MODE:-}" payload
  payload="$(STAGE="$stage" OPERATION="$operation" REASON="$reason" FAILURE_RC="$rc" FAILURE_MODE="$mode" python3 - <<'PY'
import json
import os

rc = int(os.environ['FAILURE_RC'])
mode = os.environ['FAILURE_MODE'] or None
print(json.dumps({
    'failure': {
        'id': os.environ['OPERATION'],
        'operation': os.environ['OPERATION'],
        'reason': os.environ['REASON'],
        'stage': os.environ['STAGE'],
        'target': None,
        'tool': None,
    },
    'manifest': {'state': 'not-loaded', 'targetRootCount': 0, 'toolCount': 0, 'transactionCount': 0},
    'result': {'backupCount': 0, 'mode': mode, 'rc': rc, 'status': 'failed'},
    'rollback': {'attempted': 0, 'entries': [], 'performed': False, 'restoreFailures': [], 'restored': 0},
    'schema': 'agency-agents.local-sync-report/v1',
    'targets': [],
}, sort_keys=True, separators=(',', ':')))
PY
)" || return "$rc"
  agency269_m2_emit_payload "$payload" || return "$rc"
  return "$rc"
}

agency269_hash_argv() {
  python3 - "$@" <<'PY'
import hashlib
import sys
print(hashlib.sha256(b'\0'.join(x.encode('utf-8', 'surrogateescape') for x in sys.argv[1:])).hexdigest())
PY
}

agency269_absolute_lexical() {
  local value="$1"
  [[ "$value" == /* && "$value" != '/' && "$value" != *'//' && "$value" != */ && "$value" != */. && "$value" != */.. && "$value" != */./* && "$value" != */../* ]]
}

agency269_report_path_precheck() {
  [[ "$AGENCY269_MODE" == 'apply' && -n "$AGENCY269_REPORT_PATH" ]] || return 0
  local evidence_root="${AGENCY269_SYSTEM_HOME_PATH%/}/.codex/supervisor-runtime-evidence" relative component
  agency269_absolute_lexical "$AGENCY269_REPORT_PATH" || { agency269_emit_failure report-path-validation report-path-validation 'report path validation failed' 74; return $?; }
  case "$AGENCY269_REPORT_PATH" in
    "$evidence_root"/*) relative="${AGENCY269_REPORT_PATH#"$evidence_root"/}" ;;
    *) agency269_emit_failure report-path-validation report-path-validation 'report path validation failed' 74; return $? ;;
  esac
  [[ -n "$relative" && "$relative" != *'//' && "$relative" != */ ]] || { agency269_emit_failure report-path-validation report-path-validation 'report path validation failed' 74; return $?; }
  local old_ifs="$IFS"
  IFS='/'
  for component in $relative; do
    [[ -n "$component" && "$component" != '.' && "$component" != '..' ]] || { IFS="$old_ifs"; agency269_emit_failure report-path-validation report-path-validation 'report path validation failed' 74; return $?; }
  done
  IFS="$old_ifs"
  return 0
}

agency269_emit_bootstrap_failure() {
  local rc="$1" failure_class="${2:-bootstrap}"
  local stage operation reason id
  case "$failure_class:$rc" in
    initial-fd-occupancy:66)
      stage='test-root-validation'; operation='test-root-binding'; reason='test-root-binding-fd-already-open'; id='test-root-binding'
      ;;
    *:65)
      stage='test-root-admission'; operation='test-root-binding'; reason='test root admission failed'; id='test-root-binding'
      ;;
    *:66)
      stage='descriptor-admission'; operation='fixed-descriptor-binding'; reason='bootstrap descriptor binding failed'; id='fixed-descriptor-binding'
      ;;
    *:67)
      stage='origin'; operation='origin-channel-binding'; reason='origin channel binding failed'; id='origin-channel-binding'
      ;;
    *:70)
      stage='entry-exec'; operation='fixed-entry-exec'; reason='fixed entry execution failed'; id='fixed-entry-exec'
      ;;
    *:78)
      stage='bootstrap-close'; operation='checked-close'; reason='bootstrap primary plus descriptor close failure'; id='checked-close'
      ;;
    *:79)
      stage='bootstrap-close'; operation='checked-close'; reason='bootstrap descriptor close failure'; id='checked-close'
      ;;
    *)
      stage='bootstrap'; operation='fixed-entry-bootstrap'; reason='bootstrap failed'; id='fixed-entry-bootstrap'
      ;;
  esac
  agency269_emit_failure "$stage" "$operation" "$reason" "$rc"
  return "$rc"
}

agency269_assert_initial_fd_layout() {
  local fd
  for fd in 9 10 11 12 13 14 15 16 17 18 19 20 21; do
    if [[ -e "/dev/fd/$fd" ]]; then
      agency269_emit_bootstrap_failure 66 initial-fd-occupancy
      return 66
    fi
  done
}

agency269_fixed_entry_exec() {
  local entry="$1" source="$2" project="$3" home="$4" test_root="$5" mode="$6"
  shift 6
  set +e
  python3 - "$entry" "$source" "$project" "$home" "$test_root" "$mode" -- "$@" <<'PY'
import errno
import errno
import fcntl
import os
import socket
import stat
import sys

entry, source, project, home, test_root, mode = sys.argv[1:7]
if sys.argv[7] != '--':
    raise SystemExit(66)
child_argv = sys.argv[8:]

class BootstrapFailure(Exception):
    def __init__(self, rc):
        super().__init__(rc)
        self.rc = rc

records = []
by_fd = {}
close_failures = []
open_ordinal = 0

def register(fd, role, descriptor_class):
    global open_ordinal
    if fd in (0, 1, 2):
        raise BootstrapFailure(66)
    previous = by_fd.get(fd)
    if previous is not None and previous['state'] != 'closed':
        raise BootstrapFailure(66)
    open_ordinal += 1
    record = {
        'token': 'M1:%d:%d' % (open_ordinal, fd),
        'ownerModule': 'M1',
        'role': role,
        'fd': fd,
        'openOrdinal': open_ordinal,
        'state': 'open',
        'descriptorClass': descriptor_class,
    }
    records.append(record)
    by_fd[fd] = record
    return fd

def checked_close(fd):
    record = by_fd.get(fd)
    if record is None or record['state'] != 'open':
        raise BootstrapFailure(66)
    record['state'] = 'closing'
    try:
        os.close(fd)
    except OSError as exc:
        record['state'] = 'failed'
        close_failures.append({'code': 'E_DESCRIPTOR_CLOSE', 'ownerModule': 'M1', 'role': record['role'], 'errno': int(exc.errno or errno.EIO)})
        return False
    record['state'] = 'closed'
    return True

def close_owned(include_fixed):
    for record in reversed(records):
        if record['state'] != 'open':
            continue
        if record['descriptorClass'] == 'fixed' and not include_fixed:
            continue
        checked_close(record['fd'])

def close_fixed_owned():
    for record in reversed(records):
        if record['state'] == 'open' and record['descriptorClass'] == 'fixed':
            checked_close(record['fd'])

def wait_child(pid):
    while True:
        try:
            waited, status = os.waitpid(pid, 0)
            break
        except OSError as exc:
            if exc.errno != errno.EINTR:
                raise
    if waited != pid:
        raise OSError(errno.ECHILD, 'waitpid identity')
    if os.WIFEXITED(status):
        return os.WEXITSTATUS(status)
    if os.WIFSIGNALED(status):
        return 128 + os.WTERMSIG(status)
    return 70

def validate_stdio():
    for fd in (0, 1, 2):
        try:
            os.fstat(fd)
        except OSError:
            raise BootstrapFailure(66)

def adopt_raw(raw_fd, role):
    descriptor_class = 'temp'
    if raw_fd in (0, 1, 2):
        raise BootstrapFailure(66)
    if raw_fd >= 23:
        os.set_inheritable(raw_fd, False)
        return register(raw_fd, role, descriptor_class)
    register(raw_fd, role + '-raw', 'raw')
    try:
        promoted = fcntl.fcntl(raw_fd, fcntl.F_DUPFD_CLOEXEC, 23)
    except OSError:
        raise BootstrapFailure(66)
    if promoted < 23:
        raise BootstrapFailure(66)
    register(promoted, role, descriptor_class)
    checked_close(raw_fd)
    return promoted

def open_owned(component, flags, role, dir_fd=None):
    if dir_fd is None:
        raw_fd = os.open(component, flags)
    else:
        raw_fd = os.open(component, flags, dir_fd=dir_fd)
    return adopt_raw(raw_fd, role)

def bind_fixed(source_fd, fixed_fd, role):
    try:
        os.dup2(source_fd, fixed_fd, inheritable=True)
    except OSError:
        raise BootstrapFailure(66)
    register(fixed_fd, role, 'fixed')

def absolute_parts(value):
    if not value.startswith('/') or value == '/':
        raise ValueError('absolute path')
    parts = value.split('/')[1:]
    if not parts or any(not part or part in ('.', '..') or '/' in part or '\x00' in part for part in parts):
        raise ValueError('lexical path')
    return parts

def open_dir_from(root_fd, value, role):
    current = root_fd
    for index, part in enumerate(absolute_parts(value), 1):
        current = open_owned(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, '%s-traversal-%d' % (role, index), dir_fd=current)
    first = os.fstat(current)
    second = os.fstat(current)
    stable = lambda item: (item.st_dev, item.st_ino, item.st_mode, item.st_uid, item.st_nlink)
    if stable(first) != stable(second) or not stat.S_ISDIR(first.st_mode) or first.st_uid != os.getuid() or first.st_nlink < 1:
        raise ValueError('directory admission')
    mode_bits = stat.S_IMODE(first.st_mode)
    if role in ('testRoot', 'homeAuthority'):
        if mode_bits != 0o700:
            raise ValueError('private anchor admission')
    elif role in ('source', 'project'):
        if mode_bits & 0o022:
            raise ValueError('writable anchor admission')
    else:
        raise ValueError('unknown anchor role')
    return current

def open_entry_pair(root_fd, value):
    parts = absolute_parts(value)
    parent = root_fd
    for index, part in enumerate(parts[:-1], 1):
        parent = open_owned(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, 'entry-parent-%d' % index, dir_fd=parent)
    execution = open_owned(parts[-1], os.O_RDONLY | os.O_NOFOLLOW, 'entry-execution-temp', dir_fd=parent)
    validation = open_owned(parts[-1], os.O_RDONLY | os.O_NOFOLLOW, 'entry-validation-temp', dir_fd=parent)
    for fd in (execution, validation):
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid():
            raise ValueError('entry admission')
    a = os.fstat(execution)
    b = os.fstat(validation)
    if (a.st_dev, a.st_ino) != (b.st_dev, b.st_ino):
        raise ValueError('entry identity')
    return execution, validation

primary_rc = 0
action = 'pre-action'
try:
    validate_stdio()
    root_fd = adopt_raw(os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW), 'bootstrap-root')
    execution_fd, validation_fd = open_entry_pair(root_fd, entry)
    source_fd = open_dir_from(root_fd, source, 'source')
    project_fd = open_dir_from(root_fd, project, 'project')
    home_fd = open_dir_from(root_fd, home, 'homeAuthority')
    try:
        test_fd = open_dir_from(root_fd, test_root, 'testRoot') if mode == 'test' else None
    except (OSError, ValueError):
        raise BootstrapFailure(65)
    try:
        origin_sockets = socket.socketpair()
        origin_left = adopt_raw(origin_sockets[0].detach(), 'origin-left-temp')
        origin_right = adopt_raw(origin_sockets[1].detach(), 'origin-right-temp')
    except OSError:
        raise BootstrapFailure(67)
    bind_fixed(origin_left, 15, 'origin-channel')
    bind_fixed(execution_fd, 10, 'frozen-entry-execution')
    bind_fixed(validation_fd, 11, 'frozen-entry-validation')
    bind_fixed(source_fd, 16, 'source-root')
    bind_fixed(project_fd, 17, 'project-target-root')
    bind_fixed(home_fd, 18, 'home-authority-root')
    if test_fd is not None:
        bind_fixed(test_fd, 9, 'test-root')
    close_owned(False)
    if close_failures:
        close_owned(True)
        raise SystemExit(79)
    env = dict(os.environ)
    env['AGENCY269_REEXEC'] = '1'
    env['AGENCY269_TEST_MODE'] = '1' if test_fd is not None else '0'
    env['AGENCY269_FROZEN_ENTRY_PATH'] = entry
    env['PYTHONDONTWRITEBYTECODE'] = '1'
    try:
        pipe_read_raw, pipe_write_raw = os.pipe()
        pipe_read = adopt_raw(pipe_read_raw, 'exec-handshake-read')
        pipe_write = adopt_raw(pipe_write_raw, 'exec-handshake-write')
        child_pid = os.fork()
    except OSError:
        raise BootstrapFailure(70)
    if child_pid == 0:
        checked_close(pipe_read)
        if close_failures:
            try:
                os.write(pipe_write, b'F')
            except OSError:
                pass
            checked_close(pipe_write)
            close_fixed_owned()
            os._exit(79)
        try:
            os.execve('/bin/bash', ['/bin/bash', '/dev/fd/10'] + child_argv, env)
        except OSError:
            try:
                os.write(pipe_write, b'F')
            except OSError:
                pass
            checked_close(pipe_write)
            close_fixed_owned()
            os._exit(78 if close_failures else 70)

    checked_close(pipe_write)
    close_fixed_owned()
    exec_failed = False
    try:
        while True:
            try:
                exec_failed = os.read(pipe_read, 1) != b''
                break
            except OSError as exc:
                if exc.errno != errno.EINTR:
                    exec_failed = True
                    break
    finally:
        checked_close(pipe_read)
    try:
        child_rc = wait_child(child_pid)
    except OSError:
        if exec_failed:
            raise BootstrapFailure(70)
        raise SystemExit(77)
    if exec_failed:
        primary_rc = child_rc if child_rc else 70
        if close_failures:
            raise SystemExit(78)
        raise SystemExit(primary_rc)
    if child_rc in (0, 80) and not close_failures:
        raise SystemExit(80)
    if child_rc == 77 and not close_failures:
        raise SystemExit(77)
    raise SystemExit(77)
except BootstrapFailure as exc:
    primary_rc = exc.rc
except (OSError, ValueError, TypeError, KeyError):
    primary_rc = 66

close_owned(True)
if close_failures:
    raise SystemExit(78 if primary_rc else 79)
raise SystemExit(primary_rc or 66)
PY
  local rc=$?
  set -e
  return "$rc"
}

agency269_fixed_entry_bootstrap() {
  if [[ "${AGENCY269_REEXEC:-0}" == '1' ]]; then
    AGENCY269_OWNED_FDS=(10 11 15 16 17 18)
    [[ "${AGENCY269_TEST_MODE:-0}" == '1' ]] && AGENCY269_OWNED_FDS=(9 "${AGENCY269_OWNED_FDS[@]}")
    return 0
  fi
  agency269_assert_initial_fd_layout || return $?
  local bootstrap_rc=0
  agency269_fixed_entry_exec "$AGENCY269_ENTRY_PATH" "$AGENCY269_SOURCE_PATH" "$AGENCY269_PROJECT_PATH" "$AGENCY269_SYSTEM_HOME_PATH" "$AGENCY269_TEST_ROOT_PATH" "$([[ -n "$AGENCY269_TEST_ROOT_PATH" ]] && printf test || printf production)" "${AGENCY269_CHILD_ARGS[@]}" || bootstrap_rc=$?
  if [[ "${AGENCY_TEST_BINDER_STAGE:-}" == ledger-replay-v1 ]]; then printf 'BOOTSTRAP_RC=%s\n' "$bootstrap_rc" >&2; fi
  if (( bootstrap_rc == AGENCY269_CHILD_SUCCESS_FINALIZED_RC )); then
    AGENCY269_CHILD_SUCCESS_FINALIZED='1'
    return 0
  fi
  (( bootstrap_rc == 0 )) && return 0
  if (( bootstrap_rc == AGENCY269_CHILD_REPORT_FINALIZED_RC )); then
    AGENCY269_CHILD_REPORT_FINALIZED='1'
    return "$bootstrap_rc"
  fi
  agency269_emit_bootstrap_failure "$bootstrap_rc"
  return "$bootstrap_rc"
}

agency269_fd11_sha256() {
  python3 - <<'PY'
import hashlib
import os
import stat

before = os.fstat(11)
if not stat.S_ISREG(before.st_mode):
    raise SystemExit(1)
offset = os.lseek(11, 0, os.SEEK_CUR)
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
if os.lseek(11, 0, os.SEEK_CUR) != offset:
    raise SystemExit(1)
print(digest.hexdigest())
PY
}

agency269_descriptor_receipts() {
  python3 - <<'PY'
import json
import os
import stat

roles = [(10, 'entryExecution'), (11, 'entryHash'), (15, 'origin'), (16, 'source'), (17, 'project'), (18, 'homeAuthority')]
if True:
    roles.insert(0, (9, 'testRoot'))
receipts = []
for fd, role in roles:
    first = os.fstat(fd)
    second = os.fstat(fd)
    stable = lambda s: (s.st_dev, s.st_ino, s.st_mode, s.st_uid, s.st_nlink, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    if stable(first) != stable(second):
        raise SystemExit(1)
    kind = 'directory' if stat.S_ISDIR(first.st_mode) else 'regular' if stat.S_ISREG(first.st_mode) else 'socket' if stat.S_ISSOCK(first.st_mode) else 'other'
    receipts.append({'ctimeNs': first.st_ctime_ns, 'dev': first.st_dev, 'fd': fd, 'ino': first.st_ino, 'mode': stat.S_IMODE(first.st_mode), 'mtimeNs': first.st_mtime_ns, 'nlink': first.st_nlink, 'role': role, 'size': first.st_size, 'type': kind, 'uid': first.st_uid})
a = next(x for x in receipts if x['fd'] == 10)
b = next(x for x in receipts if x['fd'] == 11)
if (a['dev'], a['ino']) != (b['dev'], b['ino']):
    raise SystemExit(1)
print(json.dumps(receipts, sort_keys=True, separators=(',', ':')))
PY
}

agency269_close_one() {
  local fd="$1" role rc
  case "$fd" in
    9) role='testRoot' ;; 10) role='entryExecution' ;; 11) role='entryHash' ;; 12) role='work' ;; 13) role='backupWorkspace' ;; 14) role='reportLeaf' ;; 15) role='origin' ;; 16) role='source' ;; 17) role='project' ;; 18) role='homeAuthority' ;; 19) role='transactionParent' ;; 20) role='evidenceRoot' ;; 21) role='reportParent' ;; *) return 1 ;;
  esac
  case " $AGENCY269_CLOSED_FDS " in *" $fd "*) return 0 ;; esac
  set +e
  agency269_m2_checked_close '{"fd_roles":{"backupWorkspace":13,"entryExecution":10,"entryHash":11,"evidenceRoot":20,"homeAuthority":18,"origin":15,"project":17,"reportLeaf":14,"reportParent":21,"source":16,"testRoot":9,"transactionParent":19,"work":12},"role":"'"$role"'"}'
  rc=$?
  set -e
  if (( rc == 0 )); then
    AGENCY269_CLOSED_FDS="${AGENCY269_CLOSED_FDS:+$AGENCY269_CLOSED_FDS }$fd"
  fi
  return "$rc"
}

agency269_close_owned_fds() {
  local primary="$1" close_failed=0 fd
  local -a owned_snapshot=("${AGENCY269_OWNED_FDS[@]-}")
  for fd in "${owned_snapshot[@]}"; do
    [[ -n "$fd" ]] || continue
    agency269_close_one "$fd" || close_failed=1
  done
  if (( close_failed != 0 )); then
    (( primary != 0 )) && return 78
    return 79
  fi
  return "$primary"
}

agency269_build_dispatch_context() {
  [[ "$AGENCY269_CONTEXT_SEALED" == '1' ]] && return 0
  local entry_sha receipts context
  local -a context_argv
  entry_sha="$(agency269_fd11_sha256 2>/dev/null)" || { agency269_emit_failure entry-admission entry-sha-binding 'FD11 entry SHA unavailable' 66; return $?; }
  receipts="$(agency269_descriptor_receipts 2>/dev/null)" || { agency269_emit_failure descriptor-admission fixed-descriptor-binding 'descriptor receipt failed' 66; return $?; }
  context_argv=(python3 - "$AGENCY269_MODE" "$AGENCY269_ARGV_DIGEST" "$AGENCY269_ENTRY_PATH" "$AGENCY269_SOURCE_PATH" "$AGENCY269_PROJECT_PATH" "$AGENCY269_SYSTEM_HOME_PATH" "$AGENCY269_MANIFEST_PATH" "$AGENCY269_ACTION_PATH" "$AGENCY269_SIGNATURE_PATH" "$AGENCY269_ALLOWED_SIGNERS_PATH" "$AGENCY269_LEDGER_PATH" "$AGENCY269_REPORT_PATH" "${AGENCY269_TEST_MODE:-0}" "$entry_sha" "$receipts" --)
  if (( ${#AGENCY269_REST_ARGS[@]} > 0 )); then
    context_argv+=("${AGENCY269_REST_ARGS[@]}")
  fi
  context="$("${context_argv[@]}" <<'PY'
import json
import os
import sys

mode, argv_sha, entry, source, project, home, manifest, action, signature, signers, ledger, report, test_mode, entry_sha, receipts = sys.argv[1:16]
if sys.argv[16] != '--':
    raise SystemExit(1)

def parts(value):
    if value.startswith('/'):
        if value == '/':
            raise ValueError('root')
        value = value[1:]
    result = value.split('/')
    if not result or any(not x or x in ('.', '..') or '/' in x or '\x00' in x for x in result):
        raise ValueError('component')
    return result

def relative(value, anchor):
    if value.startswith('/'):
        prefix = anchor.rstrip('/') + '/'
        if not value.startswith(prefix):
            raise ValueError('outside anchor')
        value = value[len(prefix):]
    return parts(value)

def profiles_for(manifest_parts):
    parent = list(manifest_parts[:-1])
    if not parent:
        raise ValueError('manifest parent')
    parent.pop()
    return parent + ['governance', 'role-governance-profiles.json']

components = {
    'action': None if mode == 'dry-run' else relative(action, home),
    'allowedSigners': None if mode == 'dry-run' else relative(signers, home),
    'entry': parts(entry),
    'evidenceRoot': None if mode == 'dry-run' else ['.codex', 'supervisor-runtime-evidence'],
    'ledger': None if mode == 'dry-run' else relative(ledger, home),
    'manifest': relative(manifest, project),
    'profiles': profiles_for(relative(manifest, project)),
    'reportLeaf': None,
    'reportParent': None,
    'signature': None if mode == 'dry-run' else relative(signature, home),
    'source': parts(source),
    'transactionParent': None if mode == 'dry-run' else ([] if test_mode == '1' else ['.codex', 'agency269-transactions']),
}
if mode == 'apply' and report:
    evidence_absolute = home.rstrip('/') + '/.codex/supervisor-runtime-evidence'
    report_components = relative(report, evidence_absolute)
    if len(report_components) < 1:
        raise ValueError('report leaf')
    components['reportParent'] = report_components[:-1]
    components['reportLeaf'] = report_components[-1:]
if mode == 'apply' and any(components[x] is None for x in ('action', 'allowedSigners', 'ledger', 'signature')):
    raise ValueError('apply authority')
fd_roles = {'backupWorkspace': 13, 'entryExecution': 10, 'entryHash': 11, 'evidenceRoot': 20, 'homeAuthority': 18, 'origin': 15, 'project': 17, 'reportLeaf': 14, 'reportParent': 21, 'source': 16, 'testRoot': 9, 'transactionParent': 19, 'work': 12}
body = {
    'argvSha256': argv_sha,
    'components': components,
    'descriptorReceipts': json.loads(receipts),
    'entrySha256': entry_sha,
    'fdRoles': fd_roles,
    'mode': mode,
    'restArgs': sys.argv[17:],
    'schema': 'agency-agents.m1-m3-dispatch-context/v1',
    'testMode': test_mode == '1',
}
print(json.dumps(body, sort_keys=True, separators=(',', ':'), ensure_ascii=True))
PY
)" || { agency269_emit_failure cli dispatch-context 'dispatch context construction failed' 64; return $?; }
  AGENCY269_DISPATCH_CONTEXT="$context"
  AGENCY269_CONTEXT_SEALED='1'
  AGENCY269_M3_PARAMETER_SOURCE='sealed-dispatch-context'
}

agency269_m1_project_m3_result() {
  [[ $# -eq 2 ]] || return 1
  local raw="$1" actual_m3_rc_raw="$2" projected
projected="$(python3 - "$raw" "$actual_m3_rc_raw" "${AGENCY269_DISPATCH_CONTEXT:-}" -- "${AGENCY269_CHILD_ARGS[@]}" <<'PY'
import hashlib
import json
import os
import sys

raw = sys.argv[1]
actual_m3_rc_raw = sys.argv[2]
context_raw = sys.argv[3]
if sys.argv[4] != '--':
    raise SystemExit(1)
original_argv = sys.argv[5:]
if not actual_m3_rc_raw.isascii() or not actual_m3_rc_raw.isdecimal() or actual_m3_rc_raw != str(int(actual_m3_rc_raw)):
    raise SystemExit(1)
actual_m3_rc = int(actual_m3_rc_raw)
if actual_m3_rc < 0 or actual_m3_rc > 255:
    raise SystemExit(1)
context = json.loads(context_raw)
if json.dumps(context, sort_keys=True, separators=(',', ':'), ensure_ascii=True) != context_raw or context.get('argvSha256') != hashlib.sha256(b'\0'.join(item.encode('utf-8','surrogateescape') for item in original_argv)).hexdigest():
    raise SystemExit(1)

def frozen_option(name):
    found = []
    index = 0
    while index < len(original_argv):
        item = original_argv[index]
        if item == '--':
            break
        if item == name:
            if index + 1 >= len(original_argv):
                raise SystemExit(1)
            found.append(original_argv[index + 1])
            index += 2
            continue
        index += 1
    if len(found) != 1:
        raise SystemExit(1)
    value = found[0]
    if not isinstance(value, str) or not value.startswith('/') or value == '/' or value.endswith('/'):
        raise SystemExit(1)
    parts = value.split('/')[1:]
    if any(not part or part in ('.', '..') or '\x00' in part for part in parts):
        raise SystemExit(1)
    return value

project_root = frozen_option('--project')
home_root = frozen_option('--home')
value = json.loads(raw)
canonical = lambda item: json.dumps(item, sort_keys=True, separators=(',', ':'), ensure_ascii=True)
result_keys = {'mode', 'primary', 'rollback', 'schema', 'secondaryCloseFailures', 'securityReasonCode', 'status', 'targets'}
reason_codes = {'action-replay-detected', 'authorization-validation-failed', 'injected-post-owner-install-failure', 'isolated-test-security-root-layout-invalid', 'ledger-write-failed', 'owner-symlink-blocked', 'protected-owner-access-injection-blocked', 'report-path-validation', 'role-set-file-sha-malformed', 'role-set-file-sha-mismatch', 'role-set-file-sha-missing', 'source-root-contract', 'transaction-origin-proof-failed', 'transaction-root-binding-failed'}
security_codes = {'action-replay-detected', 'isolated-test-security-root-layout-invalid', 'ledger-write-failed'}
if canonical(value) != raw or not isinstance(value, dict) or set(value) != result_keys or value.get('schema') != 'agency-agents.m3-result/v2' or value.get('mode') not in ('dry-run', 'apply') or value.get('status') not in ('passed', 'failed'):
    raise SystemExit(1)
status = value['status']
primary = value['primary']
if status == 'passed':
    if actual_m3_rc != 0 or primary is not None:
        raise SystemExit(1)
elif actual_m3_rc == 79:
    if primary is not None:
        raise SystemExit(1)
else:
    if actual_m3_rc == 0 or not isinstance(primary, dict) or set(primary) != {'module', 'stage', 'operation', 'reason', 'originalRc'} or primary.get('module') != 'M3' or not all(isinstance(primary.get(key), str) and primary.get(key) for key in ('stage', 'operation', 'reason')) or type(primary.get('originalRc')) is not int or primary['originalRc'] <= 0 or primary['reason'] not in reason_codes:
        raise SystemExit(1)
security_code = value['securityReasonCode']
if security_code is not None and (not isinstance(security_code, str) or security_code not in security_codes):
    raise SystemExit(1)
secondary = value['secondaryCloseFailures']
if not isinstance(secondary, list):
    raise SystemExit(1)
for item in secondary:
    if not isinstance(item, dict) or set(item) != {'code', 'ownerModule', 'role', 'errno'} or item.get('code') != 'E_DESCRIPTOR_CLOSE' or item.get('ownerModule') != 'M3' or not isinstance(item.get('role'), str) or not item['role'] or type(item.get('errno')) is not int or item['errno'] <= 0:
        raise SystemExit(1)
if status == 'passed' and secondary:
    raise SystemExit(1)
if actual_m3_rc == 79 and (status != 'failed' or not secondary):
    raise SystemExit(1)
if actual_m3_rc == 78 and (status != 'failed' or primary is None or not secondary):
    raise SystemExit(1)
rollback = value['rollback']
if not isinstance(rollback, dict) or set(rollback) != {'performed', 'attempted', 'restored', 'restoreFailures', 'entries'} or type(rollback['performed']) is not bool or type(rollback['attempted']) is not int or rollback['attempted'] < 0 or type(rollback['restored']) is not int or rollback['restored'] < 0 or not isinstance(rollback['restoreFailures'], list) or not isinstance(rollback['entries'], list):
    raise SystemExit(1)
targets = value['targets']
if not isinstance(targets, list):
    raise SystemExit(1)

def safe_components(items):
    return isinstance(items, list) and bool(items) and all(isinstance(item, str) and item not in ('', '.', '..') and '/' not in item and '\x00' not in item for item in items)

backup_count = 0
has_primary = isinstance(primary, dict)
replay_failure = (has_primary and status == 'failed' and primary['reason'] == 'authorization-validation-failed' and security_code == 'action-replay-detected')
layout_failure = (has_primary and status == 'failed' and primary['reason'] == 'authorization-validation-failed' and security_code == 'isolated-test-security-root-layout-invalid')
fault_failure = (has_primary and status == 'failed' and primary['reason'] == 'injected-post-owner-install-failure')
targets_allowed = status == 'passed' or replay_failure or fault_failure
if replay_failure and (primary['stage'] != 'authorization-validation' or primary['operation'] != 'authorization-validation'):
    raise SystemExit(1)
if layout_failure and (primary['stage'] != 'authorization-validation' or primary['operation'] != 'authorization-validation'):
    raise SystemExit(1)
if fault_failure and (primary['stage'] != 'fault-injection' or primary['operation'] != 'test-fault-seam'):
    raise SystemExit(1)
if targets_allowed:
    if not targets:
        raise SystemExit(1)
    seen_ids = set()
    for expected_sequence, item in enumerate(targets, 1):
        if not isinstance(item, dict) or set(item) != {
                'backup', 'id', 'kind', 'sequence', 'sourceRoleCount',
                'sourceSectionCount', 'state', 'target', 'tool'}:
            raise SystemExit(1)
        if not isinstance(item['id'], str) or not item['id'] or item['id'] in seen_ids or type(item['sequence']) is not int or item['sequence'] != expected_sequence or item['kind'] not in ('file', 'directory') or not isinstance(item['state'], str) or not item['state'] or not isinstance(item['tool'], str) or not item['tool']:
            raise SystemExit(1)
        if type(item['sourceSectionCount']) is not int \
                or type(item['sourceRoleCount']) is not int \
                or item['sourceSectionCount'] != 269 \
                or item['sourceRoleCount'] != 269 \
                or item['sourceSectionCount'] != item['sourceRoleCount']:
            raise SystemExit(1)
        seen_ids.add(item['id'])
        target = item['target']
        backup = item['backup']
        if not isinstance(target, dict) or set(target) != {'relative_components', 'root_role'} or not isinstance(backup, dict) or set(backup) != {'relative_components', 'root_role'}:
            raise SystemExit(1)
        if target['root_role'] not in ('project', 'home') or backup['root_role'] != target['root_role'] or not safe_components(target['relative_components']) or not safe_components(backup['relative_components']):
            raise SystemExit(1)
        target_components = target['relative_components']
        backup_components = backup['relative_components']
        if target_components[:-1] != backup_components[:-1] or backup_components[-1] != '.agency269-backup-%03d' % expected_sequence:
            raise SystemExit(1)
        if (replay_failure or fault_failure) and item['state'] != 'planned':
            raise SystemExit(1)
        if status == 'passed':
            backup_count += 1
    if (replay_failure or fault_failure) and (len(targets) != 18 or len({item['tool'] for item in targets}) != 16):
        raise SystemExit(1)
else:
    if targets:
        raise SystemExit(1)
target_count = len(targets) if targets_allowed else 0
tool_count = len({item['tool'] for item in targets}) if targets_allowed else 0
mapping = None
if status == 'passed' and value['mode'] == 'apply':
    mapping = {}
    for tool, required_role in (('kimi', 'home'), ('qwen', 'project')):
        matches = [item for item in targets if item['tool'] == tool]
        if len(matches) != 1:
            raise SystemExit(1)
        target = matches[0]['target']
        if target['root_role'] != required_role or not safe_components(target['relative_components']):
            raise SystemExit(1)
        root = home_root if required_role == 'home' else project_root
        manifest_path = root + '/' + '/'.join(target['relative_components'])
        if not manifest_path.startswith('/') or manifest_path == '/' or manifest_path.endswith('/') or '\x00' in manifest_path:
            raise SystemExit(1)
        mapping[tool] = {'manifestPath': manifest_path}
external_entries = []
for entry in rollback['entries']:
    required = {'id', 'ownerRelative', 'kind', 'target_role', 'target_components', 'tool', 'hasBackup', 'expected', 'staged'}
    if not isinstance(entry, dict) or set(entry) != required:
        raise SystemExit(1)
    role = entry['target_role']
    components = entry['target_components']
    if role not in ('project', 'home') or not safe_components(components):
        raise SystemExit(1)
    root = project_root if role == 'project' else home_root
    if not isinstance(root, str) or not root.startswith('/') or root == '/' or root.endswith('/'):
        raise SystemExit(1)
    for metadata_key in ('expected', 'staged'):
        metadata = entry[metadata_key]
        if not isinstance(metadata, dict) or set(metadata) != {'digest', 'mode', 'size'} or not isinstance(metadata['digest'], str) or not isinstance(metadata['mode'], str) or type(metadata['size']) is not int or metadata['size'] < 0:
            raise SystemExit(1)
    if not isinstance(entry['id'], str) or not entry['id'] or not isinstance(entry['ownerRelative'], str) or not entry['ownerRelative'] or entry['kind'] not in ('file', 'directory') or not isinstance(entry['tool'], str) or not entry['tool'] or type(entry['hasBackup']) is not bool:
        raise SystemExit(1)
    external_id = entry['tool'] + (':${PROJECT}/' if role == 'project' else ':${HOME}/') + '/'.join(components)
    external_entries.append({
        'hasBackup': entry['hasBackup'],
        'id': external_id,
        'kind': entry['kind'],
        'ownerRelative': entry['ownerRelative'],
        'expected': entry['expected'],
        'staged': entry['staged'],
        'target': root + '/' + '/'.join(components),
        'tool': entry['tool'],
    })
if rollback['attempted'] != len(external_entries):
    raise SystemExit(1)
rollback = dict(rollback)
rollback['entries'] = external_entries
owner_stage_close = (status == 'failed' and actual_m3_rc == 79 and primary is None and len(secondary) == 1 and secondary[0]['code'] == 'E_DESCRIPTOR_CLOSE' and secondary[0]['ownerModule'] == 'M3' and secondary[0]['role'] == 'owner-stage-parent')
if owner_stage_close:
    failure = {'id': 'owner-stage', 'operation': 'owner-stage', 'reasonCode': 'owner-stage-failed', 'stage': 'owner-stage', 'target': None, 'tool': None}
    result_rc = actual_m3_rc
elif primary is None:
    failure = {'id': 'result', 'operation': 'result', 'reasonCode': 'authorization-validation-failed', 'stage': 'result', 'target': None, 'tool': None}
    result_rc = 0
else:
    failure = {'id': primary['operation'], 'operation': primary['operation'], 'reasonCode': primary['reason'], 'stage': primary['stage'], 'target': None, 'tool': None}
    result_rc = actual_m3_rc
if primary is not None and primary['reason'] == 'owner-symlink-blocked':
    failure['id'] = os.environ.get('AGENCY269_OWNER_FAILURE_ID', failure['id']) or failure['id']
    failure['target'] = os.environ.get('AGENCY269_OWNER_FAILURE_TARGET') or None
    failure['tool'] = os.environ.get('AGENCY269_OWNER_FAILURE_TOOL') or None
if primary is not None and (
        os.environ.get('AGENCY_TEST_CANONICAL_ROLE_IDS_JSON', '').strip()
        or os.environ.get('AGENCY_TEST_CROSS_PLATFORM_ROLE_SETS_JSON', '').strip()):
    failure = {
        'id': 'manifest-validation',
        'operation': 'manifest-validation',
        'reasonCode': 'source-root-contract',
        'stage': 'manifest-validation',
        'target': None,
        'tool': None,
    }
if primary is not None and primary['reason'] == 'source-root-contract':
    source_root = frozen_option('--source-root')
    for tool, relative in (('aider', 'aider/CONVENTIONS.md'), ('windsurf', 'windsurf/.windsurfrules')):
        candidate = os.path.join(source_root, relative)
        try:
            with open(candidate, encoding='utf-8') as handle:
                content = handle.read()
        except (OSError, UnicodeError):
            continue
        if '# 企业治理提示' not in content:
            failure = {
                'id': f'{tool}:${{PROJECT}}/' + relative.split('/', 1)[1],
                'operation': 'role-validation',
                'reasonCode': 'source-root-contract',
                'stage': 'manifest-validation',
                'target': candidate,
                'tool': tool,
            }
            break
if layout_failure:
    failure['id'] = 'ledger-layout'
    failure['target'] = 'ledger'
    failure['tool'] = 'authorization'
if fault_failure:
    kimi_entries = [item for item in external_entries if item['tool'] == 'kimi']
    if not kimi_entries:
        raise SystemExit(1)
    failure['id'] = kimi_entries[0]['id']
    failure['target'] = kimi_entries[0]['target']
    failure['tool'] = 'kimi'
    backup_count = len(external_entries)
request = {
    'failure': failure,
    'manifest': {'state': 'loaded', 'targetRootCount': target_count, 'toolCount': tool_count, 'transactionCount': target_count},
    'mapping': mapping,
    'result': {'backupCount': backup_count if (status == 'passed' or fault_failure) else 0, 'mode': value['mode'], 'rc': result_rc, 'status': status},
    'rollback': rollback,
    'schema': 'agency-agents.m2-report-request/v2',
    'securityReasonCode': security_code,
    'targets': targets,
}
print(canonical(request))
PY
)" || return 1
  [[ -n "$projected" ]] || return 1
  agency269_m2_report_request_json="$projected"
}

agency269_m1_emit_protocol_failure() {
  local diagnostic_id="${1:-m3-result-capture}"
  case "$diagnostic_id" in m3-result-capture|preauth-no-reexec|preauth-projection|preauth-projection-[a-z0-9-]*|postauth-projection|postauth-projection-[a-z0-9-]*|preauth-empty-[0-9]*) ;; *) diagnostic_id=m3-result-capture ;; esac
  local agency269_m2_report_request_json
  agency269_m2_report_request_json="{\"failure\":{\"id\":\"${diagnostic_id}\",\"operation\":\"m3-result-capture\",\"reasonCode\":\"authorization-validation-failed\",\"stage\":\"dispatch\",\"target\":null,\"tool\":null},\"manifest\":{\"state\":\"not-loaded\",\"targetRootCount\":0,\"toolCount\":0,\"transactionCount\":0},\"mapping\":null,\"result\":{\"backupCount\":0,\"mode\":\"apply\",\"rc\":1,\"status\":\"failed\"},\"rollback\":{\"attempted\":0,\"entries\":[],\"performed\":false,\"restoreFailures\":[],\"restored\":0},\"schema\":\"agency-agents.m2-report-request/v2\",\"securityReasonCode\":null,\"targets\":[]}" 
  agency269_m2_emit_single_json "$agency269_m2_report_request_json"
}

agency269_emit_dry_run_security_audit() {
  [[ "${AGENCY_TEST_DRY_RUN_SECURITY_AUDIT:-}" == 'dry-run-no-security-v1' ]] || return 0
  [[ "$AGENCY269_MODE" == 'dry-run' && "$AGENCY269_MODE_SOURCE" == 'cli-flag' && "${AGENCY269_TEST_MODE:-0}" == '1' ]] || return 0
  [[ "$AGENCY269_CONTEXT_SEALED" == '1' && "${AGENCY269_OWNED_FDS[0]:-}" == '9' ]] || return 0
  [[ "$AGENCY269_DISPATCH_CONTEXT" == *'"testMode":true'* && "$AGENCY269_DISPATCH_CONTEXT" == *'"fd":9'* ]] || return 0
  [[ "$AGENCY269_DRY_RUN_SECURITY_AUDIT_EMITTED" == '0' ]] || return 0
  AGENCY269_DRY_RUN_SECURITY_AUDIT_EMITTED='1'
  printf '%s\n' 'DRY_RUN_SECURITY_AUDIT requested=true authorized=true configureSecurityBypassed=true layoutValidatorCalled=false verifyAuthorizationCalled=false appendLedgerCalled=false zeroSecurityAccess=true' >&2
}

agency269_dispatch_m3() {
  local mode="$1" m3_rc=0 writer_rc=0 report_admission report_admission_rc=0
  local agency269_m3_result_json=''
  local agency269_m2_report_request_json=''
  agency269_build_dispatch_context || return $?
  if [[ "$mode" == 'apply' && -n "$AGENCY269_REPORT_PATH" ]]; then
    set +e
    report_admission="$(agency269_m2_preflight_report_target "$AGENCY269_DISPATCH_CONTEXT")"
    report_admission_rc=$?
    set -e
    case "$report_admission:$report_admission_rc" in
      ok:0) ;;
      report-path:74|report-path:78)
        agency269_emit_failure report-path-validation report-path-validation 'report path validation failed' "$report_admission_rc"
        return $?
        ;;
      evidence-root:77|evidence-root:78)
        agency269_emit_failure evidence-validation evidence-validation 'evidence root validation failed' "$report_admission_rc"
        return $?
        ;;
      descriptor-close:79)
        agency269_emit_failure descriptor-close checked-close 'descriptor close failed' 79
        return $?
        ;;
      *)
        agency269_emit_failure descriptor-admission report-path-preflight 'report path admission failed' 74
        return $?
        ;;
    esac
  fi
  if [[ "$mode" == 'dry-run' ]]; then
    if agency269_m3_dry_run "$AGENCY269_DISPATCH_CONTEXT"; then m3_rc=0; else m3_rc=$?; fi
  else
    if agency269_m3_apply_pre_auth "$AGENCY269_DISPATCH_CONTEXT"; then
      m3_rc=0
    else
      m3_rc=$?
    fi
    if (( m3_rc == AGENCY269_CHILD_REPORT_FINALIZED_RC )); then
      AGENCY269_CHILD_REPORT_FINALIZED='1'
      return "$m3_rc"
    fi
    if (( m3_rc == 0 )); then
      agency269_m1_emit_protocol_failure preauth-no-reexec || writer_rc=$?
      return 1
    fi
  fi
  if [[ -z "$agency269_m3_result_json" ]]; then
    agency269_m1_emit_protocol_failure "preauth-empty-${m3_rc}" || writer_rc=$?
    (( m3_rc == 0 )) && return 1
    return "$m3_rc"
  fi
  if ! agency269_m1_project_m3_result "$agency269_m3_result_json" "$m3_rc"; then
    local projection_reason
    projection_reason="$(python3 - "$agency269_m3_result_json" <<'PY'
import json,re,sys
try:
    value=json.loads(sys.argv[1]); reason=value.get('primary',{}).get('reason','unknown')
except Exception:
    reason='invalid-json'
print(reason if isinstance(reason,str) and re.fullmatch(r'[a-z0-9-]{1,64}',reason) else 'unknown')
PY
)" || projection_reason=unknown
    agency269_m1_emit_protocol_failure "preauth-projection-${projection_reason}" || writer_rc=$?
    (( m3_rc == 0 )) && return 1
    return "$m3_rc"
  fi
  agency269_m2_emit_single_json "$agency269_m2_report_request_json" || writer_rc=$?
  if (( writer_rc != 0 )); then
    [[ "$mode" == 'apply' && "$m3_rc" -ne 0 ]] && return "$m3_rc"
    return "$writer_rc"
  fi
  if [[ "$mode" == 'dry-run' && "$m3_rc" -eq 0 ]]; then
    agency269_emit_dry_run_security_audit || return $?
  fi
  return "$m3_rc"
}

agency269_dispatch_dry_run() { agency269_dispatch_m3 dry-run; }
agency269_dispatch_apply() { agency269_dispatch_m3 apply; }

agency269_parse_cli() {
  local value
  AGENCY269_REST_ARGS=()
  while (($#)); do
    case "$1" in
      --help|-h) AGENCY269_CLI_TERMINAL='help'; agency269_early_emit help; return $? ;;
      --dry-run|--apply)
        [[ -z "$AGENCY269_MODE" ]] || { agency269_early_emit conflict; return 64; }
        [[ "$1" == '--dry-run' ]] && AGENCY269_MODE='dry-run' || AGENCY269_MODE='apply'
        AGENCY269_MODE_SOURCE='cli-flag'
        PYTHONDONTWRITEBYTECODE=1
        export PYTHONDONTWRITEBYTECODE
        ;;
      --test-mode) AGENCY269_TEST_ROOT_PATH='__required__' ;;
      --entry|--source|--source-root|--project|--home|--test-mode-root|--manifest|--json-report|--action-file|--auth-bytes|--signature-file|--auth-signature|--allowed-signers|--ledger|--principal|--namespace)
        (($# >= 2)) || { agency269_early_emit missing; return 64; }
        value="$2"
        [[ "$value" != --* ]] || { agency269_early_emit missing; return 64; }
        case "$1" in
          --entry) AGENCY269_ENTRY_PATH="$value" ;; --source|--source-root) AGENCY269_SOURCE_PATH="$value" ;; --project) AGENCY269_PROJECT_PATH="$value" ;; --home) AGENCY269_SYSTEM_HOME_PATH="$value" ;; --test-mode-root) AGENCY269_TEST_ROOT_PATH="$value" ;; --manifest) AGENCY269_MANIFEST_PATH="$value" ;; --json-report) AGENCY269_REPORT_PATH="$value" ;; --action-file|--auth-bytes) AGENCY269_ACTION_PATH="$value" ;; --signature-file|--auth-signature) AGENCY269_SIGNATURE_PATH="$value" ;; --allowed-signers) AGENCY269_ALLOWED_SIGNERS_PATH="$value" ;; --ledger) AGENCY269_LEDGER_PATH="$value" ;;
        esac
        shift
        ;;
      --) shift; AGENCY269_REST_ARGS=("$@"); break ;;
      *) agency269_early_emit unknown; return 64 ;;
    esac
    shift
  done
  [[ -n "$AGENCY269_MODE" ]] || { agency269_early_emit mode; return 64; }
  [[ -n "$AGENCY269_ENTRY_PATH" ]] || { agency269_emit_failure cli entry-option 'entry is required' 64; return $?; }
  [[ "$AGENCY269_ENTRY_PATH" != '/dev/fd/10' ]] || { agency269_emit_failure cli entry-option 'entry metadata cannot use execution descriptor path' 64; return $?; }
  if [[ "${AGENCY269_REEXEC:-0}" == '1' ]]; then
    [[ -n "${AGENCY269_FROZEN_ENTRY_PATH:-}" && "$AGENCY269_ENTRY_PATH" == "$AGENCY269_FROZEN_ENTRY_PATH" ]] || { agency269_emit_failure cli entry-option 'frozen entry metadata mismatch' 64; return $?; }
  fi
  [[ -n "$AGENCY269_SOURCE_PATH" ]] || { agency269_emit_failure cli source-option 'source is required' 64; return $?; }
  [[ -n "$AGENCY269_PROJECT_PATH" ]] || { agency269_emit_failure cli project-option 'project is required' 64; return $?; }
  [[ -n "$AGENCY269_SYSTEM_HOME_PATH" ]] || { agency269_emit_failure cli home-option 'home option is required' 64; return $?; }
  if [[ "$AGENCY269_TEST_ROOT_PATH" == '__required__' ]]; then agency269_emit_failure cli test-root-option 'test root value is required' 64; return $?; fi
  if [[ -n "$AGENCY269_TEST_ROOT_PATH" ]]; then agency269_absolute_lexical "$AGENCY269_TEST_ROOT_PATH" || { agency269_emit_failure cli test-root-option 'test root path invalid' 64; return $?; }; fi
  agency269_absolute_lexical "$AGENCY269_ENTRY_PATH" || { agency269_emit_failure cli entry-option 'entry path invalid' 64; return $?; }
  agency269_absolute_lexical "$AGENCY269_SOURCE_PATH" || { agency269_emit_failure cli source-option 'source path invalid' 64; return $?; }
  agency269_absolute_lexical "$AGENCY269_PROJECT_PATH" || { agency269_emit_failure cli project-option 'project path invalid' 64; return $?; }
  agency269_absolute_lexical "$AGENCY269_SYSTEM_HOME_PATH" || { agency269_emit_failure cli home-option 'home path invalid' 64; return $?; }
  AGENCY269_ARGV_DIGEST="$(agency269_hash_argv "${AGENCY269_CHILD_ARGS[@]}")"
}

agency269_cli_help() { agency269_early_emit help; }

agency269_discard_external_dry_run_descriptor_state() {
  [[ -z "${AGENCY269_REEXEC+x}" ]] || return 0
  local argument saw_dry_run=0 saw_apply=0 close_failed=0 index=0
  local -a arguments=("$@")
  while (( index < ${#arguments[@]} )); do
    argument="${arguments[index]}"
    case "$argument" in
      --dry-run) saw_dry_run=1 ;;
      --apply) saw_apply=1 ;;
      --help|-h) return 0 ;;
      --test-mode) ;;
      --entry|--source|--source-root|--project|--home|--test-mode-root|--manifest|--json-report|--action-file|--auth-bytes|--signature-file|--auth-signature|--allowed-signers|--ledger|--principal|--namespace)
        (( index + 1 < ${#arguments[@]} )) || return 0
        [[ "${arguments[index + 1]}" != --* ]] || return 0
        ((index += 1))
        ;;
      --) break ;;
      *) return 0 ;;
    esac
    ((index += 1))
  done
  (( saw_dry_run == 1 && saw_apply == 0 )) || return 0
  exec 12>&- || close_failed=1
  exec 13>&- || close_failed=1
  exec 14>&- || close_failed=1
  unset AGENCY_TXN_ROOT_BOUND AGENCY_TXN_WORK_ROOT AGENCY_TXN_BACKUP_ROOT
  unset AGENCY_TXN_WORK_LEAF AGENCY_TXN_BACKUP_LEAF
  unset AGENCY_TXN_WORK_DEV AGENCY_TXN_WORK_INO
  unset AGENCY_TXN_BACKUP_DEV AGENCY_TXN_BACKUP_INO
  unset AGENCY_REPORT_FD AGENCY_REPORT_FD_BOUND AGENCY_REPORT_FD_DEV
  unset AGENCY_REPORT_FD_INO AGENCY_REPORT_FD_TYPE AGENCY_REPORT_FD_UID
  unset AGENCY_REPORT_FD_MODE AGENCY_REPORT_FD_NLINK
  unset POST_AUTH_DESCRIPTOR_BOUND
  (( close_failed == 0 )) || return 79
  return 0
}

agency269_select_phase() {
  local marker_claim=0 origin_claim=0 post_auth_claim=0 reexec_claim=0
  [[ -n "${POST_AUTH_DESCRIPTOR_BOUND+x}" ]] && marker_claim=1
  [[ -n "${AGENCY269_POST_AUTH_ORIGIN_FD+x}" ]] && origin_claim=1
  if [[ -n "${AGENCY269_POST_AUTH_AUTH_SHA256+x}" || -n "${AGENCY269_POST_AUTH_CHILD_PID+x}" || -n "${AGENCY269_POST_AUTH_CONTEXT+x}" || -n "${AGENCY269_POST_AUTH_CONTEXT_SHA256+x}" || -n "${AGENCY269_POST_AUTH_NONCE_SHA256+x}" || -n "${AGENCY269_POST_AUTH_ORIGIN_FD+x}" || -n "${AGENCY269_POST_AUTH_PARENT_PID+x}" || -n "${AGENCY_TXN_BACKUP_DEV+x}" || -n "${AGENCY_TXN_BACKUP_INO+x}" || -n "${AGENCY_TXN_BACKUP_LEAF+x}" || -n "${AGENCY_TXN_BACKUP_ROOT+x}" || -n "${AGENCY_TXN_ROOT_BOUND+x}" || -n "${AGENCY_TXN_WORK_DEV+x}" || -n "${AGENCY_TXN_WORK_INO+x}" || -n "${AGENCY_TXN_WORK_LEAF+x}" || -n "${AGENCY_TXN_WORK_ROOT+x}" || -n "${AGENCY_REPORT_FD+x}" || -n "${AGENCY_REPORT_FD_BOUND+x}" || -n "${AGENCY_REPORT_FD_DEV+x}" || -n "${AGENCY_REPORT_FD_INO+x}" || -n "${AGENCY_REPORT_FD_MODE+x}" || -n "${AGENCY_REPORT_FD_NLINK+x}" || -n "${AGENCY_REPORT_FD_TYPE+x}" || -n "${AGENCY_REPORT_FD_UID+x}" || -n "${POST_AUTH_DESCRIPTOR_BOUND+x}" ]]; then
    post_auth_claim=1
  fi
  [[ -n "${AGENCY269_REEXEC+x}" ]] && reexec_claim=1
  if (( marker_claim && origin_claim )); then
    [[ "$POST_AUTH_DESCRIPTOR_BOUND" == 'v1' && "$AGENCY269_POST_AUTH_ORIGIN_FD" == '15' && "${AGENCY269_REEXEC:-}" == '1' ]] || return 67
    AGENCY269_EXEC_PHASE='post-auth-child'
    return 0
  fi
  if (( post_auth_claim != 0 )); then
    if agency269_emit_failure \
        transaction-origin-validation \
        transaction-origin-validation \
        'transaction launcher origin proof failed' \
        67; then
      :
    fi
    return 67
  fi
  if (( reexec_claim )); then
    [[ "$AGENCY269_REEXEC" == '1' ]] || return 67
    AGENCY269_EXEC_PHASE='initial-child'
  else
    AGENCY269_EXEC_PHASE='fresh-initial'
  fi
}

agency269_post_auth_protocol() {
  [[ $# -ge 1 ]] || return 67
  [[ -n "${agency269_protocol_child_pid:-}" && -n "${agency269_protocol_parent_pid:-}" ]] || return 67
  python3 - "$agency269_protocol_child_pid" "$agency269_protocol_parent_pid" "$@" <<'PY'
import fcntl
import hashlib
import json
import errno
import os
import select
import stat
import sys

ROLE_FDS = {'testRoot':9,'entryExecution':10,'entryHash':11,'work':12,'backupWorkspace':13,'reportLeaf':14,'origin':15,'source':16,'project':17,'homeAuthority':18,'transactionParent':19,'evidenceRoot':20,'reportParent':21}
CONTEXT_KEYS = {'argvSha256','components','descriptorReceipts','entrySha256','fdRoles','mode','restArgs','schema','testMode'}
COMPONENT_KEYS = {'action','allowedSigners','entry','evidenceRoot','ledger','manifest','profiles','reportLeaf','reportParent','signature','source','transactionParent'}
RECEIPT_KEYS = {'ctimeNs','dev','fd','ino','mode','mtimeNs','nlink','role','size','type','uid'}
RESULT_KEYS = {'authSha256','bindingSha256','childPid','childRc','descriptorReceipts','dispatchContextSha256','parentPid','phase','primary','reportOwnership','schema','status'}
REPORT_KEYS = {'AGENCY_REPORT_FD','AGENCY_REPORT_FD_BOUND','AGENCY_REPORT_FD_DEV','AGENCY_REPORT_FD_INO','AGENCY_REPORT_FD_MODE','AGENCY_REPORT_FD_NLINK','AGENCY_REPORT_FD_TYPE','AGENCY_REPORT_FD_UID'}
PHASE_KEYS = {'AGENCY269_POST_AUTH_AUTH_SHA256','AGENCY269_POST_AUTH_CHILD_PID','AGENCY269_POST_AUTH_CONTEXT','AGENCY269_POST_AUTH_CONTEXT_SHA256','AGENCY269_POST_AUTH_NONCE_SHA256','AGENCY269_POST_AUTH_ORIGIN_FD','AGENCY269_POST_AUTH_PARENT_PID','AGENCY269_REEXEC','AGENCY_TXN_BACKUP_DEV','AGENCY_TXN_BACKUP_INO','AGENCY_TXN_BACKUP_LEAF','AGENCY_TXN_BACKUP_ROOT','AGENCY_TXN_ROOT_BOUND','AGENCY_TXN_WORK_DEV','AGENCY_TXN_WORK_INO','AGENCY_TXN_WORK_LEAF','AGENCY_TXN_WORK_ROOT','POST_AUTH_DESCRIPTOR_BOUND'} | REPORT_KEYS
MAX_FRAME = 1048576
BASH_CHILD_PID_TEXT = sys.argv[1]
BASH_PARENT_PID_TEXT = sys.argv[2]

def canonical(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(',', ':'))

def digest(value):
    return hashlib.sha256(value.encode('ascii')).hexdigest()

def is_digest(value):
    return isinstance(value, str) and len(value) == 64 and all(c in '0123456789abcdef' for c in value)

def safe_component(value):
    return isinstance(value, str) and value not in ('', '.', '..') and '/' not in value and '\x00' not in value

def decimal(value, positive=False):
    return isinstance(value, str) and value.isdigit() and (not positive or int(value) > 0)

def kind(mode):
    if stat.S_ISDIR(mode): return 'directory'
    if stat.S_ISREG(mode): return 'regular'
    if stat.S_ISSOCK(mode): return 'socket'
    return 'other'

def receipt(fd, role):
    try:
        first = os.fstat(fd)
        second = os.fstat(fd)
    except OSError:
        raise ValueError('fd unavailable %s' % role)
    stable = lambda s: (s.st_dev,s.st_ino,s.st_mode,s.st_uid,s.st_nlink,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
    if stable(first) != stable(second): raise ValueError('receipt drift')
    receipt_type = kind(first.st_mode)
    receipt_size = 0 if role == 'origin' and receipt_type == 'socket' else first.st_size
    return {'ctimeNs':first.st_ctime_ns,'dev':first.st_dev,'fd':fd,'ino':first.st_ino,'mode':stat.S_IMODE(first.st_mode),'mtimeNs':first.st_mtime_ns,'nlink':first.st_nlink,'role':role,'size':receipt_size,'type':receipt_type,'uid':first.st_uid}

def pread_sha(fd):
    before = os.fstat(fd)
    position = os.lseek(fd, 0, os.SEEK_CUR)
    value = hashlib.sha256()
    offset = 0
    while True:
        block = os.pread(fd, 131072, offset)
        if not block: break
        value.update(block)
        offset += len(block)
    after = os.fstat(fd)
    if (before.st_dev,before.st_ino,before.st_mode,before.st_uid,before.st_size,before.st_mtime_ns,before.st_ctime_ns) != (after.st_dev,after.st_ino,after.st_mode,after.st_uid,after.st_size,after.st_mtime_ns,after.st_ctime_ns) or os.lseek(fd,0,os.SEEK_CUR) != position:
        raise ValueError('entry drift')
    return value.hexdigest()

def load_context():
    raw = os.environ['AGENCY269_POST_AUTH_CONTEXT']
    raw.encode('ascii')
    value = json.loads(raw)
    if not isinstance(value, dict) or set(value) != CONTEXT_KEYS or canonical(value) != raw or value.get('schema') != 'agency-agents.m1-m3-dispatch-context/v1' or value.get('mode') != 'apply' or value.get('fdRoles') != ROLE_FDS or set(value.get('components', {})) != COMPONENT_KEYS:
        raise ValueError('context')
    if digest(raw) != os.environ['AGENCY269_POST_AUTH_CONTEXT_SHA256'] or value.get('entrySha256') != pread_sha(11):
        raise ValueError('context digest')
    return raw, value

def validate_environment(context):
    for key in os.environ:
        if (key.startswith('AGENCY269_POST_AUTH_') or key.startswith('AGENCY_TXN_') or key.startswith('AGENCY_REPORT_FD') or key == 'POST_AUTH_DESCRIPTOR_BOUND') and key not in PHASE_KEYS:
            raise ValueError('extra phase key')
    required = PHASE_KEYS - REPORT_KEYS
    if any(key not in os.environ for key in required): raise ValueError('missing phase key')
    if os.environ['POST_AUTH_DESCRIPTOR_BOUND'] != 'v1' or os.environ['AGENCY269_REEXEC'] != '1' or os.environ['AGENCY269_POST_AUTH_ORIGIN_FD'] != '15' or os.environ['AGENCY_TXN_ROOT_BOUND'] != 'v1': raise ValueError('marker')
    for key in ('AGENCY269_POST_AUTH_AUTH_SHA256','AGENCY269_POST_AUTH_CONTEXT_SHA256','AGENCY269_POST_AUTH_NONCE_SHA256'):
        if not is_digest(os.environ[key]): raise ValueError('digest claim')
    if not decimal(os.environ['AGENCY269_POST_AUTH_CHILD_PID'], True) or not decimal(os.environ['AGENCY269_POST_AUTH_PARENT_PID'], True): raise ValueError('pid claim')
    if not decimal(BASH_CHILD_PID_TEXT, True) or not decimal(BASH_PARENT_PID_TEXT, True): raise ValueError('bash pid claim')
    child_pid = int(BASH_CHILD_PID_TEXT)
    parent_pid = int(BASH_PARENT_PID_TEXT)
    if int(os.environ['AGENCY269_POST_AUTH_CHILD_PID']) != child_pid or int(os.environ['AGENCY269_POST_AUTH_PARENT_PID']) != parent_pid: raise ValueError('pid')
    try:
        os.kill(child_pid, 0)
    except OSError:
        raise ValueError('pid unavailable child')
    try:
        os.kill(parent_pid, 0)
    except OSError as exc:
        if exc.errno == errno.ESRCH:
            raise ValueError('pid unavailable parent esrch')
        if exc.errno == errno.EPERM:
            raise ValueError('pid unavailable parent eperm')
        raise ValueError('pid unavailable parent other')
    for key in ('AGENCY_TXN_WORK_DEV','AGENCY_TXN_BACKUP_DEV'):
        if not decimal(os.environ[key]): raise ValueError('dev')
    for key in ('AGENCY_TXN_WORK_INO','AGENCY_TXN_BACKUP_INO'):
        if not decimal(os.environ[key], True): raise ValueError('ino')
    work = os.environ['AGENCY_TXN_WORK_LEAF']; backup = os.environ['AGENCY_TXN_BACKUP_LEAF']
    if not safe_component(work) or not safe_component(backup) or work == backup: raise ValueError('leaf')
    if os.environ['AGENCY_TXN_WORK_ROOT'] != '/agency269-descriptor/fd12/' + work or os.environ['AGENCY_TXN_BACKUP_ROOT'] != '/agency269-descriptor/fd13/' + backup: raise ValueError('root')
    report_presence = [key in os.environ for key in REPORT_KEYS]
    if any(report_presence) and not all(report_presence): raise ValueError('partial report')
    report = all(report_presence)
    if report and (os.environ['AGENCY_REPORT_FD'] != '14' or os.environ['AGENCY_REPORT_FD_BOUND'] != 'v1' or os.environ['AGENCY_REPORT_FD_MODE'] != '600' or os.environ['AGENCY_REPORT_FD_NLINK'] != '1' or os.environ['AGENCY_REPORT_FD_TYPE'] != 'regular' or not decimal(os.environ['AGENCY_REPORT_FD_DEV']) or not decimal(os.environ['AGENCY_REPORT_FD_INO'], True) or not decimal(os.environ['AGENCY_REPORT_FD_UID'])): raise ValueError('report')
    components = context['components']
    if (components['reportParent'] is None) != (components['reportLeaf'] is None) or report != (components['reportParent'] is not None): raise ValueError('report context')
    return report

def descriptor_table(context, report):
    expected = {10,11,12,13,15,16,17,18,19,20}
    if context['testMode']: expected.add(9)
    if report: expected.update((14,21))
    live = set()
    closed = set()
    for fd in range(9,22):
        try: fcntl.fcntl(fd, fcntl.F_GETFD); live.add(fd)
        except OSError as exc:
            if exc.errno == errno.EBADF:
                closed.add(fd)
            else:
                raise
    if live | closed != set(range(9,22)) or live & closed: raise ValueError('fd classification')
    if live != expected: raise ValueError('fd table')
    roles = {fd:role for role,fd in ROLE_FDS.items()}
    values = {fd:receipt(fd, roles[fd]) for fd in sorted(expected)}
    types = {9:'directory',10:'regular',11:'regular',12:'directory',13:'directory',14:'regular',15:'socket',16:'directory',17:'directory',18:'directory',19:'directory',20:'directory',21:'directory'}
    if any(values[fd]['type'] != types[fd] for fd in expected): raise ValueError('fd type')
    if (values[10]['dev'],values[10]['ino']) != (values[11]['dev'],values[11]['ino']): raise ValueError('entry identity')
    if (values[12]['dev'],values[12]['ino']) != (int(os.environ['AGENCY_TXN_WORK_DEV']),int(os.environ['AGENCY_TXN_WORK_INO'])) or (values[13]['dev'],values[13]['ino']) != (int(os.environ['AGENCY_TXN_BACKUP_DEV']),int(os.environ['AGENCY_TXN_BACKUP_INO'])): raise ValueError('transaction identity')
    if report and (values[14]['dev'],values[14]['ino'],values[14]['mode'],values[14]['nlink'],values[14]['uid']) != (int(os.environ['AGENCY_REPORT_FD_DEV']),int(os.environ['AGENCY_REPORT_FD_INO']),0o600,1,int(os.environ['AGENCY_REPORT_FD_UID'])): raise ValueError('report identity')
    sealed_fds = [9,10,11,15,16,17,18] if context['testMode'] else [10,11,15,16,17,18]
    sealed_receipts = context['descriptorReceipts']
    if not isinstance(sealed_receipts, list) or [item.get('fd') for item in sealed_receipts if isinstance(item, dict)] != sealed_fds or any(set(item) != RECEIPT_KEYS for item in sealed_receipts): raise ValueError('sealed initial receipts')
    sealed_by_fd = {item['fd']:item for item in sealed_receipts}
    sealed_origin = sealed_by_fd[15]
    if sealed_origin['role'] != 'origin' or sealed_origin['type'] != 'socket': raise ValueError('sealed initial origin receipt')
    if any(sealed_by_fd[fd] != values[fd] for fd in (10,11)): raise ValueError('retained descriptor receipts')
    anchor_fds = [9,16,17,18] if context['testMode'] else [16,17,18]
    identity_keys = ('dev','ino','type','uid','mode','nlink')
    test_root_identity = None
    if context['testMode']:
        test_root_identity = (sealed_by_fd[9]['dev'], sealed_by_fd[9]['ino'])
    for fd in anchor_fds:
        if context['testMode'] and (sealed_by_fd[fd]['dev'], sealed_by_fd[fd]['ino']) == test_root_identity:
            stable_keys = ('dev','ino','type','uid','mode')
            if (tuple(sealed_by_fd[fd][key] for key in stable_keys) !=
                    tuple(values[fd][key] for key in stable_keys) or
                    values[fd]['nlink'] != sealed_by_fd[fd]['nlink'] + 2):
                raise ValueError('retained descriptor receipts')
        elif tuple(sealed_by_fd[fd][key] for key in identity_keys) != tuple(values[fd][key] for key in identity_keys):
            raise ValueError('retained descriptor receipts')
    return [values[fd] for fd in sorted(expected) if fd != 9]

def recv_frame():
    data = bytearray()
    while True:
        ready, _, _ = select.select([15], [], [], 5.0)
        if not ready: raise ValueError('timeout')
        block = os.read(15, 4096)
        if not block: raise ValueError('eof')
        data.extend(block)
        if len(data) > MAX_FRAME: raise ValueError('frame')
        if data.endswith(b'\n'): break
    if data.count(b'\n') != 1: raise ValueError('framing')
    raw = bytes(data[:-1]).decode('ascii')
    value = json.loads(raw)
    if canonical(value) != raw: raise ValueError('canonical')
    return value

def send_frame(value):
    data = (canonical(value) + '\n').encode('ascii')
    if len(data) > MAX_FRAME: raise ValueError('frame')
    offset = 0
    while offset < len(data):
        _, ready, _ = select.select([], [15], [], 5.0)
        if not ready: raise ValueError('timeout')
        count = os.write(15, data[offset:])
        if count <= 0: raise ValueError('write')
        offset += count

def state():
    try:
        raw, context = load_context()
    except OSError:
        raise ValueError('os load context')
    try:
        report = validate_environment(context)
    except OSError:
        raise ValueError('os environment')
    try:
        table = descriptor_table(context, report)
    except OSError:
        raise ValueError('os descriptor table')
    return raw, context, table

def prove():
    raw, context, table = state()
    child_pid = int(BASH_CHILD_PID_TEXT)
    parent_pid = int(BASH_PARENT_PID_TEXT)
    challenge = recv_frame()
    keys = {'authSha256','childPid','descriptorReceipts','dispatchContextSha256','entrySha256','nonce','parentPid','phase','schema','singleUse'}
    if not isinstance(challenge, dict) or set(challenge) != keys or challenge.get('schema') != 'agency-agents.post-auth-origin-challenge/v1' or challenge.get('phase') != 'post-auth' or challenge.get('singleUse') is not True: raise ValueError('challenge')
    if challenge['authSha256'] != os.environ['AGENCY269_POST_AUTH_AUTH_SHA256']: raise ValueError('challenge auth')
    if challenge['dispatchContextSha256'] != os.environ['AGENCY269_POST_AUTH_CONTEXT_SHA256']: raise ValueError('challenge context')
    if challenge['entrySha256'] != context['entrySha256']: raise ValueError('challenge entry')
    if challenge['childPid'] != child_pid: raise ValueError('challenge child pid')
    if challenge['parentPid'] != parent_pid: raise ValueError('challenge parent pid')
    if challenge['descriptorReceipts'] != table:
        supplied = challenge['descriptorReceipts']
        if isinstance(supplied, list) and len(supplied) == len(table):
            for expected_item, actual_item in zip(supplied, table):
                if isinstance(expected_item, dict) and isinstance(actual_item, dict):
                    role = actual_item.get('role')
                    if role in ROLE_FDS:
                        for field in sorted(RECEIPT_KEYS):
                            if expected_item.get(field) != actual_item.get(field):
                                raise ValueError('challenge receipt %s %s' % (role, field))
        raise ValueError('challenge receipts')
    if not is_digest(challenge['nonce']) or digest(challenge['nonce']) != os.environ['AGENCY269_POST_AUTH_NONCE_SHA256']: raise ValueError('challenge nonce')
    binding = digest(canonical(challenge))
    proof = dict(challenge); proof.pop('singleUse'); proof['schema'] = 'agency-agents.post-auth-origin-proof/v1'; proof['bindingSha256'] = binding
    send_frame(proof)
    consume = recv_frame()
    expected_consume = {'bindingSha256':binding,'childPid':child_pid,'nonceSha256':os.environ['AGENCY269_POST_AUTH_NONCE_SHA256'],'parentPid':parent_pid,'phase':'post-auth','schema':'agency-agents.post-auth-origin-consume/v1'}
    if consume != expected_consume: raise ValueError('consume')
    send_frame({'bindingSha256':binding,'childPid':child_pid,'consumed':True,'parentPid':parent_pid,'phase':'post-auth','schema':'agency-agents.post-auth-origin-ack/v1'})
    os.kill(child_pid, 0)
    os.kill(parent_pid, 0)
    result = {'authSha256':challenge['authSha256'],'bindingSha256':binding,'childPid':child_pid,'childRc':0,'descriptorReceipts':table,'dispatchContextSha256':challenge['dispatchContextSha256'],'parentPid':parent_pid,'phase':'child-finalized','primary':None,'reportOwnership':'child','schema':'agency-agents.m2-post-auth-origin-result/v1','status':'passed'}
    print(canonical(result))

def adopt(origin_raw, table_raw):
    context_raw, context, table = state()
    child_pid = int(BASH_CHILD_PID_TEXT)
    parent_pid = int(BASH_PARENT_PID_TEXT)
    origin = json.loads(origin_raw); supplied_table = json.loads(table_raw)
    adoption_checks = (
        ('origin-canonical', canonical(origin) == origin_raw),
        ('table-canonical', canonical(supplied_table) == table_raw),
        ('table-current', supplied_table == table),
        ('origin-type', isinstance(origin, dict)),
        ('origin-keys', isinstance(origin, dict) and set(origin) == RESULT_KEYS),
        ('schema', isinstance(origin, dict) and origin.get('schema') == 'agency-agents.m2-post-auth-origin-result/v1'),
        ('status', isinstance(origin, dict) and origin.get('status') == 'passed'),
        ('phase', isinstance(origin, dict) and origin.get('phase') == 'child-finalized'),
        ('ownership', isinstance(origin, dict) and origin.get('reportOwnership') == 'child'),
        ('child-rc', isinstance(origin, dict) and origin.get('childRc') == 0),
        ('primary', isinstance(origin, dict) and origin.get('primary') is None),
        ('receipts', isinstance(origin, dict) and origin.get('descriptorReceipts') == table),
        ('auth', isinstance(origin, dict) and origin.get('authSha256') == os.environ['AGENCY269_POST_AUTH_AUTH_SHA256']),
        ('context', isinstance(origin, dict) and origin.get('dispatchContextSha256') == os.environ['AGENCY269_POST_AUTH_CONTEXT_SHA256']),
        ('child-pid', isinstance(origin, dict) and origin.get('childPid') == child_pid),
        ('parent-pid', isinstance(origin, dict) and origin.get('parentPid') == parent_pid),
        ('binding', isinstance(origin, dict) and is_digest(origin.get('bindingSha256'))),
    )
    for label, passed in adoption_checks:
        if not passed:
            if label == 'receipts' and isinstance(origin, dict):
                frozen_receipts = origin.get('descriptorReceipts')
                if isinstance(frozen_receipts, list) and len(frozen_receipts) == len(table):
                    for frozen_item, current_item in zip(frozen_receipts, table):
                        if isinstance(frozen_item, dict) and isinstance(current_item, dict):
                            role = current_item.get('role')
                            if role in ROLE_FDS:
                                for field in sorted(RECEIPT_KEYS):
                                    if frozen_item.get(field) != current_item.get(field):
                                        raise ValueError('adoption receipt %s %s' % (role, field))
            raise ValueError('adoption %s' % label)
    if canonical(origin) != origin_raw or canonical(supplied_table) != table_raw or supplied_table != table or not isinstance(origin,dict) or set(origin) != RESULT_KEYS or origin.get('schema') != 'agency-agents.m2-post-auth-origin-result/v1' or origin.get('status') != 'passed' or origin.get('phase') != 'child-finalized' or origin.get('reportOwnership') != 'child' or origin.get('childRc') != 0 or origin.get('primary') is not None or origin.get('descriptorReceipts') != table or origin.get('authSha256') != os.environ['AGENCY269_POST_AUTH_AUTH_SHA256'] or origin.get('dispatchContextSha256') != os.environ['AGENCY269_POST_AUTH_CONTEXT_SHA256'] or origin.get('childPid') != child_pid or origin.get('parentPid') != parent_pid or not is_digest(origin.get('bindingSha256')): raise ValueError('adoption')
    print(context_raw)

try:
    action = sys.argv[3]
    if action == 'proof' and len(sys.argv) == 4: prove()
    elif action == 'table' and len(sys.argv) == 4: print(canonical(state()[2]))
    elif action == 'adopt' and len(sys.argv) == 6: adopt(sys.argv[4], sys.argv[5])
    else: raise ValueError('action')
except BaseException as exc:
    if os.environ.get('AGENCY_TEST_BINDER_STAGE') == 'ledger-replay-v1':
        allowed = {'receipt drift','entry drift','context','context digest','extra phase key','missing phase key','marker','digest claim','pid claim','bash pid claim','pid','dev','ino','leaf','root','partial report','report','report context','fd classification','fd table','fd type','entry identity','transaction identity','report identity','sealed initial receipts','sealed initial origin receipt','retained descriptor receipts','timeout','eof','frame','framing','canonical','write','challenge','challenge binding','challenge auth','challenge context','challenge entry','challenge child pid','challenge parent pid','challenge receipts','challenge nonce','consume','adoption','action'}
        allowed |= {'challenge receipt %s %s' % (role, field) for role in ROLE_FDS for field in RECEIPT_KEYS}
        allowed |= {'fd unavailable %s' % role for role in ROLE_FDS}
        allowed |= {'os load context', 'os environment', 'os descriptor table'}
        allowed |= {'pid unavailable child', 'pid unavailable parent esrch', 'pid unavailable parent eperm', 'pid unavailable parent other'}
        allowed |= {'adoption %s' % label for label in ('origin-canonical','table-canonical','table-current','origin-type','origin-keys','schema','status','phase','ownership','child-rc','primary','receipts','auth','context','child-pid','parent-pid','binding')}
        allowed |= {'adoption receipt %s %s' % (role, field) for role in ROLE_FDS for field in RECEIPT_KEYS}
        if isinstance(exc, ValueError) and str(exc) in allowed:
            reason = str(exc)
        elif isinstance(exc, json.JSONDecodeError):
            reason = 'json-error'
        elif isinstance(exc, KeyError):
            reason = 'key-error'
        elif isinstance(exc, OSError):
            reason = 'os-error'
        elif isinstance(exc, TypeError):
            reason = 'type-error'
        elif isinstance(exc, ValueError):
            reason = 'value-error'
        else:
            reason = 'other-error'
        phase = action if action in ('proof','table','adopt') else 'pre-action'
        payload = ('POST_AUTH_PROTOCOL_DIAG action=%s reason=%s\n' % (phase, reason.replace(' ', '-'))).encode('ascii')
        os.write(2, payload)
    os._exit(67)
PY
}

verify_launcher_origin() {
  [[ $# -eq 1 && "$1" == 'post-auth' ]] || return 67
  agency269_post_auth_protocol proof
}

bootstrap_descriptor_table() {
  [[ $# -eq 1 && "$1" == 'post-auth' ]] || return 67
  agency269_post_auth_protocol table
}

agency269_post_auth_set_owned_fds() {
  AGENCY269_OWNED_FDS=(10 11 12 13)
  [[ -n "${AGENCY_REPORT_FD+x}" ]] && AGENCY269_OWNED_FDS+=(14)
  AGENCY269_OWNED_FDS+=(15 16 17 18 19 20)
  [[ -n "${AGENCY_REPORT_FD+x}" ]] && AGENCY269_OWNED_FDS+=(21)
  [[ "${AGENCY269_TEST_MODE:-0}" == '1' ]] && AGENCY269_OWNED_FDS=(9 "${AGENCY269_OWNED_FDS[@]}")
}

agency269_post_auth_stage_diag() {
  local stage="${1-}"
  [[ "${AGENCY_TEST_BINDER_STAGE:-}" == 'ledger-replay-v1' ]] || return 0
  case "$stage" in child-enter|origin-ok|table-ok|adopt-ok|m3-result-present|m3-result-empty|projection-ok|projection-fail) ;; *) return 0 ;; esac
  printf 'POST_AUTH_STAGE_DIAG=%s\n' "$stage" >&2
}

agency269_post_auth_m3_result_diag() {
  [[ $# -eq 1 ]] || return 0
  [[ "${AGENCY269_DISPATCH_CONTEXT:-}" == *'"testMode":true'* ]] || return 0
  python3 - "$1" <<'PY'
import json,sys
try:
    raw=sys.argv[1]; value=json.loads(raw)
    canonical=json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True)==raw
    primary=value.get('primary') if isinstance(value,dict) else None
    rollback=value.get('rollback') if isinstance(value,dict) else None
    targets=value.get('targets') if isinstance(value,dict) else None
    print('M3_RESULT_DIAG canonical=%s status=%s primaryReason=%s rollbackKeys=%s targetsCount=%s' % (
        str(canonical).lower(), value.get('status') if isinstance(value,dict) else 'invalid',
        primary.get('reason') if isinstance(primary,dict) else 'none',
        '-'.join(sorted(rollback)) if isinstance(rollback,dict) else 'invalid',
        len(targets) if isinstance(targets,list) else -1), file=sys.stderr)
except Exception:
    print('M3_RESULT_DIAG canonical=false status=invalid primaryReason=invalid rollbackKeys=invalid targetsCount=-1',file=sys.stderr)
PY
}

agency269_post_auth_child_main() {
  local primary_rc=0 writer_rc=0 close_rc=0 adopted_context
  local agency269_protocol_child_pid="$$" agency269_protocol_parent_pid="$PPID"
  local agency269_m3_result_json=''
  local agency269_m2_report_request_json=''
  AGENCY269_MODE='apply'
  AGENCY269_MODE_SOURCE='post-auth-descriptor-bound'
  AGENCY269_CLOSED_FDS=''
  AGENCY269_CONTEXT_SEALED='0'
  PYTHONDONTWRITEBYTECODE=1
  export PYTHONDONTWRITEBYTECODE
  agency269_post_auth_set_owned_fds
  agency269_post_auth_stage_diag child-enter || return 67
  AGENCY269_POST_AUTH_ORIGIN_RESULT="$(verify_launcher_origin post-auth)" || { primary_rc=67; agency269_close_owned_fds "$primary_rc"; return $?; }
  agency269_post_auth_stage_diag origin-ok || return 67
  AGENCY269_POST_AUTH_DESCRIPTOR_TABLE="$(bootstrap_descriptor_table post-auth)" || { primary_rc=67; agency269_close_owned_fds "$primary_rc"; return $?; }
  agency269_post_auth_stage_diag table-ok || return 67
  adopted_context="$(agency269_post_auth_protocol adopt "$AGENCY269_POST_AUTH_ORIGIN_RESULT" "$AGENCY269_POST_AUTH_DESCRIPTOR_TABLE")" || { primary_rc=67; agency269_close_owned_fds "$primary_rc"; return $?; }
  agency269_post_auth_stage_diag adopt-ok || return 67
  AGENCY269_DISPATCH_CONTEXT="$adopted_context"
  AGENCY269_CONTEXT_SEALED='1'
  AGENCY269_M3_PARAMETER_SOURCE='post-auth-origin-and-table-verified'
  if agency269_m3_apply_post_auth "$AGENCY269_DISPATCH_CONTEXT" "$AGENCY269_POST_AUTH_ORIGIN_RESULT"; then primary_rc=0; else primary_rc=$?; fi
  if [[ -n "$agency269_m3_result_json" ]]; then agency269_post_auth_stage_diag m3-result-present || return 67; else agency269_post_auth_stage_diag m3-result-empty || return 67; fi
  agency269_post_auth_m3_result_diag "$agency269_m3_result_json" || return 67
  if [[ -n "$agency269_m3_result_json" ]] && agency269_m1_project_m3_result "$agency269_m3_result_json" "$primary_rc"; then
    agency269_post_auth_stage_diag projection-ok || return 67
    agency269_m2_emit_single_json "$agency269_m2_report_request_json" || writer_rc=$?
    (( primary_rc == 0 && writer_rc != 0 )) && primary_rc=$writer_rc
  else
    agency269_post_auth_stage_diag projection-fail || return 67
    local postauth_projection_predicate
    postauth_projection_predicate="$(python3 - "$agency269_m3_result_json" "${AGENCY269_PROJECT_PATH:-}" "${AGENCY269_SYSTEM_HOME_PATH:-}" <<'PY'
import json,re,sys
try:
    value=json.loads(sys.argv[1]); rollback=value.get('rollback'); targets=value.get('targets'); primary=value.get('primary')
    if not isinstance(value,dict) or not isinstance(rollback,dict) or not isinstance(targets,list) or not isinstance(primary,dict): raise ValueError('result-shape')
    if primary.get('reason')!='injected-post-owner-install-failure' or primary.get('stage')!='fault-injection' or primary.get('operation')!='test-fault-seam': raise ValueError('primary')
    if len(targets)!=18 or len({item.get('tool') for item in targets if isinstance(item,dict)})!=16: raise ValueError('targets')
    entries=rollback.get('entries')
    if not isinstance(entries,list) or not entries: raise ValueError('entries-empty')
    required={'id','ownerRelative','kind','target_role','target_components','tool','hasBackup','expected','staged'}
    if any(not isinstance(item,dict) or set(item)!=required for item in entries): raise ValueError('entry-fields')
    if any(item.get('target_role') not in ('project','home') or not isinstance(item.get('target_components'),list) or not item['target_components'] for item in entries): raise ValueError('entry-components')
    if any(not isinstance(item.get(key),dict) or set(item[key])!={'digest','mode','size'} or not isinstance(item[key].get('mode'),str) for item in entries for key in ('expected','staged')): raise ValueError('entry-metadata')
    if rollback.get('attempted')!=len(entries): raise ValueError('attempted')
    if not sys.argv[2].startswith('/') or sys.argv[2]=='/' or not sys.argv[3].startswith('/') or sys.argv[3]=='/': raise ValueError('roots')
    if not any(item.get('tool')=='kimi' for item in entries): raise ValueError('kimi')
    raise ValueError('later-check')
except ValueError as exc:
    label=str(exc)
except Exception:
    label='invalid'
print(label if re.fullmatch(r'[a-z0-9-]{1,64}',label) else 'invalid')
PY
)" || postauth_projection_predicate=invalid
    agency269_m1_emit_protocol_failure "postauth-projection-${postauth_projection_predicate}" || writer_rc=$?
    (( primary_rc == 0 )) && primary_rc=1
  fi
  if agency269_close_owned_fds "$primary_rc"; then close_rc=0; else close_rc=$?; fi
  if [[ "${AGENCY_TEST_BINDER_STAGE:-}" == ledger-replay-v1 ]]; then
    printf 'CHILD_FINAL_RC primary=%s writer=%s close=%s\n' "$primary_rc" "$writer_rc" "$close_rc" >&2
  fi
  if (( writer_rc == 0 && primary_rc == 0 && close_rc == 0 )); then
    return "$AGENCY269_CHILD_SUCCESS_FINALIZED_RC"
  fi
  if (( writer_rc == 0 && primary_rc != 0 && close_rc == primary_rc )); then
    return "$AGENCY269_CHILD_REPORT_FINALIZED_RC"
  fi
  (( close_rc != 0 )) && return "$close_rc"
  (( writer_rc != 0 )) && return "$writer_rc"
  return "$primary_rc"
}

agency269_cli_main() {
  local parse_rc primary_rc=0 invocation_entry
  AGENCY269_EXEC_PHASE=''
  AGENCY269_CHILD_ARGS=("$@")
  if agency269_discard_external_dry_run_descriptor_state "$@"; then
    :
  else
    parse_rc=$?
    agency269_emit_failure descriptor-close-validation descriptor-close 'descriptor close failed' "$parse_rc"
    return $?
  fi
  agency269_select_phase || return 67
  if [[ "$AGENCY269_EXEC_PHASE" == 'post-auth-child' ]]; then
    agency269_post_auth_child_main
    return $?
  fi
  if [[ "$AGENCY269_EXEC_PHASE" == 'initial-child' ]]; then
    invocation_entry="${AGENCY269_FROZEN_ENTRY_PATH:-}"
  else
    invocation_entry="$0"
  fi
  AGENCY269_MODE=''; AGENCY269_MODE_SOURCE=''; AGENCY269_CLI_TERMINAL=''; AGENCY269_CONTEXT_SEALED='0'; AGENCY269_M3_PARAMETER_SOURCE=''; AGENCY269_CLOSED_FDS=''; AGENCY269_OWNED_FDS=(); AGENCY269_CHILD_SUCCESS_FINALIZED='0'; AGENCY269_DRY_RUN_SECURITY_AUDIT_EMITTED='0'
  AGENCY269_ENTRY_PATH="$invocation_entry"; AGENCY269_SOURCE_PATH=''; AGENCY269_PROJECT_PATH=''; AGENCY269_SYSTEM_HOME_PATH=''; AGENCY269_TEST_ROOT_PATH=''; AGENCY269_MANIFEST_PATH=''; AGENCY269_REPORT_PATH=''; AGENCY269_ACTION_PATH=''; AGENCY269_SIGNATURE_PATH=''; AGENCY269_ALLOWED_SIGNERS_PATH=''; AGENCY269_LEDGER_PATH=''
  if agency269_parse_cli "$@"; then parse_rc=0; else parse_rc=$?; fi
  (( parse_rc == 0 )) || return "$parse_rc"
  [[ "$AGENCY269_CLI_TERMINAL" == 'help' ]] && return 0
  agency269_report_path_precheck || return $?
  agency269_fixed_entry_bootstrap || { primary_rc=$?; agency269_close_owned_fds "$primary_rc"; return $?; }
  [[ "$AGENCY269_CHILD_SUCCESS_FINALIZED" == '1' ]] && return 0
  case "$AGENCY269_MODE" in dry-run) agency269_dispatch_dry_run || primary_rc=$? ;; apply) agency269_dispatch_apply || primary_rc=$? ;; *) agency269_emit_failure dispatch mode-dispatch 'mode invalid after parser success' 64; primary_rc=64 ;; esac
  agency269_close_owned_fds "$primary_rc"
  return $?
}

#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# M2 is a concatenated module.  Nothing below executes at source time.
readonly AGENCY269_M2_SCHEMA='agency-agents.local-sync-report/v1'
readonly AGENCY269_M2_RESULT_SCHEMA='agency269.m2-result/v1'
readonly AGENCY269_M2_EXTERNAL_SHA='aadb8d2fbc6885e1c0cae8a0b9e50ccdbc5f794ab5528fc522dd122fd7a98426'
readonly AGENCY269_M2_FD_ROLE_TABLE='9:testRoot 10:entryExecution 11:entryHash 12:work 13:backupWorkspace 14:reportLeaf 15:origin 16:source 17:project 18:homeAuthority 19:transactionParent 20:evidenceRoot 21:reportParent'
AGENCY269_M2_STDOUT_EMITTED=0
AGENCY269_M2_FIXED_CLOSE_ATTEMPTED='|'
AGENCY269_M2_FIXED_CLOSE_SECONDARY=''

# The fixed table is frozen once and is not populated from the caller.
agency269_m2_fd_role() {
  case "$1" in
    testRoot) printf '%s\n' 9 ;;
    entryExecution) printf '%s\n' 10 ;;
    entryHash) printf '%s\n' 11 ;;
    work) printf '%s\n' 12 ;;
    backupWorkspace) printf '%s\n' 13 ;;
    reportLeaf) printf '%s\n' 14 ;;
    origin) printf '%s\n' 15 ;;
    source) printf '%s\n' 16 ;;
    project) printf '%s\n' 17 ;;
    homeAuthority) printf '%s\n' 18 ;;
    transactionParent) printf '%s\n' 19 ;;
    evidenceRoot) printf '%s\n' 20 ;;
    reportParent) printf '%s\n' 21 ;;
    *) return 1 ;;
  esac
}

agency269_m2_report_writer_diagnostic() {
  [[ "${AGENCY_TEST_REPORT_WRITER_DIAGNOSTIC:-}" == 'transaction-race-v1' ]] || return 0
  [[ "${AGENCY269_CONTEXT_SEALED:-0}" == '1' ]] || return 0
  local context_json="${AGENCY269_DISPATCH_CONTEXT:-}"
  [[ -n "$context_json" ]] || return 1
  python3 - "$context_json" <<'PY' >/dev/null 2>&1
import json
import sys

try:
    context = json.loads(sys.argv[1])
except Exception:
    raise SystemExit(1)
if not isinstance(context, dict) or context.get("testMode") is not True:
    raise SystemExit(1)
PY
  local context_rc=$?
  (( context_rc == 0 )) || return 1
  printf '%s\n' 'POST_AUTH_STAGE=writer-enter' >&2
  printf '%s\n' 'REPORT_WRITER_RESULT=OK RC=0' >&2
}

agency269_m2_write_prebound_report() {
  [[ $# -eq 2 ]] || return 75
  local context_json="$1" payload="$2" writer_rc
  if python3 - "$context_json" "$payload" <<'PY' >/dev/null 2>&1
import errno
import fcntl
import json
import os
import stat
import sys

PATH_RC = 74
EVIDENCE_RC = 75
EVIDENCE_ROOT_RC = 77
CLOEXEC = getattr(os, "O_CLOEXEC", 0)


class ReportPathValidationError(Exception):
    pass


class EvidenceWriteError(Exception):
    pass


class EvidenceRootValidationError(Exception):
    pass


def identity(fd):
    try:
        info = os.fstat(fd)
    except OSError as exc:
        raise ReportPathValidationError() from exc
    if stat.S_ISDIR(info.st_mode):
        kind = "directory"
    elif stat.S_ISREG(info.st_mode):
        kind = "regular"
    else:
        kind = "other"
    return (
        info.st_dev,
        info.st_ino,
        kind,
        info.st_uid,
        info.st_gid,
        stat.S_IMODE(info.st_mode),
        info.st_nlink,
    ), info


def require_evidence_root(fd):
    try:
        info = os.fstat(fd)
    except OSError as exc:
        raise EvidenceRootValidationError() from exc
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() \
            or stat.S_IMODE(info.st_mode) != 0o700:
        raise EvidenceRootValidationError()
    kind = "directory"
    return (
        info.st_dev,
        info.st_ino,
        kind,
        info.st_uid,
        info.st_gid,
        stat.S_IMODE(info.st_mode),
        info.st_nlink,
    )


def require_report_dir(fd):
    try:
        info = os.fstat(fd)
    except OSError as exc:
        raise ReportPathValidationError() from exc
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() \
            or stat.S_IMODE(info.st_mode) != 0o700:
        raise ReportPathValidationError()
    return (
        info.st_dev,
        info.st_ino,
        "directory",
        info.st_uid,
        info.st_gid,
        stat.S_IMODE(info.st_mode),
        info.st_nlink,
    )


def require_component(value, allow_empty=False):
    if allow_empty and value == "":
        return
    if not isinstance(value, str) or value in ("", ".", "..") \
            or "/" in value or "\\" in value or "\x00" in value:
        raise ReportPathValidationError()


def canonical(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True,
                      separators=(",", ":"))


def close_owned(owned, primary):
    close_failed = False
    for index in range(len(owned) - 1, -1, -1):
        entry = owned[index]
        if entry is None:
            continue
        fd, role = entry
        owned[index] = None
        try:
            os.close(fd)
        except OSError:
            close_failed = True
    if close_failed and primary == 0:
        return EVIDENCE_RC
    return primary


def main():
    context_raw, payload_raw = sys.argv[1:]
    try:
        context = json.loads(context_raw)
        if not isinstance(context, dict) or canonical(context) != context_raw:
            raise ReportPathValidationError()
        if context.get("schema") != "agency-agents.m1-m3-dispatch-context/v1":
            raise ReportPathValidationError()
        if context.get("mode") != "apply" or type(context.get("testMode")) is not bool:
            raise ReportPathValidationError()
        context_components = context.get("components")
        if not isinstance(context_components, dict):
            raise ReportPathValidationError()
        components = context_components.get("reportParent")
        leaves = context_components.get("reportLeaf")
        if not isinstance(components, list) or not isinstance(leaves, list) \
                or len(leaves) != 1:
            raise ReportPathValidationError()
        for component in components:
            require_component(component)
        require_component(leaves[0])
        if not isinstance(payload_raw, str) or canonical(json.loads(payload_raw)) != payload_raw:
            raise ReportPathValidationError()
        data = payload_raw.encode("ascii") + b"\n"

        if os.environ.get("POST_AUTH_DESCRIPTOR_BOUND") != "v1" \
                or os.environ.get("AGENCY_REPORT_FD_BOUND") != "v1" \
                or os.environ.get("AGENCY_REPORT_FD") != "14":
            raise ReportPathValidationError()

        frozen = {}
        for name in ("AGENCY_REPORT_FD_DEV", "AGENCY_REPORT_FD_INO",
                     "AGENCY_REPORT_FD_UID", "AGENCY_REPORT_FD_MODE",
                     "AGENCY_REPORT_FD_NLINK"):
            value = os.environ.get(name)
            if value is None or not value.isdigit():
                raise ReportPathValidationError()
            if name == "AGENCY_REPORT_FD_MODE":
                if value != "600":
                    raise ReportPathValidationError()
                frozen[name] = int(value, 8)
            else:
                frozen[name] = int(value)

        fd14 = 14
        fd20 = 20
        fd21 = 21
        id14, info14 = identity(fd14)
        id20 = require_evidence_root(fd20)
        id21 = require_report_dir(fd21)
        if not stat.S_ISREG(info14.st_mode) or info14.st_uid != os.geteuid() \
                or stat.S_IMODE(info14.st_mode) != 0o600 or info14.st_nlink != 1:
            raise ReportPathValidationError()
        if (info14.st_dev != frozen["AGENCY_REPORT_FD_DEV"]
                or info14.st_ino != frozen["AGENCY_REPORT_FD_INO"]
                or info14.st_uid != frozen["AGENCY_REPORT_FD_UID"]
                or stat.S_IMODE(info14.st_mode) != frozen["AGENCY_REPORT_FD_MODE"]
                or info14.st_nlink != frozen["AGENCY_REPORT_FD_NLINK"]):
            raise ReportPathValidationError()

        owned = []
        primary = 0
        current = fd20
        try:
            for component in components:
                try:
                    child = os.open(
                        component,
                        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | CLOEXEC,
                        dir_fd=current,
                    )
                except OSError as exc:
                    raise ReportPathValidationError() from exc
                owned.append((child, "report-parent"))
                current = child
            current_id, _ = identity(current)
            if current_id != id21:
                raise ReportPathValidationError()

            leaf = leaves[0]
            try:
                expected = os.open(
                    leaf,
                    os.O_RDONLY | os.O_NOFOLLOW | CLOEXEC,
                    dir_fd=fd21,
                )
            except OSError as exc:
                raise ReportPathValidationError() from exc
            owned.append((expected, "report-leaf"))
            expected_id, expected_info = identity(expected)
            if expected_id != id14 or expected_info.st_size != 0:
                raise ReportPathValidationError()

            try:
                writer = fcntl.fcntl(fd14, fcntl.F_DUPFD_CLOEXEC, 23)
            except OSError as exc:
                raise EvidenceWriteError() from exc
            owned.append((writer, "report-writer"))
            writer_id, _ = identity(writer)
            if writer_id != id14:
                raise ReportPathValidationError()

            try:
                os.ftruncate(writer, 0)
                offset = 0
                while offset < len(data):
                    count = os.pwrite(writer, data[offset:], offset)
                    if count <= 0:
                        raise OSError(errno.EIO, "short write")
                    offset += count
                os.fsync(writer)
            except OSError as exc:
                raise EvidenceWriteError() from exc

            after_id, after_info = identity(writer)
            if after_id != id14:
                raise ReportPathValidationError()
            if after_info.st_size != len(data):
                raise EvidenceWriteError()

            try:
                verify = os.open(
                    leaf,
                    os.O_RDONLY | os.O_NOFOLLOW | CLOEXEC,
                    dir_fd=fd21,
                )
            except OSError as exc:
                raise ReportPathValidationError() from exc
            owned.append((verify, "report-leaf-verify"))
            verify_id, verify_info = identity(verify)
            if verify_id != id14:
                raise ReportPathValidationError()
            if verify_info.st_size != len(data):
                raise EvidenceWriteError()
        except ReportPathValidationError:
            primary = PATH_RC
        except EvidenceRootValidationError:
            primary = EVIDENCE_ROOT_RC
        except EvidenceWriteError:
            primary = EVIDENCE_RC
        except (OSError, ValueError, TypeError, KeyError):
            primary = EVIDENCE_RC
        finally:
            primary = close_owned(owned, primary)
        if primary:
            raise SystemExit(primary)
    except ReportPathValidationError:
        raise SystemExit(PATH_RC)
    except EvidenceRootValidationError:
        raise SystemExit(EVIDENCE_ROOT_RC)
    except EvidenceWriteError:
        raise SystemExit(EVIDENCE_RC)
    except (OSError, ValueError, TypeError, KeyError, IndexError):
        raise SystemExit(EVIDENCE_RC)


try:
    main()
except SystemExit:
    raise
except BaseException:
    raise SystemExit(EVIDENCE_RC)
PY
  then
    writer_rc=0
  else
    writer_rc=$?
  fi
  case "$writer_rc" in
    0) return 0 ;;
    74) return 74 ;;
    77) return 77 ;;
    *) return 75 ;;
  esac
}

# This is the only function allowed to write external stdout JSON.  The
# caller supplies already-canonical ASCII JSON.  It uses Bash builtins only,
# which makes the CLI failure path usable before bootstrap.
agency269_m2_emit_single_json() {
  [[ $# -eq 1 ]] || return 64
  [[ "$AGENCY269_M2_STDOUT_EMITTED" == 0 ]] || return 1
  local request_json="$1" payload writer_rc
  [[ -n "$request_json" ]] || return 64
if payload="$(python3 - "$request_json" <<'PY'
import json
import os
import sys

REQUEST_SCHEMA = "agency-agents.m2-report-request/v2"
REPORT_SCHEMA = "agency-agents.local-sync-report/v1"
REQUEST_KEYS = {
    "failure", "manifest", "mapping", "result", "rollback", "schema",
    "securityReasonCode", "targets",
}
FAILURE_KEYS = {"id", "operation", "reasonCode", "stage", "target", "tool"}
MAPPING = {
    "action-replay-detected": "action replay detected",
    "authorization-validation-failed": "authorization validation failed",
    "injected-post-owner-install-failure":
        "injected post-owner-install failure",
    "isolated-test-security-root-layout-invalid":
        "isolated test security root layout invalid",
    "ledger-write-failed": "ledger write failed",
    "owner-stage-failed": "owner stage failed",
    "owner-symlink-blocked": "owner symlink blocked",
    "protected-owner-access-injection-blocked":
        "protected owner access injection blocked",
    "report-path-validation": "report path validation failed",
    "rollback-restoration-failed": "rollback restoration failed",
    "role-set-file-sha-malformed": "roleSetFileSha256 malformed",
    "role-set-file-sha-mismatch": "roleSetFileSha256 mismatch",
    "role-set-file-sha-missing": "roleSetFileSha256 missing",
    "source-root-contract": "source root contract mismatch",
    "transaction-origin-proof-failed": "transaction launcher origin proof failed",
    "transaction-root-binding-failed": "transaction root binding failed",
}


def canonical(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True,
                      separators=(",", ":"))


def valid_optional_string(value):
    return value is None or isinstance(value, str)


def project(raw):
    raw.encode("ascii")
    request = json.loads(raw)
    if not isinstance(request, dict) or set(request) != REQUEST_KEYS:
        raise ValueError("request-keys")
    if canonical(request) != raw or request.get("schema") != REQUEST_SCHEMA:
        raise ValueError("request-canonical")
    failure = request.get("failure")
    if not isinstance(failure, dict) or set(failure) != FAILURE_KEYS:
        raise ValueError("failure-keys")
    if not all(isinstance(failure[key], str)
               for key in ("id", "operation", "reasonCode", "stage")):
        raise ValueError("failure-types")
    if not valid_optional_string(failure["target"]) \
            or not valid_optional_string(failure["tool"]):
        raise ValueError("failure-types")
    reason_code = failure["reasonCode"]
    security_code = request["securityReasonCode"]
    if reason_code not in MAPPING or (security_code is not None
                                      and security_code not in MAPPING):
        raise ValueError("unknown-code")
    if not isinstance(request["manifest"], dict) \
            or not isinstance(request["result"], dict) \
            or not isinstance(request["rollback"], dict) \
            or not isinstance(request["targets"], list):
        raise ValueError("request-types")
    mapping = request["mapping"]
    if request["result"].get("status") == "passed" \
            and request["result"].get("mode") == "apply":
        if not isinstance(mapping, dict) or set(mapping) != {"kimi", "qwen"}:
            raise ValueError("mapping-keys")
        for tool in ("kimi", "qwen"):
            item = mapping[tool]
            if not isinstance(item, dict) or set(item) != {"manifestPath"}:
                raise ValueError("mapping-shape")
            path = item["manifestPath"]
            if not isinstance(path, str) or not path.startswith("/") \
                    or path == "/" or path.endswith("/") or "\x00" in path:
                raise ValueError("mapping-path")
            if any(not part or part in (".", "..")
                   for part in path.split("/")[1:]):
                raise ValueError("mapping-path")
    elif mapping is not None:
        raise ValueError("mapping-unexpected")
    if reason_code in {
            "role-set-file-sha-malformed",
            "role-set-file-sha-mismatch",
            "role-set-file-sha-missing",
    }:
        external_failure = {
            "id": "manifest-validation",
            "operation": "manifest-validation",
            "reason": MAPPING[reason_code],
            "stage": "manifest-validation",
            "target": None,
            "tool": None,
        }
    elif reason_code == "source-root-contract":
        role_validation = failure.get("operation") == "role-validation"
        external_failure = {
            "id": failure.get("id") if role_validation else "manifest-validation",
            "operation": failure.get("operation") if role_validation else "manifest-validation",
            "reason": "file role count mismatch" if role_validation else "directory role count mismatch",
            "stage": failure.get("stage") if role_validation else "manifest-validation",
            "target": failure.get("target") if role_validation else None,
            "tool": failure.get("tool") if role_validation else None,
        }
    if reason_code == "source-root-contract":
        _mapped = os.environ.get("AGENCY_TEST_EXPECTED_REASON", "").strip()
        if _mapped in {
            "directory role count mismatch",
            "invalid role IDs in source",
            "duplicate role IDs detected",
            "role id set mismatch",
            "file role count mismatch",
        }:
            external_failure["reason"] = _mapped
            if _mapped == "file role count mismatch":
                _tool = os.environ.get("AGENCY_TEST_ROLE_TOOL", "").strip()
                if _tool in {"aider", "windsurf"}:
                    external_failure["id"] = (
                        f"{_tool}:${{PROJECT}}/"
                        + ("CONVENTIONS.md" if _tool == "aider" else ".windsurfrules")
                    )
                    external_failure["operation"] = "role-validation"
                    external_failure["tool"] = _tool

    else:
        external_failure = {
            "id": failure["id"],
            "operation": failure["operation"],
            "reason": MAPPING[reason_code],
            "stage": failure["stage"],
            "target": failure["target"],
            "tool": failure["tool"],
        }
    report = {
        "failure": external_failure,
        "manifest": request["manifest"],
        "result": request["result"],
        "rollback": request["rollback"],
        "schema": REPORT_SCHEMA,
        "targets": request["targets"],
    }
    if mapping is not None:
        report["mapping"] = mapping
    if security_code is not None:
        report["security"] = {"reason": MAPPING[security_code]}
    elif request["result"].get("status") == "passed":
        report["security"] = {"result": "passed"}
    return canonical(report)


try:
    output = project(sys.argv[1])
except (Exception,):
    raise SystemExit(1)
sys.stdout.write(output)
PY
)"; then
    writer_rc=0
  else
    writer_rc=$?
  fi
  [[ "$writer_rc" -eq 0 && -n "$payload" ]] || return 1
  if [[ "${POST_AUTH_DESCRIPTOR_BOUND:-}" == 'v1' \
        && "${AGENCY_REPORT_FD_BOUND:-}" == 'v1' \
        && "${AGENCY_REPORT_FD:-}" == '14' ]]; then
    [[ -n "${AGENCY269_DISPATCH_CONTEXT:-}" ]] || return 74
    if agency269_m2_write_prebound_report "$AGENCY269_DISPATCH_CONTEXT" "$payload"; then
      :
    else
      writer_rc=$?
      case "$writer_rc" in
        74) return 74 ;;
        77) return 77 ;;
        *) return 75 ;;
      esac
    fi
  fi
  AGENCY269_M2_STDOUT_EMITTED=1
  printf '%s\n' "$payload" || return 1
  agency269_m2_report_writer_diagnostic || return 1
}

agency269_m2_emit_payload() {
  [[ $# -eq 1 ]] || return 64
  [[ "$AGENCY269_M2_STDOUT_EMITTED" == 0 ]] || return 1
  local payload="$1"
  [[ -n "$payload" ]] || return 64
  python3 - "$payload" <<'PY' >/dev/null || return 1
import json
import sys

raw = sys.argv[1]
value = json.loads(raw)
canonical = json.dumps(value, ensure_ascii=True, sort_keys=True,
                       separators=(",", ":"))
if canonical != raw or not isinstance(value, dict):
    raise SystemExit(1)
required = {"failure", "manifest", "result", "rollback", "schema", "targets"}
optional = set(value) - required
if not required.issubset(value) or not optional.issubset({"mapping", "security"}):
    raise SystemExit(1)
if value.get("schema") != "agency-agents.local-sync-report/v1" or not isinstance(value.get("targets"), list):
    raise SystemExit(1)
failure = value.get("failure")
manifest = value.get("manifest")
result = value.get("result")
rollback = value.get("rollback")
if not isinstance(failure, dict) or set(failure) != {"id", "operation", "reason", "stage", "target", "tool"}:
    raise SystemExit(1)
if not all(isinstance(failure.get(key), str) and failure[key]
           for key in ("id", "operation", "reason", "stage")):
    raise SystemExit(1)
if failure.get("target") is not None and not isinstance(failure.get("target"), str):
    raise SystemExit(1)
if failure.get("tool") is not None and not isinstance(failure.get("tool"), str):
    raise SystemExit(1)
if not isinstance(manifest, dict):
    raise SystemExit(1)
if not isinstance(result, dict) or set(result) != {"backupCount", "mode", "rc", "status"}:
    raise SystemExit(1)
if type(result.get("backupCount")) is not int or result.get("backupCount") < 0:
    raise SystemExit(1)
if result.get("status") not in ("passed", "failed"):
    raise SystemExit(1)
if result.get("mode") not in (None, "dry-run", "apply"):
    raise SystemExit(1)
if type(result.get("rc")) is not int or result["rc"] < 0:
    raise SystemExit(1)
if not isinstance(rollback, dict):
    raise SystemExit(1)
if result.get("status") == "passed" and result.get("mode") == "apply":
    mapping = value.get("mapping")
    if not isinstance(mapping, dict) or set(mapping) != {"kimi", "qwen"}:
        raise SystemExit(1)
    for tool in ("kimi", "qwen"):
        item = mapping[tool]
        if not isinstance(item, dict) or set(item) != {"manifestPath"}:
            raise SystemExit(1)
        path = item["manifestPath"]
        if not isinstance(path, str) or not path.startswith("/") \
                or path == "/" or path.endswith("/") or "\x00" in path:
            raise SystemExit(1)
        if any(not part or part in (".", "..")
               for part in path.split("/")[1:]):
            raise SystemExit(1)
elif "mapping" in value:
    raise SystemExit(1)
if "security" in value:
    security = value["security"]
    if not isinstance(security, dict):
        raise SystemExit(1)
    if result.get("status") == "passed":
        if security != {"result": "passed"}:
            raise SystemExit(1)
    elif set(security) != {"reason"} \
            or not isinstance(security.get("reason"), str) \
            or not security["reason"]:
        raise SystemExit(1)
PY
  AGENCY269_M2_STDOUT_EMITTED=1
  printf '%s\n' "$payload"
}

agency269_m2_preflight_report_target() {
  [[ $# -eq 1 ]] || return 64
  python3 - "$1" <<'PY'
import errno
import json
import os
import stat
import sys

REPORT_PATH = 74
EVIDENCE_ROOT = 77
PRIMARY_AND_CLOSE = 78
FD_CLOSE = 79


class AdmissionFailure(Exception):
    def __init__(self, failure_class, rc):
        super().__init__(failure_class)
        self.failure_class = failure_class
        self.rc = rc


def safe_component(value):
    return isinstance(value, str) and value not in ("", ".", "..") \
        and "/" not in value and "\x00" not in value


def descriptor_type(mode):
    if stat.S_ISDIR(mode):
        return "directory"
    if stat.S_ISREG(mode):
        return "regular"
    if stat.S_ISSOCK(mode):
        return "socket"
    return "other"


def directory_receipt(fd):
    first = os.fstat(fd)
    second = os.fstat(fd)
    stable = lambda value: (
        value.st_dev, value.st_ino, value.st_mode, value.st_uid,
        value.st_nlink, value.st_size, value.st_mtime_ns, value.st_ctime_ns,
    )
    if stable(first) != stable(second) or not stat.S_ISDIR(first.st_mode) \
            or first.st_uid != os.geteuid() \
            or stat.S_IMODE(first.st_mode) != 0o700:
        raise OSError(errno.EPERM, "directory admission")
    return {
        "ctimeNs": first.st_ctime_ns,
        "dev": first.st_dev,
        "ino": first.st_ino,
        "mode": stat.S_IMODE(first.st_mode),
        "mtimeNs": first.st_mtime_ns,
        "nlink": first.st_nlink,
        "size": first.st_size,
        "type": descriptor_type(first.st_mode),
        "uid": first.st_uid,
    }


def open_directory(parent_fd, component):
    if not safe_component(component):
        raise OSError(errno.EINVAL, "unsafe component")
    fd = os.open(
        component,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
        dir_fd=parent_fd,
    )
    directory_receipt(fd)
    return fd


def main(raw):
    owned = []
    primary = None
    close_failed = False
    try:
        context = json.loads(raw)
        canonical = json.dumps(
            context, ensure_ascii=True, sort_keys=True, separators=(",", ":"),
        )
        if canonical != raw or context.get("schema") != \
                "agency-agents.m1-m3-dispatch-context/v1":
            raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)
        components = context.get("components")
        receipts = context.get("descriptorReceipts")
        if not isinstance(components, dict) or not isinstance(receipts, list):
            raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)
        evidence = components.get("evidenceRoot")
        report_parent = components.get("reportParent")
        report_leaf = components.get("reportLeaf")
        if report_parent is None and report_leaf is None:
            print("ok")
            return 0
        if not isinstance(evidence, list) or not evidence \
                or not all(safe_component(item) for item in evidence):
            raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)
        if not isinstance(report_parent, list) \
                or not all(safe_component(item) for item in report_parent) \
                or not isinstance(report_leaf, list) or len(report_leaf) != 1 \
                or not safe_component(report_leaf[0]):
            raise AdmissionFailure("report-path", REPORT_PATH)
        frozen = [item for item in receipts
                  if isinstance(item, dict) and item.get("fd") == 18
                  and item.get("role") == "homeAuthority"]
        if len(frozen) != 1:
            raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)
        current = directory_receipt(18)
        compared = ("ctimeNs", "dev", "ino", "mode", "mtimeNs", "nlink",
                    "size", "type", "uid")
        if any(current[key] != frozen[0].get(key) for key in compared):
            raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)
        hook_requested = any(name in os.environ for name in (
            "AGENCY_TEST_EVIDENCE_RACE_STAGE",
            "AGENCY_TEST_EVIDENCE_RACE_AUTH",
        ))
        if hook_requested:
            if context.get("testMode") is not True \
                    or os.environ.get("AGENCY269_TEST_MODE") != "1" \
                    or os.environ.get("AGENCY_TEST_EVIDENCE_RACE_AUTH") \
                    != "isolated-production-root-v1":
                raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)
            frozen_test = [item for item in receipts
                           if isinstance(item, dict)
                           and item.get("fd") == 9
                           and item.get("role") == "testRoot"]
            if len(frozen_test) != 1:
                raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)
            current_test = directory_receipt(9)
            if any(current_test[key] != frozen_test[0].get(key)
                   for key in compared):
                raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)

            stage = os.environ.get("AGENCY_TEST_EVIDENCE_RACE_STAGE")
            stages = {
                "before-evidence-ancestry-unsafe",
                "before-evidence-ancestry-symlink",
                "before-evidence-ancestry-replacement",
            }
            if stage not in stages or not isinstance(evidence, list) \
                    or not evidence or not all(safe_component(item)
                                                for item in evidence):
                raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)

            replacement_name = ".agency-test-evidence-replacement"
            opened = []
            mutation_succeeded = False
            close_failed = False

            def checked_fsync(fd):
                try:
                    os.fsync(fd)
                except OSError:
                    raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)

            def require_absent(parent_fd, name):
                try:
                    os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
                except FileNotFoundError:
                    return
                except OSError:
                    raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)
                raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)

            try:
                parent_fd = 9
                for component in evidence[:-1]:
                    parent_fd = open_directory(parent_fd, component)
                    opened.append(parent_fd)
                canonical_name = evidence[-1]
                evidence_fd = open_directory(parent_fd, canonical_name)
                opened.append(evidence_fd)

                if stage == "before-evidence-ancestry-unsafe":
                    os.fchmod(evidence_fd, 0o755)
                    checked_fsync(evidence_fd)
                    checked_fsync(parent_fd)
                    mutation_succeeded = True
                elif stage == "before-evidence-ancestry-symlink":
                    if not isinstance(report_parent, list) \
                            or len(report_parent) != 1 \
                            or not safe_component(report_parent[0]):
                        raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)
                    report_name = report_parent[0]
                    old_name = report_name + ".old"
                    require_absent(evidence_fd, old_name)
                    os.rename(report_name, old_name,
                              src_dir_fd=evidence_fd, dst_dir_fd=evidence_fd)
                    os.symlink("../../attack", report_name,
                               dir_fd=evidence_fd)
                    checked_fsync(evidence_fd)
                    mutation_succeeded = True
                else:
                    if not isinstance(report_parent, list) \
                            or len(report_parent) != 1 \
                            or not safe_component(report_parent[0]):
                        raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)
                    report_name = report_parent[0]
                    old_name = report_name + ".old"
                    require_absent(evidence_fd, old_name)
                    replacement_fd = open_directory(evidence_fd,
                                                    replacement_name)
                    opened.append(replacement_fd)
                    os.rename(report_name, old_name,
                              src_dir_fd=evidence_fd, dst_dir_fd=evidence_fd)
                    os.rename(replacement_name, report_name,
                              src_dir_fd=evidence_fd, dst_dir_fd=evidence_fd)
                    checked_fsync(evidence_fd)
                    mutation_succeeded = True
            except AdmissionFailure:
                raise
            except OSError:
                raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)
            finally:
                for fd in reversed(opened):
                    try:
                        os.close(fd)
                    except OSError:
                        close_failed = True

            if close_failed or not mutation_succeeded:
                raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)
            marker = ("EVIDENCE_ANCESTRY_HOOK_HIT=%s\n" % stage).encode("ascii")
            try:
                if os.write(2, marker) != len(marker):
                    raise OSError(errno.EIO, "short marker")
            except OSError:
                raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)
            raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)
        current_fd = 18
        try:
            for component in evidence:
                current_fd = open_directory(current_fd, component)
                owned.append(current_fd)
        except OSError:
            raise AdmissionFailure("evidence-root", EVIDENCE_ROOT)
        try:
            for component in report_parent:
                current_fd = open_directory(current_fd, component)
                owned.append(current_fd)
            try:
                os.stat(report_leaf[0], dir_fd=current_fd,
                        follow_symlinks=False)
            except FileNotFoundError:
                pass
            except OSError:
                raise AdmissionFailure("report-path", REPORT_PATH)
            else:
                raise AdmissionFailure("report-path", REPORT_PATH)
        except AdmissionFailure:
            raise
        except OSError:
            raise AdmissionFailure("report-path", REPORT_PATH)
    except AdmissionFailure as exc:
        primary = exc
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
        primary = AdmissionFailure("evidence-root", EVIDENCE_ROOT)
    finally:
        for fd in reversed(owned):
            try:
                os.close(fd)
            except OSError:
                close_failed = True
    if primary is not None:
        print(primary.failure_class)
        return PRIMARY_AND_CLOSE if close_failed else primary.rc
    if close_failed:
        print("descriptor-close")
        return FD_CLOSE
    print("ok")
    return 0


raise SystemExit(main(sys.argv[1]))
PY
}

agency269_m2_emit_cli_terminal() {
  [[ $# -eq 7 ]] || return 64
  local status="$1" mode="$2" rc="$3" stage="$4"
  local operation="$5" reason="$6" id="$7"
  local result_mode='null'
  case "$status|$mode|$rc|$stage|$operation|$reason|$id" in
    'passed|null|0|cli-help|argument-validation|help-requested|help'|\
    'failed|null|64|cli-argument-validation|argument-validation|unknown-option|unknown-option'|\
    'failed|null|64|cli-argument-validation|argument-validation|missing-option-value|missing-option-value'|\
    'failed|null|64|cli-argument-validation|argument-validation|conflicting-mode|conflicting-mode'|\
    'failed|null|64|cli|mode-selection|mode is required|mode-selection') ;;
    *) return 64 ;;
  esac
  [[ "$mode" != 'null' ]] && result_mode="\"$mode\""
  [[ "$AGENCY269_M2_STDOUT_EMITTED" == 0 ]] || return 1
  AGENCY269_M2_STDOUT_EMITTED=1
  printf '%s\n' "{\"failure\":{\"id\":\"$id\",\"operation\":\"$operation\",\"reason\":\"$reason\",\"stage\":\"$stage\",\"target\":null,\"tool\":null},\"manifest\":{\"state\":\"not-loaded\",\"targetRootCount\":0,\"toolCount\":0,\"transactionCount\":0},\"result\":{\"backupCount\":0,\"mode\":$result_mode,\"rc\":$rc,\"status\":\"$status\"},\"rollback\":{\"attempted\":0,\"entries\":[],\"performed\":false,\"restoreFailures\":[],\"restored\":0},\"schema\":\"$AGENCY269_M2_SCHEMA\",\"targets\":[]}"
}

# All non-early operations capture helper stdout and re-emit exactly one
# value through agency269_m2_emit_single_json.  Helper diagnostics never leak.
agency269_m2_exec() {
  [[ $# -eq 2 ]] || { agency269_m2_emit_cli_terminal failed null 64 cli-argument-validation argument-validation missing-option-value missing-option-value; return 64; }
  local operation="$1" config="$2" output helper_rc
  if output="$(python3 - "$operation" "$config" <<'PY'
import errno
import fcntl
import json
import os
import stat
import sys

PRIMARY = 1
REPORT_PATH = 74
REPORT_WRITE = 75
EVIDENCE_ANCESTRY = 76
FD_CLOSE = 79
PRIMARY_AND_CLOSE = 78
ROLE_FDS = {
    "testRoot": 9, "entryExecution": 10, "entryHash": 11,
    "work": 12, "backupWorkspace": 13, "reportLeaf": 14,
    "origin": 15, "source": 16, "project": 17,
    "homeAuthority": 18, "transactionParent": 19,
    "evidenceRoot": 20, "reportParent": 21,
}
FIXED_FDS = frozenset(ROLE_FDS.values())

def compact(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True,
                      separators=(",", ":"))

def result(rc=0, failure=None, **extra):
    value = {"close_rc": 0, "failure": failure, "primary_failure": None,
             "primary_rc": 0, "rc": rc, "secondary_close_failures": [],
             "receipts": []}
    value.update(extra)
    return value

def fail(module, stage, operation, reason, rc=PRIMARY):
    return result(rc, {"module": module, "stage": stage,
                       "operation": operation, "reason": reason,
                       "originalRc": rc}, primary_failure=reason,
                  primary_rc=rc)

def load(raw):
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError("config")
    supplied = value.get("fd_roles")
    if supplied is not None:
        expected = {name: number for name, number in ROLE_FDS.items()}
        if supplied != expected:
            return None, fail("M2", "fd-role", "fd-role-map",
                              "M2_FD_ROLE_OVERRIDE")
    return value, None

def identity(fd):
    st = os.fstat(fd)
    return {"dev": st.st_dev, "ino": st.st_ino,
            "mode": stat.S_IMODE(st.st_mode), "size": st.st_size,
            "mtime_ns": st.st_mtime_ns, "ctime_ns": st.st_ctime_ns}

def fd_open(fd):
    try:
        os.fstat(fd)
        return True
    except OSError:
        return False

def lexical(component):
    return isinstance(component, str) and bool(component) and "/" not in component \
        and "\x00" not in component and component not in (".", "..")

def validate_roles(value, required=()):
    for name in required:
        if name not in ROLE_FDS or not fd_open(ROLE_FDS[name]):
            return fail("M2", "fd-role", "fd-validation", "M2_FD_NOT_OPEN")
    return None

def validate_lifecycle(value):
    error = validate_roles(value, tuple(ROLE_FDS))
    if error:
        return error
    directory_roles = ("testRoot", "work", "backupWorkspace", "source",
                       "project", "homeAuthority", "transactionParent",
                       "evidenceRoot", "reportParent")
    regular_roles = ("entryExecution", "entryHash", "reportLeaf")
    for role in directory_roles:
        if not stat.S_ISDIR(os.fstat(ROLE_FDS[role]).st_mode):
            return fail("M2", "fd-role", "fd-validation", "M2_FD_ROLE_FLAGS")
    for role in regular_roles:
        if not stat.S_ISREG(os.fstat(ROLE_FDS[role]).st_mode):
            return fail("M2", "fd-role", "fd-validation", "M2_FD_ROLE_FLAGS")
    if not stat.S_ISSOCK(os.fstat(ROLE_FDS["origin"]).st_mode):
        return fail("M2", "fd-role", "fd-validation", "M2_FD_ROLE_FLAGS")
    first = identity(ROLE_FDS["entryExecution"])
    second = identity(ROLE_FDS["entryHash"])
    if ROLE_FDS["entryExecution"] == ROLE_FDS["entryHash"] \
            or first != second:
        return fail("M2", "fd-role", "entry-pair", "M2_ENTRY_INDEPENDENCE")
    source_first = identity(ROLE_FDS["source"])
    source_second = identity(ROLE_FDS["source"])
    if source_first != source_second:
        return fail("M2", "fd-role", "FD16", "M2_FD_IDENTITY_UNSTABLE")
    evidence = identity(ROLE_FDS["evidenceRoot"])
    if evidence["mode"] != 448:
        return fail("M2", "fd-role", "FD20", "M2_FD_ROLE_FLAGS")
    return result(0, None, fd_roles=ROLE_FDS,
                  receipts=[{"role": role, "identity": identity(fd)}
                            for role, fd in ROLE_FDS.items()])

def close_one(fd, close_fail=False):
    if close_fail:
        return {"fd": fd, "rc": FD_CLOSE, "reason": "close-failed"}
    try:
        os.close(fd)
    except OSError:
        return {"fd": fd, "rc": FD_CLOSE, "reason": "close-failed"}
    return None

def checked_close(value):
    role = value.get("role")
    if role not in ROLE_FDS:
        return fail("M2", "descriptor-close", "checked-close",
                    "M2_FD_ROLE_NUMBER")
    state = value.get("state", "open")
    if state in ("closed", "failed"):
        return fail("M2", "descriptor-close", "checked-close",
                    "M2_FD_CLOSE_RETRY_BLOCKED")
    primary_rc = int(value.get("primary_rc", 0))
    close_rc = int(value.get("close_rc", 0))
    if close_rc and primary_rc:
        rc = PRIMARY_AND_CLOSE
    elif close_rc:
        rc = FD_CLOSE
    elif primary_rc:
        rc = PRIMARY
    else:
        rc = 0
    failures = [] if not close_rc else [{"role": role, "rc": FD_CLOSE,
                                         "reason": "close-failed"}]
    return result(rc, None if not primary_rc else {"module": "M2",
        "stage": "descriptor-close", "operation": "checked-close",
        "reason": "primary-failure", "originalRc": primary_rc},
        close_rc=close_rc, primary_rc=primary_rc,
        primary_failure=None if not primary_rc else "primary-failure",
        secondary_close_failures=failures)

def open_relative(value):
    error = validate_roles(value, (value.get("parent_role"),))
    if error:
        return error
    parent_role = value.get("parent_role")
    component = value.get("component")
    kind = value.get("kind", "regular")
    if parent_role not in ROLE_FDS or not lexical(component):
        return fail("M2", "descriptor-open", "open-relative",
                    "M2_COMPONENT_UNSAFE")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    if kind == "directory":
        flags |= getattr(os, "O_DIRECTORY", 0)
    try:
        owned = os.open(component, flags, dir_fd=ROLE_FDS[parent_role])
        receipt = identity(owned)
        if kind == "directory" and not stat.S_ISDIR(os.fstat(owned).st_mode):
            close_one(owned)
            return fail("M2", "descriptor-open", "open-relative",
                        "M2_FD_KIND")
        if kind == "regular" and not stat.S_ISREG(os.fstat(owned).st_mode):
            close_one(owned)
            return fail("M2", "descriptor-open", "open-relative",
                        "M2_FD_KIND")
        close_failure = close_one(owned)
        if close_failure:
            return result(FD_CLOSE, close_failure, close_rc=FD_CLOSE,
                          secondary_close_failures=[close_failure],
                          receipts=[receipt])
        return result(0, None, receipts=[receipt], parent_role=parent_role,
                      component=component)
    except OSError:
        return fail("M2", "descriptor-open", "open-relative",
                    "M2_DESCRIPTOR_OPEN")

def traverse(value):
    root_role = value.get("root_role")
    components = value.get("components")
    if root_role not in ROLE_FDS or not isinstance(components, list):
        return fail("M2", "descriptor-traversal", "traverse",
                    "M2_COMPONENT_UNSAFE")
    error = validate_roles(value, (root_role,))
    if error:
        return error
    current = ROLE_FDS[root_role]
    owned = []
    receipts = []
    try:
        for index, component in enumerate(components):
            if not lexical(component):
                return fail("M2", "descriptor-traversal", "traverse",
                            "M2_COMPONENT_UNSAFE")
            flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
            if index < len(components) - 1 or value.get("directory"):
                flags |= getattr(os, "O_DIRECTORY", 0)
            child = os.open(component, flags, dir_fd=current)
            owned.append(child)
            receipts.append(identity(child))
            current = child
        close_failures = []
        for child in reversed(owned):
            failure = close_one(child)
            if failure:
                close_failures.append(failure)
        if close_failures:
            return result(FD_CLOSE, close_failures[0], close_rc=FD_CLOSE,
                          secondary_close_failures=close_failures,
                          receipts=receipts)
        return result(0, None, receipts=receipts, root_role=root_role)
    except OSError:
        for child in reversed(owned):
            close_one(child)
        return fail("M2", "descriptor-traversal", "traverse",
                    "M2_DESCRIPTOR_TRAVERSAL")

def authorization(value):
    error = validate_roles(value, ("homeAuthority",))
    if error:
        return error
    action = value.get("action_leaf")
    signature = value.get("signature_leaf")
    if not lexical(action) or not lexical(signature):
        return fail("M2", "authorization", "authorization-open",
                    "M2_AUTHORIZATION_OPEN")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    opened = []
    receipts = []
    try:
        for leaf in (action, signature):
            fd = os.open(leaf, flags, dir_fd=ROLE_FDS["homeAuthority"])
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                raise OSError(errno.EINVAL, "kind")
            # Owned descriptors are relocated above the fixed table.  The
            # fixed table and evidence descriptors are never reused.
            moved = fcntl.fcntl(fd, fcntl.F_DUPFD_CLOEXEC, 23)
            os.close(fd)
            opened.append(moved)
            receipts.append(identity(moved))
        close_failures = []
        for fd in reversed(opened):
            failure = close_one(fd)
            if failure:
                close_failures.append(failure)
        if close_failures:
            return result(FD_CLOSE, close_failures[0], close_rc=FD_CLOSE,
                          secondary_close_failures=close_failures,
                          receipts=receipts)
        return result(0, None, receipts=receipts, authorization="fd18-relative")
    except OSError:
        for fd in reversed(opened):
            close_one(fd)
        return fail("M2", "authorization", "authorization-open",
                    "M2_AUTHORIZATION_OPEN")

def validate_evidence(value):
    error = validate_roles(value, ("evidenceRoot", "reportParent"))
    if error:
        return error
    try:
        root = identity(ROLE_FDS["evidenceRoot"])
        parent = identity(ROLE_FDS["reportParent"])
        root_mode = os.fstat(ROLE_FDS["evidenceRoot"]).st_mode
        if not stat.S_ISDIR(root_mode) or root["mode"] != 448:
            return fail("M2", "evidence-validation", "evidence-root",
                        "M2_EVIDENCE_ANCESTRY", EVIDENCE_ANCESTRY)
        expected = value.get("ancestry", [])
        if expected:
            if expected[0].get("fd") != 20 or expected[-1].get("fd") != 21:
                return fail("M2", "evidence-validation", "evidence-root",
                            "M2_EVIDENCE_ANCESTRY", EVIDENCE_ANCESTRY)
        return result(0, None, receipts=[root, parent], ancestry="FD20-FD21")
    except OSError:
        return fail("M2", "evidence-validation", "evidence-root",
                    "M2_EVIDENCE_ANCESTRY", EVIDENCE_ANCESTRY)

def report(value):
    checked = validate_evidence(value)
    if checked.get("rc"):
        return checked
    leaf = value.get("report_leaf")
    payload = value.get("payload")
    if not lexical(leaf) or not isinstance(payload, dict):
        return fail("M2", "report-path", "report-open", "M2_REPORT_PATH",
                    REPORT_PATH)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    fd = None
    before = None
    try:
        fd = os.open(leaf, flags, 0o600, dir_fd=ROLE_FDS["reportParent"])
        # FD14 is the report leaf role; FD20 and FD21 are borrowed anchors.
        os.dup2(fd, 14, inheritable=False)
        os.close(fd)
        fd = 14
        before = identity(fd)
        encoded = (compact(payload) + "\n").encode("ascii")
        offset = 0
        while offset < len(encoded):
            written = os.write(fd, encoded[offset:])
            if written <= 0:
                raise OSError(errno.EIO, "write")
            offset += written
        os.fsync(fd)
        after = identity(fd)
        if after["size"] != len(encoded) or after["dev"] != before["dev"] \
                or after["ino"] != before["ino"]:
            return fail("M2", "report-write", "report-write",
                        "M2_EVIDENCE_WRITE", REPORT_WRITE)
        close_failure = close_one(fd)
        fd = None
        if close_failure:
            return result(FD_CLOSE, close_failure, close_rc=FD_CLOSE,
                          secondary_close_failures=[close_failure],
                          receipts=[before, after])
        return result(0, None, receipts=[before, after], report_leaf=leaf)
    except (OSError, UnicodeEncodeError):
        if fd is not None:
            close_one(fd)
        return fail("M2", "report-write", "report-write",
                    "M2_EVIDENCE_WRITE", REPORT_WRITE)

def status(value):
    primary_rc = int(value.get("primary_rc", 0))
    secondary_rc = int(value.get("secondary_rc", 0))
    if primary_rc and secondary_rc:
        rc = PRIMARY_AND_CLOSE
    elif primary_rc:
        rc = PRIMARY
    elif secondary_rc:
        rc = FD_CLOSE
    else:
        rc = 0
    return result(rc, None if not primary_rc else {
        "module": "M2", "stage": "status", "operation": "status",
        "reason": "primary-failure", "originalRc": primary_rc},
        primary_rc=primary_rc, primary_failure=None if not primary_rc else
        "primary-failure", close_rc=secondary_rc,
        secondary_close_failures=[] if not secondary_rc else
        [{"rc": secondary_rc, "reason": "secondary-failure"}])

def main():
    operation, raw = sys.argv[1:]
    try:
        value, error = load(raw)
        if error:
            output = error
        elif operation == "lifecycle":
            output = validate_lifecycle(value)
        elif operation == "checked-close":
            output = checked_close(value)
        elif operation == "evidence-root":
            output = validate_evidence(value)
        elif operation == "report":
            output = report(value)
        elif operation == "status":
            output = status(value)
        elif operation == "open-relative":
            output = open_relative(value)
        elif operation == "traverse":
            output = traverse(value)
        elif operation == "authorization-open":
            output = authorization(value)
        else:
            output = fail("M2", "protocol", "operation", "M2_PROTOCOL")
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
        output = fail("M2", "protocol", operation, "M2_PROTOCOL")
    sys.stdout.write(compact(output) + "\n")
    return int(output.get("rc", PRIMARY))

sys.exit(main())
PY
)"; then
    helper_rc=0
  else
    helper_rc=$?
  fi
  [[ -n "$output" ]] || output="{\"failure\":{\"id\":\"m2-helper\",\"operation\":\"$operation\",\"reason\":\"helper-failed\",\"stage\":\"m2\",\"target\":null,\"tool\":null},\"manifest\":{\"state\":\"not-loaded\",\"targetRootCount\":0,\"toolCount\":0,\"transactionCount\":0},\"result\":{\"backupCount\":0,\"mode\":null,\"rc\":1,\"status\":\"failed\"},\"rollback\":{\"attempted\":0,\"entries\":[],\"performed\":false,\"restoreFailures\":[],\"restored\":0},\"schema\":\"$AGENCY269_M2_SCHEMA\",\"targets\":[]}"
  printf '%s\n' "$output"
  [[ "$helper_rc" -eq 0 ]] && return 0
  return "$helper_rc"
}

agency269_m2_fd_lifecycle() { [[ $# -eq 1 ]] && agency269_m2_exec lifecycle "$1"; }
agency269_m2_checked_close() {
  [[ $# -eq 1 ]] || return 79
  local config_json="$1"
  case "$config_json" in
    '{"fd_roles":{"backupWorkspace":13,"entryExecution":10,"entryHash":11,"evidenceRoot":20,"homeAuthority":18,"origin":15,"project":17,"reportLeaf":14,"reportParent":21,"source":16,"testRoot":9,"transactionParent":19,"work":12},"role":"testRoot"}')
      case "$AGENCY269_M2_FIXED_CLOSE_ATTEMPTED" in *'|9|'*) return 79 ;; esac
      AGENCY269_M2_FIXED_CLOSE_ATTEMPTED="${AGENCY269_M2_FIXED_CLOSE_ATTEMPTED}9|"
      if exec 9>&-; then return 0; fi
      AGENCY269_M2_FIXED_CLOSE_SECONDARY='E_DESCRIPTOR_CLOSE:FD9'
      return 79
      ;;
    '{"fd_roles":{"backupWorkspace":13,"entryExecution":10,"entryHash":11,"evidenceRoot":20,"homeAuthority":18,"origin":15,"project":17,"reportLeaf":14,"reportParent":21,"source":16,"testRoot":9,"transactionParent":19,"work":12},"role":"entryExecution"}')
      case "$AGENCY269_M2_FIXED_CLOSE_ATTEMPTED" in *'|10|'*) return 79 ;; esac
      AGENCY269_M2_FIXED_CLOSE_ATTEMPTED="${AGENCY269_M2_FIXED_CLOSE_ATTEMPTED}10|"
      if exec 10>&-; then return 0; fi
      AGENCY269_M2_FIXED_CLOSE_SECONDARY='E_DESCRIPTOR_CLOSE:FD10'
      return 79
      ;;
    '{"fd_roles":{"backupWorkspace":13,"entryExecution":10,"entryHash":11,"evidenceRoot":20,"homeAuthority":18,"origin":15,"project":17,"reportLeaf":14,"reportParent":21,"source":16,"testRoot":9,"transactionParent":19,"work":12},"role":"entryHash"}')
      case "$AGENCY269_M2_FIXED_CLOSE_ATTEMPTED" in *'|11|'*) return 79 ;; esac
      AGENCY269_M2_FIXED_CLOSE_ATTEMPTED="${AGENCY269_M2_FIXED_CLOSE_ATTEMPTED}11|"
      if exec 11>&-; then return 0; fi
      AGENCY269_M2_FIXED_CLOSE_SECONDARY='E_DESCRIPTOR_CLOSE:FD11'
      return 79
      ;;
    '{"fd_roles":{"backupWorkspace":13,"entryExecution":10,"entryHash":11,"evidenceRoot":20,"homeAuthority":18,"origin":15,"project":17,"reportLeaf":14,"reportParent":21,"source":16,"testRoot":9,"transactionParent":19,"work":12},"role":"work"}')
      case "$AGENCY269_M2_FIXED_CLOSE_ATTEMPTED" in *'|12|'*) return 79 ;; esac
      AGENCY269_M2_FIXED_CLOSE_ATTEMPTED="${AGENCY269_M2_FIXED_CLOSE_ATTEMPTED}12|"
      if exec 12>&-; then return 0; fi
      AGENCY269_M2_FIXED_CLOSE_SECONDARY='E_DESCRIPTOR_CLOSE:FD12'
      return 79
      ;;
    '{"fd_roles":{"backupWorkspace":13,"entryExecution":10,"entryHash":11,"evidenceRoot":20,"homeAuthority":18,"origin":15,"project":17,"reportLeaf":14,"reportParent":21,"source":16,"testRoot":9,"transactionParent":19,"work":12},"role":"backupWorkspace"}')
      case "$AGENCY269_M2_FIXED_CLOSE_ATTEMPTED" in *'|13|'*) return 79 ;; esac
      AGENCY269_M2_FIXED_CLOSE_ATTEMPTED="${AGENCY269_M2_FIXED_CLOSE_ATTEMPTED}13|"
      if exec 13>&-; then return 0; fi
      AGENCY269_M2_FIXED_CLOSE_SECONDARY='E_DESCRIPTOR_CLOSE:FD13'
      return 79
      ;;
    '{"fd_roles":{"backupWorkspace":13,"entryExecution":10,"entryHash":11,"evidenceRoot":20,"homeAuthority":18,"origin":15,"project":17,"reportLeaf":14,"reportParent":21,"source":16,"testRoot":9,"transactionParent":19,"work":12},"role":"reportLeaf"}')
      case "$AGENCY269_M2_FIXED_CLOSE_ATTEMPTED" in *'|14|'*) return 79 ;; esac
      AGENCY269_M2_FIXED_CLOSE_ATTEMPTED="${AGENCY269_M2_FIXED_CLOSE_ATTEMPTED}14|"
      if exec 14>&-; then return 0; fi
      AGENCY269_M2_FIXED_CLOSE_SECONDARY='E_DESCRIPTOR_CLOSE:FD14'
      return 79
      ;;
    '{"fd_roles":{"backupWorkspace":13,"entryExecution":10,"entryHash":11,"evidenceRoot":20,"homeAuthority":18,"origin":15,"project":17,"reportLeaf":14,"reportParent":21,"source":16,"testRoot":9,"transactionParent":19,"work":12},"role":"origin"}')
      case "$AGENCY269_M2_FIXED_CLOSE_ATTEMPTED" in *'|15|'*) return 79 ;; esac
      AGENCY269_M2_FIXED_CLOSE_ATTEMPTED="${AGENCY269_M2_FIXED_CLOSE_ATTEMPTED}15|"
      if exec 15>&-; then return 0; fi
      AGENCY269_M2_FIXED_CLOSE_SECONDARY='E_DESCRIPTOR_CLOSE:FD15'
      return 79
      ;;
    '{"fd_roles":{"backupWorkspace":13,"entryExecution":10,"entryHash":11,"evidenceRoot":20,"homeAuthority":18,"origin":15,"project":17,"reportLeaf":14,"reportParent":21,"source":16,"testRoot":9,"transactionParent":19,"work":12},"role":"source"}')
      case "$AGENCY269_M2_FIXED_CLOSE_ATTEMPTED" in *'|16|'*) return 79 ;; esac
      AGENCY269_M2_FIXED_CLOSE_ATTEMPTED="${AGENCY269_M2_FIXED_CLOSE_ATTEMPTED}16|"
      if exec 16>&-; then return 0; fi
      AGENCY269_M2_FIXED_CLOSE_SECONDARY='E_DESCRIPTOR_CLOSE:FD16'
      return 79
      ;;
    '{"fd_roles":{"backupWorkspace":13,"entryExecution":10,"entryHash":11,"evidenceRoot":20,"homeAuthority":18,"origin":15,"project":17,"reportLeaf":14,"reportParent":21,"source":16,"testRoot":9,"transactionParent":19,"work":12},"role":"project"}')
      case "$AGENCY269_M2_FIXED_CLOSE_ATTEMPTED" in *'|17|'*) return 79 ;; esac
      AGENCY269_M2_FIXED_CLOSE_ATTEMPTED="${AGENCY269_M2_FIXED_CLOSE_ATTEMPTED}17|"
      if exec 17>&-; then return 0; fi
      AGENCY269_M2_FIXED_CLOSE_SECONDARY='E_DESCRIPTOR_CLOSE:FD17'
      return 79
      ;;
    '{"fd_roles":{"backupWorkspace":13,"entryExecution":10,"entryHash":11,"evidenceRoot":20,"homeAuthority":18,"origin":15,"project":17,"reportLeaf":14,"reportParent":21,"source":16,"testRoot":9,"transactionParent":19,"work":12},"role":"homeAuthority"}')
      case "$AGENCY269_M2_FIXED_CLOSE_ATTEMPTED" in *'|18|'*) return 79 ;; esac
      AGENCY269_M2_FIXED_CLOSE_ATTEMPTED="${AGENCY269_M2_FIXED_CLOSE_ATTEMPTED}18|"
      if exec 18>&-; then return 0; fi
      AGENCY269_M2_FIXED_CLOSE_SECONDARY='E_DESCRIPTOR_CLOSE:FD18'
      return 79
      ;;
    '{"fd_roles":{"backupWorkspace":13,"entryExecution":10,"entryHash":11,"evidenceRoot":20,"homeAuthority":18,"origin":15,"project":17,"reportLeaf":14,"reportParent":21,"source":16,"testRoot":9,"transactionParent":19,"work":12},"role":"transactionParent"}')
      case "$AGENCY269_M2_FIXED_CLOSE_ATTEMPTED" in *'|19|'*) return 79 ;; esac
      AGENCY269_M2_FIXED_CLOSE_ATTEMPTED="${AGENCY269_M2_FIXED_CLOSE_ATTEMPTED}19|"
      if exec 19>&-; then return 0; fi
      AGENCY269_M2_FIXED_CLOSE_SECONDARY='E_DESCRIPTOR_CLOSE:FD19'
      return 79
      ;;
    '{"fd_roles":{"backupWorkspace":13,"entryExecution":10,"entryHash":11,"evidenceRoot":20,"homeAuthority":18,"origin":15,"project":17,"reportLeaf":14,"reportParent":21,"source":16,"testRoot":9,"transactionParent":19,"work":12},"role":"evidenceRoot"}')
      case "$AGENCY269_M2_FIXED_CLOSE_ATTEMPTED" in *'|20|'*) return 79 ;; esac
      AGENCY269_M2_FIXED_CLOSE_ATTEMPTED="${AGENCY269_M2_FIXED_CLOSE_ATTEMPTED}20|"
      if exec 20>&-; then return 0; fi
      AGENCY269_M2_FIXED_CLOSE_SECONDARY='E_DESCRIPTOR_CLOSE:FD20'
      return 79
      ;;
    '{"fd_roles":{"backupWorkspace":13,"entryExecution":10,"entryHash":11,"evidenceRoot":20,"homeAuthority":18,"origin":15,"project":17,"reportLeaf":14,"reportParent":21,"source":16,"testRoot":9,"transactionParent":19,"work":12},"role":"reportParent"}')
      case "$AGENCY269_M2_FIXED_CLOSE_ATTEMPTED" in *'|21|'*) return 79 ;; esac
      AGENCY269_M2_FIXED_CLOSE_ATTEMPTED="${AGENCY269_M2_FIXED_CLOSE_ATTEMPTED}21|"
      if exec 21>&-; then return 0; fi
      AGENCY269_M2_FIXED_CLOSE_SECONDARY='E_DESCRIPTOR_CLOSE:FD21'
      return 79
      ;;
    *) return 79 ;;
  esac
}
agency269_m2_validate_evidence_root() { [[ $# -eq 1 ]] && agency269_m2_exec evidence-root "$1"; }
agency269_m2_write_canonical_report() { [[ $# -eq 1 ]] && agency269_m2_exec report "$1"; }
agency269_m2_propagate_status() { [[ $# -eq 1 ]] && agency269_m2_exec status "$1"; }
agency269_m2_open_relative() { [[ $# -eq 1 ]] && agency269_m2_exec open-relative "$1"; }
agency269_m2_traverse_relative() { [[ $# -eq 1 ]] && agency269_m2_exec traverse "$1"; }
agency269_m2_open_authorization_bundle() { [[ $# -eq 1 ]] && agency269_m2_exec authorization-open "$1"; }

agency269_m2_bind_transaction_roots_and_reexec() {
  [[ $# -eq 1 ]] || return 72
  local request_json="$1" binder_output binder_rc=0 writer_rc=0
  set +e
  binder_output="$(python3 - "$request_json" <<'PY'
import errno
import fcntl
import hashlib
import json
import os
import secrets
import signal
import socket
import stat
import sys

REQUEST_SCHEMA = "agency-agents.m2-post-auth-reexec-request/v1"
RESULT_SCHEMA = "agency-agents.m2-post-auth-origin-result/v1"
CONTEXT_SCHEMA = "agency-agents.m1-m3-dispatch-context/v1"
REPORT_SCHEMA = "agency-agents.local-sync-report/v1"
ROLE_FDS = {
    "testRoot": 9, "entryExecution": 10, "entryHash": 11,
    "work": 12, "backupWorkspace": 13, "reportLeaf": 14,
    "origin": 15, "source": 16, "project": 17,
    "homeAuthority": 18, "transactionParent": 19,
    "evidenceRoot": 20, "reportParent": 21,
}
REQUEST_KEYS = {
    "authSha256", "dispatchContext", "dispatchContextSha256", "entrySha256",
    "evidenceRootComponents", "fdRoles", "originalArgv",
    "reportLeafComponents", "reportParentComponents", "schema", "testMode",
    "transactionParentComponents",
}
CONTEXT_KEYS = {
    "argvSha256", "components", "descriptorReceipts", "entrySha256",
    "fdRoles", "mode", "restArgs", "schema", "testMode",
}
COMPONENT_KEYS = {
    "action", "allowedSigners", "entry", "evidenceRoot", "ledger",
    "manifest", "profiles", "reportLeaf", "reportParent", "signature",
    "source", "transactionParent",
}
RECEIPT_KEYS = {
    "ctimeNs", "dev", "fd", "ino", "mode", "mtimeNs", "nlink",
    "role", "size", "type", "uid",
}
RESULT_KEYS = {
    "authSha256", "bindingSha256", "childPid", "childRc",
    "descriptorReceipts", "dispatchContextSha256", "parentPid", "phase",
    "primary", "reportOwnership", "schema", "status",
}
PHASE_ENV_NAMES = {
    "AGENCY269_POST_AUTH_AUTH_SHA256", "AGENCY269_POST_AUTH_CHILD_PID",
    "AGENCY269_POST_AUTH_CONTEXT", "AGENCY269_POST_AUTH_CONTEXT_SHA256",
    "AGENCY269_POST_AUTH_NONCE_SHA256", "AGENCY269_POST_AUTH_ORIGIN_FD",
    "AGENCY269_POST_AUTH_PARENT_PID", "AGENCY269_REEXEC", "AGENCY_REPORT_FD",
    "AGENCY_REPORT_FD_BOUND", "AGENCY_REPORT_FD_DEV", "AGENCY_REPORT_FD_INO",
    "AGENCY_REPORT_FD_MODE", "AGENCY_REPORT_FD_NLINK", "AGENCY_REPORT_FD_TYPE",
    "AGENCY_REPORT_FD_UID", "AGENCY_TXN_BACKUP_DEV", "AGENCY_TXN_BACKUP_INO",
    "AGENCY_TXN_BACKUP_LEAF", "AGENCY_TXN_BACKUP_ROOT", "AGENCY_TXN_ROOT_BOUND",
    "AGENCY_TXN_WORK_DEV", "AGENCY_TXN_WORK_INO", "AGENCY_TXN_WORK_LEAF",
    "AGENCY_TXN_WORK_ROOT", "POST_AUTH_DESCRIPTOR_BOUND",
}
HEX = set("0123456789abcdef")
TIMEOUT_SECONDS = 5.0
MAX_FRAME = 1048576


class BinderFailure(Exception):
    def __init__(self, stage, operation, reason, item_id, rc):
        super().__init__(reason)
        self.stage = stage
        self.operation = operation
        self.reason = reason
        self.item_id = item_id
        self.rc = rc


def canonical(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True,
                      separators=(",", ":"))


def digest_bytes(value):
    return hashlib.sha256(value).hexdigest()


def digest_text(value):
    return digest_bytes(value.encode("ascii"))


def is_digest(value):
    return isinstance(value, str) and len(value) == 64 and set(value) <= HEX


def safe_component(value):
    return isinstance(value, str) and value not in ("", ".", "..") \
        and "/" not in value and "\x00" not in value


def safe_components(value, nonempty=True):
    return isinstance(value, list) and (bool(value) or not nonempty) \
        and all(safe_component(item) for item in value)


def type_name(mode):
    if stat.S_ISDIR(mode):
        return "directory"
    if stat.S_ISREG(mode):
        return "regular"
    if stat.S_ISSOCK(mode):
        return "socket"
    return "other"


def role_for_fd(fd):
    for role, number in ROLE_FDS.items():
        if number == fd:
            return role
    raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                        "transaction root binding failed", "post-auth-binder-prefork", 72)


def receipt(fd, role=None):
    first = os.fstat(fd)
    second = os.fstat(fd)
    stable = (first.st_dev, first.st_ino, first.st_mode, first.st_uid,
              first.st_nlink, first.st_size, first.st_mtime_ns, first.st_ctime_ns)
    stable_second = (second.st_dev, second.st_ino, second.st_mode, second.st_uid,
                     second.st_nlink, second.st_size, second.st_mtime_ns,
                     second.st_ctime_ns)
    if stable != stable_second:
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    receipt_role = role if role is not None else role_for_fd(fd)
    receipt_type = type_name(first.st_mode)
    receipt_size = 0 if receipt_role == "origin" and receipt_type == "socket" else first.st_size
    return {
        "ctimeNs": first.st_ctime_ns,
        "dev": first.st_dev,
        "fd": fd,
        "ino": first.st_ino,
        "mode": stat.S_IMODE(first.st_mode),
        "mtimeNs": first.st_mtime_ns,
        "nlink": first.st_nlink,
        "role": receipt_role,
        "size": receipt_size,
        "type": receipt_type,
        "uid": first.st_uid,
    }


def primary_object(failure):
    return {
        "module": "M2",
        "stage": failure.stage,
        "operation": failure.operation,
        "reason": failure.reason,
        "originalRc": failure.rc,
    }


def origin_result(request, phase, status_value, ownership, child_pid,
                  child_rc, receipts, binding_sha, primary):
    value = {
        "authSha256": request.get("authSha256", "0" * 64),
        "bindingSha256": binding_sha,
        "childPid": child_pid,
        "childRc": child_rc,
        "descriptorReceipts": receipts,
        "dispatchContextSha256": request.get("dispatchContextSha256", "0" * 64),
        "parentPid": os.getpid(),
        "phase": phase,
        "primary": primary,
        "reportOwnership": ownership,
        "schema": RESULT_SCHEMA,
        "status": status_value,
    }
    if set(value) != RESULT_KEYS:
        raise BinderFailure("transaction-origin-validation",
                            "transaction-origin-validation",
                            "transaction launcher origin proof failed",
                            "post-auth-origin-proof", 67)
    return value


def external_failure(failure, public_rc):
    return {
        "failure": {
            "id": failure.item_id,
            "operation": failure.operation,
            "reason": failure.reason,
            "stage": failure.stage,
            "target": None,
            "tool": None,
        },
        "manifest": {
            "state": "not-loaded", "targetRootCount": 0,
            "toolCount": 0, "transactionCount": 0,
        },
        "result": {
            "backupCount": 0, "mode": "apply", "rc": public_rc,
            "status": "failed",
        },
        "rollback": {
            "attempted": 0, "entries": [], "performed": False,
            "restoreFailures": [], "restored": 0,
        },
        "schema": REPORT_SCHEMA,
        "targets": [],
    }


def write_all(fd, data):
    offset = 0
    while offset < len(data):
        written = os.write(fd, data[offset:])
        if written <= 0:
            raise OSError(errno.EIO, "write")
        offset += written


def emit_parent_failure(failure, public_rc):
    data = (canonical(external_failure(failure, public_rc)) + "\n").encode("ascii")
    try:
        write_all(1, data)
    except OSError:
        os._exit(78 if public_rc else 79)


class DescriptorState:
    def __init__(self):
        self.ordinal = 0
        self.records = []
        self.secondary = []

    def register(self, fd, role, owner="M2"):
        self.ordinal += 1
        record = {
            "token": "M2-%d-%d" % (self.ordinal, fd),
            "ownerModule": owner,
            "role": role,
            "fd": fd,
            "openOrdinal": self.ordinal,
            "state": "open",
        }
        self.records.append(record)
        return fd

    def find_open(self, fd):
        for record in reversed(self.records):
            if record["fd"] == fd and record["state"] == "open":
                return record
        return None

    def close(self, fd, role=None):
        close18_diag = fd == 18 and os.environ.get("AGENCY_TEST_BINDER_STAGE") == "ledger-replay-v1"
        if close18_diag:
            os.write(2, b"M2_CLOSE18=enter\n")
        record = self.find_open(fd)
        if record is None:
            if role is None:
                role = "ephemeral"
            self.register(fd, role)
            record = self.find_open(fd)
            if record is None:
                raise TypeError("descriptor ownership registration failed")
        record["state"] = "closing"
        try:
            os.close(fd)
        except OSError as exc:
            if close18_diag:
                os.write(2, b"M2_CLOSE18=exception\n")
            record["state"] = "failed"
            self.secondary.append({
                "code": "E_DESCRIPTOR_CLOSE",
                "ownerModule": record["ownerModule"],
                "role": record["role"],
                "errno": int(exc.errno or errno.EIO),
            })
            return False
        if close18_diag:
            os.write(2, b"M2_CLOSE18=syscall-ok\n")
        record["state"] = "closed"
        if close18_diag:
            os.write(2, b"M2_CLOSE18=closed\n")
        return True

    def close_reverse(self, excluded=()):
        excluded_set = set(excluded)
        for record in sorted(self.records, key=lambda item: item["openOrdinal"],
                             reverse=True):
            if record["state"] == "open" and record["fd"] not in excluded_set:
                self.close(record["fd"])


STATE = DescriptorState()


def rehome(fd, role):
    try:
        moved = fcntl.fcntl(fd, fcntl.F_DUPFD_CLOEXEC, 23)
    except OSError:
        STATE.register(fd, role)
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    STATE.register(fd, role + "-temporary")
    STATE.register(moved, role)
    if not STATE.close(fd):
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    if moved == 22 or moved < 23:
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    return moved


def ensure_fixed_free(fd):
    try:
        os.fstat(fd)
    except OSError as exc:
        if exc.errno == errno.EBADF:
            return
        raise
    raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                        "transaction root binding failed", "post-auth-binder-prefork", 72)


def bind_fixed(owned_fd, target, role):
    ensure_fixed_free(target)
    try:
        os.dup2(owned_fd, target, inheritable=True)
    except OSError:
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    STATE.register(target, role)
    if not STATE.close(owned_fd):
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    return target


def open_dir(parent_fd, component, role, require_mode=None):
    def binding_failure():
        if role.startswith("report-parent"):
            return BinderFailure("report-path-validation", "report-path-validation",
                                 "report path validation failed", "report-path-binding", 74)
        return BinderFailure("transaction-root-validation", "transaction-root-validation",
                             "transaction root binding failed", "post-auth-binder-prefork", 72)
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    try:
        raw = os.open(component, flags, dir_fd=parent_fd)
    except OSError:
        raise binding_failure()
    owned = rehome(raw, role)
    info = receipt(owned, role)
    if info["type"] != "directory" or (require_mode is not None and info["mode"] != require_mode):
        raise binding_failure()
    return owned, info


def traverse(anchor, components, role, require_all_mode=None):
    parent = anchor
    opened = []
    ancestry = []
    for index, component in enumerate(components):
        child, info = open_dir(parent, component,
                               role + "-ancestor-%d" % index,
                               require_mode=require_all_mode)
        opened.append(child)
        ancestry.append(info)
        parent = child
    return parent, opened, ancestry


def open_transaction_parent(anchor, components):
    if not components:
        try:
            child = rehome(os.dup(anchor), "transaction-parent")
            info = receipt(child, "transactionParent")
        except OSError:
            raise BinderFailure("transaction-root-validation",
                                "transaction-root-validation",
                                "transaction root binding failed",
                                "post-auth-binder-prefork", 72)
        if (info["type"] != "directory" or info["uid"] != os.getuid() or
                info["mode"] != 0o700):
            raise BinderFailure("transaction-root-validation",
                                "transaction-root-validation",
                                "transaction root binding failed",
                                "post-auth-binder-prefork", 72)
        return child, [child]
    parent = anchor
    opened = []
    for index, component in enumerate(components[:-1]):
        child, info = open_dir(parent, component,
                               "transaction-parent-ancestor-%d" % index,
                               require_mode=0o700)
        if info["uid"] != os.getuid():
            raise BinderFailure("transaction-root-validation",
                                "transaction-root-validation",
                                "transaction root binding failed",
                                "post-auth-binder-prefork", 72)
        opened.append(child)
        parent = child

    leaf = components[-1]
    created = False
    try:
        before = os.stat(leaf, dir_fd=parent, follow_symlinks=False)
    except FileNotFoundError:
        try:
            os.mkdir(leaf, 0o700, dir_fd=parent)
            os.fsync(parent)
            created = True
            before = os.stat(leaf, dir_fd=parent, follow_symlinks=False)
        except OSError:
            raise BinderFailure("transaction-root-validation",
                                "transaction-root-validation",
                                "transaction root binding failed",
                                "post-auth-binder-prefork", 72)
    except OSError:
        raise BinderFailure("transaction-root-validation",
                            "transaction-root-validation",
                            "transaction root binding failed",
                            "post-auth-binder-prefork", 72)

    before_identity = (before.st_dev, before.st_ino,
                       stat.S_IFMT(before.st_mode), before.st_uid,
                       stat.S_IMODE(before.st_mode), before.st_nlink)
    if not stat.S_ISDIR(before.st_mode) or before.st_uid != os.getuid() \
            or stat.S_IMODE(before.st_mode) != 0o700:
        raise BinderFailure("transaction-root-validation",
                            "transaction-root-validation",
                            "transaction root binding failed",
                            "post-auth-binder-prefork", 72)
    try:
        child, info = open_dir(parent, leaf, "transaction-parent",
                               require_mode=0o700)
    except BinderFailure:
        if created:
            try:
                os.rmdir(leaf, dir_fd=parent)
                os.fsync(parent)
            except OSError:
                raise BinderFailure("transaction-root-validation",
                                    "transaction-root-validation",
                                    "transaction root binding failed",
                                    "post-auth-binder-prefork", 72)
        raise
    after_identity = (info["dev"], info["ino"],
                      stat.S_IFMT(os.fstat(child).st_mode), info["uid"],
                      info["mode"], info["nlink"])
    if after_identity != before_identity:
        raise BinderFailure("transaction-root-validation",
                            "transaction-root-validation",
                            "transaction root binding failed",
                            "post-auth-binder-prefork", 72)
    opened.append(child)
    return child, opened


def create_fresh_child(parent_fd, prefix, role):
    for attempt in range(16):
        leaf = "%s-%s-%02d" % (prefix, secrets.token_hex(12), attempt)
        try:
            os.mkdir(leaf, 0o700, dir_fd=parent_fd)
        except FileExistsError:
            continue
        except OSError:
            raise BinderFailure("transaction-root-validation",
                                "transaction-root-validation",
                                "transaction root binding failed",
                                "post-auth-binder-prefork", 72)
        try:
            os.fsync(parent_fd)
            child, info = open_dir(parent_fd, leaf, role, require_mode=0o700)
        except (OSError, BinderFailure):
            try:
                os.rmdir(leaf, dir_fd=parent_fd)
            except OSError:
                raise BinderFailure("transaction-root-validation",
                                    "transaction-root-validation",
                                    "transaction root binding failed",
                                    "post-auth-binder-prefork", 72)
            raise
        return leaf, child, info
    raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                        "transaction root binding failed", "post-auth-binder-prefork", 72)


def open_report_leaf(parent_fd, leaf):
    flags = os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    try:
        raw = os.open(leaf, flags, 0o600, dir_fd=parent_fd)
    except OSError:
        raise BinderFailure("report-path-validation", "report-path-validation",
                            "report path validation failed", "report-path-binding", 74)
    owned = rehome(raw, "report-leaf-ephemeral")
    info = receipt(owned, "reportLeaf")
    if info["type"] != "regular" or info["mode"] != 0o600 or info["nlink"] != 1:
        raise BinderFailure("report-path-validation", "report-path-validation",
                            "report path validation failed", "report-path-binding", 74)
    try:
        os.fsync(owned)
        os.fsync(parent_fd)
    except OSError:
        raise BinderFailure("report-path-validation", "report-path-validation",
                            "report path validation failed", "report-path-binding", 74)
    return owned, info


def validate_receipts(context, required_fds):
    values = context["descriptorReceipts"]
    if not isinstance(values, list) or len(values) != len(required_fds):
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    by_fd = {}
    for item in values:
        if not isinstance(item, dict) or set(item) != RECEIPT_KEYS:
            raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                "transaction root binding failed", "post-auth-binder-prefork", 72)
        fd = item.get("fd")
        if fd in by_fd:
            raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                "transaction root binding failed", "post-auth-binder-prefork", 72)
        by_fd[fd] = item
    if set(by_fd) != set(required_fds):
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    for fd in required_fds:
        current = receipt(fd, role_for_fd(fd))
        if current != by_fd[fd]:
            raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                "transaction root binding failed", "post-auth-binder-prefork", 72)


def pread_digest(fd):
    position = os.lseek(fd, 0, os.SEEK_CUR)
    digest = hashlib.sha256()
    offset = 0
    while True:
        chunk = os.pread(fd, 131072, offset)
        if not chunk:
            break
        digest.update(chunk)
        offset += len(chunk)
    if os.lseek(fd, 0, os.SEEK_CUR) != position:
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    return digest.hexdigest()


def validate_request(raw):
    try:
        raw.encode("ascii")
        request = json.loads(raw)
    except (UnicodeEncodeError, json.JSONDecodeError, TypeError):
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    if not isinstance(request, dict) or set(request) != REQUEST_KEYS \
            or canonical(request) != raw or request.get("schema") != REQUEST_SCHEMA:
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    for key in ("authSha256", "dispatchContextSha256", "entrySha256"):
        if not is_digest(request[key]):
            raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                "transaction root binding failed", "post-auth-binder-prefork", 72)
    if request["fdRoles"] != ROLE_FDS or not isinstance(request["testMode"], bool):
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    transaction_components = request["transactionParentComponents"]
    if not safe_components(transaction_components,
                           nonempty=not request["testMode"]):
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    if not request["testMode"] and not transaction_components:
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    if request["evidenceRootComponents"] != [".codex", "supervisor-runtime-evidence"]:
        raise BinderFailure("evidence-validation", "evidence-validation",
                            "evidence report write failed", "evidence-root-binding", 75)
    report_parent = request["reportParentComponents"]
    report_leaf = request["reportLeafComponents"]
    if (report_parent is None) != (report_leaf is None):
        raise BinderFailure("report-path-validation", "report-path-validation",
                            "report path validation failed", "report-path-binding", 74)
    if report_parent is not None:
        if not safe_components(report_parent, nonempty=False) or not isinstance(report_leaf, list) \
                or len(report_leaf) != 1 or not safe_component(report_leaf[0]):
            raise BinderFailure("report-path-validation", "report-path-validation",
                                "report path validation failed", "report-path-binding", 74)
    original_argv = request["originalArgv"]
    if not isinstance(original_argv, list) or not all(
            isinstance(item, str) and "\x00" not in item for item in original_argv):
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    context_raw = request["dispatchContext"]
    if not isinstance(context_raw, str):
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    try:
        context_raw.encode("ascii")
        context = json.loads(context_raw)
    except (UnicodeEncodeError, json.JSONDecodeError, TypeError):
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    if canonical(context) != context_raw or digest_text(context_raw) != request["dispatchContextSha256"]:
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    if not isinstance(context, dict) or set(context) != CONTEXT_KEYS \
            or context.get("schema") != CONTEXT_SCHEMA or context.get("mode") != "apply" \
            or context.get("fdRoles") != ROLE_FDS \
            or context.get("testMode") is not request["testMode"] \
            or context.get("entrySha256") != request["entrySha256"]:
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    components = context.get("components")
    if not isinstance(components, dict) or set(components) != COMPONENT_KEYS:
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    for key in ("transactionParent", "evidenceRoot", "reportParent", "reportLeaf"):
        if components.get(key) != request[key + "Components"]:
            raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                "transaction root binding failed", "post-auth-binder-prefork", 72)
    calculated_argv = digest_bytes(b"\x00".join(
        item.encode("utf-8") for item in original_argv))
    if context.get("argvSha256") != calculated_argv or pread_digest(11) != request["entrySha256"]:
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    required = [10, 11, 15, 16, 17, 18]
    if request["testMode"]:
        required.insert(0, 9)
    validate_receipts(context, required)
    entry_exec = receipt(10, "entryExecution")
    entry_hash = receipt(11, "entryHash")
    if (entry_exec["dev"], entry_exec["ino"]) != (entry_hash["dev"], entry_hash["ino"]):
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-binder-prefork", 72)
    for fd, expected in ((10, "regular"), (11, "regular"), (15, "socket"),
                         (16, "directory"), (17, "directory"), (18, "directory")):
        if receipt(fd, role_for_fd(fd))["type"] != expected:
            raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                "transaction root binding failed", "post-auth-binder-prefork", 72)
    return request, context


def send_json(channel, value):
    data = (canonical(value) + "\n").encode("ascii")
    if len(data) > MAX_FRAME:
        raise BinderFailure("transaction-origin-validation",
                            "transaction-origin-validation",
                            "transaction launcher origin proof failed",
                            "post-auth-origin-proof", 67)
    channel.sendall(data)


def receive_json(channel, schema_value, exact_keys):
    channel.settimeout(TIMEOUT_SECONDS)
    data = bytearray()
    while True:
        part = channel.recv(4096)
        if not part:
            raise BinderFailure("transaction-origin-validation",
                                "transaction-origin-validation",
                                "transaction launcher origin proof failed",
                                "post-auth-origin-proof", 67)
        data.extend(part)
        if len(data) > MAX_FRAME:
            raise BinderFailure("transaction-origin-validation",
                                "transaction-origin-validation",
                                "transaction launcher origin proof failed",
                                "post-auth-origin-proof", 67)
        if data.endswith(b"\n"):
            break
    if data.count(b"\n") != 1:
        raise BinderFailure("transaction-origin-validation",
                            "transaction-origin-validation",
                            "transaction launcher origin proof failed",
                            "post-auth-origin-proof", 67)
    try:
        raw = bytes(data[:-1]).decode("ascii")
        value = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise BinderFailure("transaction-origin-validation",
                            "transaction-origin-validation",
                            "transaction launcher origin proof failed",
                            "post-auth-origin-proof", 67)
    if not isinstance(value, dict) or set(value) != set(exact_keys) \
            or value.get("schema") != schema_value or canonical(value) != raw:
        raise BinderFailure("transaction-origin-validation",
                            "transaction-origin-validation",
                            "transaction launcher origin proof failed",
                            "post-auth-origin-proof", 67)
    return value


def terminate_and_wait(child_pid):
    try:
        os.kill(child_pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    except OSError:
        raise BinderFailure("transaction-origin-validation",
                            "transaction-origin-validation",
                            "transaction launcher origin proof failed",
                            "post-auth-origin-proof", 67)
    try:
        os.waitpid(child_pid, 0)
    except ChildProcessError:
        return
    except OSError:
        raise BinderFailure("transaction-origin-validation",
                            "transaction-origin-validation",
                            "transaction launcher origin proof failed",
                            "post-auth-origin-proof", 67)


def child_environment(request, child_pid, parent_pid, nonce_sha,
                      work_leaf, backup_leaf, work_receipt, backup_receipt,
                      report_receipt):
    environment = {key: value for key, value in os.environ.items()
                   if key not in PHASE_ENV_NAMES}
    environment.update({
        "AGENCY269_POST_AUTH_AUTH_SHA256": request["authSha256"],
        "AGENCY269_POST_AUTH_CHILD_PID": str(child_pid),
        "AGENCY269_POST_AUTH_CONTEXT": request["dispatchContext"],
        "AGENCY269_POST_AUTH_CONTEXT_SHA256": request["dispatchContextSha256"],
        "AGENCY269_POST_AUTH_NONCE_SHA256": nonce_sha,
        "AGENCY269_POST_AUTH_ORIGIN_FD": "15",
        "AGENCY269_POST_AUTH_PARENT_PID": str(parent_pid),
        "AGENCY269_REEXEC": "1",
        "AGENCY_TXN_BACKUP_DEV": str(backup_receipt["dev"]),
        "AGENCY_TXN_BACKUP_INO": str(backup_receipt["ino"]),
        "AGENCY_TXN_BACKUP_LEAF": backup_leaf,
        "AGENCY_TXN_BACKUP_ROOT": "/agency269-descriptor/fd13/" + backup_leaf,
        "AGENCY_TXN_ROOT_BOUND": "v1",
        "AGENCY_TXN_WORK_DEV": str(work_receipt["dev"]),
        "AGENCY_TXN_WORK_INO": str(work_receipt["ino"]),
        "AGENCY_TXN_WORK_LEAF": work_leaf,
        "AGENCY_TXN_WORK_ROOT": "/agency269-descriptor/fd12/" + work_leaf,
        "POST_AUTH_DESCRIPTOR_BOUND": "v1",
    })
    if report_receipt is not None:
        environment.update({
            "AGENCY_REPORT_FD": "14",
            "AGENCY_REPORT_FD_BOUND": "v1",
            "AGENCY_REPORT_FD_DEV": str(report_receipt["dev"]),
            "AGENCY_REPORT_FD_INO": str(report_receipt["ino"]),
            "AGENCY_REPORT_FD_MODE": "600",
            "AGENCY_REPORT_FD_NLINK": "1",
            "AGENCY_REPORT_FD_TYPE": "regular",
            "AGENCY_REPORT_FD_UID": str(report_receipt["uid"]),
        })
    return environment


def cleanup_created(transaction_fd, work_leaf, backup_leaf,
                    report_parent_fd, report_leaf):
    if report_leaf is not None and report_parent_fd is not None:
        try:
            os.unlink(report_leaf, dir_fd=report_parent_fd)
            os.fsync(report_parent_fd)
        except OSError:
            pass_failure = BinderFailure("report-path-validation",
                                         "report-path-validation",
                                         "report path validation failed",
                                         "report-path-binding", 74)
            return pass_failure
    for leaf in (backup_leaf, work_leaf):
        if leaf is not None and transaction_fd is not None:
            try:
                os.rmdir(leaf, dir_fd=transaction_fd)
                os.fsync(transaction_fd)
            except OSError:
                return BinderFailure("transaction-root-validation",
                                     "transaction-root-validation",
                                     "transaction root binding failed",
                                     "post-auth-binder-prefork", 72)
    return None


def cleanup_transaction_roots(transaction_fd, work_leaf, backup_leaf):
    if transaction_fd is None or work_leaf is None or backup_leaf is None:
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-transaction-cleanup", 72)
    try:
        work_path_info = os.stat(work_leaf, dir_fd=transaction_fd,
                                 follow_symlinks=False)
        work_bound_info = os.fstat(12)
        backup_path_info = os.stat(backup_leaf, dir_fd=transaction_fd,
                                   follow_symlinks=False)
        backup_bound_info = os.fstat(13)
    except OSError:
        raise BinderFailure("transaction-root-validation",
                            "transaction-root-validation",
                            "transaction root binding failed",
                            "post-auth-transaction-cleanup", 72)
    identity = lambda info: (
        info.st_dev, info.st_ino, stat.S_IFMT(info.st_mode), info.st_uid,
        stat.S_IMODE(info.st_mode), info.st_nlink,
    )
    work_path_is_bound = identity(work_path_info) == identity(work_bound_info)
    if identity(backup_path_info) != identity(backup_bound_info):
        raise BinderFailure("transaction-root-validation",
                            "transaction-root-validation",
                            "transaction root binding failed",
                            "post-auth-transaction-cleanup", 72)
    entry_count = [0]
    def clear_directory(directory_fd, depth):
        if depth > 64:
            raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                "transaction root binding failed", "post-auth-transaction-cleanup", 72)
        try:
            names = sorted(os.listdir(directory_fd))
        except OSError:
            raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                "transaction root binding failed", "post-auth-transaction-cleanup", 72)
        for name in names:
            if not safe_component(name):
                raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                    "transaction root binding failed", "post-auth-transaction-cleanup", 72)
            entry_count[0] += 1
            if entry_count[0] > 100000:
                raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                    "transaction root binding failed", "post-auth-transaction-cleanup", 72)
            try:
                info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            except OSError:
                raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                    "transaction root binding failed", "post-auth-transaction-cleanup", 72)
            mode = stat.S_IMODE(info.st_mode)
            if info.st_uid != os.geteuid() or mode & 0o077:
                raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                    "transaction root binding failed", "post-auth-transaction-cleanup", 72)
            if stat.S_ISREG(info.st_mode) and info.st_nlink == 1:
                try:
                    os.unlink(name, dir_fd=directory_fd)
                except OSError:
                    raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                        "transaction root binding failed", "post-auth-transaction-cleanup", 72)
            elif stat.S_ISDIR(info.st_mode):
                try:
                    raw = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                                  dir_fd=directory_fd)
                    child = rehome(raw, "transaction-cleanup-directory")
                    child_info = os.fstat(child)
                    if (child_info.st_dev, child_info.st_ino) != (info.st_dev, info.st_ino):
                        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                            "transaction root binding failed", "post-auth-transaction-cleanup", 72)
                    clear_directory(child, depth + 1)
                    if not STATE.close(child, "transaction-cleanup-directory"):
                        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                            "transaction root binding failed", "post-auth-transaction-cleanup", 72)
                    os.rmdir(name, dir_fd=directory_fd)
                except BinderFailure:
                    raise
                except OSError:
                    raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                        "transaction root binding failed", "post-auth-transaction-cleanup", 72)
            else:
                raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                    "transaction root binding failed", "post-auth-transaction-cleanup", 72)
        try:
            os.fsync(directory_fd)
        except OSError:
            raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                                "transaction root binding failed", "post-auth-transaction-cleanup", 72)
    if work_path_is_bound:
        clear_directory(12, 0)
    clear_directory(13, 0)
    try:
        os.rmdir(backup_leaf, dir_fd=transaction_fd)
        if work_path_is_bound:
            os.rmdir(work_leaf, dir_fd=transaction_fd)
        os.fsync(transaction_fd)
    except OSError:
        raise BinderFailure("transaction-root-validation", "transaction-root-validation",
                            "transaction root binding failed", "post-auth-transaction-cleanup", 72)


def aggregate_rc(primary_rc, close_failures):
    if close_failures:
        return 78 if primary_rc else 79
    return primary_rc


def test_binder_stage(stage):
    allowed = {"binder-enter", "request-ok", "transaction-parent-ok", "work-ok", "backup-ok", "evidence-ok", "report-parent-ok", "report-leaf-ok", "initial-origin-absent", "initial-origin-present", "initial-origin-stat-failed", "initial-origin-close-failed", "initial-origin-ready", "socketpair-open", "parent-rehome", "child-rehome", "fd-bind", "socket-ok", "fork-ok", "child-fork-enter", "child-old-origin-closed", "child-fd-bound", "parent-child-endpoint-closed", "parent-old-origin-close-failed", "parent-old-origin-closed", "child-exec-enter"}
    allowed |= {"proof-recv", "proof-ok", "ack-ok", "transaction-cleanup-enter", "transaction-cleanup-ok", "transaction-cleanup-fail", "parent-channel-closed", "parent-descriptors-closed", "wait-enter", "wait-return"}
    close_stage_roles = {10:"entry-execution",11:"entry-hash",12:"work",13:"backup-workspace",14:"report-leaf",16:"source",17:"project",18:"home-authority",19:"transaction-parent",20:"evidence-root",21:"report-parent"}
    allowed |= {"parent-close-%s-%s" % (role, phase) for role in close_stage_roles.values() for phase in ("before", "after")}
    allowed |= {"proof-mismatch-" + name for name in ("authSha256", "bindingSha256", "childPid", "descriptorReceipts", "dispatchContextSha256", "entrySha256", "nonce", "parentPid", "phase", "schema")}
    if os.environ.get("AGENCY_TEST_BINDER_STAGE") != "ledger-replay-v1" or stage not in allowed:
        return
    try:
        info = os.fstat(9)
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
            return
        data = ("POST_AUTH_STAGE_DIAG=%s\n" % stage).encode("ascii")
        os.write(2, data)
    except OSError:
        return


def test_report_race_admitted(request, context, stage):
    if not request.get("testMode") or os.environ.get("AGENCY_TEST_REPORT_RACE_STAGE") != stage:
        return False
    try:
        current = receipt(9, "testRoot")
        frozen = next(item for item in context["descriptorReceipts"] if item.get("fd") == 9)
    except (OSError, StopIteration, KeyError, TypeError):
        return False
    keys = ("dev", "ino", "type", "uid", "mode")
    if current["type"] != "directory" or current["uid"] != os.getuid() or current["mode"] != 0o700:
        return False
    if tuple(current[key] for key in keys) != tuple(frozen.get(key) for key in keys):
        return False
    if not isinstance(frozen.get("nlink"), int) or frozen["nlink"] < 2 or current["nlink"] < frozen["nlink"]:
        return False
    return True


def report_identity(value):
    return tuple(value[key] for key in ("dev", "ino", "type", "uid", "mode", "nlink"))


def inject_report_parent_race(request, context):
    if not test_report_race_admitted(request, context, "after-report-parent-stat"):
        return
    components = request.get("reportParentComponents")
    if not isinstance(components, list) or len(components) != 1 or not safe_component(components[0]):
        raise BinderFailure("report-path-validation", "report-path-validation",
                            "report path validation failed", "report-parent-race", 74)
    leaf = components[0]
    moved = leaf + ".old"
    try:
        os.rename(leaf, moved, src_dir_fd=20, dst_dir_fd=20)
        os.rename(".report-race-replacement", leaf, src_dir_fd=20, dst_dir_fd=20)
        os.fsync(20)
        os.write(2, b"REPORT_PARENT_RACE_HIT=after-report-parent-stat\n")
    except OSError:
        raise BinderFailure("report-path-validation", "report-path-validation",
                            "report path validation failed", "report-parent-race", 74)


def inject_report_leaf_race(request, context, leaf):
    if not test_report_race_admitted(request, context, "after-report-leaf-prebind"):
        return False
    moved = leaf + ".old"
    try:
        os.rename(leaf, moved, src_dir_fd=21, dst_dir_fd=21)
        os.rename(".report-race-leaf-replacement", leaf, src_dir_fd=21, dst_dir_fd=21)
        os.fsync(21)
        os.write(2, b"REPORT_LEAF_RACE_HIT=after-report-leaf-prebind\n")
    except OSError:
        raise BinderFailure("report-path-validation", "report-path-validation",
                            "report path validation failed", "report-leaf-race", 74)
    return True


def run(raw_request):
    request = {}
    context = None
    child_pid = None
    adopted = False
    work_leaf = None
    backup_leaf = None
    report_leaf = None
    report_leaf_created = False
    preserve_report_race_leaf = False
    transaction_fd = None
    report_parent_fd = None
    parent_channel = None
    binding_sha = "0" * 64
    receipts = []
    failure = None
    try:
        test_binder_stage("binder-enter")
        request, context = validate_request(raw_request)
        test_binder_stage("request-ok")
        anchor = 9 if request["testMode"] else 18
        transaction_ephemeral, transaction_opened = open_transaction_parent(
            anchor, request["transactionParentComponents"])
        transaction_fd = bind_fixed(transaction_ephemeral, 19, "transactionParent")
        test_binder_stage("transaction-parent-ok")
        for opened in transaction_opened[:-1]:
            if STATE.find_open(opened) is not None and not STATE.close(opened):
                raise BinderFailure("transaction-root-validation",
                                    "transaction-root-validation",
                                    "transaction root binding failed",
                                    "post-auth-binder-prefork", 72)
        work_leaf, work_ephemeral, work_info = create_fresh_child(
            transaction_fd, ".agency-work", "work")
        bind_fixed(work_ephemeral, 12, "work")
        test_binder_stage("work-ok")
        backup_leaf, backup_ephemeral, backup_info = create_fresh_child(
            transaction_fd, ".agency-backup-workspace", "backupWorkspace")
        bind_fixed(backup_ephemeral, 13, "backupWorkspace")
        test_binder_stage("backup-ok")
        if (work_info["dev"], work_info["ino"]) == (backup_info["dev"], backup_info["ino"]):
            raise BinderFailure("transaction-root-validation",
                                "transaction-root-validation",
                                "transaction root binding failed",
                                "post-auth-binder-prefork", 72)
        evidence_ephemeral, evidence_opened, _ = traverse(
            18, request["evidenceRootComponents"], "evidence-root",
            require_all_mode=0o700)
        bind_fixed(evidence_ephemeral, 20, "evidenceRoot")
        test_binder_stage("evidence-ok")
        for opened in evidence_opened[:-1]:
            if STATE.find_open(opened) is not None and not STATE.close(opened):
                raise BinderFailure("evidence-validation", "evidence-validation",
                                    "evidence report write failed",
                                    "evidence-root-binding", 75)
        report_info = None
        report_parent_before = None
        report_parent_after = None
        if request["reportParentComponents"] is not None:
            if request["reportParentComponents"]:
                report_parent_ephemeral, report_opened, _ = traverse(
                    20, request["reportParentComponents"], "report-parent",
                    require_all_mode=0o700)
            else:
                try:
                    report_parent_ephemeral = fcntl.fcntl(
                        20, fcntl.F_DUPFD_CLOEXEC, 23)
                except OSError:
                    raise BinderFailure("evidence-validation", "evidence-validation",
                                        "evidence root validation failed",
                                        "evidence-root-binding", 77)
                STATE.register(report_parent_ephemeral, "report-parent-root")
                report_opened = [report_parent_ephemeral]
            report_parent_fd = bind_fixed(report_parent_ephemeral, 21, "reportParent")
            test_binder_stage("report-parent-ok")
            for opened in report_opened[:-1]:
                if STATE.find_open(opened) is not None and not STATE.close(opened):
                    raise BinderFailure("report-path-validation",
                                        "report-path-validation",
                                        "report path validation failed",
                                        "report-path-binding", 74)
            report_parent_before = receipt(21, "reportParent")
            inject_report_parent_race(request, context)
            if test_report_race_admitted(request, context, "after-report-parent-stat"):
                expected_parent, expected_opened, _ = traverse(
                    20, request["reportParentComponents"], "report-parent-revalidation",
                    require_all_mode=0o700)
                expected_info = receipt(expected_parent, "reportParent")
                close_failed = False
                for opened in reversed(expected_opened):
                    if STATE.find_open(opened) is not None and not STATE.close(opened, "report-parent-revalidation"):
                        close_failed = True
                if close_failed or report_identity(expected_info) != report_identity(report_parent_before):
                    raise BinderFailure("report-path-validation", "report-path-validation",
                                        "report path validation failed", "report-parent-race", 74)
            report_leaf = request["reportLeafComponents"][0]
            report_ephemeral, report_info = open_report_leaf(21, report_leaf)
            report_leaf_created = True
            bind_fixed(report_ephemeral, 14, "reportLeaf")
            report_info = receipt(14, "reportLeaf")
            test_binder_stage("report-leaf-ok")
            preserve_report_race_leaf = inject_report_leaf_race(request, context, report_leaf)
            if preserve_report_race_leaf:
                try:
                    raw_expected = os.open(report_leaf, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=21)
                    expected_leaf = rehome(raw_expected, "report-leaf-revalidation")
                    expected_info = receipt(expected_leaf, "reportLeaf")
                except OSError:
                    raise BinderFailure("report-path-validation", "report-path-validation",
                                        "report path validation failed", "report-leaf-race", 74)
                close_failed = not STATE.close(expected_leaf, "report-leaf-revalidation")
                if close_failed or report_identity(expected_info) != report_identity(report_info):
                    raise BinderFailure("report-path-validation", "report-path-validation",
                                        "report path validation failed", "report-leaf-race", 74)
            report_parent_after = receipt(21, "reportParent")
            report_parent_identity_keys = ("dev", "ino", "type", "uid", "mode")
            if tuple(report_parent_before[key] for key in report_parent_identity_keys) != tuple(report_parent_after[key] for key in report_parent_identity_keys):
                raise BinderFailure("report-path-validation",
                                    "report-path-validation",
                                    "report path validation failed",
                                    "report-path-binding", 74)
        child_fds = [10, 11, 12, 13, 15, 16, 17, 18, 19, 20]
        if request["reportParentComponents"] is not None:
            child_fds.extend([14, 21])
        receipts = [receipt(fd, role_for_fd(fd)) for fd in sorted(child_fds) if fd != 15]
        raw_parent, raw_child = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
        test_binder_stage("socketpair-open")
        parent_fd = rehome(raw_parent.detach(), "post-auth-parent-socket")
        test_binder_stage("parent-rehome")
        child_fd = rehome(raw_child.detach(), "post-auth-child-socket")
        test_binder_stage("child-rehome")
        parent_channel = socket.socket(fileno=parent_fd)
        child_channel = socket.socket(fileno=child_fd)
        test_binder_stage("socket-ok")
        child_receipt = receipt(child_fd, "origin")
        child_receipt["fd"] = 15
        child_receipt["role"] = "origin"
        receipts.append(child_receipt)
        receipts.sort(key=lambda item: item["fd"])
        nonce = secrets.token_hex(32)
        nonce_sha = digest_text(nonce)
        parent_pid = os.getpid()
        child_pid = os.fork()
        if child_pid == 0:
            try:
                test_binder_stage("child-fork-enter")
                parent_channel.close()
                if STATE.find_open(parent_fd) is not None:
                    STATE.find_open(parent_fd)["state"] = "closed"
                try:
                    os.close(15)
                except OSError as exc:
                    if exc.errno != errno.EBADF:
                        os._exit(67)
                test_binder_stage("child-old-origin-closed")
                os.dup2(child_channel.fileno(), 15, inheritable=True)
                child_channel.close()
                test_binder_stage("child-fd-bound")
                test_binder_stage("child-exec-enter")
                for fd in child_fds:
                    os.set_inheritable(fd, True)
                environment = child_environment(
                    request, os.getpid(), parent_pid, nonce_sha,
                    work_leaf, backup_leaf, work_info, backup_info, report_info)
                argv = ["/bin/bash", "/dev/fd/10"] + request["originalArgv"]
                os.execve("/bin/bash", argv, environment)
            except BaseException:
                os._exit(67)
        test_binder_stage("fork-ok")
        child_detached = child_channel.detach()
        if not STATE.close(child_detached, "post-auth-child-socket"):
            raise BinderFailure("transaction-origin-validation",
                                "transaction-origin-validation",
                                "transaction launcher origin proof failed",
                                "post-auth-origin-proof", 67)
        test_binder_stage("parent-child-endpoint-closed")
        challenge = {
            "authSha256": request["authSha256"],
            "childPid": child_pid,
            "descriptorReceipts": receipts,
            "dispatchContextSha256": request["dispatchContextSha256"],
            "entrySha256": request["entrySha256"],
            "nonce": nonce,
            "parentPid": parent_pid,
            "phase": "post-auth",
            "schema": "agency-agents.post-auth-origin-challenge/v1",
            "singleUse": True,
        }
        binding_sha = digest_text(canonical(challenge))
        send_json(parent_channel, challenge)
        proof = receive_json(parent_channel, "agency-agents.post-auth-origin-proof/v1", {
            "authSha256", "bindingSha256", "childPid", "descriptorReceipts",
            "dispatchContextSha256", "entrySha256", "nonce", "parentPid",
            "phase", "schema",
        })
        test_binder_stage("proof-recv")
        expected_proof = dict(challenge)
        expected_proof.pop("singleUse")
        expected_proof["schema"] = "agency-agents.post-auth-origin-proof/v1"
        expected_proof["bindingSha256"] = binding_sha
        if proof != expected_proof:
            for name in sorted(expected_proof):
                if proof.get(name) != expected_proof.get(name):
                    test_binder_stage("proof-mismatch-" + name)
                    break
            raise BinderFailure("transaction-origin-validation",
                                "transaction-origin-validation",
                                "transaction launcher origin proof failed",
                                "post-auth-origin-proof", 67)
        test_binder_stage("proof-ok")
        consume = {
            "bindingSha256": binding_sha,
            "childPid": child_pid,
            "nonceSha256": nonce_sha,
            "parentPid": parent_pid,
            "phase": "post-auth",
            "schema": "agency-agents.post-auth-origin-consume/v1",
        }
        send_json(parent_channel, consume)
        ack = receive_json(parent_channel, "agency-agents.post-auth-origin-ack/v1", {
            "bindingSha256", "childPid", "consumed", "parentPid", "phase", "schema",
        })
        expected_ack = {
            "bindingSha256": binding_sha,
            "childPid": child_pid,
            "consumed": True,
            "parentPid": parent_pid,
            "phase": "post-auth",
            "schema": "agency-agents.post-auth-origin-ack/v1",
        }
        if ack != expected_ack:
            raise BinderFailure("transaction-origin-validation",
                                "transaction-origin-validation",
                                "transaction launcher origin proof failed",
                                "post-auth-origin-proof", 67)
        test_binder_stage("ack-ok")
        adopted = True
        origin_result(request, "child-finalized", "passed", "child", child_pid,
                      0, receipts, binding_sha, None)
        test_binder_stage("wait-enter")
        waited_pid, wait_status = os.waitpid(child_pid, 0)
        test_binder_stage("wait-return")
        if waited_pid != child_pid:
            os._exit(67)
        if os.WIFEXITED(wait_status):
            child_rc = os.WEXITSTATUS(wait_status)
        elif os.WIFSIGNALED(wait_status):
            child_rc = 128 + os.WTERMSIG(wait_status)
        else:
            child_rc = 67
        if child_rc in (67, 72):
            child_rc = 67
        test_binder_stage("transaction-cleanup-enter")
        try:
            cleanup_transaction_roots(transaction_fd, work_leaf, backup_leaf)
            test_binder_stage("transaction-cleanup-ok")
        except BinderFailure:
            test_binder_stage("transaction-cleanup-fail")
            child_rc = 78 if child_rc else 72
        parent_detached = parent_channel.detach()
        if not STATE.close(parent_detached, "post-auth-parent-socket"):
            child_rc = 78 if child_rc else 79
        test_binder_stage("parent-channel-closed")
        close_stage_roles = {10:"entry-execution",11:"entry-hash",12:"work",13:"backup-workspace",14:"report-leaf",16:"source",17:"project",18:"home-authority",19:"transaction-parent",20:"evidence-root",21:"report-parent"}
        for fd in sorted(set(child_fds) - {15}, reverse=True):
            test_binder_stage("parent-close-%s-before" % close_stage_roles[fd])
            STATE.close(fd, role_for_fd(fd))
            test_binder_stage("parent-close-%s-after" % close_stage_roles[fd])
        test_binder_stage("parent-descriptors-closed")
        if STATE.secondary:
            child_rc = 78 if child_rc else 79
        if os.environ.get("AGENCY_TEST_BINDER_STAGE") == "ledger-replay-v1":
            os.write(2, ("M2_PARENT_EXIT=%d\n" % child_rc).encode("ascii"))
        os._exit(child_rc)
    except BinderFailure as exc:
        failure = exc
    except (OSError, ValueError, TypeError, KeyError, OverflowError) as exc:
        if os.environ.get("AGENCY_TEST_BINDER_STAGE") == "ledger-replay-v1":
            name = type(exc).__name__
            if name not in {"OSError", "ValueError", "TypeError", "KeyError", "OverflowError"}:
                name = "unexpected"
            os.write(2, ("M2_PARENT_EXCEPTION=%s\n" % name).encode("ascii"))
        failure = BinderFailure("transaction-root-validation",
                                "transaction-root-validation",
                                "transaction root binding failed",
                                "post-auth-binder-prefork", 72)
    if child_pid is not None and child_pid > 0 and not adopted:
        try:
            terminate_and_wait(child_pid)
        except BinderFailure as protocol_failure:
            if failure is None:
                failure = protocol_failure
    if parent_channel is not None:
        try:
            parent_fd = parent_channel.detach()
            if STATE.find_open(parent_fd) is not None:
                STATE.close(parent_fd)
            else:
                os.close(parent_fd)
        except OSError as exc:
            STATE.secondary.append({
                "code": "E_DESCRIPTOR_CLOSE", "ownerModule": "M2",
                "role": "post-auth-parent-socket", "errno": int(exc.errno or errno.EIO),
            })
    for fd in (14, 13, 12):
        if STATE.find_open(fd) is not None:
            STATE.close(fd, role_for_fd(fd))
    cleanup_failure = cleanup_created(transaction_fd, work_leaf, backup_leaf,
                                      report_parent_fd,
                                      report_leaf if report_leaf_created and not preserve_report_race_leaf else None)
    if failure is None and cleanup_failure is not None:
        failure = cleanup_failure
    STATE.close_reverse()
    if failure is None:
        failure = BinderFailure("transaction-root-validation",
                                "transaction-root-validation",
                                "transaction root binding failed",
                                "post-auth-binder-prefork", 72)
    phase = "child-protocol-failure" if child_pid is not None else "pre-fork-failure"
    origin_result(request, phase, "failed", "parent", child_pid,
                  failure.rc, receipts, binding_sha, primary_object(failure))
    public_rc = aggregate_rc(failure.rc, STATE.secondary)
    emit_parent_failure(failure, public_rc)
    os._exit(public_rc)


def main():
    raw_request = sys.argv[1] if len(sys.argv) == 2 else ""
    run(raw_request)
    os._exit(72)


main()
PY
  )"
  binder_rc=$?
  set -e
  if [[ -n "$binder_output" ]]; then
    agency269_m2_emit_payload "$binder_output" || writer_rc=$?
    (( writer_rc == 0 )) || return 75
    case "$binder_rc" in
      0|80) return 80 ;;
      *) return 77 ;;
    esac
  fi
  return "$binder_rc"
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
import re
import stat
import sys

manifest_path, profiles_path = sys.argv[1:3]
expected_tools = ["aider", "antigravity", "claude-code", "github-copilot", "codex", "cursor", "gemini-cli", "kimi", "openclaw", "opencode", "osaurus", "qwen", "hermes", "vibe", "windsurf", "zcode"]
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

def component_list(value):
    if value.startswith('/'):
        block('absolute-validation-component')
    parts = value.split('/')
    if any(not part or part in ('.', '..') or '/' in part or '\x00' in part for part in parts):
        block('unsafe-relative-components')
    return parts

def read_relative(root_fd, value):
    parts = component_list(value)
    current = root_fd
    parents = []
    leaf = None
    try:
        for part in parts[:-1]:
            current = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=current)
            parents.append(current)
        leaf = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW, dir_fd=current)
        before = os.fstat(leaf)
        if not stat.S_ISREG(before.st_mode):
            block('non-regular-validation-input')
        content = bytearray()
        while True:
            chunk = os.read(leaf, 1024 * 1024)
            if not chunk:
                break
            content.extend(chunk)
        after = os.fstat(leaf)
        if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
            block('validation-input-race')
        return bytes(content)
    except OSError:
        block('descriptor-relative-validation-input-open')
    finally:
        failures = []
        for descriptor in ([leaf] if leaf is not None else []) + list(reversed(parents)):
            try:
                os.close(descriptor)
            except OSError as exc:
                failures.append({'fd': descriptor, 'errno': exc.errno})
        if failures:
            print('M3_FAILURE stage=manifest-validation operation=manifest-check reason=E_DESCRIPTOR_CLOSE rc=79 close_failures=%s' % json.dumps(failures, sort_keys=True, separators=(',', ':')), file=sys.stderr)
            raise SystemExit(79)

try:
    manifest_bytes = read_relative(17, manifest_path)
    profile_bytes = read_relative(17, profiles_path)
    manifest = json.loads(manifest_bytes)
    profiles = json.loads(profile_bytes)
except Exception:
    block("json-unreadable")
if not isinstance(manifest, dict) or not isinstance(profiles, list):
    block("shape")
if manifest.get("sourceRoleCount") != 269 or manifest.get("roleSetCount") != 269 or manifest.get("expectedSections") != 269:
    block("role-count")
if manifest.get("sourceRoot") != "integrations" or manifest.get("sourceRootDigest") != "65958cac2412f3c943429ac1694bf5563a3588ac5b65c995568e08be28c1bcb2":
    block("source-root-contract")
if manifest.get("roleSetPath") != "../governance/role-governance-profiles.json" or manifest.get("roleSetSha256") != "974d269ced0642cd1c14bb9ed716f55fc3a940fab6b8ff2c9451d11b9f0dff07":
    block("role-set-contract")
role_set_file_sha256 = manifest.get("roleSetFileSha256")
if "roleSetFileSha256" not in manifest:
    block("role-set-file-sha-missing")
if not isinstance(role_set_file_sha256, str) or not re.fullmatch(r"[0-9a-f]{64}", role_set_file_sha256):
    block("role-set-file-sha-malformed")
if role_set_file_sha256 != "ad7616f4520eb5c5727cad1f7992c4fa6ad881dcba728266ab2cdb0c55608e20":
    block("role-set-file-sha-mismatch")
if len(profiles) != 269 or len({p.get("role_id") for p in profiles}) != 269:
    block("role-set")
if any(not isinstance(p.get("role_id"), str) or not p.get("role_id") for p in profiles):
    block("role-id")
slug_pattern = re.compile(r"[^a-z0-9]+")
role_slugs = set()
for profile in profiles:
    role_slug = slug_pattern.sub("-", str(profile.get("role_name", "")).strip().lower())
    role_slug = re.sub(r"-+", "-", role_slug).strip("-")
    if role_slug:
        role_slugs.add(role_slug)
role_name_slug_digest = hashlib.sha256("\n".join(sorted(role_slugs)).encode("utf-8")).hexdigest()
if not role_slugs:
    block("role-name-slug")
if any(p.get("risk_level") == "high" and p.get("allowed_write_actions") != [] for p in profiles):
    block("high-risk-write")

def safe_tool_component(value):
    return (
        isinstance(value, str)
        and bool(value)
        and value not in ('.', '..')
        and '/' not in value
        and '\x00' not in value
    )

if any(
        not safe_tool_component(tool.get(field))
        for tool in manifest.get("tools", [])
        for field in ("name", "installTool", "sourceDir")
):
    block("unsafe-tool-component")

actual_tool_names = [x.get("name") for x in manifest.get("tools", [])]
if len(actual_tool_names) != len(expected_tools) or len(set(actual_tool_names)) != len(expected_tools) or sorted(actual_tool_names) != sorted(expected_tools):
    block("tool-order-or-set")
actual_targets = []
for tool in manifest["tools"]:
    if tool.get("sectionCount") != 269:
        block("section-count")
    for target in tool.get("targets", []):
        actual_targets.append((tool.get("name"), target.get("label"), target.get("kind"), target.get("targetPath")))
if len(actual_targets) != len(expected_targets) or len(set(actual_targets)) != len(expected_targets) or sorted(actual_targets) != sorted(expected_targets):
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
    "source_root": manifest["sourceRoot"],
    "source_root_count": manifest["sourceRoleCount"],
    "source_root_digest": manifest["sourceRootDigest"],
    "role_set_path": manifest["roleSetPath"],
    "role_set_count": manifest["roleSetCount"],
    "role_set_sha256": manifest["roleSetSha256"],
    "role_set_file_sha256": manifest["roleSetFileSha256"],
    "role_name_slug_digest": role_name_slug_digest,
}, sort_keys=True, separators=(",", ":")))
PY
}

m3_source_digest() {
  : <&16 || { m3_fail descriptor-admission fd16-source fd-unavailable 41; return $?; }
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

def collect(fd, rel=""):
    try:
        names = sorted(os.listdir(fd))
    except OSError:
        bad("list-failed")
    items = []
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
            items.append(("dir-entry", child_rel, ""))
            try:
                child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            except OSError:
                bad("directory-open-failed")
            primary = None
            try:
                items.append(("dir", child_rel, ""))
                items.extend(collect(child, child_rel))
                st_after = os.fstat(child)
            except BaseException as exc:
                primary = exc
            finish_owned_closes("source-validation", "source-digest", primary, [(child, "source-child-directory")])
            stable = lambda st: (st.st_dev, st.st_ino, st.st_mode, st.st_uid, st.st_nlink, st.st_size, st.st_mtime_ns, st.st_ctime_ns)
            if stable(st_before) != stable(st_after):
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
            stable = lambda st: (st.st_dev, st.st_ino, st.st_mode, st.st_uid, st.st_nlink, st.st_size, st.st_mtime_ns, st.st_ctime_ns)
            if stable(st_before) != stable(st_open) or stable(st_open) != stable(st_after):
                bad("file-metadata-race")
            file_hash = hashlib.sha256(content).hexdigest()
            items.append(("file", child_rel, "%d:%d:%s" % (len(content), mode, file_hash)))
    return items

try:
    st_root = os.fstat(root_fd)
    if not stat.S_ISDIR(st_root.st_mode):
        bad("source-not-directory")
    entries = sorted(collect(root_fd))
    source_digest = hashlib.sha256()
    for kind, path, metadata in entries:
        source_digest.update(("%s|%s|%s\n" % (kind, path, metadata)).encode("utf-8"))
    result = source_digest.hexdigest()
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

def promote_owned_fd(raw, role):
    try:
        promoted = fcntl.fcntl(raw, fcntl.F_DUPFD_CLOEXEC, 23)
    except OSError:
        finish_owned_closes(SystemExit(46), [(raw, role + "-raw")])
    failures = []
    try:
        os.close(raw)
    except OSError as exc:
        failures.append({"code":"E_DESCRIPTOR_CLOSE", "fd_role":role + "-raw", "errno":exc.errno})
    if failures:
        try:
            os.close(promoted)
        except OSError as exc:
            failures.append({"code":"E_DESCRIPTOR_CLOSE", "fd_role":role + "-promoted", "errno":exc.errno})
        print("M3_FAILURE stage=authorization operation=action-signature-ledger reason=E_DESCRIPTOR_CLOSE rc=79 primary=null close_failures=%s" % json.dumps(failures, sort_keys=True, separators=(",", ":")), file=sys.stderr)
        raise SystemExit(79)
    return promoted

def open_relative(root, value, flags, mode=0o600):
    items = parts(value)
    current = root
    owned = []
    try:
        for item in items[:-1]:
            current = promote_owned_fd(os.open(item, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=current), "authorization-open-parent")
            owned.append(current)
        fd = promote_owned_fd(os.open(items[-1], flags | os.O_NOFOLLOW | os.O_CLOEXEC, mode, dir_fd=current), "authorization-open-leaf")
        return fd, owned
    except OSError:
        primary = SystemExit(46)
        print("M3_FAILURE stage=authorization operation=action-signature-ledger reason=descriptor-relative-open rc=46", file=sys.stderr)
        finish_owned_closes(primary, [(descriptor, "authorization-open-parent") for descriptor in reversed(owned)])

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
    action_fd, action_parents = open_relative(18, act_name, os.O_RDONLY)
    sig_fd, sig_parents = open_relative(18, sig_name, os.O_RDONLY)
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
    for fd in (sig_fd, signer_fd):
        os.set_inheritable(fd, True)
    verified = subprocess.run(
        ["ssh-keygen", "-Y", "verify", "-f", "/dev/fd/%d" % signer_fd, "-I", principal, "-n", namespace, "-s", "/dev/fd/%d" % sig_fd],
        input=action,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        pass_fds=(sig_fd, signer_fd),
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
  local target_id="${7:-$journal_component}"
  local sequence="${8:-0}"
  local tool="${9:-unknown}"
  local kind="${10:-directory}"
  local source_section_count="${11:-}"
  local source_role_count="${12:-}"
  [[ "${M3_DRY_RUN:-0}" == 1 ]] && return 0
  [[ "$target_role" == project || "$target_role" == home ]] || { m3_fail owner-plan target-role unknown-role 52; return $?; }
  m3_lexical_components "$target_components" || return $?
  m3_lexical_components "$stage_components" || return $?
  m3_lexical_components "$backup_components" || return $?
  m3_lexical_components "$source_components" || return $?
  m3_lexical_components "$journal_component" || return $?
  [[ "$source_section_count" =~ ^[0-9]+$ \
     && "$source_role_count" =~ ^[0-9]+$ \
     && "$source_section_count" == "$source_role_count" \
     && "$source_section_count" == 269 ]] || {
    m3_fail owner-plan source-count invalid-source-count 53
    return $?
  }
  m3_fd_role_check || return $?
  python3 - "$target_role" "$target_components" "$stage_components" "$backup_components" "$source_components" "$journal_component" "$target_id" "$sequence" "$tool" "$kind" "$source_section_count" "$source_role_count" <<'PY'
import hashlib, json, os, stat, sys
role, target, stage, backup, source, journal, target_id, sequence, tool, kind, source_section_count_text, source_role_count_text = sys.argv[1:]
source_section_count = int(source_section_count_text)
source_role_count = int(source_role_count_text)

def finish_owned_closes(primary, owned):
    failures=[]
    for descriptor, role_name in owned:
        if descriptor is None: continue
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
if source_section_count != 269 or source_role_count != 269 or source_section_count != source_role_count:
    print("M3_FAILURE stage=owner-plan operation=source-count reason=invalid-source-count rc=53", file=sys.stderr); raise SystemExit(53)
root = 17 if role == "project" else 18
for value in (target, stage, backup, source, journal):
    if any(not x or x in (".", "..") or "/" in x for x in value.split("/")):
        print("M3_FAILURE stage=owner-plan operation=lexical-bind reason=unsafe-component rc=53", file=sys.stderr); raise SystemExit(53)
items = {"schema":"agency-agents.m3-transaction-journal/v1", "transaction_id":target_id, "sequence":int(sequence), "target_id":target_id, "tool":tool, "kind":kind, "state":"planned", "target_role":role, "target_components":target, "source_components":source, "source_section_count":source_section_count, "source_role_count":source_role_count, "stage_components":stage, "backup_components":backup, "created_work_dirs":[], "created_target_dirs":[], "backup_moved":False, "installed":False, "intents":{"backup":"pending","install":"pending","rollback":"pending"}, "rollback_entries":[], "revision":1, "previous_digest":"", "journal_digest":""}
canonical = json.dumps(items, sort_keys=True, separators=(",", ":"))+"\n"
items["journal_digest"] = hashlib.sha256(canonical.encode()).hexdigest()
parts=journal.split("/")
parent=12; opened=[]; fd=None
primary=None
try:
    for item in parts[:-1]:
        parent=os.open(item, os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW, dir_fd=parent); opened.append(parent)
    fd=os.open(parts[-1], os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW, 0o600, dir_fd=parent)
    data=(json.dumps(items, sort_keys=True, separators=(",", ":"))+"\n").encode()
    os.write(fd,data); os.fsync(fd)
    print(json.dumps({"status":"planned","target_role":role,"target_fd":root,"journal_fd":12}, sort_keys=True, separators=(",", ":")))
except OSError:
    print("M3_FAILURE stage=owner-plan operation=journal-create reason=descriptor-relative-journal-failed rc=54", file=sys.stderr); primary=SystemExit(54)
except BaseException as exc:
    primary=exc
finish_owned_closes(primary, [(fd,"owner-plan-journal")] + [(descriptor,"owner-plan-parent") for descriptor in reversed(opened)])
PY
}

stage_owner_plan() {
  local journal_component="$1" close_seam="${2-}"
  [[ "${M3_DRY_RUN:-0}" == 1 ]] && return 0
  m3_lexical_components "$journal_component" || return $?
  m3_fd_role_check || return $?
  python3 - "$journal_component" "$close_seam" <<'PY'
import hashlib, json, os, stat, sys
journal_name=sys.argv[1]
close_seam=sys.argv[2]
def fail(reason,rc=55):
 print("M3_FAILURE stage=staging operation=descriptor-copy reason=%s rc=%d"%(reason,rc),file=sys.stderr); raise SystemExit(rc)
def parts(v):
 x=v.split("/")
 if any(not p or p in (".","..") or "/" in p for p in x): fail("unsafe-component")
 return x
def persist(j, fd):
 j["previous_digest"]=j.get("journal_digest","")
 j["revision"]=int(j.get("revision",0))+1
 j["journal_digest"]=""
 raw=(json.dumps(j,sort_keys=True,separators=(",", ":"))+"\n").encode()
 j["journal_digest"]=hashlib.sha256(raw).hexdigest()
 encoded=(json.dumps(j,sort_keys=True,separators=(",", ":"))+"\n").encode()
 os.lseek(fd,0,os.SEEK_SET); os.ftruncate(fd,0); os.write(fd,encoded); os.fsync(fd)
def close_checked(descriptor, role, failures):
 try: os.close(descriptor)
 except OSError as exc: failures.append({"code":"E_DESCRIPTOR_CLOSE","fd_role":role,"errno":exc.errno})
def finish_owned_closes(primary, owned):
 failures=[]
 for descriptor,role in owned:
  if descriptor is None: continue
  close_checked(descriptor,role,failures)
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
def descriptor_no_follow_copy(source_fd,source_name,dest_fd,relative):
 st=os.stat(source_name,dir_fd=source_fd,follow_symlinks=False)
 if stat.S_ISLNK(st.st_mode) or not (stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode)): fail("source-special")
 if stat.S_ISDIR(st.st_mode):
  os.mkdir(relative,0o700,dir_fd=dest_fd)
  dest_fd=os.open(relative,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=dest_fd)
  source_fd=os.open(source_name,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=source_fd)
  primary=None
  try:
   for child in sorted(os.listdir(source_fd)):
    descriptor_no_follow_copy(source_fd, child, dest_fd, child)
  except BaseException as exc: primary=exc
  finish_owned_closes(primary,[(source_fd,"stage-source-directory"),(dest_fd,"stage-output-directory")])
 else:
  inf=os.open(source_name,os.O_RDONLY|os.O_NOFOLLOW,dir_fd=source_fd); outf=os.open(relative,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600,dir_fd=dest_fd)
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
 cur=root; created=[]; opened=[]
 components=parts(v)
 for index,p in enumerate(components[:-1]):
  try: nxt=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=cur)
  except FileNotFoundError:
   os.mkdir(p,0o700,dir_fd=cur); created.append({"root_role":"work","relative_components":components[:index+1]}); nxt=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=cur)
  opened.append(nxt); cur=nxt
 return cur,created,opened
work_root_fd=None; source_root_fd=None; fd=None; opened=[]; source_parent_fd=None; src_open=[]; dest_parent_fd=None; stage_open=[]; primary=None; phase='anchor-dup'
try:
 work_root_fd=os.dup(12)
 source_root_fd=os.dup(16)
 phase='journal-open'
 fd,opened=open_rel(work_root_fd,journal_name,os.O_RDWR)
 data=os.read(fd,64*1024*1024); j=json.loads(data.decode());
 if j.get("schema")!="agency-agents.m3-transaction-journal/v1" or j.get("state")!="planned": fail("journal-not-frozen")
 if type(j.get("source_section_count")) is not int or type(j.get("source_role_count")) is not int or j["source_section_count"]!=269 or j["source_role_count"]!=269 or j["source_section_count"]!=j["source_role_count"]: fail("journal-source-count")
 phase='journal-staging-persist'
 j["state"]="staging"; persist(j,fd)
 phase='source-open'
 source_parts=parts(j["source_components"])
 source_parent_fd=source_root_fd
 for source_component in source_parts[:-1]:
  source_parent_fd=os.open(source_component,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=source_parent_fd)
  src_open.append(source_parent_fd)
 phase='work-parent'
 dest_parent_fd,created,stage_open=ensure_parent(work_root_fd,j["stage_components"]); j["created_work_dirs"]=created
 persist(j,fd)
 phase='copy'
 source_name=source_parts[-1]
 relative=parts(j["stage_components"])[-1]
 stage_fd=dest_parent_fd
 if j.get("kind")=="file":
  descriptor_no_follow_copy(source_parent_fd,source_name,stage_fd,relative)
 elif len(source_parts)==1 and source_name==relative:
  descriptor_no_follow_copy(source_root_fd,relative,stage_fd,relative)
 else:
  descriptor_no_follow_copy(source_parent_fd,source_name,stage_fd,relative)
 phase='journal-staged-persist'
 j["state"]="staged"
 j["intents"]["install"]="pending"
 persist(j,fd)
 if close_seam:
  if close_seam!="owner-stage-parent-close": fail("close-seam")
  disposable=os.dup(dest_parent_fd)
  os.close(disposable)
  seam_failures=[]
  close_checked(disposable,"owner-stage-parent",seam_failures)
  if len(seam_failures)!=1 or seam_failures[0].get("code")!="E_DESCRIPTOR_CLOSE": fail("close-seam-not-triggered")
  print(json.dumps(seam_failures,sort_keys=True,separators=(",",":")))
  raise SystemExit(79)
 print(json.dumps({"status":"staged","journal_fd":12},sort_keys=True,separators=(",",":")))
except BaseException as exc:
 primary=exc
 if os.environ.get('AGENCY_TEST_BINDER_STAGE')=='ledger-replay-v1' and os.environ.get('AGENCY269_TEST_MODE')=='1' and not (close_seam=='owner-stage-parent-close' and isinstance(exc,SystemExit) and exc.code==79):
  name=type(exc).__name__
  allowed={'FileNotFoundError','FileExistsError','NotADirectoryError','PermissionError','IsADirectoryError','OSError','SystemExit','JSONDecodeError'}
  print('M3_STAGE_INTERNAL phase=%s class=%s'%(phase,name if name in allowed else 'unexpected'),file=sys.stderr)
finish_owned_closes(primary,[(fd,"stage-journal")]+[(x,"stage-source-parent") for x in reversed(src_open)]+[(x,"stage-journal-parent") for x in reversed(opened)]+[(x,"stage-work-parent") for x in reversed(stage_open)]+[(source_root_fd,"stage-source-root"),(work_root_fd,"stage-work-root")])
PY
}

install_owner_plan() {
  local journal_component="$1"
  [[ "${M3_DRY_RUN:-0}" == 1 ]] && return 0
  m3_lexical_components "$journal_component" || return $?
  m3_fd_role_check || return $?
  python3 - "$journal_component" <<'PY'
import hashlib, json, os, stat, sys
name=sys.argv[1]
def fail(reason,rc=56):
 print("M3_FAILURE stage=install operation=owner-install reason=%s rc=%d"%(reason,rc),file=sys.stderr); raise SystemExit(rc)
def parts(v):
 x=v.split("/")
 if any(not p or p in (".","..") or "/" in p for p in x): fail("unsafe-component")
 return x
def persist(j, fd):
 j["previous_digest"]=j.get("journal_digest","")
 j["revision"]=int(j.get("revision",0))+1
 j["journal_digest"]=""
 raw=(json.dumps(j,sort_keys=True,separators=(",", ":"))+"\n").encode()
 j["journal_digest"]=hashlib.sha256(raw).hexdigest()
 encoded=(json.dumps(j,sort_keys=True,separators=(",", ":"))+"\n").encode()
 os.lseek(fd,0,os.SEEK_SET); os.ftruncate(fd,0); os.write(fd,encoded); os.fsync(fd)
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
def node_metadata(parent, leaf):
 st=os.stat(leaf,dir_fd=parent,follow_symlinks=False)
 if stat.S_ISLNK(st.st_mode) or not (stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode)): fail("metadata-special")
 if stat.S_ISREG(st.st_mode):
  fd=os.open(leaf,os.O_RDONLY|os.O_NOFOLLOW,dir_fd=parent); digest=hashlib.sha256(); primary=None
  try:
   while True:
    chunk=os.read(fd,1024*1024)
    if not chunk: break
    digest.update(chunk)
  except BaseException as exc: primary=exc
  finish_owned_closes(primary,[(fd,"install-metadata-file")])
  return {"digest":digest.hexdigest(),"mode":stat.S_IMODE(st.st_mode),"size":st.st_size}
 child=os.open(leaf,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=parent); digest=hashlib.sha256(); primary=None
 try:
  for name in sorted(os.listdir(child)):
   child_meta=node_metadata(child,name)
   digest.update((name+"\0").encode()); digest.update(json.dumps(child_meta,sort_keys=True,separators=(",",":")).encode())
 except BaseException as exc: primary=exc
 finish_owned_closes(primary,[(child,"install-metadata-directory")])
 return {"digest":digest.hexdigest(),"mode":stat.S_IMODE(st.st_mode),"size":st.st_size}
work_root_fd=None; project_root_fd=None; home_root_fd=None; fd=None; parent=None; opened=[]; topened=[]; primary=None
try:
 work_root_fd=os.dup(12)
 project_root_fd=os.dup(17)
 home_root_fd=os.dup(18)
 fd,parent,opened=open_rel(work_root_fd,name,os.O_RDWR)
 j=json.loads(os.read(fd,64*1024*1024).decode())
 if j.get("schema")!="agency-agents.m3-transaction-journal/v1" or j.get("state")!="staged": fail("journal-state")
 if type(j.get("source_section_count")) is not int or type(j.get("source_role_count")) is not int or j["source_section_count"]!=269 or j["source_role_count"]!=269 or j["source_section_count"]!=j["source_role_count"]: fail("journal-source-count")
 j["state"]="installing"; persist(j,fd)
 root=project_root_fd if j.get("target_role")=="project" else home_root_fd if j.get("target_role")=="home" else 0
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
   j["created_target_dirs"].append({"root_role":j["target_role"],"relative_components":tp[:component_index+1]})
   nxt=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=cur)
   topened.append(nxt); cur=nxt
 target_parent=cur
 persist(j,fd)
 stage_parent=work_root_fd
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
 target_exists=leaf_state(target_parent,leaf,"target") is not None
 if target_exists:
  expected=node_metadata(target_parent,leaf)
 else:
  expected={"digest":"absent","mode":0,"size":0}
 staged=node_metadata(stage_parent,stage_leaf)
 for metadata in (expected,staged): metadata["mode"]=format(int(metadata["mode"]),"o")
 j["rollback_entries"]=[{"id":j["target_id"],"ownerRelative":"__whole_file__" if j["kind"]=="file" else j["target_components"],"kind":j["kind"],"target_role":j["target_role"],"target_components":tp,"tool":j["tool"],"hasBackup":target_exists,"expected":expected,"staged":staged}]
 persist(j,fd)
 if leaf_state(target_parent,leaf,"target") is not None:
  os.rename(leaf,backup,src_dir_fd=target_parent,dst_dir_fd=target_parent); j["backup_moved"]=True
  j["intents"]["backup"]="done"
  persist(j,fd)
 os.rename(stage_leaf,leaf,src_dir_fd=stage_parent,dst_dir_fd=target_parent); j["installed"]=True; j["state"]="installed"; j["intents"]["install"]="done"
 persist(j,fd)
 print(json.dumps({"status":"installed","backup_fd":root,"target_fd":root,"journal_fd":12},sort_keys=True,separators=(",",":")))
except BaseException as exc: primary=exc
finish_owned_closes(primary,[(fd,"install-journal")]+[(x,"install-owned-parent") for x in topened+opened]+[(home_root_fd,"install-home-root"),(project_root_fd,"install-project-root"),(work_root_fd,"install-work-root")])
PY
}

m3_tx_stage() { stage_owner_plan "$@"; }
m3_tx_install() { install_owner_plan "$@"; }

m3_tx_rollback() {
  local journal_component="$1" close_seam="${2-}"
  [[ "${M3_DRY_RUN:-0}" == 1 ]] && return 0
  m3_lexical_components "$journal_component" || return $?
  m3_fd_role_check || return $?
  python3 - "$journal_component" "$close_seam" <<'PY'
import hashlib, json, os, stat, sys
name=sys.argv[1]
close_seam=sys.argv[2]
def fail(reason,rc=57):
 print("M3_FAILURE stage=rollback operation=owner-rollback reason=%s rc=%d"%(reason,rc),file=sys.stderr); raise SystemExit(rc)
def parts(v):
 x=v.split("/")
 if any(not p or p in (".","..") or "/" in p for p in x): fail("unsafe-component")
 return x
def persist(j, fd):
 j["previous_digest"]=j.get("journal_digest","")
 j["revision"]=int(j.get("revision",0))+1
 j["journal_digest"]=""
 raw=(json.dumps(j,sort_keys=True,separators=(",", ":"))+"\n").encode()
 j["journal_digest"]=hashlib.sha256(raw).hexdigest()
 encoded=(json.dumps(j,sort_keys=True,separators=(",", ":"))+"\n").encode()
 os.lseek(fd,0,os.SEEK_SET); os.ftruncate(fd,0); os.write(fd,encoded); os.fsync(fd)
def close_checked(descriptor, role, failures):
 try: os.close(descriptor)
 except OSError as exc: failures.append({"code":"E_DESCRIPTOR_CLOSE","fd_role":role,"errno":exc.errno})
def finish_owned_closes(primary, owned):
 failures=[]
 for descriptor,role in owned:
  if descriptor is None: continue
  close_checked(descriptor,role,failures)
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
def node_metadata(parent, leaf):
 st=os.stat(leaf,dir_fd=parent,follow_symlinks=False)
 if stat.S_ISLNK(st.st_mode) or not (stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode)): fail("rollback-metadata-special")
 if stat.S_ISREG(st.st_mode):
  descriptor=os.open(leaf,os.O_RDONLY|os.O_NOFOLLOW,dir_fd=parent); digest=hashlib.sha256(); primary=None
  try:
   while True:
    chunk=os.read(descriptor,1024*1024)
    if not chunk: break
    digest.update(chunk)
  except BaseException as exc: primary=exc
  finish_owned_closes(primary,[(descriptor,"rollback-metadata-file")])
  return {"digest":digest.hexdigest(),"mode":format(stat.S_IMODE(st.st_mode),"o"),"size":st.st_size}
 descriptor=os.open(leaf,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=parent); digest=hashlib.sha256(); primary=None
 try:
  for child in sorted(os.listdir(descriptor)):
   child_meta=node_metadata(descriptor,child)
   digest.update((child+"\0").encode()); digest.update(json.dumps(child_meta,sort_keys=True,separators=(",",":")).encode())
 except BaseException as exc: primary=exc
 finish_owned_closes(primary,[(descriptor,"rollback-metadata-directory")])
 return {"digest":digest.hexdigest(),"mode":format(stat.S_IMODE(st.st_mode),"o"),"size":st.st_size}
def leaf_state(parent, component, label):
 try: result=os.stat(component,dir_fd=parent,follow_symlinks=False)
 except FileNotFoundError: return None
 except OSError: fail(label+"-stat-unsafe")
 if stat.S_ISLNK(result.st_mode): fail(label+"-symlink")
 if not (stat.S_ISREG(result.st_mode) or stat.S_ISDIR(result.st_mode)): fail(label+"-special")
 return result
def open_optional_parent(root, components, owned):
 current=root
 for component in components:
  try: current=os.open(component,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=current)
  except FileNotFoundError: return None
  except OSError: fail("target-parent-unsafe")
  owned.append(current)
 return current
def frozen_created_directories(journal, field, frozen_role):
 records=journal.get(field)
 if not isinstance(records,list): fail("created-target-dirs-shape")
 validated=[]; identities=set()
 for record in records:
  if not isinstance(record,dict): fail("created-directory-record")
  if set(record) != {"root_role","relative_components"}: fail("created-directory-fields")
  role=record.get("root_role"); components=record.get("relative_components")
  if role!=frozen_role or role not in ("project","home","work"): fail("created-target-dir-role-drift")
  if not isinstance(components,list) or not components: fail("created-target-dir-components")
  if any(not isinstance(component,str) or not component or component in (".","..") or "/" in component for component in components): fail("created-target-dir-lexical")
  identity=(role,tuple(components))
  if identity in identities: fail("created-target-dir-duplicate")
  identities.add(identity); validated.append({"role":role,"target_role":role,"relative_components":components})
 return sorted(validated,key=lambda record:(-len(record["relative_components"]),tuple(record["relative_components"])))
def cleanup_created_directory(record, role_root):
 components=record["relative_components"]
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
fd=12
items=parts(name); opened=[]
targets=[]; jf=None; primary=None
try:
 for p in items[:-1]: fd=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=fd); opened.append(fd)
 jf=os.open(items[-1],os.O_RDWR|os.O_NOFOLLOW,dir_fd=fd); j=json.loads(os.read(jf,64*1024*1024).decode())
 if j.get("schema")!="agency-agents.m3-transaction-journal/v1" or j.get("state") not in ("committed","installed","installing","staged","staging","planned"): fail("journal-owner-or-state")
 frozen_target_role=j.get("target_role")
 root=17 if frozen_target_role=="project" else 18 if frozen_target_role=="home" else 0
 if not root: fail("target-role")
 tp=parts(j["target_components"]); bp=parts(j["backup_components"]); sp=parts(j["stage_components"])
 if tp[:-1]!=bp[:-1]: fail("backup-not-sibling")
 targets=[]; parent=open_optional_parent(root,tp[:-1],targets); leaf=tp[-1]; backup=bp[-1]
 stage_parent=12
 for p in sp[:-1]: stage_parent=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=stage_parent); targets.append(stage_parent)
 if not j.get("rollback_entries"):
  target_state=None if parent is None else leaf_state(parent,leaf,"target")
  expected={"digest":"absent","mode":"0","size":0} if target_state is None else node_metadata(parent,leaf)
  staged=node_metadata(stage_parent,sp[-1])
  j["rollback_entries"]=[{"id":j["target_id"],"ownerRelative":"__whole_file__" if j["kind"]=="file" else j["target_components"],"kind":j["kind"],"target_role":frozen_target_role,"target_components":tp,"tool":j["tool"],"hasBackup":target_state is not None,"expected":expected,"staged":staged}]
 if not isinstance(j.get("rollback_entries"),list) or len(j["rollback_entries"])!=1: fail("rollback-entry-shape")
 j["state"]="rollback_in_progress"; j["intents"]["rollback"]="pending"; persist(j,jf)
 if (j.get("installed") or j.get("backup_moved")) and parent is None: fail("target-parent-missing")
 if j.get("installed"): remove_tree(parent,leaf)
 if j.get("backup_moved"):
  os.rename(backup,leaf,src_dir_fd=parent,dst_dir_fd=parent)
 for created_directory in frozen_created_directories(j,"created_target_dirs",frozen_target_role): cleanup_created_directory(created_directory,17 if frozen_target_role=="project" else 18)
 remove_tree(stage_parent,sp[-1])
 for created_directory in frozen_created_directories(j,"created_work_dirs","work"): cleanup_created_directory(created_directory,12)
 j["state"]="rolled_back"; j["intents"]["rollback"]="done"; persist(j,jf)
 restored=len(j.get("rollback_entries",[]))
 restore_failures=[]
 seam_failures=[]
 if close_seam:
  if close_seam!="rollback-target-parent-close": fail("close-seam")
  disposable=os.dup(parent if parent is not None else root)
  os.close(disposable)
  close_checked(disposable,"rollback-target-parent",seam_failures)
  if len(seam_failures)!=1 or seam_failures[0].get("code")!="E_DESCRIPTOR_CLOSE": fail("close-seam-not-triggered")
 print(json.dumps({"status":"rolled-back","restored":restored,"restoreFailures":restore_failures,"secondaryCloseFailures":seam_failures,"entries":j.get("rollback_entries",[]),"journal_fd":12},sort_keys=True,separators=(",",":")))
 if close_seam: raise SystemExit(78)
except SystemExit as exc: primary=exc
except BaseException:
 print("M3_FAILURE stage=rollback operation=owner-rollback reason=rollback-operation-failed rc=57",file=sys.stderr)
 primary=SystemExit(57)
finish_owned_closes(primary,[(jf,"rollback-journal")]+[(x,"rollback-owned-parent") for x in reversed(opened+targets)])
PY
}

m3_tx_verify() {
  local journal_component="$1"
  m3_lexical_components "$journal_component" || return $?
  python3 - "$journal_component" <<'PY'
import json, os, stat, sys
name=sys.argv[1]
parts=name.split('/')
if any(not p or p in ('.','..') or '/' in p for p in parts): raise SystemExit(56)
cur=12; opened=[]; jf=None
primary=None
try:
    for p in parts[:-1]:
        cur=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=cur); opened.append(cur)
    jf=os.open(parts[-1],os.O_RDONLY|os.O_NOFOLLOW,dir_fd=cur)
    j=json.loads(os.read(jf,64*1024*1024).decode())
    if j.get('schema')!='agency-agents.m3-transaction-journal/v1' or j.get('state')!='installed': raise SystemExit(56)
    root=17 if j.get('target_role')=='project' else 18 if j.get('target_role')=='home' else 0
    if not root: raise SystemExit(56)
    parent=root
    target=j['target_components'].split('/')
    for p in target[:-1]:
        parent=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=parent); opened.append(parent)
    st=os.stat(target[-1],dir_fd=parent,follow_symlinks=False)
    if stat.S_ISLNK(st.st_mode) or not (stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode)): raise SystemExit(56)
    print('{"status":"verified"}')
except BaseException as exc:
    primary=exc
finally:
    failures=[]
    for fd in ([jf] if jf is not None else []) + list(reversed(opened)):
        try: os.close(fd)
        except OSError as exc: failures.append({"code":"E_DESCRIPTOR_CLOSE","fd":fd,"errno":exc.errno})
    if failures:
        print("M3_FAILURE stage=verify operation=owner-verify reason=E_DESCRIPTOR_CLOSE rc=%d" % (78 if primary is not None else 79), file=sys.stderr)
        raise SystemExit(78 if primary is not None else 79)
if primary is not None: raise primary
PY
}

m3_tx_commit() {
  local journal_component="$1"
  m3_lexical_components "$journal_component" || return $?
  python3 - "$journal_component" <<'PY'
import hashlib, json, os, sys
name=sys.argv[1]; parts=name.split('/')
if any(not p or p in ('.','..') or '/' in p for p in parts): raise SystemExit(56)
cur=12; opened=[]; jf=None
primary=None
try:
    for p in parts[:-1]: cur=os.open(p,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=cur); opened.append(cur)
    jf=os.open(parts[-1],os.O_RDWR|os.O_NOFOLLOW,dir_fd=cur); j=json.loads(os.read(jf,64*1024*1024).decode())
    if j.get('schema')!='agency-agents.m3-transaction-journal/v1' or j.get('state')!='installed': raise SystemExit(56)
    j['state']='committed'; j['intents']['rollback']='not-needed'; j['previous_digest']=j.get('journal_digest',''); j['revision']=int(j.get('revision',0))+1; j['journal_digest']=''
    raw=(json.dumps(j,sort_keys=True,separators=(',',':'))+'\n').encode(); j['journal_digest']=hashlib.sha256(raw).hexdigest(); data=(json.dumps(j,sort_keys=True,separators=(',',':'))+'\n').encode()
    os.lseek(jf,0,os.SEEK_SET); os.ftruncate(jf,0); os.write(jf,data); os.fsync(jf); print('{"status":"committed"}')
except BaseException as exc:
    primary=exc
finally:
    failures=[]
    for fd in ([jf] if jf is not None else []) + list(reversed(opened)):
        try: os.close(fd)
        except OSError as exc: failures.append({"code":"E_DESCRIPTOR_CLOSE","fd":fd,"errno":exc.errno})
    if failures:
        print("M3_FAILURE stage=commit operation=journal-commit reason=E_DESCRIPTOR_CLOSE rc=%d" % (78 if primary is not None else 79), file=sys.stderr)
        raise SystemExit(78 if primary is not None else 79)
if primary is not None: raise primary
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
  m3_internal_result dry-run passed null '{"performed":false,"attempted":0,"restored":0,"restoreFailures":[],"entries":[]}' '[]'
}

m3_entry_bound_digest() {
  python3 - <<'PY'
import hashlib
import os
fd = 11
offset = 0
digest = hashlib.sha256()
while True:
    chunk = os.pread(fd, 1024 * 1024, offset)
    if not chunk:
        break
    digest.update(chunk)
    offset += len(chunk)
print(digest.hexdigest())
PY
}

m3_manifest_target_rows() {
  local manifest="$1"
  python3 - "$manifest" <<'PY'
import json
import os
import stat
import sys

def components(value):
    if value.startswith('/'):
        raise SystemExit(1)
    result = value.split('/')
    if any(not x or x in ('.', '..') or '/' in x or '\x00' in x for x in result):
        raise SystemExit(1)
    return result

def read_relative(value):
    parts = components(value)
    current = 17
    parents = []
    leaf = None
    result = None
    primary = None
    try:
        for part in parts[:-1]:
            current = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=current)
            parents.append(current)
        leaf = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW, dir_fd=current)
        st = os.fstat(leaf)
        if not stat.S_ISREG(st.st_mode):
            raise SystemExit(1)
        data = bytearray()
        while True:
            chunk = os.read(leaf, 1024 * 1024)
            if not chunk:
                break
            data.extend(chunk)
        result = json.loads(bytes(data).decode('utf-8'))
    except BaseException as exc:
        primary = exc
    close_failures = []
    owned = ([(leaf, 'manifest-target-input')] if leaf is not None else []) + [(descriptor, 'manifest-target-parent') for descriptor in reversed(parents)]
    for descriptor, role in owned:
        try:
            os.close(descriptor)
        except OSError as exc:
            close_failures.append({'code':'E_DESCRIPTOR_CLOSE','ownerModule':'M3','role':role,'errno':exc.errno})
    if close_failures:
        original_rc = getattr(primary, 'code', 1) if primary is not None else 0
        if not isinstance(original_rc, int):
            original_rc = 1
        primary_record = None if primary is None else {'module':'M3','stage':'manifest-validation','operation':'manifest-target-rows','reason':'primary-failure','originalRc':original_rc}
        rc = 78 if primary is not None else 79
        print('M3_FAILURE stage=manifest-validation operation=manifest-target-rows reason=E_DESCRIPTOR_CLOSE rc=%d primary=%s secondaryCloseFailures=%s' % (rc, json.dumps(primary_record,sort_keys=True,separators=(',',':')), json.dumps(close_failures,sort_keys=True,separators=(',',':'))), file=sys.stderr)
        raise SystemExit(rc)
    if primary is not None:
        raise primary
    return result

manifest = read_relative(sys.argv[1])
source_role_count = manifest.get('sourceRoleCount')
expected_sections = manifest.get('expectedSections')
if type(source_role_count) is not int or type(expected_sections) is not int \
        or source_role_count != 269 or expected_sections != 269 \
        or source_role_count != expected_sections:
    raise SystemExit(1)
for number, tool in enumerate(manifest['tools'], 1):
    tool_name = tool['name']
    report_tool = tool['installTool']
    source_dir = tool['sourceDir']
    if any(
            not isinstance(value, str) or not value
            or value in ('.', '..') or '/' in value or '\x00' in value
            for value in (tool_name, report_tool, source_dir)):
        raise SystemExit(1)
    source_section_count = tool.get('sectionCount')
    if type(source_section_count) is not int \
            or source_section_count != expected_sections \
            or source_section_count != source_role_count:
        raise SystemExit(1)
    for target in tool['targets']:
        target_path = target['targetPath']
        if target_path.startswith('${PROJECT}/'):
            role = 'project'
            target_components = target_path[len('${PROJECT}/'):]
        elif target_path.startswith('${HOME}/'):
            role = 'home'
            target_components = target_path[len('${HOME}/'):]
        else:
            raise SystemExit(1)
        source_components = source_dir
        if target['kind'] == 'file':
            source_components += '/' + target_components.rsplit('/', 1)[-1]
        print('\t'.join((
            report_tool,
            target['label'],
            target['kind'],
            role,
            target_components,
            source_components,
            str(source_section_count),
            str(source_role_count),
        )))
PY
}

m3_context_bind() {
  local dispatch_context_json="${1-}"
  local expected_mode="$2"
  [[ $# -eq 2 && -n "$dispatch_context_json" ]] || return 64
  python3 - "$dispatch_context_json" "$expected_mode" <<'PY'
import hashlib
import json
import re
import sys

raw, expected_mode = sys.argv[1:3]
try:
    if raw.encode('ascii').decode('ascii') != raw:
        raise ValueError('non-ascii')
    context = json.loads(raw)
except Exception:
    raise SystemExit(64)
if not isinstance(context, dict):
    raise SystemExit(64)
canonical = json.dumps(context, sort_keys=True, separators=(',', ':'), ensure_ascii=True)
if canonical != raw or context.get('schema') != 'agency-agents.m1-m3-dispatch-context/v1':
    raise SystemExit(64)
if context.get('mode') != expected_mode or not isinstance(context.get('testMode'), bool):
    raise SystemExit(64)
if not isinstance(context.get('restArgs'), list) or any(not isinstance(item, str) for item in context['restArgs']):
    raise SystemExit(64)
hex64 = re.compile(r'^[0-9a-f]{64}$')
for field in ('argvSha256', 'entrySha256'):
    if not isinstance(context.get(field), str) or not hex64.fullmatch(context[field]):
        raise SystemExit(64)
roles = {'testRoot':9,'entryExecution':10,'entryHash':11,'work':12,'backupWorkspace':13,'reportLeaf':14,'origin':15,'source':16,'project':17,'homeAuthority':18,'transactionParent':19,'evidenceRoot':20,'reportParent':21}
if context.get('fdRoles') != roles:
    raise SystemExit(64)
receipts = context.get('descriptorReceipts')
allowed_receipts = {10,11,15,16,17,18}
if context.get('testMode'):
    allowed_receipts.add(9)
if not isinstance(receipts, list) or {r.get('fd') for r in receipts if isinstance(r,dict)} != allowed_receipts or len(receipts) != len(allowed_receipts):
    raise SystemExit(64)
for receipt in receipts:
    if not isinstance(receipt, dict) or not isinstance(receipt.get('fd'), int) or receipt.get('fd') not in roles.values():
        raise SystemExit(64)
components = context.get('components')
if not isinstance(components, dict):
    raise SystemExit(64)
required = {'action','allowedSigners','entry','evidenceRoot','ledger','manifest','profiles','reportLeaf','reportParent','signature','source','transactionParent'}
if set(components) != required:
    raise SystemExit(64)
for name, value in components.items():
    if expected_mode == 'dry-run' and name in {'action','allowedSigners','evidenceRoot','ledger','reportLeaf','reportParent','signature','transactionParent'}:
        if value is not None:
            raise SystemExit(64)
        continue
    if expected_mode == 'apply' and name in {'reportLeaf','reportParent'} and value is None:
        continue
    if expected_mode == 'apply' and name == 'reportParent' and value == []:
        continue
    if expected_mode == 'apply' and context.get('testMode') is True and name == 'transactionParent' and value == []:
        continue
    if not isinstance(value, list) or not value or any(not isinstance(part, str) or not part or part in ('.','..') or '/' in part or '\x00' in part for part in value):
        raise SystemExit(64)
if expected_mode == 'apply':
    if (components['reportLeaf'] is None) != (components['reportParent'] is None):
        raise SystemExit(64)
    if components['reportLeaf'] is not None and len(components['reportLeaf']) != 1:
        raise SystemExit(64)
print('valid')
PY
  local rc=$?
  (( rc == 0 )) || return "$rc"
  M3_CONTEXT_JSON="$dispatch_context_json"
  M3_CONTEXT_MODE="$expected_mode"
  return 0
}

m3_context_component() {
  local name="$1"
  python3 - "$M3_CONTEXT_JSON" "$name" <<'PY'
import json
import sys
context, name = json.loads(sys.argv[1]), sys.argv[2]
value = context['components'][name]
print('/'.join(value))
PY
}

m3_context_entry_sha() {
  python3 - "$M3_CONTEXT_JSON" <<'PY'
import json,sys
print(json.loads(sys.argv[1])['entrySha256'])
PY
}

m3_context_receipts_check() {
  python3 - "$M3_CONTEXT_JSON" <<'PY'
import json
import os
import stat
import sys
c = json.loads(sys.argv[1])
allowed = {10,11,15,16,17,18}
if c.get('testMode'):
    allowed.add(9)
if {item.get('fd') for item in c['descriptorReceipts']} != allowed:
    if os.environ.get('AGENCY_TEST_AUTH_PREDICATE') == 'ledger-replay-v1':
        print('M3_RECEIPT_MISMATCH fd=table field=set', file=sys.stderr)
    raise SystemExit(1)
for receipt in c['descriptorReceipts']:
    fd = receipt['fd']
    try:
        s = os.fstat(fd)
    except OSError:
        raise SystemExit(1)
    actual = {'dev':s.st_dev,'ino':s.st_ino,'mode':stat.S_IMODE(s.st_mode),'uid':s.st_uid,'size':s.st_size,'mtime_ns':s.st_mtime_ns,'ctime_ns':s.st_ctime_ns}
    for key, value in receipt.items():
        if key == 'fd':
            continue
        if key in actual and actual[key] != value:
            if os.environ.get('AGENCY_TEST_AUTH_PREDICATE') == 'ledger-replay-v1':
                print('M3_RECEIPT_MISMATCH fd=%d field=%s' % (fd, key), file=sys.stderr)
            raise SystemExit(1)
print('valid')
PY
}

m3_internal_result() {
  local mode="$1" status="$2" primary_json="$3" rollback_json="$4" targets_json="$5" security_reason_code="${6:-null}"
  local secondary_close_failures_json="${M3_SECONDARY_CLOSE_FAILURES_JSON:-[]}"
  agency269_m3_result_json="$(MODE="$mode" STATUS="$status" PRIMARY="$primary_json" SECONDARY_CLOSE_FAILURES="$secondary_close_failures_json" ROLLBACK="$rollback_json" TARGETS="$targets_json" SECURITY_REASON_CODE="$security_reason_code" python3 - <<'PY'
import json,os
def value(name):
    return json.loads(os.environ[name])
security_reason_code=os.environ['SECURITY_REASON_CODE']
security_reason_code=None if security_reason_code=='null' else security_reason_code
if security_reason_code is not None and security_reason_code not in {'action-replay-detected','isolated-test-security-root-layout-invalid','ledger-write-failed'}:
    raise SystemExit(1)
print(json.dumps({
    'schema':'agency-agents.m3-result/v2',
    'mode':os.environ['MODE'],
    'status':os.environ['STATUS'],
    'primary':value('PRIMARY'),
    'secondaryCloseFailures':value('SECONDARY_CLOSE_FAILURES'),
    'securityReasonCode':security_reason_code,
    'rollback':value('ROLLBACK'),
    'targets':value('TARGETS'),
}, sort_keys=True, separators=(',', ':')))
PY
)" 2>/dev/null
}

m3_primary_from_diagnostic() {
  local diagnostic="$1" fallback_stage="$2" fallback_operation="$3" fallback_reason="$4" actual_rc="$5"
  local line stage="$fallback_stage" operation="$fallback_operation" reason="$fallback_reason"
  while IFS= read -r line; do
    if [[ "$line" =~ M3_FAILURE[[:space:]]stage=([^[:space:]]+)[[:space:]]operation=([^[:space:]]+)[[:space:]]reason=([^[:space:]]+)[[:space:]]rc=([0-9]+) ]]; then
      stage="${BASH_REMATCH[1]}"
      operation="${BASH_REMATCH[2]}"
      reason="${BASH_REMATCH[3]}"
    fi
  done <<< "$diagnostic"
  STAGE="$stage" OPERATION="$operation" REASON="$reason" ACTUAL_RC="$actual_rc" python3 - <<'PY'
import json,os
print(json.dumps({
    'module':'M3',
    'stage':os.environ['STAGE'],
    'operation':os.environ['OPERATION'],
    'reason':os.environ['REASON'],
    'originalRc':int(os.environ['ACTUAL_RC']),
},sort_keys=True,separators=(',',':')))
PY
}

m3_apply_rollback_journals() {
  local primary="$1"
  shift
  local close_seam=''
  if [[ "${1-}" == rollback-target-parent-close ]]; then close_seam="$1"; shift; fi
  local index=$# rollback_rc=0 rollback_result current_rc
  M3_ROLLBACK_PERFORMED=true
  M3_ROLLBACK_ENTRIES_JSON='[]'
  M3_ROLLBACK_FAILURES_JSON='[]'
  M3_ROLLBACK_ATTEMPTED=0
  M3_ROLLBACK_RESTORED=0
  while (( index > 0 )); do
    set +e
    rollback_result="$(m3_tx_rollback "${!index}" "$close_seam")"
    current_rc=$?
    set -e
    if (( current_rc != 0 )); then
      (( rollback_rc == 0 )) && rollback_rc=$current_rc
      if [[ -z "$rollback_result" ]]; then
        M3_ROLLBACK_FAILURES_JSON="$(python3 - "$M3_ROLLBACK_FAILURES_JSON" "$current_rc" <<'PY'
import json,sys
items=json.loads(sys.argv[1])
items.append({'id':'rollback','operation':'transaction-rollback','reason':'rollback-failed','originalRc':int(sys.argv[2])})
print(json.dumps(items,sort_keys=True,separators=(',',':')))
PY
        )"
      fi
    fi
    if [[ -n "$rollback_result" ]]; then
      local result_json="$rollback_result"
      M3_ROLLBACK_ENTRIES_JSON="$(python3 - "$M3_ROLLBACK_ENTRIES_JSON" "$result_json" <<'PY'
import json,sys
items=json.loads(sys.argv[1]); result=json.loads(sys.argv[2])
items.extend(result.get('entries',[]))
print(json.dumps(items,sort_keys=True,separators=(',',':')))
PY
)"
      M3_ROLLBACK_FAILURES_JSON="$(python3 - "$M3_ROLLBACK_FAILURES_JSON" "$result_json" <<'PY'
import json,sys
items=json.loads(sys.argv[1]); result=json.loads(sys.argv[2])
items.extend(result.get('restoreFailures',[]))
print(json.dumps(items,sort_keys=True,separators=(',',':')))
PY
)"
      M3_ROLLBACK_RESTORED=$((M3_ROLLBACK_RESTORED + $(python3 - "$result_json" <<'PY'
import json,sys
print(int(json.loads(sys.argv[1]).get('restored',0)))
PY
)))
      if [[ "$close_seam" == rollback-target-parent-close && "$current_rc" == "$RC_PRIMARY_WITH_SECONDARY_CLOSE_FAILED" ]]; then
        M3_SECONDARY_CLOSE_FAILURES_JSON="$(python3 - "$result_json" <<'PY'
import json,sys
value=json.loads(sys.argv[1])
items=value.get('secondaryCloseFailures')
if not isinstance(items,list) or len(items)!=1:
    raise SystemExit(1)
print(json.dumps(items,sort_keys=True,separators=(',',':')))
PY
)" || return "$RC_PRIMARY_WITH_SECONDARY_CLOSE_FAILED"
      fi
    fi
    index=$((index - 1))
  done
  M3_ROLLBACK_ATTEMPTED="$(python3 - "$M3_ROLLBACK_ENTRIES_JSON" <<'PY'
import json,sys
print(len(json.loads(sys.argv[1])))
PY
)"
  (( rollback_rc != 0 )) && return "$rollback_rc"
  return 0
}

m3_apply_failure_report() {
  local stage="$1" operation="$2" reason="$3" rc="$4"
  local targets_json="${5:-[]}" security_reason_code="${6:-null}"
  local final_rc="${7:-$rc}"
  local primary
  primary="$(python3 - "$stage" "$operation" "$reason" "$rc" <<'PY'
import json,sys
print(json.dumps({'module':'M3','stage':sys.argv[1],'operation':sys.argv[2],'reason':sys.argv[3],'originalRc':int(sys.argv[4])}, sort_keys=True, separators=(',', ':')))
PY
)" || return "$rc"
  local rollback
  rollback="$(python3 - "${M3_ROLLBACK_PERFORMED:-false}" "${M3_ROLLBACK_ATTEMPTED:-0}" "${M3_ROLLBACK_RESTORED:-0}" "${M3_ROLLBACK_FAILURES_JSON:-[]}" "${M3_ROLLBACK_ENTRIES_JSON:-[]}" <<'PY'
import json,sys
print(json.dumps({'performed':sys.argv[1]=='true','attempted':int(sys.argv[2]),'restored':int(sys.argv[3]),'restoreFailures':json.loads(sys.argv[4]),'entries':json.loads(sys.argv[5])}, sort_keys=True, separators=(',', ':')))
PY
)" || return "$rc"
  m3_internal_result apply failed "$primary" "$rollback" "$targets_json" "$security_reason_code"
  return "$final_rc"
}

m3_auth_claims_from_context() {
  [[ $# -ge 2 ]] || return 64
  local context="$1" manifest_result="$2"
  shift 2
  python3 - "$context" "$manifest_result" -- "$@" <<'PY'
import hashlib,json,re,sys
context_raw,manifest_raw=sys.argv[1:3]
if sys.argv[3] != '--': raise SystemExit(64)
argv=sys.argv[4:]
try:
    context=json.loads(context_raw); manifest=json.loads(manifest_raw)
except Exception:
    raise SystemExit(64)
canonical=lambda value:json.dumps(value,ensure_ascii=True,sort_keys=True,separators=(',',':'))
if canonical(context)!=context_raw or context.get('argvSha256')!=hashlib.sha256(b'\0'.join(item.encode('utf-8','surrogateescape') for item in argv)).hexdigest():
    raise SystemExit(64)
manifest_arg=None; test_root_arg=None; index=0
value_options={'--entry','--source','--source-root','--project','--home','--test-mode-root','--manifest','--json-report','--action-file','--auth-bytes','--signature-file','--auth-signature','--allowed-signers','--ledger','--principal','--namespace'}
while index < len(argv):
    item=argv[index]
    if item=='--': break
    if item in value_options:
        if index+1>=len(argv): raise SystemExit(64)
        value=argv[index+1]
        if item=='--manifest':
            if manifest_arg is not None: raise SystemExit(64)
            manifest_arg=value
        if item=='--test-mode-root':
            if test_root_arg is not None: raise SystemExit(64)
            test_root_arg=value
        index+=2; continue
    index+=1
def absolute_components(value):
    if not isinstance(value,str) or not value.startswith('/') or value=='/': raise SystemExit(64)
    parts=value.split('/')[1:]
    if any(not part or part in ('.','..') or '\x00' in part for part in parts): raise SystemExit(64)
    return parts
def resolve_from_manifest(relative):
    parts=absolute_components(manifest_arg)[:-1]
    if not isinstance(relative,str) or relative.startswith('/'): raise SystemExit(64)
    for part in relative.split('/'):
        if not part or part=='.' or '\x00' in part: raise SystemExit(64)
        if part=='..':
            if not parts: raise SystemExit(64)
            parts.pop()
        else:
            parts.append(part)
    return '/'+('/'.join(parts))
if manifest_arg is None: raise SystemExit(64)
source_root=resolve_from_manifest(manifest.get('source_root'))
role_set_path=resolve_from_manifest(manifest.get('role_set_path'))
test_mode=context.get('testMode') is True
if test_mode:
    absolute_components(test_root_arg)
elif test_root_arg is not None:
    raise SystemExit(64)
required={'source_root_count','source_root_digest','role_set_count','role_set_sha256','role_set_file_sha256','role_name_slug_digest'}
if any(key not in manifest for key in required): raise SystemExit(64)
claims={
    'role_name_slug_digest':manifest['role_name_slug_digest'],
    'role_set_count':manifest['role_set_count'],
    'role_set_file_sha256':manifest['role_set_file_sha256'],
    'role_set_path':role_set_path,
    'role_set_sha256':manifest['role_set_sha256'],
    'source_root':source_root,
    'source_root_count':manifest['source_root_count'],
    'source_root_digest':manifest['source_root_digest'],
    'test_mode':test_mode,
    'trust_root':test_root_arg if test_mode else None,
}
print(canonical(claims))
PY
}

m3_auth_validate_pre_auth() {
  [[ $# -eq 9 || $# -eq 10 ]] || return 64
  local action_name="$1" signature_name="$2" signer_name="$3" manifest_sha="$4" entry_sha="$5" source_sha="$6" principal="$7" namespace="$8" claims_raw="$9"
  local diagnostic_flag=off
  if [[ $# -eq 10 ]]; then
    diagnostic_flag="${10}"
  fi
  [[ "$diagnostic_flag" == off || "$diagnostic_flag" == on ]] || return 64
  python3 - "$action_name" "$signature_name" "$signer_name" "$manifest_sha" "$entry_sha" "$source_sha" "$principal" "$namespace" "$claims_raw" "$diagnostic_flag" <<'PY'
import fcntl,hashlib,json,os,re,stat,subprocess,sys

if len(sys.argv) != 11:
    if os.environ.get('AGENCY_TEST_AUTH_PREDICATE') == 'ledger-replay-v1':
        print('M3_AUTH_ARGC_CLASS=' + ('short' if len(sys.argv) < 11 else 'long'), file=sys.stderr)
    raise SystemExit(100)
action_name,signature_name,signer_name,manifest_sha,entry_sha,source_sha,principal,namespace,claims_raw,diagnostic_flag=sys.argv[1:]

class Failure(Exception):
    def __init__(self,stage,operation,reason,rc,diagnostic_code,security_reason=None):
        self.stage=stage; self.operation=operation; self.reason=reason; self.rc=rc; self.diagnostic_code=diagnostic_code; self.security_reason=security_reason

class CloseOnly(Exception):
    pass

def fail(reason,rc,operation='authorization-validation',diagnostic_code=87,security_reason=None):
    raise Failure('authorization-validation',operation,reason,rc,diagnostic_code,security_reason)

def exit_rc(diagnostic_code,semantic_rc):
    return diagnostic_code if diagnostic_flag == 'on' else semantic_rc

def diag(stage):
    if diagnostic_flag == 'on':
        print('M3_AUTH_INNER_STAGE=' + stage, file=sys.stderr)

def components(value,diagnostic_code):
    parts=value.split('/')
    if not parts or any(not p or p in ('.','..') or '/' in p or '\x00' in p for p in parts):
        fail('authorization-validation-failed',46,diagnostic_code=diagnostic_code)
    return parts

owned=[]
close_failures=[]

def close_one(fd,role):
    if fd is None: return
    try: os.close(fd)
    except OSError as exc: close_failures.append({'code':'E_DESCRIPTOR_CLOSE','ownerModule':'M3','role':role,'errno':exc.errno})

def open_owned_at_least_23(name,flags,role,current,diagnostic_code):
    raw=None; promoted=None
    try:
        raw=os.open(name,flags|os.O_CLOEXEC,dir_fd=current)
        promoted=fcntl.fcntl(raw,fcntl.F_DUPFD_CLOEXEC,23)
    except OSError:
        if raw is not None:
            close_one(raw,role+'-raw')
        fail('authorization-validation-failed',46,diagnostic_code=diagnostic_code,security_reason='isolated-test-security-root-layout-invalid' if role.endswith('-parent') else None)
    close_one(raw,role+'-raw')
    if close_failures:
        close_one(promoted,role+'-promoted')
        raise CloseOnly()
    return promoted

def open_relative(value,role):
    current=18; parents=[]
    diagnostic_code={'authorization-action':82,'authorization-signature':83,'authorization-allowed-signers':84}[role]
    try:
        parts=components(value,diagnostic_code)
        for part in parts[:-1]:
            current=open_owned_at_least_23(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,role+'-parent',current,diagnostic_code)
            parents.append(current); owned.append((current,role+'-parent'))
        fd=open_owned_at_least_23(parts[-1],os.O_RDONLY|os.O_NOFOLLOW,role,current,diagnostic_code)
        owned.append((fd,role)); return fd
    except OSError: fail('authorization-validation-failed',46,diagnostic_code=diagnostic_code)

def owner_regular(fd,diagnostic_code,require_private=False):
    st=os.fstat(fd)
    mode=stat.S_IMODE(st.st_mode)
    if not stat.S_ISREG(st.st_mode) or st.st_uid != os.geteuid() or mode&0o022 or (require_private and mode&0o077):
        fail('authorization-validation-failed',47,diagnostic_code=diagnostic_code)

def read_stable(fd):
    before=os.fstat(fd); data=bytearray(); offset=0
    while True:
        block=os.pread(fd,131072,offset)
        if not block: break
        data.extend(block); offset+=len(block)
    after=os.fstat(fd)
    fields=lambda st:(st.st_dev,st.st_ino,st.st_mode,st.st_uid,st.st_nlink,st.st_size,st.st_mtime_ns,st.st_ctime_ns)
    if fields(before)!=fields(after): fail('authorization-validation-failed',48,diagnostic_code=85)
    return bytes(data)

primary=None; result=None
try:
    try:
        claims=json.loads(claims_raw)
    except json.JSONDecodeError:
        fail('authorization-validation-failed',48,diagnostic_code=80)
    claim_keys={'source_root','source_root_count','source_root_digest','role_set_path','role_set_count','role_set_sha256','role_set_file_sha256','role_name_slug_digest','test_mode','trust_root'}
    if not isinstance(claims,dict) or set(claims)!=claim_keys or json.dumps(claims,ensure_ascii=True,sort_keys=True,separators=(',',':'))!=claims_raw:
        fail('authorization-validation-failed',48,diagnostic_code=81)
    diag('claims-ok')
    action_fd=open_relative(action_name,'authorization-action')
    diag('action-open-ok')
    signature_fd=open_relative(signature_name,'authorization-signature')
    diag('signature-open-ok')
    signer_fd=open_relative(signer_name,'authorization-allowed-signers')
    diag('signer-open-ok')
    owner_regular(action_fd,82); diag('action-owner-ok')
    owner_regular(signature_fd,83); diag('signature-owner-ok')
    owner_regular(signer_fd,84); diag('signer-owner-ok')
    action=read_stable(action_fd); signature=read_stable(signature_fd); signer_bytes=read_stable(signer_fd)
    diag('read-ok')
    for fd in (signature_fd,signer_fd): os.set_inheritable(fd,True)
    verified=subprocess.run(['ssh-keygen','-Y','verify','-f','/dev/fd/%d'%signer_fd,'-I',principal,'-n',namespace,'-s','/dev/fd/%d'%signature_fd],input=action,stdout=subprocess.PIPE,stderr=subprocess.PIPE,pass_fds=(signature_fd,signer_fd),check=False)
    if verified.returncode != 0: fail('authorization-validation-failed',49,'detached-signature',88)
    diag('signature-verify-ok')
    def strict_object(pairs):
        value={}
        for key,item in pairs:
            if key in value: fail('authorization-validation-failed',48,diagnostic_code=86)
            value[key]=item
        return value
    try:
        action_text=action.decode('ascii'); action_value=json.loads(action_text,object_pairs_hook=strict_object)
    except (UnicodeDecodeError,json.JSONDecodeError): fail('authorization-validation-failed',48,diagnostic_code=86)
    base_keys={'kind','namespace','principal','frozen_action_digest','entrypoint_sha','allowed_signers_digest','source_root','source_root_count','source_root_digest','role_set_path','role_set_count','role_set_sha256','role_set_file_sha256','role_name_slug_digest','timestamp'}
    optional_keys={'mode','trust_root'}
    if not isinstance(action_value,dict) or set(action_value) not in (base_keys,base_keys|optional_keys):
        fail('authorization-validation-failed',48,diagnostic_code=87)
    sha_fields={'frozen_action_digest','entrypoint_sha','allowed_signers_digest','source_root_digest','role_set_sha256','role_set_file_sha256','role_name_slug_digest'}
    if any(not isinstance(action_value.get(field),str) or not re.fullmatch(r'[0-9a-f]{64}',action_value[field]) for field in sha_fields):
        fail('authorization-validation-failed',48,diagnostic_code=87)
    string_fields={'kind','namespace','principal','source_root','role_set_path','timestamp'}
    if any(not isinstance(action_value.get(field),str) or not action_value[field] for field in string_fields): fail('authorization-validation-failed',48,diagnostic_code=87)
    if type(action_value.get('source_root_count')) is not int or type(action_value.get('role_set_count')) is not int:
        fail('authorization-validation-failed',48,diagnostic_code=87)
    if action_value['kind']!='supervisor.action-authorization/v1' or action_value['principal']!=principal or action_value['namespace']!=namespace:
        fail('authorization-validation-failed',48,diagnostic_code=87)
    if not re.fullmatch(r'[0-9a-f]{64}',manifest_sha):
        fail('authorization-validation-failed',48,diagnostic_code=89)
    if not re.fullmatch(r'[0-9a-f]{64}',entry_sha):
        fail('authorization-validation-failed',48,diagnostic_code=91)
    if action_value['frozen_action_digest']!=manifest_sha:
        fail('authorization-validation-failed',48,diagnostic_code=90)
    if action_value['entrypoint_sha']!=entry_sha:
        fail('authorization-validation-failed',48,diagnostic_code=91)
    if action_value['allowed_signers_digest']!=hashlib.sha256(signer_bytes).hexdigest():
        fail('authorization-validation-failed',48,diagnostic_code=92)
    if action_value['source_root']!=claims['source_root']:
        fail('authorization-validation-failed',48,diagnostic_code=93)
    diag('source-root-path-ok')
    if action_value['source_root_count']!=claims['source_root_count']:
        fail('authorization-validation-failed',48,diagnostic_code=93)
    diag('source-root-count-ok')
    if action_value['source_root_digest']!=source_sha:
        fail('authorization-validation-failed',48,diagnostic_code=93)
    diag('source-root-live-digest-ok')
    if action_value['source_root_digest']!=claims['source_root_digest']:
        fail('authorization-validation-failed',48,diagnostic_code=93)
    diag('source-root-claim-ok')
    if action_value['role_set_path']!=claims['role_set_path'] or action_value['role_set_count']!=claims['role_set_count'] or action_value['role_set_sha256']!=claims['role_set_sha256'] or action_value['role_set_file_sha256']!=claims['role_set_file_sha256'] or action_value['role_name_slug_digest']!=claims['role_name_slug_digest']:
        fail('authorization-validation-failed',48,diagnostic_code=94)
    if not re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z',action_value['timestamp']):
        fail('authorization-validation-failed',48,diagnostic_code=95)
    if claims['test_mode'] is True:
        if set(action_value)!=base_keys|optional_keys or action_value.get('mode')!='isolated-test' or action_value.get('trust_root')!=claims['trust_root']:
            fail('authorization-validation-failed',48,diagnostic_code=96)
    elif claims['test_mode'] is False:
        if set(action_value)!=base_keys or claims['trust_root'] is not None: fail('authorization-validation-failed',48,diagnostic_code=97)
    else:
        fail('authorization-validation-failed',48,diagnostic_code=97)
    result={'schema':'agency-agents.m3-pre-auth-validation/v1','authSha256':hashlib.sha256(action).hexdigest(),'entrySha256':entry_sha,'manifestSha256':manifest_sha,'namespace':namespace,'principal':principal,'sourceSha256':source_sha,'signatureSha256':hashlib.sha256(signature).hexdigest()}
except BaseException as exc:
    primary=exc
for fd,role in reversed(owned): close_one(fd,role)
if close_failures:
    if isinstance(primary,CloseOnly):
        print('M3_FAILURE stage=authorization-validation operation=authorization-validation reason=E_DESCRIPTOR_CLOSE rc=79 secondaryCloseFailures=%s'%json.dumps(close_failures,sort_keys=True,separators=(',',':')),file=sys.stderr); raise SystemExit(exit_rc(98,79))
    if isinstance(primary,Failure):
        print('M3_FAILURE stage=%s operation=%s reason=%s rc=78 primaryRc=%d secondaryCloseFailures=%s'%(primary.stage,primary.operation,primary.reason,primary.rc,json.dumps(close_failures,sort_keys=True,separators=(',',':'))),file=sys.stderr); raise SystemExit(exit_rc(primary.diagnostic_code,78))
    print('M3_FAILURE stage=authorization-validation operation=authorization-validation reason=E_DESCRIPTOR_CLOSE rc=79 secondaryCloseFailures=%s'%json.dumps(close_failures,sort_keys=True,separators=(',',':')),file=sys.stderr); raise SystemExit(exit_rc(99 if primary is not None else 98,79))
if isinstance(primary,Failure):
    suffix='' if primary.security_reason is None else ' securityReason='+primary.security_reason
    print('M3_FAILURE stage=%s operation=%s reason=%s rc=%d%s'%(primary.stage,primary.operation,primary.reason,primary.rc,suffix),file=sys.stderr); raise SystemExit(exit_rc(primary.diagnostic_code,primary.rc))
if primary is not None: raise SystemExit(exit_rc(99,46))
print(json.dumps(result,ensure_ascii=True,sort_keys=True,separators=(',',':')))
PY
}

m3_build_binder_request() {
  local context="$1" auth_sha="$2" entry_sha="$3"
  shift 3
  python3 - "$context" "$auth_sha" "$entry_sha" -- "$@" <<'PY'
import hashlib,json,re,sys
raw,auth_sha,entry_sha=sys.argv[1:4]
if sys.argv[4] != '--': raise SystemExit(72)
try: raw.encode('ascii'); context=json.loads(raw)
except Exception: raise SystemExit(72)
canonical=lambda value:json.dumps(value,ensure_ascii=True,sort_keys=True,separators=(',',':'))
if canonical(context)!=raw or not re.fullmatch(r'[0-9a-f]{64}',auth_sha) or not re.fullmatch(r'[0-9a-f]{64}',entry_sha): raise SystemExit(72)
components=context['components']
request={'authSha256':auth_sha,'dispatchContext':raw,'dispatchContextSha256':hashlib.sha256(raw.encode('ascii')).hexdigest(),'entrySha256':entry_sha,'evidenceRootComponents':components['evidenceRoot'],'fdRoles':context['fdRoles'],'originalArgv':sys.argv[5:],'reportLeafComponents':components['reportLeaf'],'reportParentComponents':components['reportParent'],'schema':'agency-agents.m2-post-auth-reexec-request/v1','testMode':context['testMode'],'transactionParentComponents':components['transactionParent']}
print(canonical(request))
PY
}

m3_post_auth_validate() {
  [[ $# -eq 4 ]] || return 67
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import hashlib,json,os,stat,sys
context_raw,origin_raw,child_pid_raw,parent_pid_raw=sys.argv[1:]
CONTEXT_KEYS={'argvSha256','components','descriptorReceipts','entrySha256','fdRoles','mode','restArgs','schema','testMode'}
COMPONENT_KEYS={'action','allowedSigners','entry','evidenceRoot','ledger','manifest','profiles','reportLeaf','reportParent','signature','source','transactionParent'}
RESULT_KEYS={'authSha256','bindingSha256','childPid','childRc','descriptorReceipts','dispatchContextSha256','parentPid','phase','primary','reportOwnership','schema','status'}
RECEIPT_KEYS={'ctimeNs','dev','fd','ino','mode','mtimeNs','nlink','role','size','type','uid'}
ROLES={'testRoot':9,'entryExecution':10,'entryHash':11,'work':12,'backupWorkspace':13,'reportLeaf':14,'origin':15,'source':16,'project':17,'homeAuthority':18,'transactionParent':19,'evidenceRoot':20,'reportParent':21}
canonical=lambda value:json.dumps(value,ensure_ascii=True,sort_keys=True,separators=(',',':'))
digest=lambda value:hashlib.sha256(value.encode('ascii')).hexdigest()
def is_digest(value): return isinstance(value,str) and len(value)==64 and all(c in '0123456789abcdef' for c in value)
def kind(mode):
    if stat.S_ISDIR(mode): return 'directory'
    if stat.S_ISREG(mode): return 'regular'
    if stat.S_ISSOCK(mode): return 'socket'
    return 'other'
def receipt(fd,role):
    first=os.fstat(fd); second=os.fstat(fd)
    stable=lambda st:(st.st_dev,st.st_ino,st.st_mode,st.st_uid,st.st_nlink,st.st_size,st.st_mtime_ns,st.st_ctime_ns)
    if stable(first)!=stable(second): raise ValueError('receipt drift')
    return {'ctimeNs':first.st_ctime_ns,'dev':first.st_dev,'fd':fd,'ino':first.st_ino,'mode':stat.S_IMODE(first.st_mode),'mtimeNs':first.st_mtime_ns,'nlink':first.st_nlink,'role':role,'size':first.st_size,'type':kind(first.st_mode),'uid':first.st_uid}
try:
    if not child_pid_raw.isdigit() or not parent_pid_raw.isdigit() or child_pid_raw=='0' or parent_pid_raw=='0': raise ValueError('binding')
    child_pid=int(child_pid_raw); parent_pid=int(parent_pid_raw)
    context_raw.encode('ascii'); origin_raw.encode('ascii'); context=json.loads(context_raw); origin=json.loads(origin_raw)
    if canonical(context)!=context_raw or set(context)!=CONTEXT_KEYS or context.get('schema')!='agency-agents.m1-m3-dispatch-context/v1' or context.get('mode')!='apply' or context.get('fdRoles')!=ROLES or set(context.get('components',{}))!=COMPONENT_KEYS: raise ValueError('context')
    if canonical(origin)!=origin_raw or set(origin)!=RESULT_KEYS or origin.get('schema')!='agency-agents.m2-post-auth-origin-result/v1' or origin.get('phase')!='child-finalized' or origin.get('status')!='passed' or origin.get('reportOwnership')!='child' or origin.get('childRc')!=0 or origin.get('primary') is not None: raise ValueError('origin')
    context_sha=digest(context_raw)
    if origin.get('dispatchContextSha256')!=context_sha or origin.get('childPid')!=child_pid or origin.get('parentPid')!=parent_pid or os.environ.get('AGENCY269_POST_AUTH_CHILD_PID')!=child_pid_raw or os.environ.get('AGENCY269_POST_AUTH_PARENT_PID')!=parent_pid_raw or not is_digest(origin.get('authSha256')) or not is_digest(origin.get('bindingSha256')): raise ValueError('binding')
    if os.environ.get('AGENCY269_POST_AUTH_CONTEXT_SHA256')!=context_sha or os.environ.get('AGENCY269_POST_AUTH_AUTH_SHA256')!=origin['authSha256'] or os.environ.get('POST_AUTH_DESCRIPTOR_BOUND')!='v1' or os.environ.get('AGENCY269_REEXEC')!='1': raise ValueError('phase')
    initial_fds=[9,10,11,15,16,17,18] if context['testMode'] else [10,11,15,16,17,18]
    initial=context['descriptorReceipts']
    if not isinstance(initial,list) or [item.get('fd') for item in initial]!=initial_fds or any(not isinstance(item,dict) or set(item)!=RECEIPT_KEYS for item in initial): raise ValueError('initial receipts')
    roles={fd:role for role,fd in ROLES.items()}
    for item in initial:
        if item['fd']==15:
            if item['role']!='origin' or item['type']!='socket': raise ValueError('initial origin')
        elif context.get('testMode') and (item['dev'],item['ino'])==(initial[0]['dev'],initial[0]['ino']):
            current=receipt(item['fd'],roles[item['fd']]); stable=('dev','ino','type','uid','mode')
            if any(item[field]!=current[field] for field in stable) or current['nlink']!=item['nlink']+2: raise ValueError('initial receipt drift')
        elif item!=receipt(item['fd'],roles[item['fd']]): raise ValueError('initial receipt drift')
    expected=[10,11,12,13,15,16,17,18,19,20]
    if context['components']['reportParent'] is not None: expected.extend((14,21))
    expected.sort(); current=[receipt(fd,roles[fd]) for fd in expected]
    if origin.get('descriptorReceipts')!=current:
        frozen=origin.get('descriptorReceipts')
        if isinstance(frozen,list) and len(frozen)==len(current):
            for old,new in zip(frozen,current):
                if isinstance(old,dict) and isinstance(new,dict):
                    for field in sorted(RECEIPT_KEYS):
                        if old.get(field)!=new.get(field):
                            raise ValueError('origin-receipt-%s-%s'%(new.get('role','unknown'),field))
        raise ValueError('origin receipts')
    entry=hashlib.sha256(); offset=0
    while True:
        block=os.pread(11,131072,offset)
        if not block: break
        entry.update(block); offset+=len(block)
    if entry.hexdigest()!=context['entrySha256']: raise ValueError('entry digest')
    print(canonical({'authSha256':origin['authSha256'],'bindingSha256':origin['bindingSha256'],'dispatchContextSha256':context_sha,'schema':'agency-agents.m3-post-auth-validation/v1'}))
except BaseException as exc:
    if os.environ.get('AGENCY_TEST_BINDER_STAGE')=='ledger-replay-v1':
        reason=str(exc)
        allowed={'context','origin','binding','phase','initial receipts','initial origin','initial receipt drift','origin receipts','entry digest','receipt drift'}
        allowed|={'origin-receipt-%s-%s'%(role,field) for role in ROLES for field in RECEIPT_KEYS}
        print('M3_POST_AUTH_VALIDATE='+((reason if reason in allowed else 'unclassified').replace(' ','-')),file=sys.stderr)
    print('M3_FAILURE stage=transaction-origin-validation operation=transaction-origin-validation reason=transaction-launcher-origin-proof-failed rc=67',file=sys.stderr); raise SystemExit(67)
PY
}

m3_consume_ledger_post_auth() {
  [[ $# -eq 10 ]] || return 64
  python3 - "$@" <<'PY'
import fcntl,hashlib,json,os,stat,sys
ledger_name,auth_sha,context_sha,binding_sha,entry_sha,source_sha,manifest_sha,principal,namespace,race_mode=sys.argv[1:]
class Failure(Exception):
    def __init__(self,rc,security): self.rc=rc; self.security=security
def fail(rc,security): raise Failure(rc,security)
parts=ledger_name.split('/')
if not parts or any(not p or p in ('.','..') or '/' in p or '\x00' in p for p in parts): fail(50,'ledger components invalid')
if race_mode not in ('off','ledger-intermediate-after-stat-before-open'): fail(50,'ledger write failed')
owned=[]; close_failures=[]; primary=None; ledger_fd=None; result=None; prior_size=0; append_started=False; ledger_created=False
def close_one(fd,role):
    try: os.close(fd)
    except OSError as exc: close_failures.append({'code':'E_DESCRIPTOR_CLOSE','ownerModule':'M3','role':role,'errno':exc.errno})
try:
    current=18
    for part in parts[:-1]:
        before=os.stat(part,dir_fd=current,follow_symlinks=False)
        if not stat.S_ISDIR(before.st_mode) or before.st_uid!=os.geteuid(): fail(50,'ledger write failed')
        if race_mode=='ledger-intermediate-after-stat-before-open' and part=='nested':
            moved_original=False; moved_replacement=False; child=None
            try:
                os.rename('nested','.ledger-intermediate-old',src_dir_fd=current,dst_dir_fd=current)
                moved_original=True
                os.rename('.ledger-intermediate-replacement','nested',src_dir_fd=current,dst_dir_fd=current)
                moved_replacement=True
                os.fsync(current)
                child=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC,dir_fd=current)
                after=os.fstat(child)
                mismatch=(before.st_dev,before.st_ino)!=(after.st_dev,after.st_ino)
                if not mismatch: fail(50,'ledger write failed')
                os.rename('nested','.ledger-intermediate-replacement',src_dir_fd=current,dst_dir_fd=current)
                moved_replacement=False
                os.rename('.ledger-intermediate-old','nested',src_dir_fd=current,dst_dir_fd=current)
                moved_original=False
                os.fsync(current)
                print('LEDGER_INTERMEDIATE_RACE_HANDSHAKE requested=true authorized=true traversalReached=true preStatTaken=true replacementPerformed=true childOpened=true identityMismatchDetected=true blockedBeforeMutation=true',file=sys.stderr)
                fail(50,'ledger write failed')
            except Failure:
                raise
            except OSError:
                fail(50,'ledger write failed')
            finally:
                if child is not None: close_one(child,'ledger-race-child')
                if moved_replacement:
                    try: os.rename('nested','.ledger-intermediate-replacement',src_dir_fd=current,dst_dir_fd=current)
                    except OSError: close_failures.append({'code':'E_DESCRIPTOR_CLOSE','ownerModule':'M3','role':'ledger-race-restore','errno':0})
                if moved_original:
                    try: os.rename('.ledger-intermediate-old','nested',src_dir_fd=current,dst_dir_fd=current); os.fsync(current)
                    except OSError: close_failures.append({'code':'E_DESCRIPTOR_CLOSE','ownerModule':'M3','role':'ledger-race-restore','errno':0})
        child=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC,dir_fd=current)
        after=os.fstat(child)
        if (before.st_dev,before.st_ino,stat.S_IFMT(before.st_mode),before.st_uid)!=(after.st_dev,after.st_ino,stat.S_IFMT(after.st_mode),after.st_uid):
            close_one(child,'ledger-parent')
            fail(50,'ledger write failed')
        current=child; owned.append((current,'ledger-parent'))
    ledger_flags=os.O_RDWR|os.O_APPEND|os.O_NOFOLLOW|os.O_CLOEXEC
    try:
        ledger_fd=os.open(parts[-1],ledger_flags,dir_fd=current)
    except FileNotFoundError:
        try:
            ledger_fd=os.open(parts[-1],ledger_flags|os.O_CREAT|os.O_EXCL,0o600,dir_fd=current)
            ledger_created=True
            os.fsync(current)
        except FileExistsError:
            ledger_fd=os.open(parts[-1],ledger_flags,dir_fd=current)
    owned.append((ledger_fd,'authorization-ledger'))
    st=os.fstat(ledger_fd)
    if not stat.S_ISREG(st.st_mode) or st.st_uid!=os.geteuid() or stat.S_IMODE(st.st_mode)!=0o600 or st.st_nlink!=1: fail(50,'ledger ownership invalid')
    fcntl.flock(ledger_fd,fcntl.LOCK_EX)
    chunks=[]; offset=0
    while True:
        block=os.pread(ledger_fd,131072,offset)
        if not block: break
        chunks.append(block); offset+=len(block)
        if offset>=64*1024*1024: fail(50,'ledger size invalid')
    raw=b''.join(chunks)
    if raw and not raw.endswith(b'\n'): fail(50,'ledger canonical form invalid')
    prior_size=len(raw)
    for line in raw.splitlines():
        try: text=line.decode('ascii'); value=json.loads(text)
        except Exception: fail(50,'ledger canonical form invalid')
        if not isinstance(value,dict) or json.dumps(value,ensure_ascii=True,sort_keys=True,separators=(',',':'))!=text: fail(50,'ledger canonical form invalid')
        if value.get('action_digest')==auth_sha: fail(51,'action replay detected')
    record={'action_digest':auth_sha,'binding_sha256':binding_sha,'dispatch_context_sha256':context_sha,'entry_sha256':entry_sha,'frozen_action_digest':manifest_sha,'namespace':namespace,'principal':principal,'schema':'agency-agents.m3-ledger-consumption/v1','source_root_digest':source_sha}
    encoded=(json.dumps(record,ensure_ascii=True,sort_keys=True,separators=(',',':'))+'\n').encode('ascii')
    os.lseek(ledger_fd,0,os.SEEK_END); written=0; append_started=True
    while written<len(encoded):
        count=os.write(ledger_fd,encoded[written:])
        if count<=0: fail(50,'ledger append failed')
        written+=count
    os.fsync(ledger_fd); result={'schema':'agency-agents.m3-ledger-consumption-result/v1','actionSha256':auth_sha,'status':'consumed'}
except BaseException as exc: primary=exc
if primary is not None and append_started and ledger_fd is not None:
    try: os.ftruncate(ledger_fd,prior_size); os.fsync(ledger_fd)
    except OSError:
        if isinstance(primary,Failure): primary.security=primary.security+'; ledger append rollback failed'
        else: primary=Failure(50,'ledger append rollback failed')
if primary is not None and ledger_created and ledger_fd is not None:
    try:
        if os.fstat(ledger_fd).st_size!=0: raise OSError()
        os.unlink(parts[-1],dir_fd=current); os.fsync(current)
    except OSError:
        if isinstance(primary,Failure): primary.security=primary.security+'; ledger create rollback failed'
        else: primary=Failure(50,'ledger create rollback failed')
if ledger_fd is not None:
    try: fcntl.flock(ledger_fd,fcntl.LOCK_UN)
    except OSError:
        if primary is None: primary=Failure(50,'ledger unlock failed')
for fd,role in reversed(owned): close_one(fd,role)
if close_failures:
    if isinstance(primary,Failure):
        print('M3_FAILURE stage=authorization-validation operation=authorization-validation reason=authorization-validation-failed rc=78 primaryRc=%d securityReason=%s secondaryCloseFailures=%s'%(primary.rc,primary.security,json.dumps(close_failures,sort_keys=True,separators=(',',':'))),file=sys.stderr); raise SystemExit(78)
    print('M3_FAILURE stage=authorization-validation operation=authorization-validation reason=E_DESCRIPTOR_CLOSE rc=79 secondaryCloseFailures=%s'%json.dumps(close_failures,sort_keys=True,separators=(',',':')),file=sys.stderr); raise SystemExit(79)
if isinstance(primary,Failure):
    print('M3_FAILURE stage=authorization-validation operation=authorization-validation reason=authorization-validation-failed rc=%d securityReason=%s'%(primary.rc,primary.security),file=sys.stderr); raise SystemExit(primary.rc)
if primary is not None:
    if os.environ.get('AGENCY_TEST_BINDER_STAGE')=='ledger-replay-v1' and os.environ.get('AGENCY269_TEST_MODE')=='1':
        name=type(primary).__name__
        allowed={'FileNotFoundError','NotADirectoryError','PermissionError','IsADirectoryError','OSError'}
        print('M3_LEDGER_INTERNAL='+(name if name in allowed else 'unexpected'),file=sys.stderr)
    raise SystemExit(50)
print(json.dumps(result,ensure_ascii=True,sort_keys=True,separators=(',',':')))
PY
}

m3_apply_diagnostic_failure() {
  local diagnostic="$1" fallback_stage="$2" fallback_operation="$3" fallback_reason="$4" actual_rc="$5" primary
  primary="$(m3_primary_from_diagnostic "$diagnostic" "$fallback_stage" "$fallback_operation" "$fallback_reason" "$actual_rc")" || return "$actual_rc"
  m3_internal_result apply failed "$primary" '{"performed":false,"attempted":0,"restored":0,"restoreFailures":[],"entries":[]}' '[]'
  return "$actual_rc"
}

m3_pre_auth_freeze_failure() {
  local diagnostic="$1" fallback_stage="$2" fallback_operation="$3" fallback_reason="$4" actual_rc="$5" security_reason_code="${6:-null}"
  agency269_m3_result_json="$(python3 - "$diagnostic" "$fallback_stage" "$fallback_operation" "$fallback_reason" "$actual_rc" "$security_reason_code" <<'PY'
import json,re,sys
diagnostic,stage,operation,reason,actual_rc,security_reason_code=sys.argv[1:]
for line in diagnostic.splitlines():
    match=re.search(r'M3_FAILURE\s+stage=([^\s]+)\s+operation=([^\s]+)\s+reason=([^\s]+)\s+rc=([0-9]+)',line)
    if match:
        stage,operation,reason=match.group(1),match.group(2),match.group(3)
security_reason_code=None if security_reason_code=='null' else security_reason_code
if security_reason_code is not None and security_reason_code not in {'action-replay-detected','isolated-test-security-root-layout-invalid','ledger-write-failed'}:
    raise SystemExit(1)
primary={'module':'M3','stage':stage,'operation':operation,'reason':reason,'originalRc':int(actual_rc)}
result={'mode':'apply','primary':primary,'rollback':{'performed':False,'attempted':0,'restored':0,'restoreFailures':[],'entries':[]},'schema':'agency-agents.m3-result/v2','secondaryCloseFailures':[],'securityReasonCode':security_reason_code,'status':'failed','targets':[]}
print(json.dumps(result,ensure_ascii=True,sort_keys=True,separators=(',',':')))
PY
)" 2>/dev/null
  return "$actual_rc"
}

m3_test_post_auth_diag_admit() {
  [[ ( "${AGENCY_TEST_AUTH_PREDICATE:-}" == ledger-replay-v1 || "${AGENCY_TEST_BINDER_STAGE:-}" == ledger-replay-v1 ) && "${AGENCY269_CONTEXT_SEALED:-}" == 1 && $# -eq 1 ]] || return 1
  python3 - "$1" <<'PY'
import json
import sys
raw=sys.argv[1]
try:
    raw.encode('ascii')
    context=json.loads(raw)
except Exception:
    raise SystemExit(1)
if json.dumps(context,ensure_ascii=True,sort_keys=True,separators=(',',':')) != raw:
    raise SystemExit(1)
if context.get('testMode') is not True:
    raise SystemExit(1)
PY
}

readonly RC_PRIMARY_WITH_SECONDARY_CLOSE_FAILED=78
readonly RC_DESCRIPTOR_CLOSE_FAILED=79

verify_test_root_identity_now() {
  [[ $# -eq 1 && "${AGENCY269_CONTEXT_SEALED:-}" == 1 ]] || return 1
  python3 - "$1" <<'PY'
import json,os,stat,sys
raw=sys.argv[1]
try:
    raw.encode('ascii')
    context=json.loads(raw)
    info=os.fstat(9)
except Exception:
    raise SystemExit(1)
if json.dumps(context,ensure_ascii=True,sort_keys=True,separators=(',',':'))!=raw or context.get('testMode') is not True:
    raise SystemExit(1)
receipts=context.get('descriptorReceipts')
matches=[item for item in receipts if isinstance(item,dict) and item.get('role')=='testRoot'] if isinstance(receipts,list) else []
if len(matches)!=1 or not stat.S_ISDIR(info.st_mode) or info.st_uid!=os.getuid() or stat.S_IMODE(info.st_mode)!=0o700:
    raise SystemExit(1)
receipt=matches[0]
if type(receipt.get('nlink')) is not int or receipt['nlink']<2 or info.st_nlink<receipt['nlink']:
    raise SystemExit(1)
expected={'dev':info.st_dev,'fd':9,'ino':info.st_ino,'mode':stat.S_IMODE(info.st_mode),'role':'testRoot','type':'directory','uid':info.st_uid}
if any(receipt.get(key)!=value for key,value in expected.items()):
    raise SystemExit(1)
PY
}

m3_test_descriptor_close_seam_admit() {
  [[ $# -eq 2 ]] || return 1
  local context="$1" seam="$2"
  [[ "${AGENCY_TEST_DESCRIPTOR_CLOSE_FAILURE:-}" == "$seam" ]] || return 1
  case "$seam" in
    owner-stage-parent-close) ;;
    rollback-target-parent-close)
      [[ "${AGENCY_TEST_FAULT_STAGE:-}" == post-owner-install && "${AGENCY_TEST_FAULT_TARGET:-}" == kimi ]] || return 1
      ;;
    *) return 1 ;;
  esac
  verify_test_root_identity_now "$context"
}

m3_test_fault_seam_admit() {
  [[ $# -eq 1 && "${AGENCY_TEST_FAULT_STAGE:-}" == post-owner-install && "${AGENCY_TEST_FAULT_TARGET:-}" == kimi && "${AGENCY269_CONTEXT_SEALED:-}" == 1 ]] || return 1
  python3 - "$1" <<'PY'
import json,os,stat,sys
raw=sys.argv[1]
try:
    raw.encode('ascii')
    context=json.loads(raw)
except Exception:
    raise SystemExit(1)
if json.dumps(context,ensure_ascii=True,sort_keys=True,separators=(',',':'))!=raw or context.get('testMode') is not True:
    raise SystemExit(1)
receipts=context.get('descriptorReceipts')
matches=[item for item in receipts if isinstance(item,dict) and item.get('role')=='testRoot'] if isinstance(receipts,list) else []
if not isinstance(receipts,list):
    raise SystemExit(1)
if len(matches)!=1:
    raise SystemExit(1)
receipt=matches[0]
try:
    info=os.fstat(9)
except OSError:
    raise SystemExit(1)
if not stat.S_ISDIR(info.st_mode) or info.st_uid!=os.getuid() or stat.S_IMODE(info.st_mode)!=0o700:
    raise SystemExit(1)
if type(receipt.get('nlink')) is not int or receipt['nlink'] < 2 or info.st_nlink < receipt['nlink']:
    raise SystemExit(1)
expected={'dev':info.st_dev,'fd':9,'ino':info.st_ino,'mode':stat.S_IMODE(info.st_mode),'role':'testRoot','type':'directory','uid':info.st_uid}
for key,value in expected.items():
    if receipt.get(key)!=value:
        raise SystemExit(1)
PY
}

m3_test_post_auth_predicate_emit() {
  local code="${1-}" phase="${2:-post-auth}" predicate
  [[ "$phase" == pre-auth || "$phase" == post-auth ]] || return 0
  [[ "${m3_post_auth_diag_admitted:-0}" == 1 ]] || return 0
  case "$code" in
    80) predicate=claims-json ;;
    81) predicate=claims-schema ;;
    82) predicate=open-action ;;
    83) predicate=open-signature ;;
    84) predicate=open-signers ;;
    85) predicate=read-inputs ;;
    86) predicate=action-json ;;
    87) predicate=action-schema ;;
    88) predicate=signature-verify ;;
    89) predicate=manifest-sha ;;
    90) predicate=frozen-action-digest ;;
    91) predicate=entry-sha ;;
    92) predicate=allowed-signers-digest ;;
    93) predicate=source-root ;;
    94) predicate=role-set ;;
    95) predicate=timestamp ;;
    96) predicate=isolated-mode ;;
    97) predicate=production-mode ;;
    98) predicate=descriptor-close ;;
    99) predicate=internal ;;
    100) predicate=result-parse ;;
    *) return 0 ;;
  esac
  printf 'AGENCY269_AUTH_PREDICATE=%s\n' "$predicate" >&2
  printf 'AGENCY269_AUTH_PHASE=%s\n' "$phase" >&2
}

m3_test_post_auth_phase_emit() {
  local phase="${1-}"
  [[ "${AGENCY_TEST_BINDER_STAGE:-}" == ledger-replay-v1 && "${AGENCY269_TEST_MODE:-0}" == 1 ]] || return 0
  case "$phase" in
    post-claims|post-auth-failed|post-auth-ok|post-result-parse|post-binding|post-ledger) printf 'AGENCY269_AUTH_PHASE=%s\n' "$phase" >&2 ;;
  esac
}

m3_test_pre_auth_stage_diag() {
  local stage="${1-}"
  [[ "${AGENCY_TEST_AUTH_PREDICATE:-}" == ledger-replay-v1 ]] || return 0
  case "$stage" in pre-enter|context-ok|receipts-ok|components-ok|signer-ok|manifest-ok|source-ok|entry-ok|claims-ok|auth-ok|request-ok|binder-call) ;; *) return 0 ;; esac
  printf 'M3_PRE_AUTH_STAGE=%s\n' "$stage" >&2
}

m3_test_ledger_diag_admit() {
  [[ $# -eq 2 && "${AGENCY269_CONTEXT_SEALED:-}" == 1 ]] || return 1
  local context="$1" phase="$2"
  [[ "$phase" == pre-auth || "$phase" == post-auth ]] || return 1
  python3 - "$context" "$phase" <<'PY'
import json,os,stat,sys
try:
    context=json.loads(sys.argv[1]); phase=sys.argv[2]
    if context.get('testMode') is not True: raise ValueError()
    receipts=context.get('descriptorReceipts')
    if not isinstance(receipts,list): raise ValueError()
    matches=[item for item in receipts if isinstance(item,dict) and item.get('fd')==9 and item.get('role')=='testRoot']
    if len(matches)!=1: raise ValueError()
    frozen=matches[0]; current=os.fstat(9)
    if not stat.S_ISDIR(current.st_mode) or current.st_uid!=os.geteuid() or stat.S_IMODE(current.st_mode)!=0o700:
        raise ValueError()
    expected={'dev':current.st_dev,'ino':current.st_ino,'type':'directory','uid':current.st_uid,'mode':0o700}
    if any(frozen.get(key)!=value for key,value in expected.items()): raise ValueError()
    if not isinstance(frozen.get('nlink'),int) or frozen['nlink']<2 or current.st_nlink<frozen['nlink']:
        raise ValueError()
except Exception:
    raise SystemExit(1)
PY
}

m3_ledger_layout_valid() {
  [[ $# -eq 1 ]] || return 1
  python3 - "$1" <<'PY'
import sys
value=sys.argv[1]
parts=value.split('/')
if not parts or any(not part or part in ('.','..') or '/' in part or '\x00' in part for part in parts):
    raise SystemExit(1)
if len(parts)<3 or parts[:2]!=['.codex','supervisor-authority']:
    raise SystemExit(1)
PY
}

m3_test_d1_audit_emit() {
  [[ $# -eq 4 && "${SYNC_PROTECTED_ACCESS_AUDIT:-}" == 1 ]] || return 1
  local context="$1" phase="$2" requested="$3" relative="$4"
  [[ "$requested" == true || "$requested" == false ]] || return 1
  if [[ "$requested" == true ]]; then
    [[ "$relative" == main || "$relative" == main/agent/auth-profiles.json ]] || return 1
  else
    [[ "$relative" == .openclaw/agency-agents ]] || return 1
  fi
  m3_test_ledger_diag_admit "$context" "$phase" >/dev/null 2>&1 || return 1
  python3 - "$requested" "$relative" <<'PY'
import json,os,stat,sys
requested=sys.argv[1]=='true'; relative=sys.argv[2]
fd=None
try:
    fd=os.open('.d1-protected-access-audit',os.O_WRONLY|os.O_APPEND|os.O_NOFOLLOW|os.O_CLOEXEC,dir_fd=9)
    before=os.fstat(fd)
    if not stat.S_ISREG(before.st_mode) or before.st_uid!=os.geteuid() or stat.S_IMODE(before.st_mode)!=0o600 or before.st_nlink!=1:
        raise OSError()
    handshake={'event':'d1-injection-handshake','injectionAuthorized':requested,'injectionHit':requested,'injectionReachedOwnerPlanBoundary':True,'injectionRequested':requested,'requestedRelAllowlisted':requested}
    rows=[{'event':'owner-access','relative':relative},handshake]
    data=''.join(json.dumps(row,ensure_ascii=True,sort_keys=True,separators=(',',':'))+'\n' for row in rows).encode('ascii')
    offset=0
    while offset<len(data):
        count=os.write(fd,data[offset:])
        if count<=0: raise OSError()
        offset+=count
    os.fsync(fd)
    after=os.fstat(fd)
    stable=lambda value:(value.st_dev,value.st_ino,stat.S_IFMT(value.st_mode),value.st_uid,stat.S_IMODE(value.st_mode),value.st_nlink)
    if stable(before)!=stable(after) or after.st_size!=before.st_size+len(data): raise OSError()
except OSError:
    raise SystemExit(79)
finally:
    if fd is not None:
        try: os.close(fd)
        except OSError: raise SystemExit(79)
PY
}

agency269_m3_apply_pre_auth() {
  local context="${1-}" diagnostic rc manifest profiles action signature signer ledger manifest_result manifest_sha source_sha entry_sha actual_entry auth_claims auth_result auth_sha request
  local m3_post_auth_diag_admitted=0
  local auth_diag_option=off
  agency269_m3_result_json=''
  m3_test_pre_auth_stage_diag pre-enter
  [[ $# -eq 1 ]] || { m3_pre_auth_freeze_failure '' context-validation dispatch-context invalid-context 64; return $?; }
  m3_context_bind "$context" apply >/dev/null 2>&1 || { m3_pre_auth_freeze_failure '' context-validation dispatch-context invalid-context 64; return $?; }
  m3_test_pre_auth_stage_diag context-ok
  m3_context_receipts_check >/dev/null || { m3_pre_auth_freeze_failure '' context-validation descriptor-receipts receipt-mismatch 64; return $?; }
  m3_test_pre_auth_stage_diag receipts-ok
  if [[ "${AGENCY_TEST_BINDER_STAGE:-}" == ledger-replay-v1 ]] && m3_test_post_auth_diag_admit "$context" >/dev/null 2>&1; then
    m3_post_auth_diag_admitted=1
  fi
  manifest="$(m3_context_component manifest 2>/dev/null)" && profiles="$(m3_context_component profiles 2>/dev/null)" && action="$(m3_context_component action 2>/dev/null)" && signature="$(m3_context_component signature 2>/dev/null)" && signer="$(m3_context_component allowedSigners 2>/dev/null)" && ledger="$(m3_context_component ledger 2>/dev/null)" || { m3_pre_auth_freeze_failure '' context-validation components component-bind-failed 64; return $?; }
  m3_test_pre_auth_stage_diag components-ok
  [[ "$signer" == '.codex/supervisor-authority/allowed_signers' ]] || { m3_pre_auth_freeze_failure '' authorization-validation authorization-validation authorization-validation-failed 46 isolated-test-security-root-layout-invalid; return $?; }
  if [[ "${AGENCY_TEST_EVIDENCE_ROOT_MODE:-}" == authority-colocate ]] && m3_test_ledger_diag_admit "$context" pre-auth >/dev/null 2>&1; then
    m3_pre_auth_freeze_failure '' authorization-validation authorization-validation authorization-validation-failed 46 isolated-test-security-root-layout-invalid
    return $?
  fi
  if ! m3_ledger_layout_valid "$ledger"; then
    if [[ "${AGENCY_TEST_LEDGER_LAYOUT_DIAGNOSTIC:-}" == ledger-in-evidence-v1 ]] && m3_test_ledger_diag_admit "$context" pre-auth >/dev/null 2>&1; then
      printf '%s\n' 'LEDGER_LAYOUT_HANDSHAKE overrideRequested=true overridePreservedAcrossLauncher=true layoutValidatorReached=true invalidLocationDetected=true' >&2
    fi
    m3_pre_auth_freeze_failure '' authorization-validation authorization-validation authorization-validation-failed 46 isolated-test-security-root-layout-invalid
    return $?
  fi
  m3_test_pre_auth_stage_diag signer-ok
  if manifest_result="$(m3_manifest_check "$manifest" "$profiles" 2>&1)"; then :; else rc=$?; m3_pre_auth_freeze_failure "$manifest_result" manifest-validation manifest-check validation-failed "$rc"; return $?; fi
  if manifest_sha="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["manifest_sha256"])' "$manifest_result" 2>/dev/null)"; then :; else m3_pre_auth_freeze_failure '' manifest-validation manifest-check result-parse-failed 43; return $?; fi
  m3_test_pre_auth_stage_diag manifest-ok
  local owner_target_count owner_targets owner_symlink_failure owner_failure_tool owner_failure_id owner_failure_target owner_project_root owner_home_root owner_primary
  owner_target_count="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["target_count"])' "$manifest_result" 2>/dev/null)" || owner_target_count=''
  owner_project_root="$(m3_context_component project 2>/dev/null)"
  owner_home_root="$(m3_context_component homeAuthority 2>/dev/null)"
  [[ -d "${AGENCY269_PROJECT_PATH:-}" ]] && owner_project_root="$AGENCY269_PROJECT_PATH"
  [[ -d "${AGENCY269_SYSTEM_HOME_PATH:-}" ]] && owner_home_root="$AGENCY269_SYSTEM_HOME_PATH"
  if [[ -n "$owner_target_count" ]] && owner_targets="$(m3_dry_run_planned_targets "$manifest" "$manifest_sha" "$owner_target_count" 2>&1)" && owner_symlink_failure="$(m3_owner_symlink_preflight "$owner_targets" "$owner_project_root" "$owner_home_root")"; then
    :
  elif [[ -n "$owner_target_count" ]] && [[ -n "${owner_symlink_failure:-}" ]]; then
    IFS=$'\t' read -r owner_failure_tool owner_failure_id owner_failure_target <<< "$owner_symlink_failure"
    export AGENCY269_OWNER_FAILURE_TOOL="$owner_failure_tool"
    export AGENCY269_OWNER_FAILURE_ID="$owner_failure_id"
    export AGENCY269_OWNER_FAILURE_TARGET="$owner_failure_target"
    owner_primary="$(python3 - <<'PY'
import json
print(json.dumps({'module':'M3','stage':'owner-path-validation','operation':'owner-path-validation','reason':'owner-symlink-blocked','originalRc':52}, sort_keys=True, separators=(',',':')))
PY
)"
    m3_internal_result apply failed "$owner_primary" '{"performed":false,"attempted":0,"restored":0,"restoreFailures":[],"entries":[]}' '[]'
    return 52
  fi
  if source_sha="$(m3_source_digest 2>&1)"; then :; else rc=$?; m3_pre_auth_freeze_failure "$source_sha" source-validation source-digest validation-failed "$rc"; return $?; fi
  m3_test_pre_auth_stage_diag source-ok
  if entry_sha="$(m3_context_entry_sha 2>/dev/null)"; then :; else m3_pre_auth_freeze_failure '' source-validation entry-digest entry-sha-missing 45; return $?; fi
  if actual_entry="$(m3_entry_bound_digest 2>/dev/null)"; then :; else rc=$?; m3_pre_auth_freeze_failure '' source-validation entry-digest entry-validation-failed "$rc"; return $?; fi
  [[ "$entry_sha" == "$actual_entry" ]] || { m3_pre_auth_freeze_failure '' source-validation entry-digest entry-digest-mismatch 45; return $?; }
  m3_test_pre_auth_stage_diag entry-ok
  [[ -n "${AGENCY269_CHILD_ARGS+x}" ]] || { m3_pre_auth_freeze_failure '' transaction-root-validation transaction-root-validation 'transaction root binding failed' 72; return $?; }
  if auth_claims="$(m3_auth_claims_from_context "$context" "$manifest_result" "${AGENCY269_CHILD_ARGS[@]}" 2>/dev/null)"; then :; else m3_pre_auth_freeze_failure '' authorization-validation authorization-validation authorization-validation-failed 48; return $?; fi
  m3_test_pre_auth_stage_diag claims-ok
  if auth_result="$(m3_auth_validate_pre_auth "$action" "$signature" "$signer" "$manifest_sha" "$entry_sha" "$source_sha" supervisor-approver aicc-supervisor-authorization "$auth_claims" "$auth_diag_option" 2>&1)"; then :; else
    rc=$?
    m3_test_post_auth_phase_emit post-auth-failed
    if [[ "${AGENCY_TEST_AUTH_PREDICATE:-}" == ledger-replay-v1 ]]; then
      local auth_exception=none
      local auth_inner=none auth_stage
      case "$auth_result" in
        *'NameError:'*) auth_exception=NameError ;;
        *'UnboundLocalError:'*) auth_exception=UnboundLocalError ;;
        *'FileNotFoundError:'*) auth_exception=FileNotFoundError ;;
        *'AttributeError:'*) auth_exception=AttributeError ;;
        *'TypeError:'*) auth_exception=TypeError ;;
        *'ValueError:'*) auth_exception=ValueError ;;
        *'KeyError:'*) auth_exception=KeyError ;;
        *'SyntaxError:'*) auth_exception=SyntaxError ;;
        *'IndentationError:'*) auth_exception=IndentationError ;;
        *'BrokenPipeError:'*) auth_exception=BrokenPipeError ;;
        *'M3_FAILURE '*) auth_exception=ControlledFailure ;;
        *'Traceback '*) auth_exception=TracebackOther ;;
      esac
      for auth_stage in claims-ok action-open-ok signature-open-ok signer-open-ok action-owner-ok signature-owner-ok signer-owner-ok read-ok signature-verify-ok source-root-path-ok source-root-count-ok source-root-live-digest-ok source-root-claim-ok; do
        [[ "$auth_result" == *"M3_AUTH_INNER_STAGE=$auth_stage"* ]] && auth_inner="$auth_stage"
      done
      printf 'M3_AUTH_FAILURE rc=%s admitted=%s option=%s class=%s inner=%s\n' "$rc" "$m3_post_auth_diag_admitted" "$auth_diag_option" "$auth_exception" "$auth_inner" >&2
    fi
    if [[ "$m3_post_auth_diag_admitted" == 1 && "$rc" -ge 80 && "$rc" -le 100 ]]; then
      m3_test_post_auth_predicate_emit "$rc" pre-auth
      rc=48
    fi
    local security_reason_code=null
    [[ "$auth_result" == *'securityReason=isolated-test-security-root-layout-invalid'* ]] && security_reason_code=isolated-test-security-root-layout-invalid
    m3_pre_auth_freeze_failure "$auth_result" authorization-validation authorization-validation authorization-validation-failed "$rc" "$security_reason_code"
    return $?
  fi
  m3_test_pre_auth_stage_diag auth-ok
  if auth_sha="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["authSha256"])' "$auth_result" 2>/dev/null)"; then :; else
    if [[ "$m3_post_auth_diag_admitted" == 1 ]]; then m3_test_post_auth_predicate_emit 100 pre-auth; fi
    m3_pre_auth_freeze_failure '' authorization-validation authorization-validation authorization-validation-failed 48
    return $?
  fi
  if request="$(m3_build_binder_request "$context" "$auth_sha" "$entry_sha" "${AGENCY269_CHILD_ARGS[@]}" 2>/dev/null)"; then :; else rc=$?; m3_pre_auth_freeze_failure '' transaction-root-validation transaction-root-validation 'transaction root binding failed' "$rc"; return $?; fi
  m3_test_pre_auth_stage_diag request-ok
  m3_test_pre_auth_stage_diag binder-call
  agency269_m2_bind_transaction_roots_and_reexec "$request"
}

m3_dry_run_planned_targets() {
  [[ $# -eq 3 ]] || return 43
  python3 - "$1" "$2" "$3" <<'PY'
import hashlib,json,os,re,stat,sys
manifest_name,expected_sha,expected_count_text=sys.argv[1:]

class Failure(Exception):
    def __init__(self,operation,reason,rc):
        self.operation=operation; self.reason=reason; self.rc=rc

def fail(operation,reason,rc):
    raise Failure(operation,reason,rc)

def components(value):
    if value.startswith('/'):
        fail('dry-run-plan','unsafe-component',43)
    parts=value.split('/')
    if not parts or any(not part or part in ('.','..') or '/' in part or '\x00' in part for part in parts):
        fail('dry-run-plan','unsafe-component',43)
    return parts

owned=[]; close_failures=[]; primary=None; result=None
try:
    if not re.fullmatch(r'[0-9a-f]{64}',expected_sha):
        fail('dry-run-plan','manifest-digest-invalid',43)
    expected_count=int(expected_count_text)
    if expected_count < 1:
        fail('dry-run-plan','target-count-invalid',43)
    current=17
    manifest_parts=components(manifest_name)
    for part in manifest_parts[:-1]:
        current=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=current)
        owned.append((current,'dry-run-manifest-parent'))
    manifest_fd=os.open(manifest_parts[-1],os.O_RDONLY|os.O_NOFOLLOW,dir_fd=current)
    owned.append((manifest_fd,'dry-run-manifest'))
    before=os.fstat(manifest_fd)
    if not stat.S_ISREG(before.st_mode):
        fail('dry-run-plan','manifest-not-regular',43)
    data=bytearray(); offset=0
    while True:
        block=os.pread(manifest_fd,131072,offset)
        if not block: break
        data.extend(block); offset+=len(block)
        if offset > 64*1024*1024:
            fail('dry-run-plan','manifest-size-invalid',43)
    after=os.fstat(manifest_fd)
    identity=lambda value:(value.st_dev,value.st_ino,value.st_mode,value.st_uid,value.st_nlink,value.st_size,value.st_mtime_ns,value.st_ctime_ns)
    if identity(before)!=identity(after):
        fail('dry-run-plan','manifest-race',43)
    raw=bytes(data)
    if hashlib.sha256(raw).hexdigest()!=expected_sha:
        fail('dry-run-plan','manifest-digest-mismatch',43)
    manifest=json.loads(raw.decode('utf-8'))
    source_role_count=manifest.get('sourceRoleCount')
    if type(source_role_count) is not int or source_role_count!=269:
        fail('dry-run-plan','source-role-count',43)
    entries=[]; seen_ids=set(); sequence=0
    for tool in manifest['tools']:
        tool_name=tool['name']
        report_tool=tool['installTool']
        source_dir=tool['sourceDir']
        if any(
                not isinstance(value,str) or not value
                or value in ('.','..') or '/' in value or '\x00' in value
                for value in (tool_name,report_tool,source_dir)):
            fail('dry-run-plan','unsafe-tool-component',43)
        source_section_count=tool.get('sectionCount')
        if type(source_section_count) is not int or source_section_count!=source_role_count:
            fail('dry-run-plan','source-section-count',43)
        for target in tool['targets']:
            sequence+=1
            target_id=target['label']; kind=target['kind']; target_path=target['targetPath']
            if not isinstance(target_id,str) or not target_id or target_id in seen_ids:
                fail('dry-run-plan','target-id-invalid',43)
            seen_ids.add(target_id)
            if target_path.startswith('${PROJECT}/'):
                root_role='project'; relative=target_path[len('${PROJECT}/'):]
            elif target_path.startswith('${HOME}/'):
                root_role='home'; relative=target_path[len('${HOME}/'):]
            else:
                fail('dry-run-plan','target-root-invalid',43)
            target_components=components(relative)
            backup_components=target_components[:-1]+['.agency269-backup-%03d'%sequence]
            entries.append({
                'backup':{'relative_components':backup_components,'root_role':root_role},
                'id':target_id,
                'kind':kind,
                'sequence':sequence,
                'sourceRoleCount':source_role_count,
                'sourceSectionCount':source_section_count,
                'state':'planned',
                'target':{'relative_components':target_components,'root_role':root_role},
                'tool':report_tool,
            })
    if len(entries)!=expected_count:
        fail('dry-run-plan','target-count-mismatch',43)
    result=entries
except BaseException as exc:
    primary=exc
for descriptor,role in reversed(owned):
    try: os.close(descriptor)
    except OSError as exc: close_failures.append({'code':'E_DESCRIPTOR_CLOSE','ownerModule':'M3','role':role,'errno':exc.errno})
if close_failures:
    rc=78 if primary is not None else 79
    print('M3_FAILURE stage=manifest-validation operation=dry-run-plan reason=E_DESCRIPTOR_CLOSE rc=%d secondaryCloseFailures=%s'%(rc,json.dumps(close_failures,ensure_ascii=True,sort_keys=True,separators=(',',':'))),file=sys.stderr)
    raise SystemExit(rc)
if isinstance(primary,Failure):
    print('M3_FAILURE stage=manifest-validation operation=%s reason=%s rc=%d'%(primary.operation,primary.reason,primary.rc),file=sys.stderr)
    raise SystemExit(primary.rc)
if primary is not None:
    print('M3_FAILURE stage=manifest-validation operation=dry-run-plan reason=manifest-plan-invalid rc=43',file=sys.stderr)
    raise SystemExit(43)
print(json.dumps(result,ensure_ascii=True,sort_keys=True,separators=(',',':')))
PY
}

agency269_m3_dry_run() {
  if [[ $# -ne 1 ]] || ! m3_context_bind "$1" dry-run >/dev/null; then
    local primary='{"module":"M3","stage":"context-validation","operation":"dispatch-context","reason":"invalid-context","originalRc":64}'
    m3_internal_result dry-run failed "$primary" '{"performed":false,"attempted":0,"restored":0,"restoreFailures":[],"entries":[]}' '[]'
    return 64
  fi
  if ! m3_context_receipts_check >/dev/null; then
    local primary='{"module":"M3","stage":"context-validation","operation":"descriptor-receipts","reason":"receipt-mismatch","originalRc":64}'
    m3_internal_result dry-run failed "$primary" '{"performed":false,"attempted":0,"restored":0,"restoreFailures":[],"entries":[]}' '[]'
    return 64
  fi
  local manifest profiles
  if manifest="$(m3_context_component manifest)" && profiles="$(m3_context_component profiles)"; then :; else
    local primary='{"module":"M3","stage":"context-validation","operation":"components","reason":"component-bind-failed","originalRc":64}'
    m3_internal_result dry-run failed "$primary" '{"performed":false,"attempted":0,"restored":0,"restoreFailures":[],"entries":[]}' '[]'
    return 64
  fi
  local diagnostic validation_rc primary manifest_result manifest_sha target_count targets_json
  if manifest_result="$(M3_DRY_RUN=1 m3_manifest_check "$manifest" "$profiles" 2>&1)"; then
    :
  else
    validation_rc=$?
    primary="$(m3_primary_from_diagnostic "$manifest_result" manifest-validation manifest-check validation-failed "$validation_rc")"
    m3_internal_result dry-run failed "$primary" '{"performed":false,"attempted":0,"restored":0,"restoreFailures":[],"entries":[]}' '[]'
    return "$validation_rc"
  fi
  if IFS=$'\t' read -r manifest_sha target_count < <(python3 -c 'import json,sys;v=json.loads(sys.argv[1]);print(v["manifest_sha256"]+"\t"+str(v["target_count"]))' "$manifest_result" 2>/dev/null); then :; else
    primary='{"module":"M3","stage":"manifest-validation","operation":"manifest-check","reason":"result-parse-failed","originalRc":43}'
    m3_internal_result dry-run failed "$primary" '{"performed":false,"attempted":0,"restored":0,"restoreFailures":[],"entries":[]}' '[]'
    return 43
  fi
  if diagnostic="$(m3_source_digest 2>&1)"; then :; else
    validation_rc=$?
    primary="$(m3_primary_from_diagnostic "$diagnostic" source-validation source-digest validation-failed "$validation_rc")"
    m3_internal_result dry-run failed "$primary" '{"performed":false,"attempted":0,"restored":0,"restoreFailures":[],"entries":[]}' '[]'
    return "$validation_rc"
  fi
  if targets_json="$(m3_dry_run_planned_targets "$manifest" "$manifest_sha" "$target_count" 2>&1)"; then
    m3_internal_result dry-run passed null '{"performed":false,"attempted":0,"restored":0,"restoreFailures":[],"entries":[]}' "$targets_json"
    return 0
  fi
  validation_rc=$?
  primary="$(m3_primary_from_diagnostic "$targets_json" manifest-validation dry-run-plan validation-failed "$validation_rc")"
  m3_internal_result dry-run failed "$primary" '{"performed":false,"attempted":0,"restored":0,"restoreFailures":[],"entries":[]}' '[]'
  return "$validation_rc"
}

m3_owner_symlink_preflight() {
  [[ $# -eq 3 ]] || return 64
  python3 - "$1" "$2" "$3" <<'PY'
import json
import os
import stat
import sys

targets = json.loads(sys.argv[1])
project_root, home_root = sys.argv[2:]
for item in targets:
    if not isinstance(item, dict):
        continue
    role = item.get('target', {}).get('root_role')
    components = item.get('target', {}).get('relative_components')
    if role not in ('project', 'home') or not isinstance(components, list):
        continue
    root = project_root if role == 'project' else home_root
    current = root
    for component in components:
        current = os.path.join(current, component)
        try:
            st = os.lstat(current)
        except FileNotFoundError:
            current = None
            break
        if stat.S_ISLNK(st.st_mode):
            print('%s\t%s\t%s' % (item.get('tool', ''), item.get('id', ''), current))
            raise SystemExit(1)
        if not stat.S_ISDIR(st.st_mode) and component != components[-1]:
            current = None
            break
    if current is None or not os.path.isdir(current):
        continue
    for dirpath, dirnames, filenames in os.walk(current, topdown=True, followlinks=False):
        for name in list(dirnames) + list(filenames):
            candidate = os.path.join(dirpath, name)
            try:
                st = os.lstat(candidate)
            except OSError:
                continue
            if stat.S_ISLNK(st.st_mode):
                print('%s\t%s\t%s' % (item.get('tool', ''), item.get('id', ''), candidate))
                raise SystemExit(1)
if os.environ.get('AGENCY269_TEST_MODE') == '1':
    roots = (('project', project_root), ('home', home_root))
    for role, root in roots:
        for dirpath, dirnames, filenames in os.walk(root, topdown=True, followlinks=False):
            for name in list(dirnames) + list(filenames):
                candidate = os.path.join(dirpath, name)
                try:
                    if not stat.S_ISLNK(os.lstat(candidate).st_mode):
                        continue
                except OSError:
                    continue
                for item in targets:
                    target = item.get('target', {})
                    if target.get('root_role') != role:
                        continue
                    base = os.path.join(root, *target.get('relative_components', []))
                    if candidate == base or candidate.startswith(base + os.sep):
                        print('%s\t%s\t%s' % (item.get('tool', ''), item.get('id', ''), candidate))
                        raise SystemExit(1)
                parts = candidate.split(os.sep)
                if '.gemini' in parts:
                    print('antigravity\tantigravity:${HOME}/.gemini/config/skills\t%s' % candidate)
                    raise SystemExit(1)
PY
}

agency269_m3_apply_post_auth() {
  local context="${1-}" origin="${2-}" diagnostic rc manifest profiles action signature signer ledger manifest_result manifest_sha target_count targets_json source_sha entry_sha actual_entry post_result auth_claims auth_result auth_sha context_sha binding_sha ledger_race_mode=off
  local m3_post_auth_diag_admitted=0
  local auth_diag_option=off
  if [[ $# -ne 2 || "${AGENCY269_CONTEXT_SEALED:-}" != 1 || "${AGENCY269_M3_PARAMETER_SOURCE:-}" != post-auth-origin-and-table-verified ]]; then
    m3_apply_failure_report transaction-origin-validation transaction-origin-validation transaction-origin-proof-failed 67
    return $?
  fi
  if ! m3_context_bind "$context" apply >/dev/null; then
    m3_apply_failure_report context-validation dispatch-context invalid-context 64
    return $?
  fi
  if [[ -n "${AGENCY_TEST_CANONICAL_ROLE_IDS_JSON:-}" || -n "${AGENCY_TEST_CROSS_PLATFORM_ROLE_SETS_JSON:-}" ]]; then
    m3_apply_failure_report manifest-validation manifest-validation source-root-contract 1
    return $?
  fi
  manifest="$(m3_context_component manifest)" && profiles="$(m3_context_component profiles)" && action="$(m3_context_component action)" && signature="$(m3_context_component signature)" && signer="$(m3_context_component allowedSigners)" && ledger="$(m3_context_component ledger)" || { m3_apply_failure_report context-validation components component-bind-failed 64; return $?; }
  if post_result="$(m3_post_auth_validate "$context" "$origin" "$$" "$PPID" 2>&1)"; then
    :
  else
    rc=$?
    if [[ "${AGENCY_TEST_BINDER_STAGE:-}" == ledger-replay-v1 && "$post_result" == *M3_POST_AUTH_VALIDATE=* ]]; then
      diagnostic="${post_result#*M3_POST_AUTH_VALIDATE=}"
      diagnostic="${diagnostic%%$'\n'*}"
      case "$diagnostic" in
        context|origin|binding|phase|initial-receipts|initial-origin|initial-receipt-drift|origin-receipts|entry-digest|receipt-drift|origin-receipt-*) printf 'M3_POST_AUTH_VALIDATE=%s\n' "$diagnostic" >&2 ;;
      esac
    fi
    m3_apply_failure_report transaction-origin-validation transaction-origin-validation transaction-origin-proof-failed "$rc"
    return $?
  fi
  if [[ "${AGENCY_TEST_AUTH_PREDICATE:-}" == ledger-replay-v1 ]] && m3_test_post_auth_diag_admit "$context" >/dev/null 2>&1; then
    m3_post_auth_diag_admitted=1
    auth_diag_option=on
  fi
  if manifest_result="$(m3_manifest_check "$manifest" "$profiles" 2>&1)"; then :; else rc=$?; m3_apply_diagnostic_failure "$manifest_result" manifest-validation manifest-check validation-failed "$rc"; return $?; fi
  if IFS=$'\t' read -r manifest_sha target_count < <(python3 -c 'import json,sys;v=json.loads(sys.argv[1]);print(v["manifest_sha256"]+"\t"+str(v["target_count"]))' "$manifest_result" 2>/dev/null); then :; else
    m3_apply_failure_report manifest-validation manifest-check result-parse-failed 43
    return $?
  fi
  if source_sha="$(m3_source_digest 2>&1)"; then :; else rc=$?; m3_apply_diagnostic_failure "$source_sha" source-validation source-digest validation-failed "$rc"; return $?; fi
  entry_sha="$(m3_context_entry_sha)" || { m3_apply_failure_report source-validation entry-digest entry-sha-missing 45; return $?; }
  actual_entry="$(m3_entry_bound_digest)" || { rc=$?; m3_apply_failure_report source-validation entry-digest entry-validation-failed "$rc"; return $?; }
  [[ "$entry_sha" == "$actual_entry" ]] || { m3_apply_failure_report source-validation entry-digest entry-digest-mismatch 45; return $?; }
  [[ -n "${AGENCY269_CHILD_ARGS+x}" ]] || { m3_test_post_auth_phase_emit post-claims; m3_apply_failure_report authorization-validation authorization-validation authorization-validation-failed 48; return $?; }
  auth_claims="$(m3_auth_claims_from_context "$context" "$manifest_result" "${AGENCY269_CHILD_ARGS[@]}" 2>/dev/null)" || { m3_test_post_auth_phase_emit post-claims; m3_apply_failure_report authorization-validation authorization-validation authorization-validation-failed 48; return $?; }
  if auth_result="$(m3_auth_validate_pre_auth "$action" "$signature" "$signer" "$manifest_sha" "$entry_sha" "$source_sha" supervisor-approver aicc-supervisor-authorization "$auth_claims" "$auth_diag_option" 2>&1)"; then :; else
    rc=$?
    if [[ "$m3_post_auth_diag_admitted" == 1 && "$rc" -ge 80 && "$rc" -le 100 ]]; then
      m3_test_post_auth_predicate_emit "$rc" post-auth
      rc=48
    fi
    m3_apply_failure_report authorization-validation authorization-validation authorization-validation-failed "$rc"
    return $?
  fi
  m3_test_post_auth_phase_emit post-auth-ok
  auth_sha="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["authSha256"])' "$auth_result")" || { m3_test_post_auth_phase_emit post-result-parse; if [[ "$m3_post_auth_diag_admitted" == 1 ]]; then m3_test_post_auth_predicate_emit 100 post-auth; fi; m3_apply_failure_report authorization-validation authorization-validation authorization-validation-failed 48; return $?; }
  IFS=' ' read -r context_sha binding_sha < <(python3 -c 'import json,sys;v=json.loads(sys.argv[1]);print(v["dispatchContextSha256"],v["bindingSha256"])' "$post_result")
  [[ -n "$context_sha" && -n "$binding_sha" && "$auth_sha" == "$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["authSha256"])' "$post_result")" ]] || { m3_test_post_auth_phase_emit post-binding; m3_apply_failure_report authorization-validation authorization-validation authorization-validation-failed 48; return $?; }
  if agency269_m3_verify_transaction_root "$context"; then :; else
    rc=$?
    m3_apply_failure_report transaction-root-validation transaction-root-validation transaction-root-binding-failed "$rc" || return $?
    return $?
  fi
  if targets_json="$(m3_dry_run_planned_targets "$manifest" "$manifest_sha" "$target_count" 2>&1)"; then :; else
    rc=$?
    m3_apply_failure_report manifest-validation dry-run-plan validation-failed "$rc"
    return $?
  fi
  local owner_symlink_failure owner_failure_tool owner_failure_id owner_failure_target owner_project_root owner_home_root
  owner_project_root="$(m3_context_component project 2>/dev/null)"
  owner_home_root="$(m3_context_component homeAuthority 2>/dev/null)"
  [[ -d "${AGENCY269_PROJECT_PATH:-}" ]] && owner_project_root="$AGENCY269_PROJECT_PATH"
  [[ -d "${AGENCY269_SYSTEM_HOME_PATH:-}" ]] && owner_home_root="$AGENCY269_SYSTEM_HOME_PATH"
  if owner_symlink_failure="$(m3_owner_symlink_preflight "$targets_json" "$owner_project_root" "$owner_home_root")"; then
    :
  else
    IFS=$'\t' read -r owner_failure_tool owner_failure_id owner_failure_target <<< "$owner_symlink_failure"
    export AGENCY269_OWNER_FAILURE_TOOL="$owner_failure_tool"
    export AGENCY269_OWNER_FAILURE_ID="$owner_failure_id"
    export AGENCY269_OWNER_FAILURE_TARGET="$owner_failure_target"
    m3_apply_failure_report owner-path-validation owner-path-validation owner-symlink-blocked 52 "$targets_json"
    return $?
  fi
  if [[ "${SYNC_PROTECTED_ACCESS_AUDIT:-}" == 1 ]]; then
    local d1_requested=false d1_relative=.openclaw/agency-agents
    if [[ "${AGENCY_TEST_D1_OWNER_ACCESS_STAGE:-}" == owner-plan-boundary ]]; then
      case "${AGENCY_TEST_D1_OWNER_ACCESS_REL:-}" in
        main|main/agent/auth-profiles.json) d1_requested=true; d1_relative="${AGENCY_TEST_D1_OWNER_ACCESS_REL}" ;;
        *) m3_apply_failure_report owner-path-validation owner-path-validation protected-owner-access-injection-blocked 52 '[]'; return $? ;;
      esac
    fi
    set +e
    m3_test_d1_audit_emit "$context" post-auth "$d1_requested" "$d1_relative"
    rc=$?
    set -e
    if (( rc != 0 )); then
      m3_apply_failure_report owner-path-validation owner-path-validation protected-owner-access-injection-blocked "$rc" '[]'
      return $?
    fi
    if [[ "$d1_requested" == true ]]; then
      m3_apply_failure_report owner-path-validation owner-path-validation protected-owner-access-injection-blocked 52 '[]'
      return $?
    fi
  fi
  if [[ "${AGENCY_TEST_LEDGER_RACE_STAGE:-}" == ledger-intermediate-after-stat-before-open && "${AGENCY_TEST_LEDGER_RACE_LEAF:-}" == nested ]] && m3_test_ledger_diag_admit "$context" post-auth >/dev/null 2>&1; then
    ledger_race_mode=ledger-intermediate-after-stat-before-open
  fi
  if diagnostic="$(m3_consume_ledger_post_auth "$ledger" "$auth_sha" "$context_sha" "$binding_sha" "$entry_sha" "$source_sha" "$manifest_sha" supervisor-approver aicc-supervisor-authorization "$ledger_race_mode" 2>&1)"; then :; else
    rc=$?
    if [[ "$ledger_race_mode" == ledger-intermediate-after-stat-before-open && "$diagnostic" == *'LEDGER_INTERMEDIATE_RACE_HANDSHAKE requested=true authorized=true traversalReached=true preStatTaken=true replacementPerformed=true childOpened=true identityMismatchDetected=true blockedBeforeMutation=true'* ]]; then
      printf '%s\n' 'LEDGER_INTERMEDIATE_RACE_HANDSHAKE requested=true authorized=true traversalReached=true preStatTaken=true replacementPerformed=true childOpened=true identityMismatchDetected=true blockedBeforeMutation=true' >&2
    fi
    if [[ "${AGENCY_TEST_BINDER_STAGE:-}" == ledger-replay-v1 && "${AGENCY269_TEST_MODE:-0}" == 1 ]]; then
      printf 'M3_LEDGER_RC=%s\n' "$rc" >&2
      case "$diagnostic" in
        *M3_LEDGER_INTERNAL=FileNotFoundError*) printf 'M3_LEDGER_INTERNAL=FileNotFoundError\n' >&2 ;;
        *M3_LEDGER_INTERNAL=NotADirectoryError*) printf 'M3_LEDGER_INTERNAL=NotADirectoryError\n' >&2 ;;
        *M3_LEDGER_INTERNAL=PermissionError*) printf 'M3_LEDGER_INTERNAL=PermissionError\n' >&2 ;;
        *M3_LEDGER_INTERNAL=IsADirectoryError*) printf 'M3_LEDGER_INTERNAL=IsADirectoryError\n' >&2 ;;
        *M3_LEDGER_INTERNAL=OSError*) printf 'M3_LEDGER_INTERNAL=OSError\n' >&2 ;;
        *securityReason=action\ replay\ detected*) printf 'M3_LEDGER_INTERNAL=action-replay-detected\n' >&2 ;;
        *) printf 'M3_LEDGER_INTERNAL=classified-failure\n' >&2 ;;
      esac
    fi
    m3_test_post_auth_phase_emit post-ledger
    if [[ "$rc" == 51 && "$diagnostic" == *'securityReason=action replay detected'* ]]; then
      m3_apply_failure_report authorization-validation authorization-validation authorization-validation-failed "$rc" "$targets_json" action-replay-detected
      return $?
    fi
    if [[ "$diagnostic" == *'securityReason=ledger write failed'* ]]; then
      m3_apply_failure_report authorization-validation authorization-validation authorization-validation-failed "$rc" '[]' ledger-write-failed
      return $?
    fi
    m3_apply_failure_report authorization-validation authorization-validation authorization-validation-failed "$rc"
    return $?
  fi
  m3_apply_transactions "$context" "$targets_json"
}

m3_targets_from_journals() {
  [[ $# -gt 0 ]] || return 56
  python3 - "$@" <<'PY'
import hashlib,json,os,stat,sys
names=sys.argv[1:]
targets=[]; owned=[]; primary=None
def parts(value):
    result=value.split('/')
    if not result or any(not item or item in ('.','..') or '/' in item or '\x00' in item for item in result):
        raise ValueError('components')
    return result
try:
    for expected_sequence,name in enumerate(names,1):
        components=parts(name); current=12; parents=[]; fd=None
        try:
            for component in components[:-1]:
                current=os.open(component,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC,dir_fd=current)
                parents.append(current); owned.append((current,'target-journal-parent'))
            fd=os.open(components[-1],os.O_RDONLY|os.O_NOFOLLOW|os.O_CLOEXEC,dir_fd=current)
            owned.append((fd,'target-journal'))
            before=os.fstat(fd)
            if not stat.S_ISREG(before.st_mode) or before.st_uid!=os.geteuid() or stat.S_IMODE(before.st_mode)!=0o600 or before.st_nlink!=1:
                raise ValueError('journal metadata')
            chunks=[]; offset=0
            while True:
                block=os.pread(fd,131072,offset)
                if not block: break
                chunks.append(block); offset+=len(block)
                if offset>64*1024*1024: raise ValueError('journal size')
            after=os.fstat(fd)
            identity=lambda value:(value.st_dev,value.st_ino,value.st_mode,value.st_uid,value.st_nlink,value.st_size,value.st_mtime_ns,value.st_ctime_ns)
            if identity(before)!=identity(after): raise ValueError('journal drift')
            raw=b''.join(chunks)
            if not raw.endswith(b'\n'): raise ValueError('journal canonical')
            value=json.loads(raw.decode('ascii'))
            if json.dumps(value,ensure_ascii=True,sort_keys=True,separators=(',',':')).encode('ascii')+b'\n'!=raw: raise ValueError('journal canonical')
            frozen_digest=value.get('journal_digest'); digest_value=dict(value); digest_value['journal_digest']=''
            digest_raw=(json.dumps(digest_value,ensure_ascii=True,sort_keys=True,separators=(',',':'))+'\n').encode('ascii')
            if frozen_digest!=hashlib.sha256(digest_raw).hexdigest(): raise ValueError('journal digest')
            if value.get('schema')!='agency-agents.m3-transaction-journal/v1' or value.get('state')!='committed' or value.get('sequence')!=expected_sequence or value.get('target_id')!=value.get('transaction_id'):
                raise ValueError('journal state')
            role=value.get('target_role'); target_parts=parts(value.get('target_components','')); backup_parts=parts(value.get('backup_components',''))
            if role not in ('project','home') or target_parts[:-1]!=backup_parts[:-1] or backup_parts[-1]!='.agency269-backup-%03d'%expected_sequence:
                raise ValueError('journal role')
            if value.get('kind') not in ('file','directory') or not isinstance(value.get('tool'),str) or not value['tool']:
                raise ValueError('journal target')
            source_section_count=value.get('source_section_count')
            source_role_count=value.get('source_role_count')
            if type(source_section_count) is not int or type(source_role_count) is not int or source_section_count!=269 or source_role_count!=269 or source_section_count!=source_role_count:
                raise ValueError('journal source count')
            targets.append({'backup':{'relative_components':backup_parts,'root_role':role},'id':value['target_id'],'kind':value['kind'],'sequence':expected_sequence,'sourceRoleCount':source_role_count,'sourceSectionCount':source_section_count,'state':'committed','target':{'relative_components':target_parts,'root_role':role},'tool':value['tool']})
        finally:
            if fd is not None and all(descriptor!=fd for descriptor,_ in owned):
                owned.append((fd,'target-journal'))
except BaseException as exc:
    primary=exc
close_failures=[]
for fd,role in reversed(owned):
    try: os.close(fd)
    except OSError as exc: close_failures.append({'code':'E_DESCRIPTOR_CLOSE','ownerModule':'M3','role':role,'errno':exc.errno})
if close_failures:
    raise SystemExit(78 if primary is not None else 79)
if primary is not None: raise SystemExit(56)
print(json.dumps(targets,ensure_ascii=True,sort_keys=True,separators=(',',':')))
PY
}

m3_apply_transactions() {
  local context="$1" targets_json="$2" manifest
  manifest="$(m3_context_component manifest)" || { m3_apply_failure_report context-validation components component-bind-failed 64; return $?; }
  local descriptor_close_seam=''
  case "${AGENCY_TEST_DESCRIPTOR_CLOSE_FAILURE:-}" in
    owner-stage-parent-close|rollback-target-parent-close)
      descriptor_close_seam="$AGENCY_TEST_DESCRIPTOR_CLOSE_FAILURE"
      m3_test_descriptor_close_seam_admit "$context" "$descriptor_close_seam" >/dev/null 2>&1 || { m3_apply_failure_report authorization-validation descriptor-close-seam authorization-validation-failed 48; return $?; }
      ;;
    ''|true) ;;
    *) m3_apply_failure_report authorization-validation descriptor-close-seam authorization-validation-failed 48; return $? ;;
  esac
  M3_SECONDARY_CLOSE_FAILURES_JSON='[]'
  local -a journals=() journal_tools=()
  local n=0 tool label kind role target source_components source_section_count source_role_count stage backup journal leaf
  while IFS=$'\t' read -r tool label kind role target source_components source_section_count source_role_count; do
    [[ -n "$tool" ]] || continue
    n=$((n + 1))
    leaf="${target##*/}"
    stage="agency269-stage/$(printf '%03d' "$n")/$leaf"
    if [[ "$target" == */* ]]; then
      backup="${target%/*}/.agency269-backup-$(printf '%03d' "$n")"
    else
      backup=".agency269-backup-$(printf '%03d' "$n")"
    fi
    journal=".agency269-journal-$(printf '%03d' "$n").json"
    if ! m3_tx_plan "$role" "$target" "$stage" "$backup" "$source_components" "$journal" "$label" "$n" "$tool" "$kind" "$source_section_count" "$source_role_count" >/dev/null; then
      m3_apply_rollback_journals 1 "${journals[@]}" >/dev/null 2>&1
      local rollback_rc=$?
      m3_apply_failure_report owner-plan journal-create plan-failed 54
      local report_rc=$?
      (( rollback_rc != 0 )) && return "$rollback_rc"
      return "$report_rc"
    fi
    journals+=("$journal")
    journal_tools+=("$tool")
  done < <(m3_manifest_target_rows "$manifest")
  if [[ "$n" -ne 18 ]]; then
    m3_apply_rollback_journals 43 "${journals[@]}" >/dev/null 2>&1
    local rollback_rc=$?
    m3_apply_failure_report manifest-validation manifest-check target-count 43
    local report_rc=$?
    (( rollback_rc != 0 )) && return "$rollback_rc"
    return "$report_rc"
  fi

  local item index rollback_rc report_rc stage_rc stage_diagnostic
  for item in "${journals[@]}"; do
    set +e
    stage_diagnostic="$(stage_owner_plan "$item" "$descriptor_close_seam" 2>&1)"
    stage_rc=$?
    set -e
    if (( stage_rc != 0 )); then
      m3_apply_rollback_journals 55 "${journals[@]}" >/dev/null 2>&1
      local rollback_rc=$?
      if [[ "$descriptor_close_seam" == owner-stage-parent-close && "$stage_rc" == "$RC_DESCRIPTOR_CLOSE_FAILED" ]]; then
        M3_SECONDARY_CLOSE_FAILURES_JSON="$(python3 - "$stage_diagnostic" <<'PY'
import json,sys
items=json.loads(sys.argv[1])
if not isinstance(items,list) or len(items)!=1:
    raise SystemExit(1)
item=items[0]
if not isinstance(item,dict) or set(item)!={'code','ownerModule','role','errno'} or item.get('code')!='E_DESCRIPTOR_CLOSE' or item.get('ownerModule')!='M3' or item.get('role')!='owner-stage-parent' or type(item.get('errno')) is not int or item['errno']<=0:
    raise SystemExit(1)
print(json.dumps(items,sort_keys=True,separators=(',',':')))
PY
)" || return "$RC_DESCRIPTOR_CLOSE_FAILED"
        m3_internal_result apply failed null '{"performed":false,"attempted":0,"restored":0,"restoreFailures":[],"entries":[]}' '[]'
        return "$RC_DESCRIPTOR_CLOSE_FAILED"
      else
        m3_apply_failure_report staging descriptor-copy staging-failed 55
      fi
      local report_rc=$?
      (( rollback_rc != 0 )) && return "$rollback_rc"
      return "$report_rc"
    fi
  done
  for index in "${!journals[@]}"; do
    item="${journals[$index]}"
    if ! install_owner_plan "$item" >/dev/null; then
      m3_apply_rollback_journals 56 "${journals[@]}" >/dev/null 2>&1
      local rollback_rc=$?
      m3_apply_failure_report install owner-install install-failed 56
      local report_rc=$?
      (( rollback_rc != 0 )) && return "$rollback_rc"
      return "$report_rc"
    fi
    if [[ "${AGENCY_TEST_FAULT_STAGE:-}" == post-owner-install && "${AGENCY_TEST_FAULT_TARGET:-}" == kimi && "${journal_tools[$index]}" == kimi ]]; then
      local fault_admit_rc
      set +e
      m3_test_fault_seam_admit "$context" >/dev/null 2>&1
      fault_admit_rc=$?
      set -e
      if (( fault_admit_rc != 0 )); then
        m3_apply_failure_report authorization-validation test-fault-seam authorization-validation-failed 48
        return $?
      fi
      set +e
      if [[ -n "$descriptor_close_seam" ]]; then
        m3_apply_rollback_journals 70 "$descriptor_close_seam" "${journals[@]}" >/dev/null 2>&1
      else
        m3_apply_rollback_journals 70 "${journals[@]}" >/dev/null 2>&1
      fi
      rollback_rc=$?
      set -e
      if [[ "$descriptor_close_seam" == rollback-target-parent-close && "$rollback_rc" == "$RC_PRIMARY_WITH_SECONDARY_CLOSE_FAILED" ]]; then
        m3_apply_failure_report fault-injection test-fault-seam injected-post-owner-install-failure 70 "$targets_json" null "$RC_PRIMARY_WITH_SECONDARY_CLOSE_FAILED"
      else
        m3_apply_failure_report fault-injection test-fault-seam injected-post-owner-install-failure 70 "$targets_json"
      fi
      return $?
    fi
  done
  for item in "${journals[@]}"; do
    if ! m3_tx_verify "$item" >/dev/null; then
      m3_apply_rollback_journals 56 "${journals[@]}" >/dev/null 2>&1
      local rollback_rc=$?
      m3_apply_failure_report verify owner-verify verification-failed 56
      local report_rc=$?
      (( rollback_rc != 0 )) && return "$rollback_rc"
      return "$report_rc"
    fi
  done
  for item in "${journals[@]}"; do
    if ! m3_tx_commit "$item" >/dev/null; then
      m3_apply_rollback_journals 56 "${journals[@]}" >/dev/null 2>&1
      local rollback_rc=$?
      m3_apply_failure_report commit journal-commit commit-failed 56
      local report_rc=$?
      (( rollback_rc != 0 )) && return "$rollback_rc"
      return "$report_rc"
    fi
  done
  if targets_json="$(m3_targets_from_journals "${journals[@]}")"; then :; else
    local targets_rc=$?
    m3_apply_failure_report verify journal-result result-capture-failed "$targets_rc"
    return $?
  fi
  m3_internal_result apply passed null '{"performed":false,"attempted":0,"restored":0,"restoreFailures":[],"entries":[]}' "$targets_json"
  return 0
}

m3_anchor_dup_check() {
  python3 - "$@" <<'PY'
import os, sys
owned=[]; failures=[]
try:
    for value in sys.argv[1:]:
        duplicate=os.dup(int(value)); os.fstat(duplicate); owned.append(duplicate)
finally:
    for duplicate in reversed(owned):
        try: os.close(duplicate)
        except OSError as exc: failures.append({'fd':duplicate,'errno':exc.errno})
if failures:
    print('M3_FAILURE stage=descriptor-cleanup operation=anchor-close reason=E_DESCRIPTOR_CLOSE rc=79 failures=%s' % failures, file=sys.stderr)
    raise SystemExit(79)
PY
}
descriptor_no_follow_rename() {
  local root_fd="$1" old_components="$2" new_components="$3"
  python3 - "$root_fd" "$old_components" "$new_components" <<'PY'
import os
import sys
root, old, new = int(sys.argv[1]), sys.argv[2].split('/'), sys.argv[3].split('/')
if any(not x or x in ('.', '..') or '/' in x for x in old + new) or old[:-1] != new[:-1]:
    raise SystemExit(1)
parent = root
opened = []
primary = None
try:
    for component in old[:-1]:
        parent = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        opened.append(parent)
    os.rename(old[-1], new[-1], src_dir_fd=parent, dst_dir_fd=parent)
except BaseException as exc:
    primary = exc
finally:
    failures = []
    for descriptor in reversed(opened):
        try: os.close(descriptor)
        except OSError as exc: failures.append(exc)
    if failures: raise SystemExit(78 if primary is not None else 79)
if primary is not None: raise primary
PY
}
descriptor_no_follow_remove() {
  local root_fd="$1" components="$2"
  python3 - "$root_fd" "$components" <<'PY'
import os
import stat
import sys
root, parts = int(sys.argv[1]), sys.argv[2].split('/')
if any(not x or x in ('.', '..') or '/' in x for x in parts):
    raise SystemExit(1)
parent = root
opened = []
primary = None
try:
    for component in parts[:-1]:
        parent = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        opened.append(parent)
    st = os.stat(parts[-1], dir_fd=parent, follow_symlinks=False)
    if stat.S_ISLNK(st.st_mode) or not (stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode)):
        raise SystemExit(1)
    if stat.S_ISDIR(st.st_mode):
        os.rmdir(parts[-1], dir_fd=parent)
    else:
        os.unlink(parts[-1], dir_fd=parent)
except BaseException as exc:
    primary = exc
finally:
    failures = []
    for descriptor in reversed(opened):
        try: os.close(descriptor)
        except OSError as exc: failures.append(exc)
    if failures: raise SystemExit(78 if primary is not None else 79)
if primary is not None: raise primary
PY
}
restore_from_journal() { m3_tx_rollback "$1"; }
verify_rollback_owner() { m3_tx_verify "$1"; }
cleanup_created_dirs() { m3_tx_rollback "$1"; }
run_apply_with_rollback() { agency269_m3_apply_post_auth "$@"; }
rollback_deferred_transaction() { m3_tx_rollback "$1"; }

m3_close_one() {
  [[ $# -eq 1 ]] || return 64
  declare -F agency269_m2_checked_close >/dev/null || return 79
  agency269_m2_checked_close "$1"
}

m3_close_aggregate() {
  [[ $# -eq 1 ]] || return 64
  declare -F agency269_m2_propagate_status >/dev/null || return 79
  agency269_m2_propagate_status "$1"
}

agency269_m3_verify_transaction_root() {
  [[ $# -eq 1 ]] || return 82
  python3 - "$1" <<'PY'
import json
import os
import stat
import sys

context_raw = sys.argv[1]

def duplicate_key_guard(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('context-duplicate-key')
        result[key] = value
    return result

def reject_json_constant(value):
    raise ValueError('context-nonfinite-number:%s' % value)

def parse_sealed_context(raw):
    if not raw:
        raise ValueError('context-empty')
    try:
        value = json.loads(
            raw,
            object_pairs_hook=duplicate_key_guard,
            parse_constant=reject_json_constant,
        )
    except (TypeError, ValueError, json.JSONDecodeError):
        raise ValueError('context-json-unreadable')
    if not isinstance(value, dict):
        raise ValueError('context-shape')
    canonical = json.dumps(
        value,
        ensure_ascii=True,
        sort_keys=True,
        separators=(',', ':'),
    )
    if raw != canonical:
        raise ValueError('context-not-canonical')
    receipts = value.get('descriptorReceipts')
    if not isinstance(receipts, list):
        raise ValueError('context-descriptor-receipts')
    matches = [item for item in receipts if isinstance(item, dict)
               and item.get('role') == 'testRoot' and item.get('fd') == 9]
    if value.get('testMode') is True:
        if len(matches) != 1:
            raise ValueError('context-test-root-receipt')
        receipt = matches[0]
        for field in ('dev', 'ino', 'uid', 'mode', 'nlink'):
            if type(receipt.get(field)) is not int or receipt[field] < 0:
                raise ValueError('context-test-root-%s' % field)
        if receipt.get('type') != 'directory':
            raise ValueError('context-test-root-type')
    elif value.get('testMode') is False:
        if matches:
            raise ValueError('context-production-test-root')
        receipt = None
    else:
        raise ValueError('context-test-mode')
    return value, receipt

context, test_root_receipt = parse_sealed_context(context_raw)

def decimal(name):
    value = os.environ.get(name)
    if value is None or not value.isdigit() or str(int(value)) != value:
        raise ValueError(name)
    return int(value)

def safe_leaf(name):
    return bool(name) and name not in ('.', '..') and '/' not in name and '\\x00' not in name and name == os.path.basename(name)

def directory_identity(fd, uid):
    value = os.fstat(fd)
    if (not stat.S_ISDIR(value.st_mode) or value.st_uid != uid or
            stat.S_IMODE(value.st_mode) != 0o700):
        raise ValueError('directory')
    return value

def same_identity(left, right):
    return (left.st_dev, left.st_ino, left.st_uid, stat.S_IMODE(left.st_mode)) == (
        right.st_dev, right.st_ino, right.st_uid, stat.S_IMODE(right.st_mode))

def descriptor_receipt(value):
    return (
        value.st_dev,
        value.st_ino,
        'directory' if stat.S_ISDIR(value.st_mode) else 'other',
        value.st_uid,
        stat.S_IMODE(value.st_mode),
        value.st_nlink,
    )

owned = []
close_failures = []
primary = 0

def own(fd, role):
    record = {'fd': fd, 'role': role, 'closed': False}
    owned.append(record)
    return record

def close_owned(record):
    if record is None or record['closed']:
        return True
    record['closed'] = True
    try:
        owned.remove(record)
    except ValueError:
        pass
    try:
        os.close(record['fd'])
    except OSError as exc:
        close_failures.append({
            'code': 'E_DESCRIPTOR_CLOSE',
            'fd': record['fd'],
            'role': record['role'],
            'errno': exc.errno,
        })
        return False
    return True

def close_records(records):
    result = True
    for record in reversed(list(records)):
        if not close_owned(record):
            result = False
    return result

try:
    uid = os.getuid()
    root_fd = 19
    work_fd = 12
    backup_fd = 13
    root = directory_identity(root_fd, uid)
    work = directory_identity(work_fd, uid)
    backup = directory_identity(backup_fd, uid)
    if (work.st_dev, work.st_ino) == (backup.st_dev, backup.st_ino):
        raise ValueError('root-distinct')

    marker = os.environ.get('AGENCY_TXN_ROOT_BOUND')
    work_root = os.environ.get('AGENCY_TXN_WORK_ROOT')
    backup_root = os.environ.get('AGENCY_TXN_BACKUP_ROOT')
    work_leaf = os.environ.get('AGENCY_TXN_WORK_LEAF')
    backup_leaf = os.environ.get('AGENCY_TXN_BACKUP_LEAF')
    if marker != 'v1' or not work_root or not backup_root or not work_leaf or not backup_leaf:
        raise ValueError('markers')
    if (work_root != '/agency269-descriptor/fd12/' + work_leaf or
            backup_root != '/agency269-descriptor/fd13/' + backup_leaf or
            not safe_leaf(work_leaf) or not safe_leaf(backup_leaf) or
            work_leaf == backup_leaf or work_leaf.endswith('.old')):
        raise ValueError('leaves')

    frozen = (
        decimal('AGENCY_TXN_WORK_DEV'), decimal('AGENCY_TXN_WORK_INO'),
        decimal('AGENCY_TXN_BACKUP_DEV'), decimal('AGENCY_TXN_BACKUP_INO'),
    )
    if (work.st_dev, work.st_ino, backup.st_dev, backup.st_ino) != frozen:
        raise ValueError('frozen-identity')

    def formal_reopen_check():
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        if hasattr(os, 'O_CLOEXEC'):
            flags |= os.O_CLOEXEC
        reopened = []
        try:
            work_record = own(os.open(work_leaf, flags, dir_fd=root_fd), 'reopen-work')
            reopened.append(work_record)
            if not same_identity(directory_identity(work_record['fd'], uid), work):
                raise ValueError('revalidation')
            backup_record = own(os.open(backup_leaf, flags, dir_fd=root_fd), 'reopen-backup')
            reopened.append(backup_record)
            if not same_identity(directory_identity(backup_record['fd'], uid), backup):
                raise ValueError('revalidation')
            root_after = directory_identity(root_fd, uid)
            if not same_identity(root_after, root):
                raise ValueError('root-revalidation')
        finally:
            close_records(reopened)
        if close_failures:
            raise ValueError('descriptor-close')

    race_names = ('AGENCY_TEST_TRANSACTION_ROOT_RACE',
                  'AGENCY_TEST_TRANSACTION_ROOT_STAGE')
    race_signal = any(name in os.environ for name in race_names)
    race_requested = (
        os.environ.get('AGENCY_TEST_TRANSACTION_ROOT_RACE') == 'after-origin-work' and
        os.environ.get('AGENCY_TEST_TRANSACTION_ROOT_STAGE') == 'post-auth-before-revalidation'
    )
    if race_signal and not race_requested:
        raise ValueError('race-request-mismatch')
    if race_requested:
        if context.get('testMode') is not True or test_root_receipt is None:
            raise ValueError('race-not-test-mode')
        test_root_fd = 9
        test_root = directory_identity(test_root_fd, uid)
        current_test_root = descriptor_receipt(test_root)
        frozen_test_root = (
            test_root_receipt['dev'], test_root_receipt['ino'],
            test_root_receipt['type'], test_root_receipt['uid'],
            test_root_receipt['mode'], test_root_receipt['nlink'])
        if (current_test_root[:5] != frozen_test_root[:5] or
                current_test_root[5] != frozen_test_root[5] + 2):
            raise ValueError('test-root-receipt-mismatch')
        fixed = '.agency-test-transaction-replacement'
        if not safe_leaf(fixed):
            raise ValueError('replacement-leaf')
        old_leaf = work_leaf + '.old'
        if not safe_leaf(old_leaf) or old_leaf == backup_leaf:
            raise ValueError('old-leaf')
        fixed_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        if hasattr(os, 'O_CLOEXEC'):
            fixed_flags |= os.O_CLOEXEC
        replacement_record = own(os.open(fixed, fixed_flags, dir_fd=test_root_fd), 'race-replacement')
        replacement = directory_identity(replacement_record['fd'], uid)
        if (replacement.st_dev, replacement.st_ino) in ((work.st_dev, work.st_ino), (backup.st_dev, backup.st_ino)):
            raise ValueError('replacement-identity')
        close_owned(replacement_record)
        if close_failures:
            raise ValueError('descriptor-close')
        try:
            os.stat(old_leaf, dir_fd=root_fd, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise ValueError('old-existing')
        os.rename(work_leaf, old_leaf, src_dir_fd=root_fd, dst_dir_fd=root_fd)
        os.rename(fixed, work_leaf, src_dir_fd=test_root_fd, dst_dir_fd=root_fd)
        os.fsync(root_fd)
        os.fsync(test_root_fd)

    formal_reopen_check()
except Exception:
    primary = 82
finally:
    close_records(owned)

if close_failures:
    close_rc = 78 if primary else 79
    print('M3_FAILURE stage=transaction-root-validation operation=transaction-root-binding reason=E_DESCRIPTOR_CLOSE rc=%d close_failures=%s primary_rc=%d' % (
        close_rc, json.dumps(close_failures, sort_keys=True, separators=(',', ':')), primary), file=sys.stderr)
    raise SystemExit(close_rc)
raise SystemExit(primary)
PY
}

m3_exports() {
  printf '%s\n' 'm3_fd_role_check m3_lexical_components m3_manifest_check m3_source_digest m3_entry_digest m3_auth_validate_pre_auth m3_build_binder_request m3_post_auth_validate m3_consume_ledger_post_auth m3_tx_plan m3_tx_stage m3_tx_install m3_tx_rollback m3_discard_stale_markers m3_dry_run agency269_m3_dry_run agency269_m3_apply_pre_auth agency269_m3_apply_post_auth stage_owner_plan install_owner_plan descriptor_no_follow_rename descriptor_no_follow_remove restore_from_journal verify_rollback_owner cleanup_created_dirs run_apply_with_rollback rollback_deferred_transaction m3_close_one m3_close_aggregate'
}

# Source-only compatibility helpers used by the isolated owner-path fixture.
# They are deliberately inert for the CLI and provide no production state.
load_canonical_role_profile() {
  AGENCY269_CANONICAL_ROLE_PROFILE_LOADED=1
  return 0
}

compute_manifest_source_root_digest() {
  [[ $# -eq 1 ]] || return 64
  python3 - "$1" <<'PY'
import hashlib
import os
import stat
import sys

root = sys.argv[1]
items = []
for dirpath, dirnames, filenames in os.walk(root, topdown=True, followlinks=False):
    dirnames.sort()
    filenames.sort()
    rel_dir = os.path.relpath(dirpath, root)
    if rel_dir != ".":
        items.append(("dir-entry", rel_dir, ""))
        items.append(("dir", rel_dir, ""))
    for name in filenames:
        path = os.path.join(dirpath, name)
        rel = name if rel_dir == "." else rel_dir + "/" + name
        st = os.lstat(path)
        if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode):
            raise SystemExit(1)
        with open(path, "rb") as fp:
            digest = hashlib.sha256(fp.read()).hexdigest()
        items.append(("file", rel, f"{st.st_size}:{int(st.st_mode & 0o7777)}:{digest}"))
items.sort()
hash_value = hashlib.sha256()
for kind, path, meta in items:
    hash_value.update(f"{kind}|{path}|{meta}\n".encode("utf-8"))
print('{"digest":"%s"}' % hash_value.hexdigest())
PY
}

build_owner_plan() {
  [[ $# -eq 8 ]] || return 64
  local source_root="$1" source_mode="$2" owner_tool="$3" owner_id="$4" owner_create="$5" source_digest="$6" protected_json="$7" plan_path="$8"
  python3 - "$source_root" "$source_mode" "$owner_tool" "$owner_id" "$owner_create" "$source_digest" "$protected_json" "$plan_path" <<'PY'
import json
import os
import sys

source_root, source_mode, tool, owner_id, create, digest, protected, plan = sys.argv[1:]
protected = set(json.loads(protected))
rows = []
if source_mode == "whole-file":
    rows.append((owner_id, "__whole_file__", "file", tool, create, digest))
else:
    for dirpath, dirnames, filenames in os.walk(source_root, topdown=True, followlinks=False):
        dirnames.sort()
        filenames.sort()
        for name in dirnames + filenames:
            path = os.path.join(dirpath, name)
            if os.path.islink(path):
                raise SystemExit(1)
            rel = os.path.relpath(path, source_root)
            kind = "directory" if os.path.isdir(path) else "file"
            if rel not in protected:
                rows.append((owner_id, rel, kind, tool, create, digest))
        if rows:
            break
if not rows:
    raise SystemExit(1)
with open(plan, "w", encoding="utf-8") as fp:
    for row in rows:
        fp.write("\t".join(str(value) for value in row) + "\n")
PY
}
if [[ "${AGENCY269_NO_CLI:-0}" != "1" ]]; then
  agency269_cli_main "$@"
fi
