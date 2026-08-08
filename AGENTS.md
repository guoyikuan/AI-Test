# AI-Test Codex Agent / Skill Governance Loader

## Scope

This file applies to the entire AI-Test repository.

## Canonical policy

The sole canonical repository policy for Agent / Skill evolution is:

`agency-agents/governance/agent-skill-evolution-policy.zh-CN.md`

This `AGENTS.md` is only a Codex loading and enforcement adapter. It must not become a second policy source.

## Mandatory startup behavior

Before planning, delegating, evaluating, or changing any Skill, Agent, subagent, council, orchestrator, protocol, script, evaluation, or governance mechanism in this repository, Codex must:

1. Read the canonical policy in full.
2. Treat every requirement in that policy as mandatory.
3. Inventory existing relevant Skills and Agents before proposing a new implementation.
4. Identify the evidence, lifecycle state, permission ceiling, evaluation contract, canonical source, and rollback reference for the proposed change.
5. Fail closed if the policy is missing, unreadable, contradictory, or cannot be applied to the requested scope.

## Non-negotiable enforcement

- Evolution must not expand tool, repository, production, deployment, release, or memory permissions.
- Ordinary business development and operations must not be represented as Skill or Agent evolution.
- Duplicate capabilities must be merged into the canonical source instead of creating another implementation.
- Candidate evaluation must use frozen inputs, explicit scoring, auditable receipts, and defined failure behavior.
- High-risk decisions require independent verification and current user authorization for the exact action.
- Codex must not claim complete, passed, fixed, adopted, or releasable without a fresh, task-bound `supervisor.assurance-decision/v1` with `decision=ALLOW`.
- Codex must not write long-term memory unless the current user explicitly requests that exact memory update.

If this adapter and the canonical policy differ, stop and report policy drift. Do not silently choose one version or weaken the more restrictive applicable instruction.
