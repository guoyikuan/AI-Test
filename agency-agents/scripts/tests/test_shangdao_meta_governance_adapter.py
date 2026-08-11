#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


AGENCY_ROOT = Path(__file__).resolve().parents[2]
ADAPTER_PATH = AGENCY_ROOT / "scripts" / "shangdao_meta_governance_adapter.py"
BINDING_PATH = AGENCY_ROOT / "governance" / "shangdao-meta-governance-adapter.json"
SPEC = importlib.util.spec_from_file_location("shangdao_adapter", ADAPTER_PATH)
assert SPEC and SPEC.loader
ADAPTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ADAPTER)


class ShangdaoMetaGovernanceAdapterTests(unittest.TestCase):
    def test_real_binding_and_unique_owner(self) -> None:
        evidence = ADAPTER.verify_binding()
        self.assertEqual(evidence["decision"], "ALLOW")
        self.assertEqual(evidence["classification"], "platform-adapter")
        self.assertEqual(evidence["canonical_owner"], "codex-local")
        self.assertFalse(evidence["default_activation"])
        self.assertFalse(evidence["permission_expansion"])
        self.assertEqual(len(evidence["canonical_files"]), 4)

    def test_doctor_cli_is_content_addressed(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(ADAPTER_PATH), "doctor"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        evidence = json.loads(completed.stdout)
        self.assertEqual(evidence["decision"], "ALLOW")
        self.assertEqual(evidence["binding_sha256"], ADAPTER.sha256_file(BINDING_PATH))

    def test_tampered_binding_fails_closed(self) -> None:
        binding = json.loads(BINDING_PATH.read_text(encoding="utf-8"))
        binding["canonical_files"][0]["sha256"] = "0" * 64
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "binding.json"
            path.write_text(json.dumps(binding), encoding="utf-8")
            with self.assertRaises(ADAPTER.AdapterError) as raised:
                ADAPTER.verify_binding(path)
        self.assertEqual(raised.exception.code, "SHANGDAO_ADAPTER_CANONICAL_TAMPER")

    def test_registry_owner_mismatch_fails_closed(self) -> None:
        real = ADAPTER.verify_binding()
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / "codex"
            canonical = home / "skills" / "shangdao-meta-governance"
            canonical.parent.mkdir(parents=True)
            shutil.copytree(Path(real["canonical_path"]), canonical)
            registry_path = home / "skill-portfolio" / "registry.json"
            registry_path.parent.mkdir(parents=True)
            registry_path.write_text(
                json.dumps({"capability_registry": {"entries": []}}),
                encoding="utf-8",
            )
            with self.assertRaises(ADAPTER.AdapterError) as raised:
                ADAPTER.verify_binding(BINDING_PATH, home)
        self.assertEqual(raised.exception.code, "SHANGDAO_ADAPTER_OWNER_MISMATCH")

    def test_unsupported_command_is_blocked(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(ADAPTER_PATH), "adopt"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 2)
        result = json.loads(completed.stdout)
        self.assertEqual(result["decision"], "BLOCK")
        self.assertEqual(result["code"], "SHANGDAO_ADAPTER_UNSUPPORTED_COMMAND")

    def test_self_test_delegates_to_canonical_validator(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(ADAPTER_PATH), "self-test"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads(completed.stdout)
        self.assertEqual(result["total"], 22)
        self.assertTrue(result["passed"])
        self.assertTrue(all(case["pass"] for case in result["results"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
