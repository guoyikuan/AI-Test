"""Deterministic, standard-library validation for Agency Agents governance."""

import json
import re
from pathlib import Path


_GOVERNANCE_ROOT = Path(__file__).resolve().parent
_SCHEMA_FILES = {
    "governed-response": "governed-response.schema.json",
    "governed-response.schema.json": "governed-response.schema.json",
    "role-governance-profile": "role-governance-profile.schema.json",
    "role-governance-profile.schema.json": "role-governance-profile.schema.json",
}


class GovernanceValidationError(ValueError):
    """Raised when a governance document violates its closed schema."""


def load_schema(name):
    """Load one of the two canonical governance schemas by name."""
    if not isinstance(name, str) or name not in _SCHEMA_FILES:
        raise ValueError("unknown canonical governance schema: {!r}".format(name))
    schema_path = _GOVERNANCE_ROOT / "schemas" / _SCHEMA_FILES[name]
    return json.loads(schema_path.read_text(encoding="utf-8"))


def _resolve_ref(root, reference):
    if not isinstance(reference, str) or not reference.startswith("#/"):
        raise GovernanceValidationError("unsupported schema reference: {!r}".format(reference))
    value = root
    for component in reference[2:].split("/"):
        if component not in value:
            raise GovernanceValidationError("unresolved schema reference: {}".format(reference))
        value = value[component]
    return value


def _type_matches(value, expected):
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "null":
        return value is None
    raise GovernanceValidationError("unsupported schema type: {}".format(expected))


def _validate(value, schema, root, path):
    if "$ref" in schema:
        _validate(value, _resolve_ref(root, schema["$ref"]), root, path)
    if "type" in schema and not _type_matches(value, schema["type"]):
        raise GovernanceValidationError("{} must be {}".format(path, schema["type"]))
    if "enum" in schema and value not in schema["enum"]:
        raise GovernanceValidationError("{} is not an allowed enum value".format(path))

    if isinstance(value, dict):
        missing = [name for name in schema.get("required", []) if name not in value]
        if missing:
            raise GovernanceValidationError("{} missing required fields: {}".format(path, ", ".join(missing)))
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            unknown = sorted(set(value) - set(properties))
            if unknown:
                raise GovernanceValidationError("{} has unknown fields: {}".format(path, ", ".join(unknown)))
        for name, child in value.items():
            if name in properties:
                _validate(child, properties[name], root, "{}.{}".format(path, name))

    if isinstance(value, list):
        if schema.get("uniqueItems"):
            encoded = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in value]
            if len(encoded) != len(set(encoded)):
                raise GovernanceValidationError("{} must contain unique items".format(path))
        if "items" in schema:
            for index, child in enumerate(value):
                _validate(child, schema["items"], root, "{}[{}]".format(path, index))
        if "minItems" in schema and len(value) < schema["minItems"]:
            raise GovernanceValidationError("{} has fewer than minItems".format(path))
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            raise GovernanceValidationError("{} exceeds maxItems".format(path))

    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            raise GovernanceValidationError("{} is shorter than minLength".format(path))
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            raise GovernanceValidationError("{} exceeds maxLength".format(path))
        if "pattern" in schema and re.fullmatch(schema["pattern"], value) is None:
            raise GovernanceValidationError("{} does not match pattern".format(path))

    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            raise GovernanceValidationError("{} is below minimum".format(path))
        if "maximum" in schema and value > schema["maximum"]:
            raise GovernanceValidationError("{} exceeds maximum".format(path))


def validate_profile(profile):
    """Validate one role profile and return True; invalid input raises ValueError."""
    schema = load_schema("role-governance-profile")
    _validate(profile, schema, schema, "$")
    return True


__all__ = ["GovernanceValidationError", "load_schema", "validate_profile"]
