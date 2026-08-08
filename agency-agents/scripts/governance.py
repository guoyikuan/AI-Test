#!/usr/bin/env python3
"""Deterministically resolve governance profiles from Agency Agent sources."""
from __future__ import annotations

from datetime import datetime, timezone
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
try:
    import tomllib
except ImportError:  # pragma: no cover - py<3.11 compatibility fallback
    import tomli as tomllib

_REPO_ROOT = Path(__file__).resolve().parents[1]
if str(_REPO_ROOT) in sys.path:
    sys.path.remove(str(_REPO_ROOT))
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
}

SIDE_EFFECTS = (
    'write',
    'external_side_effect',
)

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
_UNRESOLVED_GOVERNANCE_TOKEN = re.compile(
    r"\{\{(?:ROLE_NAME|ALLOWED_READ_ACTIONS|ALLOWED_WRITE_ACTIONS|FORBIDDEN_ACTIONS|RISK_RULES|APPROVAL_MATRIX|ALLOWED_SYSTEMS)\}\}"
)
_SENSITIVE_TOKEN_PATTERNS = (
    (
        "PEM_PRIVATE_KEY_BLOCK",
        re.compile(
            r"-----BEGIN[^\n]*PRIVATE KEY-----.*?-----END[^\n]*PRIVATE KEY-----",
            re.IGNORECASE | re.DOTALL,
        ),
    ),
    (
        "LONG_SECRET_CREDENTIAL",
        re.compile(
            r"(?i)\b(?:api[_-]?key|access[_-]?token|auth(?:orization)?\s*token|secret[_-]?key)\s*[:=]\s*['\"]?[A-Za-z0-9_+/=-]{24,}['\"]?",
        ),
    ),
)
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


def _get_raw_frontmatter_value(path: Path, key: str) -> str | None:
    """Return raw frontmatter value for a key, preserving surrounding quotes.

    This mirrors the legacy Bash `get_field` behavior used by convert.sh.
    """
    try:
        content = path.read_bytes()
    except OSError:
        return None
    start, body_start = _frontmatter_bounds(content, path)
    if start is None:
        return None
    try:
        frontmatter = content[start:body_start].decode("utf-8")
    except UnicodeDecodeError:
        return None
    for line in frontmatter.splitlines():
        if line.startswith(f"{key}: "):
            return line[len(f"{key}: "):]
    return None


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
        'approval_matrix': dict(APPROVAL_MATRIX),
        'side_effects': list(SIDE_EFFECTS) if risk == 'high' else [],
        'source_hash': agent.source_sha256, 'source_path': agent.source_path,
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


def _bound_profile(
    repo_root: Path,
    source: Path,
    *,
    agents_by_source: dict[str, Agent] | None = None,
    profiles_by_id: dict[str, dict[str, Any]] | None = None,
) -> tuple[dict[str, Any], str]:
    source, relative = _relative_source(repo_root, source)
    if agents_by_source is None:
        agents_by_source = {
            agent.source_path: agent for agent in discover_agents(repo_root)
        }
    if profiles_by_id is None:
        profiles_by_id = _profiles_by_id(repo_root)
    agent = agents_by_source.get(relative)
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
    profile = profiles_by_id.get(binding)
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


def _compact_matrix(matrix: Any, side_effects: Any = ()) -> str:
    if not isinstance(matrix, dict):
        raise GovernanceError('INVALID_APPROVAL_MATRIX')
    labels = {
        'low': '低风险',
        'medium': '中风险',
        'high': '高风险',
        'write': '写入',
        'external_side_effect': '外部副作用',
    }
    requested_side_effects = (
        side_effects
        if isinstance(side_effects, (list, tuple))
        else ()
    )
    return '；'.join(
        '{}：{}'.format(
            labels[key],
            matrix.get(key, '无'),
        )
        for key in ('low', 'medium', 'high')
        if key in matrix or key in ('low', 'medium', 'high')
    ) + '；{}：{}'.format(
        labels['write'],
        matrix['high'] if 'write' in requested_side_effects else '无',
    ) + '；{}：{}'.format(
        labels['external_side_effect'],
        matrix['high'] if 'external_side_effect' in requested_side_effects else '无',
    )


