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
    errors = _validation_errors(value, schema, root, path)
    if errors:
        raise GovernanceValidationError(errors[0])


def _validation_errors(value, schema, root, path):
    if "$ref" in schema:
        schema = _resolve_ref(root, schema["$ref"])

    errors = []
    if "type" in schema and not _type_matches(value, schema["type"]):
        return ["{} must be {}".format(path, schema["type"])]
    if "enum" in schema and value not in schema["enum"]:
        errors.append("{} is not an allowed enum value".format(path))

    if isinstance(value, dict):
        missing = [name for name in schema.get("required", []) if name not in value]
        if missing:
            errors.append("{} missing required fields: {}".format(path, ", ".join(sorted(missing))))
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            unknown = sorted(set(value) - set(properties))
            if unknown:
                errors.append("{} has unknown fields: {}".format(path, ", ".join(unknown)))
        for name, child in sorted(value.items()):
            if name in properties:
                errors.extend(_validation_errors(child, properties[name], root, "{}.{}".format(path, name)))

    if isinstance(value, list):
        if schema.get("uniqueItems"):
            encoded = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in value]
            if len(encoded) != len(set(encoded)):
                errors.append("{} must contain unique items".format(path))
        if "items" in schema:
            for index, child in enumerate(value):
                errors.extend(_validation_errors(child, schema["items"], root, "{}[{}]".format(path, index)))
        if "minItems" in schema and len(value) < schema["minItems"]:
            errors.append("{} has fewer than minItems".format(path))
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append("{} exceeds maxItems".format(path))

    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            errors.append("{} is shorter than minLength".format(path))
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errors.append("{} exceeds maxLength".format(path))
        if "pattern" in schema and re.fullmatch(schema["pattern"], value) is None:
            errors.append("{} does not match pattern".format(path))

    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append("{} is below minimum".format(path))
        if "maximum" in schema and value > schema["maximum"]:
            errors.append("{} exceeds maximum".format(path))
    return errors


def _validate_contract(document, schema_name):
    schema = load_schema(schema_name)
    return sorted(set(_validation_errors(document, schema, schema, "$")))


def validate_profile(profile: dict) -> list[str]:
    """Return a sorted error list; return [] when the role profile is valid."""
    return _validate_contract(profile, "role-governance-profile")


def validate_response(response):
    """Return a sorted error list; return [] when a governed response is valid."""
    return _validate_contract(response, "governed-response")


__all__ = ["GovernanceValidationError", "load_schema", "validate_profile", "validate_response"]
