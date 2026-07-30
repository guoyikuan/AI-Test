import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GOVERNANCE_ROOT = ROOT / "governance"


class GovernanceContractTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
