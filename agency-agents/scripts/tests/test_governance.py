import json
import re
import shutil
import tempfile
import unittest
from pathlib import Path

from governance import load_schema, validate_profile, validate_response
from scripts.governance import (
    GovernanceError,
    bind_sources,
    build_profiles,
    discover_agents,
    read_agent,
    render_governance,
    render_governed_body,
)


ROOT = Path(__file__).resolve().parents[2]
GOVERNANCE_ROOT = ROOT / "governance"


class GovernanceContractTests(unittest.TestCase):
    def _valid_profile(self):
        return {
            "role_id": "frontend-dev",
            "role_name": "Frontend Developer",
            "division": "engineering",
            "risk_level": "medium",
            "allowed_read_actions": ["read_repository"],
            "allowed_write_actions": ["write_local_branch"],
            "forbidden_actions": ["production_release"],
            "risk_rules": ["human_approval_for_high_risk"],
            "allowed_systems": ["codex"],
            "approval_matrix": {
                "low": "self-service",
                "medium": "current-user-approval",
                "high": "current-user-and-supervisor",
                "write": "current-user-and-supervisor",
                "external_side_effect": "current-user-and-supervisor",
            },
            "source_hash": "a" * 64,
            "source_path": "engineering/frontend-dev.md",
            "policy_source": "governance/policies/engineering.json",
            "exception_source": "governance/exceptions/engineering.json",
        }

    def test_governed_response_requires_complete_fixed_object(self):
        schema = json.loads(
            (GOVERNANCE_ROOT / "schemas/governed-response.schema.json").read_text()
        )

        self.assertEqual(
            schema["required"],
            [
                "decision",
                "role",
                "risk_level",
                "plan",
                "evidence",
                "learning_report",
                "human_actions_needed",
            ],
        )
        self.assertEqual(
            schema["properties"]["decision"]["enum"],
            ["ALLOW", "NEED_APPROVAL", "BLOCK"],
        )
        self.assertEqual(schema["properties"]["risk_level"]["enum"], [
            "low",
            "medium",
            "high",
        ])

    def test_governed_response_schema_is_closed_and_bounded(self):
        schema = json.loads(
            (GOVERNANCE_ROOT / "schemas/governed-response.schema.json").read_text()
        )

        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(schema["properties"]["plan"]["maxItems"], 5)
        self.assertEqual(
            schema["properties"]["learning_report"]["properties"]["patterns"][
                "maxItems"
            ],
            3,
        )
        self.assertEqual(schema["properties"]["evidence"]["minItems"], 7)
        self.assertEqual(schema["properties"]["evidence"]["maxItems"], 7)
        self.assertTrue(schema["properties"]["evidence"]["uniqueItems"])

    def _valid_response(self):
        return {
            "decision": "ALLOW",
            "role": "frontend-dev",
            "risk_level": "low",
            "plan": [{
                "step": 1,
                "action": "读取已授权输入",
                "reason": "完成任务解析",
                "preconditions": "输入已在授权域",
                "acceptance": "返回结构化结果",
                "rollback": "不写入外部系统",
            }],
            "evidence": [
                "request_id",
                "actor",
                "timestamp",
                "input_hash",
                "result",
                "failure_reason",
                "rollback",
            ],
            "learning_report": {
                "successes": [],
                "failures": [],
                "human_interventions": [],
                "patterns": [],
                "proposal": {"text": "", "confidence": 0},
            },
            "human_actions_needed": [],
        }

    def test_governed_response_accepts_valid_fixed_object(self):
        self.assertEqual(validate_response(self._valid_response()), [])

    def test_governed_response_rejects_unknown_top_level_field(self):
        response = self._valid_response()
        response["unexpected"] = True
        self.assertTrue(validate_response(response))

    def test_governed_response_rejects_more_than_five_plan_steps(self):
        response = self._valid_response()
        response["plan"] = response["plan"] * 6
        self.assertTrue(validate_response(response))

    def test_governed_response_rejects_more_than_three_patterns(self):
        response = self._valid_response()
        response["learning_report"]["patterns"] = ["a", "b", "c", "d"]
        self.assertTrue(validate_response(response))

    def test_governed_response_rejects_incomplete_evidence(self):
        response = self._valid_response()
        response["evidence"] = response["evidence"][:-1]
        self.assertTrue(validate_response(response))

    def test_role_governance_profile_declares_complete_identity_and_policy_contract(self):
        schema = json.loads(
            (GOVERNANCE_ROOT / "schemas/role-governance-profile.schema.json").read_text()
        )

        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(
            schema["required"],
            [
                "role_id",
                "role_name",
                "division",
                "risk_level",
                "allowed_read_actions",
                "allowed_write_actions",
                "forbidden_actions",
                "risk_rules",
                "allowed_systems",
                "approval_matrix",
                "source_hash",
                "source_path",
                "policy_source",
                "exception_source",
            ],
        )

        for field in (
            "allowed_read_actions",
            "allowed_write_actions",
            "forbidden_actions",
            "risk_rules",
            "allowed_systems",
        ):
            self.assertEqual(schema["properties"][field]["type"], "array")

    def test_base_prompt_contains_every_resolved_variable_and_fixed_json(self):
        text = (GOVERNANCE_ROOT / "base-prompt.zh-CN.md").read_text()

        for name in (
            "ROLE_NAME",
            "ALLOWED_READ_ACTIONS",
            "ALLOWED_WRITE_ACTIONS",
            "FORBIDDEN_ACTIONS",
            "RISK_RULES",
            "APPROVAL_MATRIX",
            "ALLOWED_SYSTEMS",
        ):
            self.assertIn("{{" + name + "}}", text)

        self.assertIn('"decision":"ALLOW|NEED_APPROVAL|BLOCK"', text)
        example_match = re.search(r"```json\n(\{.*?\n\})\n```", text, re.DOTALL)
        self.assertIsNotNone(example_match)
        example = json.loads(example_match.group(1))
        self.assertEqual(validate_response(example), [])
        for field in (
            "decision",
            "role",
            "risk_level",
            "plan",
            "evidence",
            "learning_report",
            "human_actions_needed",
        ):
            self.assertIn('"' + field + '"', text)
        self.assertIn("每次始终输出完整固定 JSON", text)

    def test_profile_validator_accepts_complete_profile(self):
        self.assertEqual(validate_profile(self._valid_profile()), [])

    def test_profile_validator_rejects_unknown_field(self):
        profile = self._valid_profile()
        profile["unexpected"] = True
        errors = validate_profile(profile)
        self.assertEqual(errors, sorted(errors))
        self.assertTrue(errors)

    def test_profile_validator_rejects_action_list_bound(self):
        profile = self._valid_profile()
        profile["allowed_read_actions"] = ["action-{}".format(index) for index in range(101)]
        self.assertTrue(validate_profile(profile))

    def test_schema_loader_rejects_unknown_or_traversal_names(self):
        self.assertEqual(load_schema("role-governance-profile")["title"], "Agency Agents Role Governance Profile")
        for name in ("unknown", "../role-governance-profile", "role-governance-profile.json"):
            with self.assertRaises(ValueError):
                load_schema(name)

    def test_profiles_cover_exactly_all_discovered_agents(self):
        profiles = build_profiles(ROOT)
        role_ids = [profile["role_id"] for profile in profiles]
        expected_divisions = set(
            json.loads((ROOT / "divisions.json").read_text())["divisions"]
        )

        self.assertEqual(len(expected_divisions), 17)
        self.assertEqual(len(profiles), 269)
        self.assertEqual(len(set(role_ids)), 269)
        self.assertEqual(
            {profile["division"] for profile in profiles}, expected_divisions
        )

    def test_high_risk_profiles_have_no_unapproved_write_default(self):
        profiles = build_profiles(ROOT)
        high_risk_profiles = [
            profile for profile in profiles if profile["risk_level"] == "high"
        ]

        self.assertTrue(high_risk_profiles)
        for profile in high_risk_profiles:
            self.assertEqual(profile["allowed_write_actions"], [])
            self.assertEqual(
                profile["approval_matrix"]["write"],
                "current-user-and-supervisor",
            )
            self.assertEqual(
                profile["approval_matrix"]["external_side_effect"],
                "current-user-and-supervisor",
            )

    def test_profile_order_and_source_hashes_are_deterministic(self):
        first = build_profiles(ROOT)
        second = build_profiles(ROOT)

        self.assertEqual(first, second)
        self.assertEqual(
            [profile["role_id"] for profile in first],
            sorted(profile["role_id"] for profile in first),
        )
        for profile in first:
            self.assertRegex(profile["source_hash"], r"^[0-9a-f]{64}$")

    def test_agent_discovery_carries_deterministic_authority_text(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "divisions.json").write_text(
                json.dumps({"divisions": {"engineering": {}}}),
                encoding="utf-8",
            )
            division = root / "engineering"
            division.mkdir()
            (division / "authority-sample.md").write_text(
                "---\n"
                "name: Authority Sample\n"
                "authority: Explicit authority boundary\n"
                "description: Explicit description\n"
                "responsibility: Explicit responsibility\n"
                "---\n\n# Sample\n",
                encoding="utf-8",
            )
            first = discover_agents(root)[0]
            second = discover_agents(root)[0]
            self.assertEqual(
                first.authority,
                "Explicit authority boundary | Explicit description | Explicit responsibility",
            )
            self.assertEqual(first.authority, second.authority)

    def test_duplicate_role_id_failure_is_isolated_and_deterministic(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "divisions.json").write_text(
                json.dumps({"divisions": {"design": {}, "engineering": {}}}),
                encoding="utf-8",
            )
            for division in ("design", "engineering"):
                path = root / division
                path.mkdir()
                (path / "duplicate-role.md").write_text(
                    "---\nname: Duplicate Role\ndescription: Test authority\n---\n",
                    encoding="utf-8",
                )
            with self.assertRaisesRegex(GovernanceError, "DUPLICATE_ROLE_ID"):
                discover_agents(root)

    def test_sensitive_title_or_authority_roles_have_explicit_overrides(self):
        profiles = build_profiles(ROOT)
        overrides = json.loads(
            (GOVERNANCE_ROOT / "role-overrides.json").read_text()
        )
        override_ids = set(overrides)
        sensitive_terms = (
            "security",
            "finance",
            "financial",
            "legal",
            "compliance",
            "production",
            "release",
            "permission",
            "external",
            "call",
            "telephony",
        )

        agents_by_id = {agent.role_id: agent for agent in discover_agents(ROOT)}
        sensitive_profiles = []
        for profile in profiles:
            agent = agents_by_id[profile["role_id"]]
            authority = json.dumps(agent.authority, ensure_ascii=False).lower()
            title_or_authority = " ".join(
                (profile["role_name"].lower(), authority)
            )
            if any(term in title_or_authority for term in sensitive_terms):
                sensitive_profiles.append(profile)

        discovered_ids = {profile["role_id"] for profile in profiles}
        sensitive_ids = {profile["role_id"] for profile in sensitive_profiles}
        self.assertEqual(
            sensitive_ids - override_ids,
            set(),
            "sensitive roles missing explicit overrides",
        )
        self.assertEqual(
            override_ids - discovered_ids,
            set(),
            "overrides contain stale undiscovered roles",
        )
        self.assertTrue(sensitive_profiles)
        for profile in sensitive_profiles:
            self.assertIn(profile["role_id"], override_ids)

    def test_every_source_has_exact_profile_binding(self):
        agents = discover_agents(ROOT)

        self.assertEqual(len(agents), 269)
        for agent in agents:
            fields, _ = read_agent(ROOT / agent.source_path)
            self.assertEqual(
                fields.get("governance_profile"),
                agent.role_id,
                agent.source_path,
            )

    def test_renderer_resolves_every_source_without_unresolved_variables(self):
        agents = discover_agents(ROOT)

        self.assertEqual(len(agents), 269)
        for agent in agents:
            source = ROOT / agent.source_path
            rendered = render_governance(ROOT, source)
            self.assertNotRegex(
                rendered,
                r"\{\{[^{}\r\n]+\}\}",
                agent.source_path,
            )

    def test_rendered_body_preserves_persona_text_and_fixed_decision_contract(self):
        agents = discover_agents(ROOT)
        governance_variables = (
            "ROLE_NAME",
            "ALLOWED_READ_ACTIONS",
            "ALLOWED_WRITE_ACTIONS",
            "FORBIDDEN_ACTIONS",
            "RISK_RULES",
            "APPROVAL_MATRIX",
            "ALLOWED_SYSTEMS",
        )

        for agent in agents:
            source = ROOT / agent.source_path
            _, original_body = read_agent(source)
            rendered = render_governed_body(ROOT, source)

            self.assertIn(original_body, rendered, agent.source_path)
            self.assertIn('"decision":"ALLOW|NEED_APPROVAL|BLOCK"', rendered)
            for variable in governance_variables:
                self.assertNotIn(
                    f"{{{{{variable}}}}}",
                    rendered,
                    agent.source_path,
                )

    def _isolated_repo_fixture(self):
        directory = tempfile.TemporaryDirectory()
        root = Path(directory.name) / "agency-agents"
        shutil.copytree(
            ROOT,
            root,
            symlinks=True,
            ignore=shutil.ignore_patterns(".git", ".superpowers", "__pycache__"),
        )
        return directory, root

    @staticmethod
    def _body_bytes(raw):
        fences = list(re.finditer(br"(?m)^---[ \t]*\r?\n", raw))
        if len(fences) < 2:
            raise AssertionError("source does not contain a complete frontmatter block")
        return raw[fences[1].end():]

    def test_binding_preserves_body_bytes_and_is_atomic_idempotent(self):
        directory, fixture_root = self._isolated_repo_fixture()
        try:
            sources = sorted(
                fixture_root / agent.source_path
                for agent in discover_agents(fixture_root)
            )
            before = {path.relative_to(fixture_root): path.read_bytes() for path in sources}

            first_count = bind_sources(fixture_root)
            first_state = {
                path.relative_to(fixture_root): path.read_bytes()
                for path in sources
            }
            second_count = bind_sources(fixture_root)
            second_state = {
                path.relative_to(fixture_root): path.read_bytes()
                for path in sources
            }

            self.assertEqual(first_count, 0)
            self.assertEqual(second_count, 0)
            self.assertEqual(first_state, second_state)
            for relative_path, original in before.items():
                self.assertEqual(
                    self._body_bytes(original),
                    self._body_bytes(first_state[relative_path]),
                    str(relative_path),
                )
        finally:
            directory.cleanup()

    def test_utf8_frontmatter_and_body_survive_binding_and_rendering(self):
        directory, fixture_root = self._isolated_repo_fixture()
        try:
            agent = discover_agents(fixture_root)[0]
            source = fixture_root / agent.source_path
            raw = source.read_bytes()
            opening = re.match(br"\A---[ \t]*\r?\n", raw)
            self.assertIsNotNone(opening)
            closing = re.search(br"(?m)^---[ \t]*\r?\n", raw[opening.end():])
            self.assertIsNotNone(closing)
            unicode_frontmatter = (
                "---\n"
                "name: 中文角色 😀\n"
                "authority: 负责中文与 emoji 解析 🧪\n"
                "description: 保留多字节前言\n"
                "---\n"
            ).encode("utf-8")
            original_body = (
                "\n# 中文主体 😀\n\n必须逐字保留：中文、emoji 🧪、多字节文本。\n"
            ).encode("utf-8")
            source.write_bytes(unicode_frontmatter + original_body)

            discovered = next(
                candidate
                for candidate in discover_agents(fixture_root)
                if candidate.source_path == agent.source_path
            )
            self.assertIn("中文与 emoji 解析 🧪", discovered.authority)
            self.assertEqual(read_agent(source)[1], original_body.decode("utf-8"))

            self.assertEqual(bind_sources(fixture_root), 1)
            bound = source.read_bytes()
            self.assertEqual(self._body_bytes(bound), original_body)
            rendered = render_governed_body(fixture_root, source)
            self.assertTrue(rendered.endswith(original_body.decode("utf-8")))
            self.assertIn("中文主体 😀", rendered)
        finally:
            directory.cleanup()

    def test_binding_rejects_symlinked_sources_without_partial_write(self):
        directory, fixture_root = self._isolated_repo_fixture()
        try:
            target = next(
                path
                for path in (fixture_root / "engineering").glob("*.md")
                if path.is_file() and not path.is_symlink()
            )
            original_target = target.read_bytes()
            link = target.with_name("task3-symlink-agent.md")
            link.symlink_to(target.name)

            with self.assertRaisesRegex(GovernanceError, "SYMLINK"):
                bind_sources(fixture_root)

            self.assertEqual(target.read_bytes(), original_target)
            self.assertFalse(link.is_file() and not link.is_symlink())
        finally:
            directory.cleanup()


if __name__ == "__main__":
    unittest.main()