def _collect_cleanup_failures(temporary_paths: list[Path]) -> list[str]:
    failures: list[str] = []
    for temporary in temporary_paths:
        try:
            if temporary.exists():
                os.unlink(temporary)
        except OSError as error:
            failures.append('{}:{}'.format(temporary, error))
    return failures


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
        'APPROVAL_MATRIX': _compact_matrix(
            profile['approval_matrix'],
            profile.get('side_effects', ()),
        ),
        'ALLOWED_SYSTEMS': _compact_list(profile['allowed_systems']),
    }
    rendered = template
    for key in _GOVERNANCE_VARIABLES:
        rendered = rendered.replace('{{{{{}}}}}'.format(key), resolved[key])
    if _UNRESOLVED_GOVERNANCE_TOKEN.search(rendered):
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
        cleanup_failures = _collect_cleanup_failures([temporary])
        if cleanup_failures:
            raise GovernanceError(
                'ATOMIC_WRITE_PREPARE_FAILED:{}:{}'.format(path, ';'.join(cleanup_failures))
            ) from error
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
    except (OSError, GovernanceError) as error:
        cleanup_failures = _collect_cleanup_failures([temporary])
        if cleanup_failures:
            raise GovernanceError(
                'ROLLBACK_FAILED:{}'.format(';'.join(cleanup_failures))
            ) from error
        raise GovernanceError('BIND_ROLLBACK_FAILED:{}'.format(destination)) from error
    cleanup_failures = _collect_cleanup_failures([temporary])
    if cleanup_failures:
        raise GovernanceError(
            'BIND_CLEANUP_FAILED:{}'.format(';'.join(cleanup_failures))
        )


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
                cleanup_failures = _collect_cleanup_failures(prepared_temps)
                if cleanup_failures:
                    raise GovernanceError(
                        'BIND_CLEANUP_FAILED:{}'.format(';'.join(cleanup_failures))
                    )
                raise
            replacements.append((path, temporary, original, mode))
            prepared_temps.append(temporary)
    if not replacements:
        return 0

    replaced: list[tuple[Path, bytes, int]] = []
    for path, temporary, original, mode in replacements:
        try:
            _replace_from_temp(temporary, path)
            replaced.append((path, original, mode))
        except GovernanceError as error:
            failure = GovernanceError('BIND_REPLACE_FAILED:{}'.format(path))
            rollback_errors: list[str] = []
            for rollback_path, rollback_original, rollback_mode in reversed(replaced):
                try:
                    _rollback_to_original(rollback_path, rollback_original, rollback_mode)
                except GovernanceError as rollback_error:
                    rollback_errors.append(str(rollback_error))
            cleanup_failures = _collect_cleanup_failures(
                [item[1] for item in replacements]
            )
            if rollback_errors:
                if cleanup_failures:
                    rollback_errors.extend(cleanup_failures)
                raise GovernanceError(
                    'ROLLBACK_FAILED:{}'.format(';'.join(rollback_errors))
                ) from error
            if cleanup_failures:
                raise GovernanceError(
                    'BIND_CLEANUP_FAILED:{}'.format(';'.join(cleanup_failures))
                ) from error
            raise failure from error

    cleanup_failures = _collect_cleanup_failures(prepared_temps)
    if cleanup_failures:
        raise GovernanceError(
            'BIND_CLEANUP_FAILED:{}'.format(';'.join(cleanup_failures))
        )
    return len(replacements)


def verify_bindings(repo_root: Path) -> int:
    """Verify every discovered agent has one exact profile binding."""
    repo_root = repo_root.resolve()
    agents = discover_agents(repo_root)
    profiles = _profiles_by_id(repo_root)
    agents_by_source = {agent.source_path: agent for agent in agents}
    if len(agents) != len(profiles):
        raise GovernanceError('PROFILE_DISCOVERY_COUNT_MISMATCH')
    for agent in agents:
        profile, _ = _bound_profile(
            repo_root,
            repo_root / agent.source_path,
            agents_by_source=agents_by_source,
            profiles_by_id=profiles,
        )
        if profile['role_id'] != agent.role_id:
            raise GovernanceError('MISMATCHED_GOVERNANCE_BINDING:{}'.format(agent.source_path))
    return len(agents)


def _load_tools_list(repo_root: Path) -> list[str]:
    tools_document = load_json(repo_root / "tools.json")
    tools_section = tools_document.get("tools")
    if not isinstance(tools_section, dict):
        raise GovernanceError('INVALID_TOOLS_MANIFEST')
    return sorted(tools_section.keys())


def _resolve_directory_before_traversal(
    path: Path,
    *,
    symlink_code: str,
    invalid_code: str,
) -> Path:
    if path.is_symlink():
        raise GovernanceError('{}:{}'.format(symlink_code, path))
    try:
        resolved = path.resolve(strict=True)
    except OSError as error:
        raise GovernanceError('{}:{}'.format(invalid_code, path)) from error
    if not resolved.is_dir():
        raise GovernanceError('{}:{}'.format(invalid_code, path))
    return resolved


def _collect_manifest_entries(root: Path, output: Path | None = None) -> list[dict[str, Any]]:
    root_path = _resolve_directory_before_traversal(
        root,
        symlink_code='MANIFEST_ROOT_SYMLINK',
        invalid_code='INVALID_MANIFEST_ROOT',
    )
    output_path = output.resolve() if output is not None else None
    managed_roots = set(_expected_tool_directories().values())
    for managed_root in sorted(managed_roots):
        tool_root = root / managed_root
        if tool_root.is_symlink():
            raise GovernanceError('MANIFEST_TOOL_ROOT_SYMLINK:{}'.format(tool_root))
        if not tool_root.exists():
            continue
        try:
            tool_root.resolve(strict=True).relative_to(root_path)
        except (OSError, ValueError) as error:
            raise GovernanceError(
                'MANIFEST_TOOL_ROOT_OUTSIDE_ROOT:{}'.format(tool_root)
            ) from error

    entries: list[dict[str, Any]] = []
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        if path.is_symlink():
            raise GovernanceError('MANIFEST_ENTRY_SYMLINK:{}'.format(path))
        if not path.is_file():
            continue
        relative = path.relative_to(root)
        if relative.parts[0] not in managed_roots or path.name == "README.md":
            continue
        try:
            resolved = path.resolve(strict=True)
            resolved.relative_to(root_path)
        except (OSError, ValueError) as error:
            raise GovernanceError('MANIFEST_ENTRY_OUTSIDE_ROOT:{}'.format(path)) from error
        if output_path is not None and resolved == output_path:
            continue
        body = path.read_bytes()
        entries.append({
            "path": relative.as_posix(),
            "bytes": len(body),
            "sha256": hashlib.sha256(body).hexdigest(),
        })
    return entries


def _read_file_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        raise GovernanceError('MISSING_GENERATED_FILE:{}'.format(path)) from error


def _expected_frontmatter_text(fields: list[str], body: str) -> str:
    """Build the exact markdown artifact text used by the converters."""
    frontmatter = ["---"] + fields + ["---"]
    return "{}\n{}\n".format("\n".join(frontmatter), body)


