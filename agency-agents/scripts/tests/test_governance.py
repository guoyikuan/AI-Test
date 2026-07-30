import json
import unittest
from pathlib import Path

from governance import GovernanceValidationError, load_schema, validate_profile


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
                "low": [],
                "medium": ["human_review"],
                "high": ["explicit_human_approval"],
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
        self.assertTrue(validate_profile(self._valid_profile()))

    def test_profile_validator_rejects_unknown_field(self):
        profile = self._valid_profile()
        profile["unexpected"] = True
        with self.assertRaises(GovernanceValidationError):
            validate_profile(profile)

    def test_profile_validator_rejects_action_list_bound(self):
        profile = self._valid_profile()
        profile["allowed_read_actions"] = ["action-{}".format(index) for index in range(101)]
        with self.assertRaises(GovernanceValidationError):
            validate_profile(profile)

    def test_schema_loader_rejects_unknown_or_traversal_names(self):
        self.assertEqual(load_schema("role-governance-profile")["title"], "Agency Agents Role Governance Profile")
        for name in ("unknown", "../role-governance-profile", "role-governance-profile.json"):
            with self.assertRaises(ValueError):
                load_schema(name)


if __name__ == "__main__":
    unittest.main()
