#!/usr/bin/env python3
"""Deterministically resolve governance profiles from Agency Agent sources."""
from __future__ import annotations
import argparse
import hashlib
import json
import sys
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

def load_json(path: Path) -> dict[str, Any]:
    try:
        result = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as error:
        raise GovernanceError('INVALID_JSON:{}'.format(path)) from error
    if not isinstance(result, dict):
        raise GovernanceError('EXPECTED_OBJECT:{}'.format(path))
    return result

def parse_frontmatter_agent(path: Path, repo_root: Path) -> Agent | None:
    content = path.read_bytes()
    text = content.decode('utf-8')
    if not text.startswith('---\n'):
        return None
    end = text.find('\n---', 4)
    if end < 0:
        raise GovernanceError('UNTERMINATED_FRONTMATTER:{}'.format(path))
    metadata: dict[str, list[str]] = {key: [] for key in AUTHORITY_METADATA_KEYS}
    for line in text[4:end].splitlines():
        if ':' not in line:
            continue
        key, value = line.split(':', 1)
        key = key.strip().lower()
        value = value.strip().strip('"')
        if key in metadata and value and value not in metadata[key]:
            metadata[key].append(value)
    name = next((line.split(':', 1)[1].strip().strip('"') for line in text[4:end].splitlines() if line.startswith('name:')), '')
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
        hashlib.sha256(content).hexdigest(),
        authority,
    )

def discover_agents(repo_root: Path) -> list[Agent]:
    divisions = load_json(repo_root / 'divisions.json').get('divisions')
    if not isinstance(divisions, dict):
        raise GovernanceError('INVALID_DIVISIONS')
    agents = []
    for division in sorted(divisions):
        directory = repo_root / division
        if not directory.is_dir():
            raise GovernanceError('MISSING_DIVISION:{}'.format(division))
        agents.extend(agent for path in sorted(directory.rglob('*.md')) if (agent := parse_frontmatter_agent(path, repo_root)) is not None)
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

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    build = commands.add_parser('build-profiles')
    build.add_argument('--repo-root', type=Path, required=True)
    build.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    if args.command == 'build-profiles':
        write_canonical_json(args.output, build_profiles(args.repo_root.resolve()))
        return 0
    raise GovernanceError('UNKNOWN_COMMAND')

if __name__ == '__main__':
    raise SystemExit(main())
