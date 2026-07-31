#!/usr/bin/env python3
"""Deterministically resolve governance profiles from Agency Agent sources."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

_REPO_ROOT = Path(__file__).resolve().parents[1]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))
from governance import validate_profile

class GovernanceError(ValueError):
    """The source inventory or governance contract is invalid."""

@dataclass(frozen=True)
class Agent:
    role_id: str
    name: str
    division: str
    source_path: str
    source_sha256: str
    authority: str = ''

APPROVAL_MATRIX = {
    'low': 'self-service',
    'medium': 'current-user-approval',
    'high': 'current-user-and-supervisor',
    'write': 'current-user-and-supervisor',
    'external_side_effect': 'current-user-and-supervisor',
}

SENSITIVE_TERMS = (
    'security',
    'finance',
    'financial',
    'legal',
    'compliance',
    'production',
    'release',
    'permission',
    'external',
    'call',
    'telephony',
)

AUTHORITY_METADATA_KEYS = (
    'authority',
    'description',
    'responsibility',
    'responsibilities',
    'role',
    'mission',
    'scope',
)

_GOVERNANCE_VARIABLES = (
    'ROLE_NAME',
    'ALLOWED_READ_ACTIONS',
    'ALLOWED_WRITE_ACTIONS',
    'FORBIDDEN_ACTIONS',
    'RISK_RULES',
    'APPROVAL_MATRIX',
    'ALLOWED_SYSTEMS',
)
_FRONTMATTER_OPEN = re.compile(br'\A---[ \t]*\r?\n')
_FRONTMATTER_CLOSE = re.compile(br'(?m)^---[ \t]*\r?\n')
_GOVERNANCE_PROFILE_LINE = re.compile(
    br'(?m)^governance_profile:[^\r\n]*(?:\r?\n|$)'
)
_MUSTACHE_TOKEN = re.compile(r'\{\{[^{}\r\n]+\}\}')
_BINDING_TMP_PREFIX = '.governance-bind-'


def _frontmatter_profile_lines(frontmatter: bytes, path: Path) -> list[bytes]:
    return _GOVERNANCE_PROFILE_LINE.findall(frontmatter)


def _frontmatter_payload_without_governance(source: Path, content: bytes) -> bytes:
    start, body_start = _frontmatter_bounds(content, source)
    frontmatter = content[start:body_start]
    matches = list(_GOVERNANCE_PROFILE_LINE.finditer(frontmatter))
    if len(matches) > 1:
        raise GovernanceError('DUPLICATE_GOVERNANCE_PROFILE:{}'.format(source))
    if not matches:
        return content
    match = matches[0]
    return (
        content[:start] + frontmatter[:match.start()] + frontmatter[match.end():] + content[body_start:]
    )


def stable_source_hash(path: Path) -> str:
    content = path.read_bytes()
    payload = _frontmatter_payload_without_governance(path, content)
    return hashlib.sha256(payload).hexdigest()


def _frontmatter_bounds(content: bytes, path: Path) -> tuple[int, int]:
    """Return the first frontmatter body bounds and closing-fence end."""
    opening = _FRONTMATTER_OPEN.match(content)
    if opening is None:
        raise GovernanceError('MISSING_FRONTMATTER:{}'.format(path))
    closing = _FRONTMATTER_CLOSE.search(content, opening.end())
    if closing is None:
        raise GovernanceError('UNTERMINATED_FRONTMATTER:{}'.format(path))
    return opening.end(), closing.end()


def _parse_frontmatter_fields(frontmatter: str) -> dict[str, str]:
    """Parse top-level scalar fields without changing the original YAML bytes."""
    fields: dict[str, str] = {}
    for line in frontmatter.splitlines():
        if not line or line[:1].isspace() or ':' not in line:
            continue
        key, value = line.split(':', 1)
        key = key.strip()
        if not key:
            continue
        fields[key] = value.strip().strip('"').strip("'")
    return fields


def read_agent(path: Path) -> tuple[dict[str, str], str]:
    """Read only the first YAML frontmatter block and its unchanged persona body."""
    if path.is_symlink():
        raise GovernanceError('SYMLINKED_SOURCE:{}'.format(path))
    try:
        content = path.read_bytes()
    except OSError as error:
        raise GovernanceError('UNREADABLE_SOURCE:{}'.format(path)) from error
    start, body_start = _frontmatter_bounds(content, path)
    try:
        frontmatter = content[start:body_start].decode('utf-8')
        body = content[body_start:].decode('utf-8')
    except UnicodeDecodeError as error:
        raise GovernanceError('INVALID_UTF8_SOURCE:{}'.format(path)) from error
    return _parse_frontmatter_fields(frontmatter), body


def _source_paths(repo_root: Path) -> list[Path]:
    divisions = load_json(repo_root / 'divisions.json').get('divisions')
    if not isinstance(divisions, dict):
        raise GovernanceError('INVALID_DIVISIONS')
    paths: list[Path] = []
    for division in sorted(divisions):
        directory = repo_root / division
        if not directory.is_dir():
            raise GovernanceError('MISSING_DIVISION:{}'.format(division))
        for path in sorted(directory.rglob('*.md')):
            if path.is_symlink():
                raise GovernanceError('SYMLINKED_SOURCE:{}'.format(path))
            if path.is_file():
                paths.append(path)
    return paths

def load_json(path: Path) -> dict[str, Any]:
    try:
        result = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as error:
        raise GovernanceError('INVALID_JSON:{}'.format(path)) from error
    if not isinstance(result, dict):
        raise GovernanceError('EXPECTED_OBJECT:{}'.format(path))
    return result

def parse_frontmatter_agent(path: Path, repo_root: Path) -> Agent | None:
    if path.is_symlink():
        raise GovernanceError('SYMLINKED_SOURCE:{}'.format(path))
    content = path.read_bytes()
    text = content.decode('utf-8')
    if _FRONTMATTER_OPEN.match(content) is None:
        return None
    start, body_start = _frontmatter_bounds(content, path)
    closing = _FRONTMATTER_CLOSE.search(content, start)
    assert closing is not None
    try:
        frontmatter = content[start:closing.start()].decode('utf-8')
    except UnicodeDecodeError as error:
        raise GovernanceError('INVALID_UTF8_SOURCE:{}'.format(path)) from error
    metadata: dict[str, list[str]] = {key: [] for key in AUTHORITY_METADATA_KEYS}
    for line in frontmatter.splitlines():
        if ':' not in line:
            continue
        key, value = line.split(':', 1)
        key = key.strip().lower()
        value = value.strip().strip('"')
        if key in metadata and value and value not in metadata[key]:
            metadata[key].append(value)
    name = next(
        (
            line.split(':', 1)[1].strip().strip('"')
            for line in frontmatter.splitlines()
            if line.startswith('name:')
        ),
        '',
    )
    if not name:
        raise GovernanceError('MISSING_AGENT_NAME:{}'.format(path))
    authority = ' | '.join(
        value
        for key in AUTHORITY_METADATA_KEYS
        for value in metadata[key]
    )
    if not authority:
        raise GovernanceError('MISSING_AGENT_AUTHORITY:{}'.format(path))
    source_path = path.relative_to(repo_root).as_posix()
    return Agent(
        path.stem,
        name,
        source_path.split('/', 1)[0],
        source_path,
        stable_source_hash(path),
        authority,
    )

def discover_agents(repo_root: Path) -> list[Agent]:
    agents = []
    for path in _source_paths(repo_root):
        agent = parse_frontmatter_agent(path, repo_root)
        if agent is not None:
            agents.append(agent)
    agents.sort(key=lambda agent: agent.role_id)
    if len({agent.role_id for agent in agents}) != len(agents):
        raise GovernanceError('DUPLICATE_ROLE_ID')
    return agents

def _override(agent: Agent, overrides: dict[str, Any]) -> dict[str, Any]:
    result = overrides.get(agent.role_id, {})
    if not isinstance(result, dict):
        raise GovernanceError('INVALID_OVERRIDE:{}'.format(agent.role_id))
    return result

def is_sensitive_agent(agent: Agent) -> bool:
    title_or_authority = '{} {}'.format(agent.name, agent.authority).lower()
    return any(term in title_or_authority for term in SENSITIVE_TERMS)

def classify_risk(agent: Agent, policy: dict[str, Any], overrides: dict[str, Any]) -> str:
    override = _override(agent, overrides)
    if is_sensitive_agent(agent):
        if not override:
            raise GovernanceError('MISSING_SENSITIVE_OVERRIDE:{}'.format(agent.role_id))
        if override.get('risk_level') != 'high':
            raise GovernanceError('SENSITIVE_OVERRIDE_NOT_HIGH:{}'.format(agent.role_id))
    risk = override.get('risk_level', policy.get('risk_level'))
    if risk not in {'low', 'medium', 'high'}:
        raise GovernanceError('INVALID_RISK_LEVEL:{}'.format(agent.role_id))
    return risk

def resolve_profile(agent: Agent, policies: dict[str, Any], overrides: dict[str, Any]) -> dict[str, Any]:
    departments = policies.get('departments')
    if not isinstance(departments, dict) or not isinstance(departments.get(agent.division), dict):
        raise GovernanceError('MISSING_DEPARTMENT_POLICY:{}'.format(agent.division))
    policy = departments[agent.division]
    override = _override(agent, overrides)
    risk = classify_risk(agent, policy, overrides)
    profile = {
        'role_id': agent.role_id, 'role_name': agent.name,
        'division': agent.division, 'risk_level': risk,
        'allowed_read_actions': sorted(policy.get('allowed_read_actions', [])),
        'allowed_write_actions': [] if risk == 'high' else sorted(policy.get('allowed_write_actions', [])),
        'forbidden_actions': sorted(policy.get('forbidden_actions', [])),
        'risk_rules': sorted(policy.get('risk_rules', [])), 'allowed_systems': sorted(policy.get('allowed_systems', [])),
        'approval_matrix': dict(APPROVAL_MATRIX), 'source_hash': agent.source_sha256, 'source_path': agent.source_path,
        'policy_source': 'governance/department-policies.json#departments/{}'.format(agent.division),
        'exception_source': 'governance/role-overrides.json#{}'.format(agent.role_id) if override else 'governance/role-overrides.json#none',
    }
    errors = validate_profile(profile)
    if errors:
        raise GovernanceError('INVALID_PROFILE:{}:{}'.format(agent.role_id, ' | '.join(errors)))
    return profile

def build_profiles(repo_root: Path) -> list[dict[str, Any]]:
    policies = load_json(repo_root / 'governance/department-policies.json')
    overrides = load_json(repo_root / 'governance/role-overrides.json')
    return [resolve_profile(agent, policies, overrides) for agent in discover_agents(repo_root)]

def write_canonical_json(path: Path, document: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, ensure_ascii=False, sort_keys=True, indent=2) + '\n', encoding='utf-8')


def _profiles_by_id(repo_root: Path) -> dict[str, dict[str, Any]]:
    path = repo_root / 'governance/role-governance-profiles.json'
    try:
        document = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as error:
        raise GovernanceError('INVALID_PROFILE_INVENTORY:{}'.format(path)) from error
    if not isinstance(document, list):
        raise GovernanceError('INVALID_PROFILE_INVENTORY:{}'.format(path))
    profiles: dict[str, dict[str, Any]] = {}
    for profile in document:
        if not isinstance(profile, dict) or not isinstance(profile.get('role_id'), str):
            raise GovernanceError('INVALID_PROFILE')
        role_id = profile['role_id']
        if role_id in profiles:
            raise GovernanceError('DUPLICATE_PROFILE_ROLE_ID:{}'.format(role_id))
        errors = validate_profile(profile)
        if errors:
            raise GovernanceError('INVALID_PROFILE:{}:{}'.format(role_id, ' | '.join(errors)))
        profiles[role_id] = profile
    return profiles


def _relative_source(repo_root: Path, source: Path) -> tuple[Path, str]:
    root = repo_root.resolve()
    if source.is_symlink():
        raise GovernanceError('SYMLINKED_SOURCE:{}'.format(source))
    try:
        resolved = source.resolve(strict=True)
        relative = resolved.relative_to(root).as_posix()
    except (OSError, ValueError) as error:
        raise GovernanceError('SOURCE_OUTSIDE_REPOSITORY:{}'.format(source)) from error
    return resolved, relative


def _bound_profile(repo_root: Path, source: Path) -> tuple[dict[str, Any], str]:
    source, relative = _relative_source(repo_root, source)
    agents = {agent.source_path: agent for agent in discover_agents(repo_root)}
    agent = agents.get(relative)
    if agent is None:
        raise GovernanceError('UNKNOWN_AGENT_SOURCE:{}'.format(relative))
    raw = source.read_bytes()
    start, body_start = _frontmatter_bounds(raw, source)
    frontmatter = raw[start:body_start]
    matches = _frontmatter_profile_lines(frontmatter, source)
    if len(matches) > 1:
        raise GovernanceError('DUPLICATE_GOVERNANCE_PROFILE:{}'.format(relative))
    if not matches:
        raise GovernanceError('MISSING_GOVERNANCE_BINDING:{}'.format(relative))
    binding = (
        matches[0].split(b':', 1)[1]
        .decode('utf-8')
        .strip()
        .strip('"')
        .strip("'")
    )
    if not binding:
        raise GovernanceError('MISSING_GOVERNANCE_BINDING:{}'.format(relative))
    if binding != agent.role_id:
        raise GovernanceError('MISMATCHED_GOVERNANCE_BINDING:{}'.format(relative))
    profile = _profiles_by_id(repo_root).get(binding)
    if profile is None:
        raise GovernanceError('MISSING_GOVERNANCE_PROFILE:{}'.format(binding))
    if profile.get('source_path') != relative:
        raise GovernanceError('MISMATCHED_PROFILE_SOURCE:{}'.format(relative))
    if profile.get('source_hash') != stable_source_hash(source):
        raise GovernanceError('SOURCE_HASH_MISMATCH:{}'.format(relative))
    return profile, relative


def _compact_list(values: Any) -> str:
    if not isinstance(values, list):
        raise GovernanceError('INVALID_GOVERNANCE_LIST')
    return '无' if not values else '、'.join(str(value) for value in values)


def _compact_matrix(matrix: Any) -> str:
    if not isinstance(matrix, dict):
        raise GovernanceError('INVALID_APPROVAL_MATRIX')
    labels = {
        'low': '低风险',
        'medium': '中风险',
        'high': '高风险',
        'write': '写入',
        'external_side_effect': '外部副作用',
    }
    return '；'.join(
        '{}：{}'.format(labels[key], matrix[key])
        for key in ('low', 'medium', 'high', 'write', 'external_side_effect')
        if key in matrix
    )


def render_governance(repo_root: Path, source: Path) -> str:
    """Render the canonical governance prompt for one correctly bound source."""
    profile, _ = _bound_profile(repo_root.resolve(), source)
    template_path = repo_root / 'governance/base-prompt.zh-CN.md'
    try:
        template = template_path.read_text(encoding='utf-8')
    except OSError as error:
        raise GovernanceError('MISSING_GOVERNANCE_TEMPLATE:{}'.format(template_path)) from error
    variables = set(re.findall(r'\{\{([A-Z_]+)\}\}', template))
    if variables != set(_GOVERNANCE_VARIABLES):
        raise GovernanceError('INVALID_GOVERNANCE_VARIABLE_SET')
    resolved = {
        'ROLE_NAME': str(profile['role_name']),
        'ALLOWED_READ_ACTIONS': _compact_list(profile['allowed_read_actions']),
        'ALLOWED_WRITE_ACTIONS': _compact_list(profile['allowed_write_actions']),
        'FORBIDDEN_ACTIONS': _compact_list(profile['forbidden_actions']),
        'RISK_RULES': _compact_list(profile['risk_rules']),
        'APPROVAL_MATRIX': _compact_matrix(profile['approval_matrix']),
        'ALLOWED_SYSTEMS': _compact_list(profile['allowed_systems']),
    }
    rendered = template
    for key in _GOVERNANCE_VARIABLES:
        rendered = rendered.replace('{{{{{}}}}}'.format(key), resolved[key])
    if _MUSTACHE_TOKEN.search(rendered):
        raise GovernanceError('UNRESOLVED_GOVERNANCE_VARIABLE')
    return rendered


def render_governed_body(repo_root: Path, source: Path) -> str:
    """Return governance instructions followed by the unmodified persona body."""
    governance = render_governance(repo_root, source)
    _, persona_body = read_agent(source)
    return '{}\n\n{}'.format(governance.rstrip('\n'), persona_body)


def _bound_source_bytes(path: Path, role_id: str) -> bytes:
    if path.is_symlink():
        raise GovernanceError('SYMLINKED_SOURCE:{}'.format(path))
    raw = path.read_bytes()
    start, _ = _frontmatter_bounds(raw, path)
    closing = _FRONTMATTER_CLOSE.search(raw, start)
    assert closing is not None
    frontmatter = raw[start:closing.start()]
    match_list = list(_GOVERNANCE_PROFILE_LINE.finditer(frontmatter))
    if len(match_list) > 1:
        raise GovernanceError('DUPLICATE_GOVERNANCE_PROFILE:{}'.format(path))
    if len(match_list) == 1:
        match = match_list[0]
        current = (
            match.group(0).split(b':', 1)[1]
            .decode('utf-8')
            .strip()
            .strip('"')
            .strip("'")
        )
        if current == role_id:
            return raw
    newline = b'\r\n' if b'\r\n' in raw[:closing.end()] else b'\n'
    replacement = b'governance_profile: ' + role_id.encode('utf-8') + newline
    if match_list:
        match = match_list[0]
        updated_frontmatter = (
            frontmatter[:match.start()] + replacement + frontmatter[match.end():]
        )
        return raw[:start] + updated_frontmatter + raw[closing.start():]
    return raw[:closing.start()] + replacement + raw[closing.start():]


def _write_staged_file(path: Path, replacement: bytes) -> tuple[Path, int]:
    mode = path.stat().st_mode & 0o777
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=_BINDING_TMP_PREFIX + path.name + '.', suffix='.tmp', dir=str(path.parent)
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, 'wb') as handle:
            handle.write(replacement)
            handle.flush()
            os.fsync(handle.fileno())
            os.fchmod(handle.fileno(), mode)
    except OSError as error:
        temporary.unlink(missing_ok=True)
        raise GovernanceError('ATOMIC_WRITE_PREPARE_FAILED:{}'.format(path)) from error
    return temporary, mode


def _replace_from_temp(temporary: Path, destination: Path) -> None:
    try:
        os.replace(temporary, destination)
    except OSError as error:
        raise GovernanceError('ATOMIC_SOURCE_REPLACE_FAILED:{}'.format(destination)) from error


def _rollback_to_original(
    destination: Path,
    original: bytes,
    mode: int,
) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=_BINDING_TMP_PREFIX + destination.name + '.', suffix='.tmp', dir=str(destination.parent)
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, 'wb') as handle:
            handle.write(original)
            handle.flush()
            os.fsync(handle.fileno())
            os.fchmod(handle.fileno(), mode)
        _replace_from_temp(temporary, destination)
    except OSError as error:
        temporary.unlink(missing_ok=True)
        raise GovernanceError('BIND_ROLLBACK_FAILED:{}'.format(destination)) from error


def bind_sources(repo_root: Path) -> int:
    """Atomically add or correct one profile binding in every discovered source."""
    repo_root = repo_root.resolve()
    agents = discover_agents(repo_root)
    profiles = _profiles_by_id(repo_root)
    if len(agents) != len(profiles):
        raise GovernanceError('PROFILE_DISCOVERY_COUNT_MISMATCH')
    replacements: list[tuple[Path, Path, bytes, int]] = []
    prepared_temps: list[Path] = []
    for agent in agents:
        profile = profiles.get(agent.role_id)
        if profile is None or profile.get('source_path') != agent.source_path:
            raise GovernanceError('MISSING_OR_MISMATCHED_PROFILE:{}'.format(agent.role_id))
        path = repo_root / agent.source_path
        replacement = _bound_source_bytes(path, agent.role_id)
        current = stable_source_hash(path)
        if current != profile.get('source_hash'):
            raise GovernanceError('SOURCE_HASH_MISMATCH:{}'.format(agent.role_id))
        original = path.read_bytes()
        if replacement != original:
            try:
                temporary, mode = _write_staged_file(path, replacement)
            except GovernanceError:
                for cleanup in prepared_temps:
                    cleanup.unlink(missing_ok=True)
                raise
            replacements.append((path, temporary, original, mode))
            prepared_temps.append(temporary)
    if not replacements:
        return 0

    replaced: list[tuple[Path, bytes, int]] = []
    for index, (path, temporary, original, mode) in enumerate(replacements):
        try:
            _replace_from_temp(temporary, path)
            replaced.append((path, original, mode))
            temporary.unlink(missing_ok=True)
        except GovernanceError as error:
            failure = GovernanceError('BIND_REPLACE_FAILED:{}'.format(path))
            rollback_errors: list[str] = []
            for rollback_path, rollback_original, rollback_mode in reversed(replaced):
                try:
                    _rollback_to_original(rollback_path, rollback_original, rollback_mode)
                except GovernanceError as rollback_error:
                    rollback_errors.append(str(rollback_error))
            for rollback_temp in (item[1] for item in replacements[index:]):
                rollback_temp.unlink(missing_ok=True)
            if rollback_errors:
                raise GovernanceError(
                    'ROLLBACK_FAILED:{}'.format(';'.join(rollback_errors))
                ) from failure
            raise failure from error

    for temporary in prepared_temps:
        if temporary.exists():
            temporary.unlink(missing_ok=True)
    return len(replacements)


def verify_bindings(repo_root: Path) -> int:
    """Verify every discovered agent has one exact profile binding."""
    repo_root = repo_root.resolve()
    agents = discover_agents(repo_root)
    profiles = _profiles_by_id(repo_root)
    if len(agents) != len(profiles):
        raise GovernanceError('PROFILE_DISCOVERY_COUNT_MISMATCH')
    for agent in agents:
        profile, _ = _bound_profile(repo_root, repo_root / agent.source_path)
        if profile['role_id'] != agent.role_id:
            raise GovernanceError('MISMATCHED_GOVERNANCE_BINDING:{}'.format(agent.source_path))
    return len(agents)

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    build = commands.add_parser('build-profiles')
    build.add_argument('--repo-root', type=Path, required=True)
    build.add_argument('--output', type=Path, required=True)
    bind = commands.add_parser('bind-sources')
    bind.add_argument('--repo-root', type=Path, required=True)
    render = commands.add_parser('render')
    render.add_argument('--repo-root', type=Path, required=True)
    render.add_argument('--source', type=Path, required=True)
    verify = commands.add_parser('verify-bindings')
    verify.add_argument('--repo-root', type=Path, required=True)
    args = parser.parse_args(argv)
    if args.command == 'build-profiles':
        write_canonical_json(args.output, build_profiles(args.repo_root.resolve()))
        return 0
    if args.command == 'bind-sources':
        print(bind_sources(args.repo_root))
        return 0
    if args.command == 'render':
        print(render_governed_body(args.repo_root.resolve(), args.source))
        return 0
    if args.command == 'verify-bindings':
        print(verify_bindings(args.repo_root))
        return 0
    raise GovernanceError('UNKNOWN_COMMAND')

if __name__ == '__main__':
    raise SystemExit(main())
