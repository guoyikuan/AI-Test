import json
import re
import shutil
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from governance import load_schema, validate_profile, validate_response
import scripts.governance as governance
from scripts.governance import (
    GovernanceError,
    Agent,
    bind_sources,
    build_profiles,
    _collect_manifest_entries,
    _GOVERNANCE_PROFILE_LINE,
    _bound_source_bytes,
    _expected_tool_directories,
    _FRONTMATTER_CLOSE,
    _FRONTMATTER_OPEN,
    _validate_hermes_agents,
    discover_agents,
    read_agent,
    verify_generated,
    verify_bindings,
    verify_all,
    render_governance,
    render_governed_body,
    stable_source_hash,
    _ensure_token_free_texts,
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
            },
            "source_hash": "a" * 64,
            "source_path": "engineering/frontend-dev.md",
            "policy_source": "governance/policies/engineering.json",
            "exception_source": "governance/exceptions/engineering.json",
            "side_effects": ["write", "external_side_effect"],
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
                "side_effects",
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
            self.assertEqual(profile["approval_matrix"]["high"], "current-user-and-supervisor")
            self.assertEqual(
                sorted(profile["side_effects"]),
                sorted(["write", "external_side_effect"]),
            )
            self.assertEqual(
                profile["side_effects"],
                ["write", "external_side_effect"],
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

    def test_rendered_prompt_includes_side_effect_matrix_items(self):
        profile = self._valid_profile()
        sample_agent = discover_agents(ROOT)[0]

        with patch.object(governance, "_bound_profile", return_value=(profile, sample_agent.source_path)):
            rendered = render_governance(ROOT, ROOT / sample_agent.source_path)

        self.assertIn("低风险：self-service", rendered)
        self.assertIn("中风险：current-user-approval", rendered)
        self.assertIn("高风险：current-user-and-supervisor", rendered)
        self.assertIn("写入：current-user-and-supervisor", rendered)
        self.assertIn("外部副作用：current-user-and-supervisor", rendered)

    def test_windsurf_aggregate_includes_side_effect_matrix_items(self):
        profile = self._valid_profile()
        sample_agent = discover_agents(ROOT)[0]
        source = ROOT / sample_agent.source_path
        source_fields, source_body = read_agent(source)
        with patch.object(
            governance,
            "_bound_profile",
            return_value=(profile, sample_agent.source_path),
        ):
            governed = render_governed_body(ROOT, source)
            governance_text = render_governance(ROOT, source)

        _, sections = governance._expected_agent_output_texts(
            sample_agent,
            source_fields,
            governance_text,
            governed,
            source_body,
            source_path=source,
        )

        aggregate = governance._expected_windsurf_document([sections[1]])

        self.assertIn("低风险：self-service", aggregate)
        self.assertIn("中风险：current-user-approval", aggregate)
        self.assertIn("高风险：current-user-and-supervisor", aggregate)
        self.assertIn("写入：current-user-and-supervisor", aggregate)
        self.assertIn("外部副作用：current-user-and-supervisor", aggregate)

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

    @staticmethod
    def _frontmatter_bounds(raw: bytes) -> tuple[int, int, int, int]:
        opening = _FRONTMATTER_OPEN.match(raw)
        if opening is None:
            raise AssertionError("source missing frontmatter")
        closing = _FRONTMATTER_CLOSE.search(raw, opening.end())
        if closing is None:
            raise AssertionError("source missing frontmatter close")
        return opening.start(), opening.end(), closing.start(), closing.end()

    def _remove_governance_profile_line(self, raw: bytes) -> bytes:
        _, opening_end, closing_start, _ = self._frontmatter_bounds(raw)
        frontmatter = raw[opening_end:closing_start]
        removed = re.sub(_GOVERNANCE_PROFILE_LINE, b"", frontmatter, count=1)
        return raw[:opening_end] + removed + raw[closing_start:]

    @staticmethod
    def _is_temp_bind_file(path: Path) -> bool:
        return path.name.startswith(".governance-bind-") and path.suffix == ".tmp"

    def test_stable_source_hash_matches_persisted_profiles_and_binding_line_is_not_in_hash(self):
        directory, fixture_root = self._isolated_repo_fixture()
        try:
            agents = discover_agents(fixture_root)
            profiles = build_profiles(fixture_root)
            hashes = {profile["role_id"]: profile["source_hash"] for profile in profiles}

            self.assertEqual(len(profiles), 269)
            for agent in agents:
                source = fixture_root / agent.source_path
                self.assertEqual(stable_source_hash(source), hashes[agent.role_id])

            sample_agent = agents[0]
            sample_source = fixture_root / sample_agent.source_path
            original = sample_source.read_bytes()

            sample_source.write_bytes(self._remove_governance_profile_line(original))
            self.assertEqual(stable_source_hash(sample_source), hashes[sample_agent.role_id])

            sample_source.write_bytes(_bound_source_bytes(sample_source, sample_agent.role_id))
            self.assertEqual(stable_source_hash(sample_source), hashes[sample_agent.role_id])
        finally:
            directory.cleanup()

    def test_verify_bindings_rejects_duplicate_governance_profile_bindings(self):
        directory, fixture_root = self._isolated_repo_fixture()
        try:
            source = (fixture_root / discover_agents(fixture_root)[0].source_path)
            raw = source.read_bytes()
            _, opening_end, closing_start, _ = self._frontmatter_bounds(raw)
            frontmatter = raw[opening_end:closing_start]
            if not _GOVERNANCE_PROFILE_LINE.search(frontmatter):
                raise AssertionError("expected governance_profile binding in fixture")

            duplicated = re.sub(
                _GOVERNANCE_PROFILE_LINE,
                lambda match: match.group(0) + match.group(0),
                frontmatter,
                count=1,
            )
            source.write_bytes(raw[:opening_end] + duplicated + raw[closing_start:])

            with self.assertRaisesRegex(
                GovernanceError,
                "DUPLICATE_GOVERNANCE_PROFILE",
            ):
                verify_bindings(fixture_root)
        finally:
            directory.cleanup()

    def test_verify_bindings_rejects_removed_governance_profile(self):
        directory, fixture_root = self._isolated_repo_fixture()
        try:
            source = fixture_root / discover_agents(fixture_root)[0].source_path
            source.write_bytes(self._remove_governance_profile_line(source.read_bytes()))
            with self.assertRaisesRegex(
                GovernanceError,
                "MISSING_GOVERNANCE_BINDING",
            ):
                verify_bindings(fixture_root)
        finally:
            directory.cleanup()

    def test_verify_bindings_discovers_each_source_once(self):
        directory, fixture_root = self._isolated_repo_fixture()
        try:
            original_discover_agents = governance.discover_agents
            original_profiles_by_id = governance._profiles_by_id
            with patch.object(governance, "discover_agents") as mock_discover, patch.object(
                governance, "_profiles_by_id"
            ) as mock_profiles:
                mock_discover.side_effect = original_discover_agents
                mock_profiles.side_effect = original_profiles_by_id
                self.assertEqual(verify_bindings(fixture_root), 269)
            self.assertEqual(mock_discover.call_count, 1)
            self.assertEqual(mock_profiles.call_count, 1)
        finally:
            directory.cleanup()

    def test_bind_sources_rolls_back_when_second_replace_fails(self):
        directory, fixture_root = self._isolated_repo_fixture()
        try:
            sources = sorted(
                fixture_root / agent.source_path
                for agent in discover_agents(fixture_root)
            )
            targets = sources[:2]
            for source in targets:
                source.write_bytes(self._remove_governance_profile_line(source.read_bytes()))
            before = {path.relative_to(fixture_root): path.read_bytes() for path in sources}

            state = {"calls": 0}
            original_replace = governance.os.replace

            def flaky_replace(*args):
                state["calls"] += 1
                if state["calls"] == 2:
                    raise OSError("simulated replace failure")
                return original_replace(*args)

            with patch.object(governance.os, "replace", side_effect=flaky_replace):
                with self.assertRaisesRegex(GovernanceError, "BIND_REPLACE_FAILED"):
                    bind_sources(fixture_root)

            after = {path.relative_to(fixture_root): path.read_bytes() for path in sources}
            self.assertEqual(before, after)
            temp_files = [
                candidate
                for candidate in fixture_root.rglob("**/*")
                if candidate.is_file() and self._is_temp_bind_file(candidate)
            ]
            self.assertEqual(temp_files, [])
        finally:
            directory.cleanup()

    def test_bind_sources_raises_rollback_failed_when_replace_and_rollback_fail(self):
        directory, fixture_root = self._isolated_repo_fixture()
        try:
            agents = discover_agents(fixture_root)
            sources = sorted(fixture_root / agent.source_path for agent in agents)
            targets = sources[:2]
            target_roles = {
                fixture_root / agent.source_path: agent.role_id for agent in agents
                if fixture_root / agent.source_path in targets
            }
            for source in targets:
                source.write_bytes(self._remove_governance_profile_line(source.read_bytes()))
            before = {path.relative_to(fixture_root): path.read_bytes() for path in sources}

            state = {"calls": 0}
            original_replace = governance.os.replace

            def flaky_replace(*args):
                state["calls"] += 1
                if state["calls"] in {2, 3}:
                    raise OSError(
                        "simulated replace failure on attempt {}".format(state["calls"])
                    )
                return original_replace(*args)

            with patch.object(governance.os, "replace", side_effect=flaky_replace):
                with self.assertRaisesRegex(GovernanceError, "ROLLBACK_FAILED"):
                    bind_sources(fixture_root)

            first_target, second_target = targets[0], targets[1]
            first_after = first_target.read_bytes()
            second_after = second_target.read_bytes()
            _, opening_end, closing_start, _ = self._frontmatter_bounds(first_after)
            first_lines = re.findall(
                _GOVERNANCE_PROFILE_LINE,
                first_after[opening_end:closing_start],
            )
            self.assertEqual(len(first_lines), 1)
            first_binding = (
                first_lines[0].split(b":", 1)[1]
                .strip()
                .strip(b'"')
                .strip(b"'")
            )
            self.assertEqual(first_binding.decode("utf-8"), target_roles[first_target])

            _, opening_end, closing_start, _ = self._frontmatter_bounds(second_after)
            self.assertEqual(
                re.findall(_GOVERNANCE_PROFILE_LINE, second_after[opening_end:closing_start]),
                [],
            )

            for path in sources[2:]:
                self.assertEqual(before[path.relative_to(fixture_root)], path.read_bytes())
            temp_files = [
                candidate
                for candidate in fixture_root.rglob("**/*")
                if candidate.is_file() and self._is_temp_bind_file(candidate)
            ]
            self.assertEqual(temp_files, [])
        finally:
            directory.cleanup()

    def test_bind_sources_reports_cleanup_failure_as_binds_cleanup_error(self):
        directory, fixture_root = self._isolated_repo_fixture()
        try:
            agents = discover_agents(fixture_root)
            sources = sorted(fixture_root / agent.source_path for agent in agents)
            targets = sources[:2]
            for source in targets:
                source.write_bytes(self._remove_governance_profile_line(source.read_bytes()))
            before = {path.relative_to(fixture_root): path.read_bytes() for path in sources}

            original_replace = governance.os.replace
            original_unlink = governance.os.unlink
            replace_state = {"calls": 0}
            unlink_state = {"calls": 0}

            def flaky_replace(*args):
                replace_state["calls"] += 1
                if replace_state["calls"] == 2:
                    raise OSError("simulated replace failure")
                return original_replace(*args)

            def flaky_unlink(path):
                unlink_state["calls"] += 1
                if unlink_state["calls"] == 1:
                    raise OSError("simulated cleanup failure")
                return original_unlink(path)

            with patch.object(governance.os, "replace", side_effect=flaky_replace):
                with patch.object(governance.os, "unlink", side_effect=flaky_unlink):
                    with self.assertRaisesRegex(
                        GovernanceError,
                        "BIND_CLEANUP_FAILED",
                    ):
                        bind_sources(fixture_root)

            for target in targets:
                raw = target.read_bytes()
                _, opening_end, closing_start, _ = self._frontmatter_bounds(raw)
                self.assertEqual(
                    re.findall(_GOVERNANCE_PROFILE_LINE, raw[opening_end:closing_start]),
                    [],
                )

            for path in sources[2:]:
                self.assertEqual(before[path.relative_to(fixture_root)], path.read_bytes())

            temp_files = [
                candidate
                for candidate in fixture_root.rglob("**/*")
                if candidate.is_file() and self._is_temp_bind_file(candidate)
            ]
            self.assertEqual(len(temp_files), 1)
            self.assertEqual(replace_state["calls"], 3)
        finally:
            directory.cleanup()

    def test_verify_bindings_rejects_stable_hash_mismatch_after_persona_change(self):
        directory, fixture_root = self._isolated_repo_fixture()
        try:
            source = fixture_root / discover_agents(fixture_root)[0].source_path
            raw = source.read_bytes()
            _, _, closing_start, closing_end = self._frontmatter_bounds(raw)
            source.write_bytes(raw[:closing_end] + b"\n#changed-body-marker\n" + raw[closing_end:])

            with self.assertRaisesRegex(GovernanceError, "SOURCE_HASH_MISMATCH"):
                verify_bindings(fixture_root)
        finally:
            directory.cleanup()

    def test_binding_preserves_body_bytes_and_is_atomic_idempotent(self):
        directory, fixture_root = self._isolated_repo_fixture()
        try:
            sources = sorted(
                fixture_root / agent.source_path
                for agent in discover_agents(fixture_root)
            )
            before = {}
            for path in sources:
                unbound = self._remove_governance_profile_line(path.read_bytes())
                path.write_bytes(unbound)
                before[path.relative_to(fixture_root)] = unbound

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

            self.assertEqual(first_count, 269)
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

            profiles_path = fixture_root / "governance/role-governance-profiles.json"
            profiles = json.loads(profiles_path.read_text(encoding="utf-8"))
            profile = next(
                candidate
                for candidate in profiles
                if candidate["role_id"] == agent.role_id
            )
            profile["source_hash"] = stable_source_hash(source)
            profiles_path.write_text(
                json.dumps(profiles, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )

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

    def test_collect_manifest_entries_rejects_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "generated"
            root.mkdir()
            managed = root / "github-copilot"
            managed.mkdir(parents=True)

            target = root / "source.md"
            target.write_text("# source", encoding="utf-8")
            (managed / "agent.md").symlink_to(target)

            with self.assertRaisesRegex(
                GovernanceError,
                "MANIFEST_ENTRY_SYMLINK",
            ):
                _collect_manifest_entries(root)

    def test_collect_manifest_entries_rejects_root_and_tool_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            real_root = base / "real-generated"
            real_root.mkdir()
            linked_root = base / "linked-generated"
            linked_root.symlink_to(real_root, target_is_directory=True)
            with self.assertRaisesRegex(GovernanceError, "MANIFEST_ROOT_SYMLINK"):
                _collect_manifest_entries(linked_root)

            real_tool = base / "real-kimi"
            real_tool.mkdir()
            (real_root / "kimi").symlink_to(real_tool, target_is_directory=True)
            with self.assertRaisesRegex(
                GovernanceError,
                "MANIFEST_TOOL_ROOT_SYMLINK",
            ):
                _collect_manifest_entries(real_root)

    def test_verify_generated_rejects_generated_root_symlink_before_resolution(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            real_root = base / "real-generated"
            real_root.mkdir()
            linked_root = base / "linked-generated"
            linked_root.symlink_to(real_root, target_is_directory=True)
            with self.assertRaisesRegex(GovernanceError, "GENERATED_ROOT_SYMLINK"):
                verify_generated(base, linked_root, 1, 1)

    def test_validate_hermes_agents_rejects_body_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            repo_root = Path(directory)
            agents_root = repo_root / "agents-json"
            data_root = agents_root / "data"
            data_root.mkdir(parents=True)
            payload = [
                {
                    "slug": "frontend-developer",
                    "governance_profile": "frontend-dev",
                    "governance_digest": "f" * 64,
                    "body": "actual body",
                    "source_path": "engineering/frontend-engineer.md",
                }
            ]
            (data_root / "agents.json").write_text(
                json.dumps(payload, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )

            with patch.object(
                governance,
                "_profiles_by_id",
                return_value={
                    "frontend-dev": {
                        "source_path": "engineering/frontend-engineer.md",
                    }
                },
            ):
                fake_agent = Agent(
                    role_id="frontend-dev",
                    name="Frontend Developer",
                    division="engineering",
                    source_path="engineering/frontend-engineer.md",
                    source_sha256="a" * 64,
                )
                with patch.object(governance, "discover_agents", return_value=[fake_agent]):
                    with patch.object(
                        governance,
                        "render_governed_body",
                        return_value="expected governance body",
                    ):
                        with self.assertRaisesRegex(
                            GovernanceError,
                            "HERMES_AGENT_BODY_MISMATCH",
                        ):
                            _validate_hermes_agents(repo_root, agents_root, 1)

    def test_validate_hermes_agents_rejects_duplicate_identity_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            repo_root = Path(directory)
            agents_root = repo_root / "agents-json"
            data_root = agents_root / "data"
            data_root.mkdir(parents=True)
            rendered = "governed"
            payload = [
                {
                    "slug": "frontend-developer",
                    "governance_profile": "frontend-dev",
                    "governance_digest": governance._hash_hex(rendered),
                    "body": rendered,
                    "source_path": "engineering/frontend-engineer.md",
                },
                {
                    "slug": "different-slug",
                    "governance_profile": "frontend-dev",
                    "governance_digest": governance._hash_hex(rendered),
                    "body": rendered,
                    "source_path": "engineering/other.md",
                },
            ]
            (data_root / "agents.json").write_text(
                json.dumps(payload, ensure_ascii=False),
                encoding="utf-8",
            )
            fake_agents = [
                Agent(
                    "frontend-dev",
                    "Frontend Developer",
                    "engineering",
                    "engineering/frontend-engineer.md",
                    "a" * 64,
                ),
                Agent(
                    "other",
                    "Other",
                    "engineering",
                    "engineering/other.md",
                    "b" * 64,
                ),
            ]
            profiles = {
                "frontend-dev": {"source_path": "engineering/frontend-engineer.md"},
                "other": {"source_path": "engineering/other.md"},
            }
            with patch.object(governance, "discover_agents", return_value=fake_agents):
                with patch.object(governance, "_profiles_by_id", return_value=profiles):
                    with patch.object(
                        governance,
                        "render_governed_body",
                        return_value=rendered,
                    ):
                        with self.assertRaisesRegex(
                            GovernanceError,
                            "HERMES_DUPLICATE_GOVERNANCE_PROFILE",
                        ):
                            _validate_hermes_agents(repo_root, agents_root, 2)

    def test_validate_hermes_agents_rejects_set_drift_from_discovery(self):
        with tempfile.TemporaryDirectory() as directory:
            repo_root = Path(directory)
            agents_root = repo_root / "agents-json"
            data_root = agents_root / "data"
            data_root.mkdir(parents=True)
            rendered = "governed"
            (data_root / "agents.json").write_text(
                json.dumps([{
                    "slug": "stale",
                    "governance_profile": "stale",
                    "governance_digest": governance._hash_hex(rendered),
                    "body": rendered,
                    "source_path": "engineering/stale.md",
                }]),
                encoding="utf-8",
            )
            discovered = Agent(
                "current",
                "Current",
                "engineering",
                "engineering/current.md",
                "a" * 64,
            )
            with patch.object(governance, "discover_agents", return_value=[discovered]):
                with patch.object(
                    governance,
                    "_profiles_by_id",
                    return_value={"stale": {"source_path": "engineering/stale.md"}},
                ):
                    with patch.object(
                        governance,
                        "render_governed_body",
                        return_value=rendered,
                    ):
                        with self.assertRaisesRegex(
                            GovernanceError,
                            "HERMES_GOVERNANCE_PROFILE_SET_MISMATCH",
                        ):
                            _validate_hermes_agents(repo_root, agents_root, 1)

    def test_validate_hermes_agents_rejects_json_symlink_before_read(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            agents_root = base / "agents-json"
            agents_root.mkdir()
            external_data = base / "external-data"
            external_data.mkdir()
            (external_data / "agents.json").write_text("[]", encoding="utf-8")
            (agents_root / "data").symlink_to(external_data, target_is_directory=True)

            with self.assertRaisesRegex(
                GovernanceError,
                "HERMES_ARTIFACT_SYMLINK",
            ):
                _validate_hermes_agents(agents_root, agents_root, 1)

    def _minimal_generated_fixture(self, base: Path) -> tuple[Path, Path, Agent]:
        repo_root = base / "repo"
        generated_root = base / "generated"
        generated_root.mkdir(parents=True)
        source_path = "engineering/frontend-developer.md"
        source = repo_root / source_path
        source.parent.mkdir(parents=True)
        source.write_text(
            "---\n"
            "name: Frontend Developer\n"
            "description: Minimal fixture\n"
            "governance_profile: frontend-dev\n"
            "---\n"
            "Persona\n",
            encoding="utf-8",
        )
        agent = Agent(
            "frontend-dev",
            "Frontend Developer",
            "engineering",
            source_path,
            "a" * 64,
        )
        fields, persona = read_agent(source)
        governed = "Governance\n\nPersona"
        expected_files, sections = governance._expected_agent_output_texts(
            agent,
            fields,
            "Governance",
            governed,
            persona,
            source_path=source,
        )
        tool_directories = _expected_tool_directories()
        for directory_name in tool_directories.values():
            (generated_root / directory_name).mkdir(parents=True)
        for relative, text in expected_files.items():
            tool, tool_relative = relative.split("/", 1)
            target = generated_root / tool_directories[tool] / tool_relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if relative.startswith("codex/"):
                target.write_text(
                    'name = "Frontend Developer"\n'
                    'description = "Minimal fixture"\n'
                    'developer_instructions = "Governance\\n\\nPersona"\n',
                    encoding="utf-8",
                )
            else:
                target.write_text(text, encoding="utf-8")
        (generated_root / "aider" / "CONVENTIONS.md").write_text(
            governance._expected_aider_document([sections[0]]),
            encoding="utf-8",
        )
        (generated_root / "windsurf" / ".windsurfrules").write_text(
            governance._expected_windsurf_document([sections[1]]),
            encoding="utf-8",
        )
        (generated_root / "hermes" / "agency-agents-router").mkdir()
        (generated_root / "hermes" / "agent-manifest.json").write_text(
            "{}\n",
            encoding="utf-8",
        )
        return repo_root, generated_root, agent

    def _verify_minimal_generated(self, repo_root: Path, generated_root: Path, agent: Agent):
        profile = {
            "role_id": agent.role_id,
            "source_path": agent.source_path,
        }
        with patch.object(governance, "discover_agents", return_value=[agent]):
            with patch.object(governance, "build_profiles", return_value=[profile]):
                with patch.object(
                    governance,
                    "_load_tools_list",
                    return_value=sorted(_expected_tool_directories().keys()),
                ):
                    with patch.object(
                        governance,
                        "render_governance",
                        return_value="Governance",
                    ):
                        with patch.object(
                            governance,
                            "render_governed_body",
                            return_value="Governance\n\nPersona",
                        ):
                            with patch.object(
                                governance,
                                "_validate_hermes_agents",
                                return_value={"record_count": 1},
                            ):
                                return verify_generated(repo_root, generated_root, 1, 16)

    def test_verify_generated_rejects_kimi_vibe_and_aggregate_injection(self):
        mutations = (
            ("kimi/frontend-developer/system.md", "prefix"),
            ("vibe/prompts/frontend-developer.md", "prefix"),
            ("aider/CONVENTIONS.md", "suffix"),
            ("windsurf/.windsurfrules", "suffix"),
        )
        for relative, position in mutations:
            with self.subTest(relative=relative):
                with tempfile.TemporaryDirectory() as directory:
                    repo_root, generated_root, agent = self._minimal_generated_fixture(
                        Path(directory)
                    )
                    target = generated_root / relative
                    original = target.read_text(encoding="utf-8")
                    injected = "UNEXPECTED\n"
                    target.write_text(
                        injected + original if position == "prefix" else original + injected,
                        encoding="utf-8",
                    )
                    with self.assertRaisesRegex(
                        GovernanceError,
                        "TOOL_FILE_MISMATCH|AGGREGATE_DOCUMENT_MISMATCH",
                    ):
                        self._verify_minimal_generated(repo_root, generated_root, agent)

    def test_verify_generated_rejects_artifact_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            repo_root, generated_root, agent = self._minimal_generated_fixture(
                Path(directory)
            )
            artifact = generated_root / "kimi/frontend-developer/system.md"
            target = generated_root / "kimi/frontend-developer/real-system.md"
            artifact.rename(target)
            artifact.symlink_to(target.name)
            with self.assertRaisesRegex(
                GovernanceError,
                "GENERATED_ARTIFACT_SYMLINK",
            ):
                self._verify_minimal_generated(repo_root, generated_root, agent)


    def test_verify_generated_rejects_missing_governance_binding(self):
        with tempfile.TemporaryDirectory() as directory:
            repo_root = Path(directory)
            generated_root = repo_root / "integrations"
            generated_root.mkdir()

            tool_dirs = _expected_tool_directories()
            for directory_name in tool_dirs.values():
                (generated_root / directory_name).mkdir(parents=True)

            (generated_root / "aider" / "CONVENTIONS.md").write_text(
                "# test\n", encoding="utf-8"
            )
            (generated_root / "windsurf" / ".windsurfrules").write_text(
                "# test\n", encoding="utf-8"
            )
            (generated_root / "hermes" / "agency-agents-router").mkdir(parents=True)

            fake_agent = Agent(
                role_id="frontend-dev",
                name="Frontend Developer",
                division="engineering",
                source_path="engineering/frontend-developer.md",
                source_sha256="a" * 64,
                authority="",
            )
            fake_profile = {
                "role_id": "frontend-dev",
                "role_name": "Frontend Developer",
                "division": "engineering",
                "risk_level": "low",
                "source_path": "engineering/frontend-developer.md",
                "source_hash": "a" * 64,
            }

            # Minimal failure-path: no governance_profile binding in rendered source.
            source_fields = {
                "name": "Frontend Developer",
                "description": "Frontend test profile",
            }

            with patch.object(governance, "discover_agents", return_value=[fake_agent]):
                with patch.object(governance, "build_profiles", return_value=[fake_profile]):
                    with patch.object(
                        governance,
                        "_load_tools_list",
                        return_value=sorted(tool_dirs.keys()),
                    ):
                        with patch.object(
                            governance,
                            "read_agent",
                            return_value=(source_fields, "source body"),
                        ):
                            with patch.object(
                                governance,
                                "_validate_hermes_agents",
                                return_value={"record_count": 1},
                            ):
                                with self.assertRaisesRegex(
                                    GovernanceError,
                                    "MISMATCHED_GOVERNANCE_BINDING",
                                ):
                                    verify_generated(
                                        repo_root,
                                        generated_root,
                                        1,
                                        len(tool_dirs),
                                    )

    def _minimal_verify_all_fixture(self, base: Path) -> tuple[Path, Path, Agent]:
        return self._minimal_generated_fixture(base)

    def _minimal_verify_all_patches(self, agent, hashes: dict[str, str], output: bool = True):
        tool_names = sorted(_expected_tool_directories().keys())
        profile = {
            "role_id": agent.role_id,
            "source_path": agent.source_path,
        }
        return patch.object(
            governance,
            "discover_agents",
            return_value=[agent],
        ), patch.object(
            governance,
            "_load_tools_list",
            return_value=tool_names,
        ), patch.object(
            governance,
            "build_profiles",
            return_value=[profile],
        ), patch.object(
            governance,
            "render_governance",
            return_value="Governance",
        ), patch.object(
            governance,
            "render_governed_body",
            return_value="Governance\n\nPersona",
        ), patch.object(
            governance,
            "_validate_hermes_agents",
            return_value={"record_count": 1},
        ), patch.object(
            governance,
            "verify_bindings",
            return_value=1,
        ), patch.object(
            governance,
            "_collect_source_input_hashes",
            return_value=hashes,
        )

    def test_verify_all_cli_accepts_and_writes_report(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            repo_root, generated_root, agent = self._minimal_verify_all_fixture(base)
            output = repo_root / "verify-all-report.json"
            hashes = {
                "department_policies": "a" * 64,
                "role_overrides": "b" * 64,
                "role_governance_profiles": "c" * 64,
                "tools": "d" * 64,
            }
            patches = self._minimal_verify_all_patches(
                agent,
                hashes=hashes,
            )
            with patches[0], patches[1], patches[2], patches[3], patches[4], patches[5], patches[6], patches[7]:
                self.assertEqual(
                    governance.main(
                        [
                            "verify-all",
                            "--repo-root",
                            str(repo_root),
                            "--generated-root",
                            str(generated_root),
                            "--output",
                            str(output),
                            "--expected-agents",
                            "1",
                            "--expected-tools",
                            "16",
                        ]
                    ),
                    0,
                )
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["acceptance"]["expected_agents"], 1)
            self.assertEqual(report["acceptance"]["expected_tools"], 16)
            self.assertEqual(report["source_input_hashes"], hashes)
            self.assertEqual(report["generated_summary"]["expected_agents"], 1)
            self.assertEqual(report["generated_summary"]["expected_tools"], 16)
            self.assertEqual(report["generated_summary"]["token_scan"]["total_hits"], 0)

    def test_verify_all_rejects_verify_all_when_generated_has_sensitive_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            repo_root, generated_root, agent = self._minimal_verify_all_fixture(base)
            (generated_root / "kimi" / "frontend-developer" / "system.md").write_text(
                (
                    "-----BEGIN PRIVATE KEY-----\n"
                    "MIIEpAIBAAKCAQEA1\n"
                    "-----END PRIVATE KEY-----\n"
                ),
                encoding="utf-8",
            )
            hashes = {
                "department_policies": "a" * 64,
                "role_overrides": "b" * 64,
                "role_governance_profiles": "c" * 64,
                "tools": "d" * 64,
            }
            patches = self._minimal_verify_all_patches(
                agent,
                hashes=hashes,
            )
            with patches[0], patches[1], patches[2], patches[3], patches[4], patches[5], patches[6], patches[7]:
                with self.assertRaisesRegex(
                    GovernanceError,
                    "SENSITIVE_TOKEN_DETECTED",
                ):
                    verify_all(
                        repo_root,
                        generated_root,
                        expected_agents=1,
                        expected_tools=16,
                    )

    def test_token_scan_does_not_treat_plain_text_as_sensitive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            note = root / "notes.md"
            note.write_text(
                "This document only uses the words private key for explanation.\n",
                encoding="utf-8",
            )
            scan = _ensure_token_free_texts(root)
            self.assertEqual(scan["total_hits"], 0)
            self.assertIn("PEM_PRIVATE_KEY_BLOCK", scan["by_label"])


if __name__ == "__main__":
    unittest.main()