def _resolve_opencode_color(color_value: str) -> str:
    mapped = color_value.strip().lower()
    colors = {
        "cyan": "#00FFFF",
        "blue": "#3498DB",
        "green": "#2ECC71",
        "red": "#E74C3C",
        "purple": "#9B59B6",
        "orange": "#F39C12",
        "teal": "#008080",
        "indigo": "#6366F1",
        "pink": "#E84393",
        "gold": "#EAB308",
        "amber": "#F59E0B",
        "neon-green": "#10B981",
        "neon-cyan": "#06B6D4",
        "metallic-blue": "#3B82F6",
        "yellow": "#EAB308",
        "violet": "#8B5CF6",
        "rose": "#F43F5E",
        "lime": "#84CC16",
        "gray": "#6B7280",
        "fuchsia": "#D946EF",
    }
    if re.fullmatch(r"#[0-9a-f]{6}", mapped, flags=re.IGNORECASE):
        return "#%s" % mapped[-6:].upper()
    return colors.get(mapped, "#6B7280")


def _expected_aider_section(name: str, description: str, body: str) -> str:
    return "\n---\n\n## {}\n\n> {}\n\n{}\n".format(
        name,
        description,
        body,
    )


def _expected_windsurf_section(name: str, description: str, body: str) -> str:
    return "\n\n================================================================================\n## {}\n{}\n================================================================================\n\n{}\n".format(
        name,
        description,
        body,
    )


_AIDER_HEADER = """# The Agency — AI Agent Conventions
#
# This file provides Aider with the full roster of specialized AI agents from
# The Agency (https://github.com/msitarzewski/agency-agents).
#
# To activate an agent, reference it by name in your Aider session prompt, e.g.:
#   "Use the Frontend Developer agent to review this component."
#
# Generated by scripts/convert.sh — do not edit manually.

"""

_WINDSURF_HEADER = """# The Agency — AI Agent Rules for Windsurf
#
# Full roster of specialized AI agents from The Agency.
# To activate an agent, reference it by name in your Windsurf conversation.
#
# Generated by scripts/convert.sh — do not edit manually.

"""


def _expected_aider_document(sections: list[str]) -> str:
    return _AIDER_HEADER + ''.join(sections)


def _expected_windsurf_document(sections: list[str]) -> str:
    if not sections:
        return _WINDSURF_HEADER
    normalized_sections = [
        section.removeprefix("\n") + "\n" for section in sections
    ]
    return _WINDSURF_HEADER + normalized_sections[0] + ''.join(normalized_sections[1:])


def _expected_agent_output_texts(
    agent: Agent,
    source_fields: dict[str, str],
    rendered_governance: str,
    rendered_body: str,
    persona_body: str,
    source_path: Path | None = None,
) -> tuple[dict[str, str], list[str]]:
    """Return expected text map and expected section blocks for aggregate tools."""
    rendered_governance = rendered_governance.rstrip("\n")
    rendered_body = rendered_body.rstrip("\n")
    persona_body = persona_body.rstrip("\n")
    slug = _slugify(agent.name)
    description = source_fields.get('description', '')
    name = source_fields.get('name', agent.name)
    prompt_description = description
    prompt_name = name
    if source_path is not None:
        prompt_name = _get_raw_frontmatter_value(source_path, "name") or name
        prompt_description = _get_raw_frontmatter_value(source_path, "description") or description
        description = prompt_description
    tools = source_fields.get('tools', '')
    emoji = source_fields.get('emoji', '')
    vibe = source_fields.get('vibe', '')

    aggregate_sections = [
        _expected_aider_section(prompt_name, description, rendered_body),
        _expected_windsurf_section(prompt_name, description, rendered_body),
    ]

    outputs: dict[str, str] = {
        "antigravity/agency-{}/SKILL.md".format(slug): _expected_frontmatter_text(
            ["name: agency-{}".format(slug), "description: {}".format(description)],
            rendered_body,
        ),
        "osaurus/agency-{}/SKILL.md".format(slug): _expected_frontmatter_text(
            ["name: agency-{}".format(slug), "description: {}".format(description)],
            rendered_body,
        ),
        "codex/agents/{}.toml".format(slug): "",
        "gemini-cli/agents/{}.md".format(slug): _expected_frontmatter_text(
            ["name: {}".format(slug), "description: {}".format(description)],
            rendered_body,
        ),
        "opencode/agents/{}.md".format(slug): _expected_frontmatter_text(
            [
                "name: {}".format(name),
                "description: {}".format(description),
                "mode: subagent",
                "color: '{}'".format(_resolve_opencode_color(source_fields.get("color", "gray"))),
            ],
            rendered_body,
        ),
        "cursor/rules/{}.mdc".format(slug): _expected_frontmatter_text(
            [
                "description: {}".format(description),
                'globs: ""',
                "alwaysApply: false",
            ],
            rendered_body,
        ),
        "qwen/agents/{}.md".format(slug): _expected_frontmatter_text(
            ["name: {}".format(slug), "description: {}".format(description)] + ([]
                if not tools
                else ["tools: {}".format(tools)]),
            rendered_body,
        ),
        "zcode/agents/{}.md".format(slug): _expected_frontmatter_text(
            ["name: {}".format(slug), "description: {}".format(description)] + ([]
                if not tools else ["tools: {}".format(tools)]),
            rendered_body,
        ),
        "kimi/{}/agent.yaml".format(slug): "version: 1\nagent:\n  name: {}\n  extend: default\n  system_prompt_path: ./system.md\n".format(
            slug,
        ),
        "kimi/{}/system.md".format(slug): "# {}\n\n{}\n\n{}\n".format(
            prompt_name,
            prompt_description,
            rendered_body,
        ),
        "vibe/agents/{}.toml".format(slug): 'agent_type = "agent"\nsystem_prompt_id = "{}"\n'.format(
            slug
        ),
        "vibe/prompts/{}.md".format(slug): "# {}\n\n{}\n\n{}\n".format(
            prompt_name,
            prompt_description,
            rendered_body,
        ),
        "claude-code/agents/{}.md".format(slug): _expected_frontmatter_text(
            ["name: {}".format(name), "description: {}".format(description)],
            rendered_body,
        ),
        "copilot/agents/{}.md".format(slug): _expected_frontmatter_text(
            ["name: {}".format(name), "description: {}".format(description)],
            rendered_body,
        ),
        "openclaw/{}/AGENTS.md".format(slug): "{}\n".format(rendered_governance),
        "openclaw/{}/SOUL.md".format(slug): "{}".format(persona_body),
    }
    if emoji and vibe:
        outputs["openclaw/{}/IDENTITY.md".format(slug)] = "# {} {}\n{}\n".format(emoji, name, vibe)
    else:
        outputs["openclaw/{}/IDENTITY.md".format(slug)] = "# {}\n{}\n".format(name, description)

    return outputs, aggregate_sections


