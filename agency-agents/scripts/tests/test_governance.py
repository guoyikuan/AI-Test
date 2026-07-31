import json
import re
import unittest
from pathlib import Path

from governance import load_schema, validate_profile, validate_response
from scripts.governance import build_profiles


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

        sensitive_profiles = []
        for profile in profiles:
            authority = json.dumps(
                profile.get("authority", ""), ensure_ascii=False
            ).lower()
            title_or_authority = " ".join(
                (profile["role_name"].lower(), authority)
            )
            if any(term in title_or_authority for term in sensitive_terms):
                sensitive_profiles.append(profile)

        self.assertTrue(sensitive_profiles)
        for profile in sensitive_profiles:
            self.assertIn(profile["role_id"], override_ids)


if __name__ == "__main__":
    unittest.main()
