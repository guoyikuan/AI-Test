#!/usr/bin/env python3
"""Content-addressed AI-Test adapter for the Codex-local Shangdao Skill.

The adapter owns no governance policy. It verifies the global canonical owner
and exact files, then delegates to the canonical deterministic validator.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any


ADAPTER_SCHEMA = "shangdao.meta-governance-adapter/v1"
EXPECTED_TEMPLATE = "${CODEX_HOME}/skills/shangdao-meta-governance"
EXPECTED_REGISTRY_TEMPLATE = "${CODEX_HOME}/skill-portfolio/registry.json"
EXPECTED_ENTITY = "skill:codex:shangdao-meta-governance"
EXPECTED_OWNER = "codex-local"
EXPECTED_SCOPE = "codex"
EXPECTED_KEY = "shangdao-meta-governance"
DELEGATED_COMMANDS = ("preflight", "decision", "verify", "self-test")
DEFAULT_BINDING = (
    Path(__file__).resolve().parents[1]
    / "governance"
    / "shangdao-meta-governance-adapter.json"
)


class AdapterError(RuntimeError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path, code: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise AdapterError(code, f"cannot load JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise AdapterError(code, f"JSON object required: {path}")
    return value


def require_regular_no_symlink(path: Path, code: str) -> None:
    if path.is_symlink() or not path.is_file():
        raise AdapterError(code, f"regular non-symlink file required: {path}")


def verify_binding(
    binding_path: Path = DEFAULT_BINDING,
    codex_home: Path | None = None,
) -> dict[str, Any]:
    require_regular_no_symlink(binding_path, "SHANGDAO_ADAPTER_BINDING_INVALID")
    binding = load_json(binding_path, "SHANGDAO_ADAPTER_BINDING_INVALID")

    fixed_fields = {
        "schema": ADAPTER_SCHEMA,
        "classification": "platform-adapter",
        "default_activation": False,
        "canonical_entity_id": EXPECTED_ENTITY,
        "canonical_owner": EXPECTED_OWNER,
        "canonical_scope": EXPECTED_SCOPE,
        "canonical_root_template": EXPECTED_TEMPLATE,
        "registry_path_template": EXPECTED_REGISTRY_TEMPLATE,
        "registry_key": EXPECTED_KEY,
        "entrypoint": "scripts/validate_shangdao_meta_governance.py",
        "failure_behavior": "fail-closed",
    }
    for field, expected in fixed_fields.items():
        if binding.get(field) != expected:
            raise AdapterError(
                "SHANGDAO_ADAPTER_BINDING_INVALID",
                f"binding field mismatch: {field}",
            )
    if binding.get("delegated_commands") != list(DELEGATED_COMMANDS):
        raise AdapterError(
            "SHANGDAO_ADAPTER_BINDING_INVALID",
            "delegated command set or order mismatch",
        )
    permission_delta = binding.get("permission_delta")
    if permission_delta != {"added": [], "removed": [], "expands_permissions": False}:
        raise AdapterError(
            "SHANGDAO_ADAPTER_BINDING_INVALID",
            "adapter must not expand permissions",
        )
    if binding.get("requested_writes") != []:
        raise AdapterError(
            "SHANGDAO_ADAPTER_BINDING_INVALID",
            "adapter must not request canonical writes",
        )

    home = (codex_home or Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))).expanduser()
    if not home.is_absolute() or home.is_symlink() or not home.is_dir():
        raise AdapterError(
            "SHANGDAO_ADAPTER_CANONICAL_MISSING",
            f"invalid CODEX_HOME: {home}",
        )
    canonical_root = home / "skills" / EXPECTED_KEY
    if canonical_root.is_symlink() or not canonical_root.is_dir():
        raise AdapterError(
            "SHANGDAO_ADAPTER_CANONICAL_MISSING",
            f"canonical root missing or unsafe: {canonical_root}",
        )

    records = binding.get("canonical_files")
    if not isinstance(records, list) or len(records) != 4:
        raise AdapterError(
            "SHANGDAO_ADAPTER_BINDING_INVALID",
            "exactly four canonical file bindings are required",
        )
    expected_paths = {
        "SKILL.md",
        "contracts/shangdao.meta-governance.v1.example.json",
        "references/shangdao.meta-governance.schema.json",
        "scripts/validate_shangdao_meta_governance.py",
    }
    seen: set[str] = set()
    actual_hashes: dict[str, str] = {}
    for record in records:
        if not isinstance(record, dict):
            raise AdapterError(
                "SHANGDAO_ADAPTER_BINDING_INVALID", "invalid canonical file record"
            )
        relative = record.get("path")
        expected_digest = record.get("sha256")
        if not isinstance(relative, str) or relative not in expected_paths or relative in seen:
            raise AdapterError(
                "SHANGDAO_ADAPTER_BINDING_INVALID",
                f"invalid or duplicate canonical path: {relative}",
            )
        if not isinstance(expected_digest, str) or len(expected_digest) != 64:
            raise AdapterError(
                "SHANGDAO_ADAPTER_BINDING_INVALID",
                f"invalid sha256 binding: {relative}",
            )
        seen.add(relative)
        target = canonical_root / relative
        require_regular_no_symlink(target, "SHANGDAO_ADAPTER_CANONICAL_MISSING")
        actual = sha256_file(target)
        if actual != expected_digest:
            raise AdapterError(
                "SHANGDAO_ADAPTER_CANONICAL_TAMPER",
                f"canonical digest mismatch: {relative}",
            )
        actual_hashes[relative] = actual
    if seen != expected_paths:
        raise AdapterError(
            "SHANGDAO_ADAPTER_BINDING_INVALID", "canonical file set mismatch"
        )

    registry_path = home / "skill-portfolio" / "registry.json"
    require_regular_no_symlink(registry_path, "SHANGDAO_ADAPTER_OWNER_MISMATCH")
    registry = load_json(registry_path, "SHANGDAO_ADAPTER_OWNER_MISMATCH")
    capability_registry = registry.get("capability_registry")
    entries = capability_registry.get("entries") if isinstance(capability_registry, dict) else None
    if not isinstance(entries, list):
        raise AdapterError(
            "SHANGDAO_ADAPTER_OWNER_MISMATCH",
            "capability_registry.entries missing",
        )
    matches = [entry for entry in entries if isinstance(entry, dict) and entry.get("register_key") == EXPECTED_KEY]
    if len(matches) != 1:
        raise AdapterError(
            "SHANGDAO_ADAPTER_OWNER_MISMATCH",
            f"expected one capability owner, found {len(matches)}",
        )
    owner = matches[0]
    expected_owner = {
        "canonical_entity_id": EXPECTED_ENTITY,
        "canonical_owner": EXPECTED_OWNER,
        "canonical_path": str(canonical_root),
        "canonical_scope": EXPECTED_SCOPE,
        "classification": "canonical",
        "merge_recommended": False,
    }
    for field, expected in expected_owner.items():
        if owner.get(field) != expected:
            raise AdapterError(
                "SHANGDAO_ADAPTER_OWNER_MISMATCH",
                f"registry owner mismatch: {field}",
            )
    members = owner.get("members")
    if not isinstance(members, list) or len(members) != 1:
        raise AdapterError(
            "SHANGDAO_ADAPTER_OWNER_MISMATCH", "canonical owner must be unique"
        )
    member = members[0]
    if not isinstance(member, dict) or member != {
        "canonical_owner": True,
        "entity_id": EXPECTED_ENTITY,
        "path": str(canonical_root),
        "scope": EXPECTED_SCOPE,
    }:
        raise AdapterError(
            "SHANGDAO_ADAPTER_OWNER_MISMATCH", "canonical member binding mismatch"
        )

    return {
        "schema": ADAPTER_SCHEMA,
        "decision": "ALLOW",
        "classification": "platform-adapter",
        "canonical_entity_id": EXPECTED_ENTITY,
        "canonical_owner": EXPECTED_OWNER,
        "canonical_path": str(canonical_root),
        "registry_path": str(registry_path),
        "binding_sha256": sha256_file(binding_path),
        "canonical_files": actual_hashes,
        "entrypoint": str(canonical_root / binding["entrypoint"]),
        "default_activation": False,
        "permission_expansion": False,
    }


def emit_error(error: AdapterError) -> int:
    print(
        json.dumps(
            {"schema": ADAPTER_SCHEMA, "decision": "BLOCK", "code": error.code, "message": str(error)},
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
    )
    return 2


def main(argv: list[str] | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    if not arguments:
        print("usage: shangdao_meta_governance_adapter.py doctor|preflight|decision|verify|self-test", file=sys.stderr)
        return 2
    command, delegated_arguments = arguments[0], arguments[1:]
    if command not in ("doctor", *DELEGATED_COMMANDS):
        return emit_error(
            AdapterError(
                "SHANGDAO_ADAPTER_UNSUPPORTED_COMMAND",
                f"unsupported command: {command}",
            )
        )
    try:
        evidence = verify_binding()
    except AdapterError as error:
        return emit_error(error)
    if command == "doctor":
        if delegated_arguments:
            return emit_error(
                AdapterError(
                    "SHANGDAO_ADAPTER_UNSUPPORTED_COMMAND",
                    "doctor accepts no additional arguments",
                )
            )
        print(json.dumps(evidence, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
        return 0
    completed = subprocess.run(
        [sys.executable, evidence["entrypoint"], command, *delegated_arguments],
        check=False,
    )
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