def _assert_file_contents(path: Path, expected: str) -> None:
    actual = _read_file_text(path)
    if actual != expected:
        raise GovernanceError('TOOL_FILE_MISMATCH:{}'.format(path))


def _slugify(value: str) -> str:
    return re.sub(r'[^a-z0-9]+', '-', value.lower()).strip('-')


def _load_toml(path: Path) -> dict[str, Any]:
    try:
        text = path.read_text(encoding='utf-8')
    except OSError as error:
        raise GovernanceError('MISSING_GENERATED_FILE:{}'.format(path)) from error
    try:
        return tomllib.loads(text)
    except (tomllib.TOMLDecodeError, ValueError) as error:
        raise GovernanceError('INVALID_GENERATED_TOML:{}'.format(path)) from error


def _count_files(root: Path, pattern: str) -> int:
    return len(list(root.glob(pattern))) if root.exists() else 0


def _count_directories(root: Path) -> int:
    return len([entry for entry in root.iterdir() if entry.is_dir()]) if root.exists() else 0


def _count_openclaw_workspaces(root: Path) -> int:
    if not root.exists():
        return 0
    count = 0
    for entry in root.iterdir():
        if not entry.is_dir():
            continue
        if (entry / "SOUL.md").is_file() and (entry / "AGENTS.md").is_file():
            count += 1
    return count


def _count_markdown_sections(path: Path) -> int:
    text = _read_file_text(path).replace("\\r\\n", "\\n")
    return len(re.findall(r"(?m)^## ", text))


def _count_aider_sections(path: Path) -> int:
    text = _read_file_text(path).replace("\\r\\n", "\\n")
    return len(re.findall(r"\n---\n\n## ", text))


def _count_windsurf_sections(path: Path) -> int:
    text = _read_file_text(path).replace("\\r\\n", "\\n")
    return text.count("\n================================================================================\n## ")


def _hash_hex(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _load_agents_json(repo_root: Path) -> list[dict[str, Any]]:
    data_root = repo_root / "data"
    path = data_root / "agents.json"
    if data_root.is_symlink() or path.is_symlink():
        raise GovernanceError('HERMES_ARTIFACT_SYMLINK:{}'.format(path))
    try:
        resolved_root = repo_root.resolve(strict=True)
        path.resolve(strict=True).relative_to(resolved_root)
    except (OSError, ValueError) as error:
        raise GovernanceError('HERMES_ARTIFACT_OUTSIDE_ROOT:{}'.format(path)) from error
    if not path.is_file():
        raise GovernanceError('MISSING_HERMES_AGENTS_JSON:{}'.format(path))
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise GovernanceError('INVALID_HERMES_AGENTS_JSON:{}'.format(path)) from error
    if not isinstance(payload, list):
        raise GovernanceError('INVALID_HERMES_AGENTS_JSON:{}'.format(path))
    return payload


def _validate_unresolved_governance_tokens(text: str, target: Path) -> None:
    unresolved = _UNRESOLVED_GOVERNANCE_TOKEN.search(text)
    if unresolved:
        raise GovernanceError(
            'UNRESOLVED_GOVERNANCE_TOKEN:{}:{}'.format(target.as_posix(), unresolved.group(0))
        )


def _file_sha256(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as error:
        raise GovernanceError('MISSING_SOURCE_INPUT:{}'.format(path)) from error


def _collect_source_input_hashes(repo_root: Path) -> dict[str, str]:
    paths = {
        "department_policies": repo_root / "governance" / "department-policies.json",
        "role_overrides": repo_root / "governance" / "role-overrides.json",
        "role_governance_profiles": repo_root / "governance" / "role-governance-profiles.json",
        "tools": repo_root / "tools.json",
    }
    return {name: _file_sha256(path) for name, path in paths.items()}


def _ensure_token_free_texts(generated_root: Path) -> dict[str, Any]:
    generated_root = generated_root.resolve()
    matches: list[dict[str, str]] = []
    by_label: dict[str, int] = {
        label: 0 for label, _ in _SENSITIVE_TOKEN_PATTERNS
    }
    for path in sorted(generated_root.rglob("*")):
        if path.is_symlink():
            raise GovernanceError('GENERATED_ARTIFACT_SYMLINK:{}'.format(path))
        if not path.is_file():
            continue
        try:
            path.resolve(strict=True).relative_to(generated_root)
        except (OSError, ValueError) as error:
            raise GovernanceError(
                'GENERATED_ARTIFACT_OUTSIDE_ROOT:{}'.format(path)
            ) from error
        if path.name == "manifest.json":
            continue
        if path.name.endswith(".pyc"):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for label, pattern in _SENSITIVE_TOKEN_PATTERNS:
            if pattern.search(text):
                by_label[label] = by_label.get(label, 0) + 1
                matches.append({"label": label, "path": path.as_posix()})
                break
        _validate_unresolved_governance_tokens(text, path)

    return {
        "total_hits": len(matches),
        "by_label": by_label,
        "matches": matches,
    }


def verify_all(
    repo_root: Path,
    generated_root: Path,
    *,
    expected_agents: int | None = None,
    expected_tools: int | None = None,
) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    generated_root = _resolve_directory_before_traversal(
        generated_root,
        symlink_code='GENERATED_ROOT_SYMLINK',
        invalid_code='MISSING_GENERATED_ROOT',
    )
    tools = _load_tools_list(repo_root)
    discovered_agents = discover_agents(repo_root)
    if expected_agents is None:
        expected_agents = len(discovered_agents)
    elif expected_agents <= 0:
        raise GovernanceError('INVALID_EXPECTATION')

    if expected_tools is None:
        expected_tools = len(tools)
    elif expected_tools <= 0:
        raise GovernanceError('INVALID_EXPECTATION')

    verify_bindings(repo_root)
    generated_summary = verify_generated(
        repo_root,
        generated_root,
        expected_agents,
        expected_tools,
    )
    manifest_entries = _collect_manifest_entries(generated_root)
    manifest_payload = json.dumps(
        manifest_entries, ensure_ascii=False, sort_keys=True, indent=2
    ).encode("utf-8")
    manifest_hash = hashlib.sha256(manifest_payload).hexdigest()
    managed_roots = sorted(set(_expected_tool_directories().values()))
    manifest_roots = sorted(
        {entry["path"].split("/", 1)[0] for entry in manifest_entries}
    )
    if manifest_roots != managed_roots:
        raise GovernanceError(
            'VERIFY_ALL_MANIFEST_TOOL_MISMATCH:{}:{}'.format(
                ",".join(manifest_roots),
                ",".join(managed_roots),
            )
        )

    return {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "environment": {
            "python": sys.version.split()[0],
            "repo_root": repo_root.as_posix(),
            "generated_root": generated_root.as_posix(),
        },
        "acceptance": {
            "expected_agents": expected_agents,
            "expected_tools": expected_tools,
            "exact_count_required": True,
        },
        "source_input_hashes": _collect_source_input_hashes(repo_root),
        "generated_summary": generated_summary,
        "manifest": {
            "tool_roots": managed_roots,
            "manifest_roots": manifest_roots,
            "entry_count": len(manifest_entries),
            "sha256": manifest_hash,
        },
        "unresolved_blockers": [],
        "rollback_reference": {
            "source_agents": [agent.role_id for agent in sorted(discovered_agents, key=lambda agent: agent.role_id)],
        },
    }

def _expected_tool_directories() -> dict[str, str]:
    return {
        "antigravity": "antigravity",
        "gemini-cli": "gemini-cli",
        "opencode": "opencode",
        "cursor": "cursor",
        "aider": "aider",
        "windsurf": "windsurf",
        "openclaw": "openclaw",
        "qwen": "qwen",
        "zcode": "zcode",
        "kimi": "kimi",
        "codex": "codex",
        "osaurus": "osaurus",
        "hermes": "hermes",
        "vibe": "vibe",
        "claude-code": "claude-code",
        "copilot": "github-copilot",
    }


def _load_source_agent_count(repo_root: Path) -> int:
    return len(discover_agents(repo_root))


def _controlled_generated_path(
    generated_root: Path,
    path: Path,
    *,
    directory: bool = False,
) -> Path:
    try:
        relative = path.relative_to(generated_root)
    except ValueError as error:
        raise GovernanceError('GENERATED_ARTIFACT_OUTSIDE_ROOT:{}'.format(path)) from error

    cursor = generated_root
    for part in relative.parts:
        cursor = cursor / part
        if cursor.is_symlink():
            raise GovernanceError('GENERATED_ARTIFACT_SYMLINK:{}'.format(cursor))

    if directory:
        if not path.is_dir():
            raise GovernanceError('MISSING_GENERATED_DIRECTORY:{}'.format(path))
    elif not path.is_file():
        raise GovernanceError('MISSING_GENERATED_FILE:{}'.format(path))

    try:
        resolved = path.resolve(strict=True)
        resolved.relative_to(generated_root)
    except (OSError, ValueError) as error:
        raise GovernanceError('GENERATED_ARTIFACT_OUTSIDE_ROOT:{}'.format(path)) from error
    return resolved


def _validate_hermes_agents(repo_root: Path, agents_root: Path, expected_agents: int) -> dict[str, Any]:
    agents_payload = _load_agents_json(agents_root)
    if len(agents_payload) != expected_agents:
        raise GovernanceError(
            'HERMES_AGENT_COUNT_MISMATCH:{}:{}'.format(len(agents_payload), expected_agents)
        )

    profiles = _profiles_by_id(repo_root)
    discovered_agents = discover_agents(repo_root)
    if len(discovered_agents) != expected_agents:
        raise GovernanceError(
            'HERMES_DISCOVERED_AGENT_COUNT_MISMATCH:{}:{}'.format(
                len(discovered_agents),
                expected_agents,
            )
        )
    expected_profiles = {agent.role_id for agent in discovered_agents}
    expected_sources = {agent.source_path for agent in discovered_agents}
    expected_slugs = {_slugify(agent.name) for agent in discovered_agents}
    if len(expected_slugs) != expected_agents:
        raise GovernanceError('HERMES_DISCOVERED_SLUG_COLLISION')
    agents_by_source = {agent.source_path: agent for agent in discovered_agents}
    seen_profiles: set[str] = set()
    seen_sources: set[str] = set()
    seen_slugs: set[str] = set()

    for index, record in enumerate(agents_payload, start=1):
        if not isinstance(record, dict):
            raise GovernanceError('INVALID_HERMES_AGENT_RECORD:{}'.format(index))
        governance_profile = record.get("governance_profile")
        governance_digest = record.get("governance_digest")
        body = record.get("body")
        source_path = record.get("source_path")
        slug = record.get("slug")
        if not isinstance(governance_profile, str) or governance_profile not in profiles:
            raise GovernanceError('INVALID_HERMES_AGENT_PROFILE:{}'.format(index))
        if governance_profile in seen_profiles:
            raise GovernanceError(
                'HERMES_DUPLICATE_GOVERNANCE_PROFILE:{}'.format(governance_profile)
            )
        seen_profiles.add(governance_profile)
        if not isinstance(governance_digest, str) or not re.match(r"^[0-9a-f]{64}$", governance_digest):
            raise GovernanceError('INVALID_HERMES_AGENT_DIGEST:{}'.format(index))
        if not isinstance(body, str):
            raise GovernanceError('INVALID_HERMES_AGENT_BODY:{}'.format(index))
        if not isinstance(source_path, str):
            raise GovernanceError('INVALID_HERMES_AGENT_SOURCE_PATH:{}'.format(index))
        if not source_path:
            raise GovernanceError('INVALID_HERMES_AGENT_SOURCE_PATH:{}'.format(index))
        if source_path in seen_sources:
            raise GovernanceError('HERMES_DUPLICATE_SOURCE_PATH:{}'.format(source_path))
        seen_sources.add(source_path)
        if not isinstance(slug, str) or not slug:
            raise GovernanceError('INVALID_HERMES_AGENT_SLUG:{}'.format(index))
        if slug in seen_slugs:
            raise GovernanceError('HERMES_DUPLICATE_SLUG:{}'.format(slug))
        seen_slugs.add(slug)
        discovered_agent = agents_by_source.get(source_path)
        if discovered_agent is not None:
            if governance_profile != discovered_agent.role_id:
                raise GovernanceError(
                    'HERMES_AGENT_PROFILE_SOURCE_MISMATCH:{}:{}:{}'.format(
                        index,
                        discovered_agent.role_id,
                        governance_profile,
                    )
                )
            if slug != _slugify(discovered_agent.name):
                raise GovernanceError(
                    'HERMES_AGENT_SLUG_MISMATCH:{}:{}:{}'.format(
                        index,
                        _slugify(discovered_agent.name),
                        slug,
                    )
                )
        rendered = render_governed_body(repo_root, repo_root / source_path)
        if body != rendered:
            raise GovernanceError('HERMES_AGENT_BODY_MISMATCH:{}'.format(index))
        if _hash_hex(rendered) != governance_digest:
            raise GovernanceError('HERMES_AGENT_DIGEST_MISMATCH:{}'.format(index))
        profile = profiles[governance_profile]
        if profile.get("source_path") != source_path:
            raise GovernanceError(
                'HERMES_AGENT_PROFILE_SOURCE_MISMATCH:{}:{}:{}'.format(
                    index,
                    profile.get("source_path"),
                    source_path,
                )
            )

    if seen_profiles != expected_profiles:
        raise GovernanceError('HERMES_GOVERNANCE_PROFILE_SET_MISMATCH')
    if seen_sources != expected_sources:
        raise GovernanceError('HERMES_SOURCE_PATH_SET_MISMATCH')
    if seen_slugs != expected_slugs:
        raise GovernanceError('HERMES_SLUG_SET_MISMATCH')

    return {
        "governance_profile_count": len(seen_profiles),
        "record_count": len(agents_payload),
    }


def verify_generated(repo_root: Path, generated_root: Path, expected_agents: int, expected_tools: int) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    raw_generated_root = generated_root
    generated_root = _resolve_directory_before_traversal(
        raw_generated_root,
        symlink_code='GENERATED_ROOT_SYMLINK',
        invalid_code='MISSING_GENERATED_ROOT',
    )
    if expected_agents <= 0 or expected_tools <= 0:
        raise GovernanceError('INVALID_EXPECTATION')

    tools = _load_tools_list(repo_root)
    expected_tool_directories = _expected_tool_directories()
    expected_tool_names = sorted(expected_tool_directories.keys())
    agents = discover_agents(repo_root)
    ordered_agents = sorted(agents, key=lambda agent: agent.source_path)
    discovered_agents = len(agents)
    if tools != expected_tool_names:
        raise GovernanceError(
            'EXPECTED_TOOL_SET_MISMATCH:{}:{}'.format(
                ",".join(tools),
                ",".join(expected_tool_names),
            )
        )
    if len(tools) != expected_tools:
        raise GovernanceError('EXPECTED_TOOLS_MISMATCH:{}:{}'.format(len(tools), expected_tools))
    if discovered_agents != expected_agents:
        raise GovernanceError(
            'EXPECTED_AGENTS_MISMATCH:{}:{}'.format(discovered_agents, expected_agents)
        )

    token_scan = _ensure_token_free_texts(generated_root)
    if token_scan["total_hits"]:
        first_path = token_scan["matches"][0]["path"]
        raise GovernanceError(
            'SENSITIVE_TOKEN_DETECTED:count={}:path={}'.format(
                token_scan["total_hits"],
                first_path,
            )
        )

    raw_output_directories = {
        tool: raw_generated_root / directory
        for tool, directory in expected_tool_directories.items()
    }

    symlinked_tools = [
        tool for tool, path in raw_output_directories.items() if path.is_symlink()
    ]
    if symlinked_tools:
        raise GovernanceError(
            'GENERATED_TOOL_ROOT_SYMLINK:{}'.format(",".join(symlinked_tools))
        )
    missing_tools = [
        tool for tool, path in raw_output_directories.items() if not path.exists()
    ]
    if missing_tools:
        raise GovernanceError('MISSING_TOOL_OUTPUT:{}'.format(",".join(missing_tools)))
    non_dirs = [
        tool for tool, path in raw_output_directories.items() if not path.is_dir()
    ]
    if non_dirs:
        raise GovernanceError('INVALID_TOOL_OUTPUT:{}'.format(",".join(non_dirs)))
    output_directories: dict[str, Path] = {}
    for tool, path in raw_output_directories.items():
        try:
            resolved = path.resolve(strict=True)
            resolved.relative_to(generated_root)
        except (OSError, ValueError) as error:
            raise GovernanceError(
                'GENERATED_TOOL_ROOT_OUTSIDE_ROOT:{}'.format(tool)
            ) from error
        output_directories[tool] = resolved

    if _count_directories(generated_root / "hermes") < 1:
        raise GovernanceError('HERMES_PLUGIN_DIRECTORY_MISSING')

    aider_file = _controlled_generated_path(
        generated_root,
        output_directories["aider"] / "CONVENTIONS.md",
    )
    windsurf_file = _controlled_generated_path(
        generated_root,
        output_directories["windsurf"] / ".windsurfrules",
    )
    hermes_root = _controlled_generated_path(
        generated_root,
        output_directories["hermes"] / "agency-agents-router",
        directory=True,
    )

    profile_map = {profile["role_id"]: profile for profile in build_profiles(repo_root)}
    discovered_ids = {agent.role_id for agent in agents}
    for profile in profile_map.values():
        source_path = profile.get("source_path")
        role_id = profile.get("role_id")
        if source_path is None or not source_path:
            raise GovernanceError('INVALID_PROFILE_SOURCE_PATH:{}'.format(role_id))
        if role_id in discovered_ids:
            continue
        raise GovernanceError(
            'PROFILE_SOURCE_PATH_MISMATCH:{}:{}'.format(role_id, source_path)
        )

    per_tool_counts = {tool: 0 for tool in expected_tool_names}
    aider_sections: list[str] = []
    windsurf_sections: list[str] = []

    for agent in ordered_agents:
        source = repo_root / agent.source_path
        source_fields, source_body = read_agent(source)
        governance_profile = source_fields.get("governance_profile")
        if governance_profile != agent.role_id:
            raise GovernanceError('MISMATCHED_GOVERNANCE_BINDING:{}'.format(agent.source_path))
        profile = profile_map.get(governance_profile)
        if profile is None:
            raise GovernanceError('MISSING_PROFILE:{}'.format(agent.role_id))
        if profile.get("source_path") != agent.source_path:
            raise GovernanceError(
                'PROFILE_SOURCE_PATH_MISMATCH:{}:{}'.format(
                    agent.role_id,
                    profile.get("source_path"),
                )
            )

        rendered_governance = render_governance(repo_root, source)
        rendered_body = render_governed_body(repo_root, source)
        expected_files, sections = _expected_agent_output_texts(
            agent,
            source_fields,
            rendered_governance,
            rendered_body,
            source_body,
            source_path=source,
        )
        aider_sections.append(sections[0])
        windsurf_sections.append(sections[1])
        validated_tools: set[str] = set()

        for relative_path, expected in expected_files.items():
            # openclaw has two per-role files plus identity
            root_name = relative_path.split("/", 1)[0]
            root_path = output_directories[root_name]
            artifact_path = _controlled_generated_path(
                generated_root,
                root_path / "/".join(relative_path.split("/", 1)[1:]),
            )
            validated_tools.add(root_name)

            if root_name == "openclaw":
                if artifact_path.name == "IDENTITY.md":
                    identity_text = _read_file_text(artifact_path)
                    if not identity_text.strip() or "企业治理提示" in identity_text:
                        raise GovernanceError('TOOL_FILE_MISMATCH:{}'.format(artifact_path))
                else:
                    _assert_file_contents(artifact_path, expected)
                continue

            if root_name == "codex":
                document = _load_toml(artifact_path)
                actual_name = document.get("name")
                if (
                    not isinstance(actual_name, str)
                    or actual_name.strip() != source_fields.get("name", agent.name)
                ):
                    raise GovernanceError('TOOL_FILE_MISMATCH:{}'.format(artifact_path))
                actual_description = document.get("description")
                expected_description = source_fields.get("description", "")
                if isinstance(actual_description, str):
                    actual_description = actual_description.strip()
                if (
                    actual_description != expected_description
                    and not (
                        isinstance(actual_description, str)
                        and len(actual_description) >= 2
                        and actual_description[0] == actual_description[-1]
                        and actual_description[0] in {'"', "'"}
                        and actual_description[1:-1] == expected_description
                    )
                ):
                    raise GovernanceError('TOOL_FILE_MISMATCH:{}'.format(artifact_path))
                if document.get("developer_instructions") != rendered_body.rstrip("\n"):
                    raise GovernanceError('TOOL_FILE_MISMATCH:{}'.format(artifact_path))
                if set(document.keys()) - {"name", "description", "developer_instructions"}:
                    raise GovernanceError('TOOL_FILE_EXTRA_KEYS:{}'.format(artifact_path))
            elif root_name == "opencode":
                generated_fields, generated_body = read_agent(artifact_path)
                if generated_fields.get("name") != source_fields.get("name", agent.name):
                    raise GovernanceError('TOOL_FILE_MISMATCH:{}'.format(artifact_path))
                if generated_fields.get("description") != source_fields.get("description", ""):
                    raise GovernanceError('TOOL_FILE_MISMATCH:{}'.format(artifact_path))
                if generated_fields.get("mode") != "subagent":
                    raise GovernanceError('TOOL_FILE_MISMATCH:{}'.format(artifact_path))
                if not re.fullmatch(r"#[0-9A-Fa-f]{6}", generated_fields.get("color", "")):
                    raise GovernanceError('TOOL_FILE_MISMATCH:{}'.format(artifact_path))
                if generated_body.rstrip("\n") != rendered_body.rstrip("\n"):
                    raise GovernanceError('TOOL_FILE_MISMATCH:{}'.format(artifact_path))
            elif root_name in {
                "antigravity",
                "osaurus",
                "gemini-cli",
                "cursor",
                "qwen",
                "zcode",
                "claude-code",
                "copilot",
            }:
                generated_fields, generated_body = read_agent(artifact_path)
                if generated_fields.get("description") != source_fields.get("description", ""):
                    raise GovernanceError('TOOL_FILE_MISMATCH:{}'.format(artifact_path))
                slug = _slugify(agent.name)
                expected_names = {
                    "antigravity": "agency-{}".format(slug),
                    "osaurus": "agency-{}".format(slug),
                    "gemini-cli": slug,
                    "qwen": slug,
                    "zcode": slug,
                    "claude-code": source_fields.get("name", agent.name),
                    "copilot": source_fields.get("name", agent.name),
                }
                if root_name in expected_names and generated_fields.get("name") != expected_names[root_name]:
                    raise GovernanceError('TOOL_FILE_MISMATCH:{}'.format(artifact_path))
                if generated_body.rstrip("\n") != rendered_body.rstrip("\n"):
                    raise GovernanceError('TOOL_FILE_MISMATCH:{}'.format(artifact_path))
            else:
                _assert_file_contents(artifact_path, expected)

        for tool in validated_tools:
            per_tool_counts[tool] += 1

    if _read_file_text(aider_file) != _expected_aider_document(aider_sections):
        raise GovernanceError('AGGREGATE_DOCUMENT_MISMATCH:AIDER')
    if _read_file_text(windsurf_file) != _expected_windsurf_document(windsurf_sections):
        raise GovernanceError('AGGREGATE_DOCUMENT_MISMATCH:WINDSURF')
    per_tool_counts["aider"] = len(aider_sections)
    per_tool_counts["windsurf"] = len(windsurf_sections)
    per_tool_counts["openclaw"] = _count_openclaw_workspaces(output_directories["openclaw"])
    per_tool_counts["hermes"] = (
        _validate_hermes_agents(
            repo_root,
            hermes_root,
            expected_agents,
        ).get("record_count")
    )

    for tool, count in sorted(per_tool_counts.items()):
        if count != expected_agents:
            raise GovernanceError('TOOL_COUNT_MISMATCH:{}:{}'.format(tool, count))

    summary = {
        "tools": len(tools),
        "expected_tools": expected_tools,
        "expected_agents": expected_agents,
        "per_tool_counts": per_tool_counts,
        "generated_root": generated_root.as_posix(),
        "openclaw_workspaces": per_tool_counts["openclaw"],
        "aider_sections": per_tool_counts["aider"],
        "windsurf_sections": per_tool_counts["windsurf"],
        "token_scan": token_scan,
    }
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True, indent=2))
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    build = commands.add_parser('build-profiles')
    build.add_argument('--repo-root', type=Path, required=True)
    build.add_argument('--output', type=Path, required=True)
    bind = commands.add_parser('bind-sources')
    bind.add_argument('--repo-root', type=Path, required=True)
    render_governance_cmd = commands.add_parser('render-governance')
    render_governance_cmd.add_argument('--repo-root', type=Path, required=True)
    render_governance_cmd.add_argument('--agent', type=Path, required=True)
    render = commands.add_parser('render')
    render.add_argument('--repo-root', type=Path, required=True)
    render.add_argument('--source', type=Path, required=True)
    verify = commands.add_parser('verify-bindings')
    verify.add_argument('--repo-root', type=Path, required=True)
    verify_generated_cmd = commands.add_parser('verify-generated')
    verify_generated_cmd.add_argument('--repo-root', type=Path, required=True)
    verify_generated_cmd.add_argument('--generated-root', type=Path, required=True)
    verify_generated_cmd.add_argument('--expected-agents', type=int, required=True)
    verify_generated_cmd.add_argument('--expected-tools', type=int, required=True)
    verify_all_cmd = commands.add_parser('verify-all')
    verify_all_cmd.add_argument('--repo-root', type=Path, required=True)
    verify_all_cmd.add_argument('--generated-root', type=Path, required=True)
    verify_all_cmd.add_argument('--output', type=Path, required=True)
    verify_all_cmd.add_argument('--expected-agents', type=int)
    verify_all_cmd.add_argument('--expected-tools', type=int)
    manifest_cmd = commands.add_parser('manifest')
    manifest_cmd.add_argument('--root', type=Path, required=True)
    manifest_cmd.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    if args.command == 'build-profiles':
        write_canonical_json(args.output, build_profiles(args.repo_root.resolve()))
        return 0
    if args.command == 'bind-sources':
        print(bind_sources(args.repo_root))
        return 0
    if args.command == 'render-governance':
        print(render_governance(args.repo_root.resolve(), args.agent))
        return 0
    if args.command == 'render':
        print(render_governed_body(args.repo_root.resolve(), args.source))
        return 0
    if args.command == 'verify-bindings':
        print(verify_bindings(args.repo_root))
        return 0
    if args.command == 'verify-generated':
        verify_generated(
            args.repo_root,
            args.generated_root,
            args.expected_agents,
            args.expected_tools,
        )
        return 0
    if args.command == 'verify-all':
        output = verify_all(
            args.repo_root,
            args.generated_root,
            expected_agents=args.expected_agents,
            expected_tools=args.expected_tools,
        )
        report_path = args.output
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(
            json.dumps(output, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            encoding="utf-8",
        )
        return 0
    if args.command == 'manifest':
        manifest = _collect_manifest_entries(args.root, args.output)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return 0
    raise GovernanceError('UNKNOWN_COMMAND')

if __name__ == '__main__':
    raise SystemExit(main())
