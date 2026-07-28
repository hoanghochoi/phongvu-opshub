#!/usr/bin/env python3
"""Validate the tracked OpsHub project-scoped Codex configuration."""

from __future__ import annotations

import argparse
import pathlib
import sys
import tomllib


EXPECTED = {
    "opshub-spec-analyst.toml": "opshub_spec_analyst",
    "opshub-repo-explorer.toml": "opshub_repo_explorer",
    "opshub-implementer.toml": "opshub_implementer",
    "opshub-test-engineer.toml": "opshub_test_engineer",
    "opshub-code-reviewer.toml": "opshub_code_reviewer",
    "opshub-security-reviewer.toml": "opshub_security_reviewer",
    "opshub-ui-ux-reviewer.toml": "opshub_ui_ux_reviewer",
    "opshub-release-auditor.toml": "opshub_release_auditor",
}
REQUIRED_AGENT_FIELDS = {"name", "description", "developer_instructions"}
ALLOWED_AGENT_FIELDS = REQUIRED_AGENT_FIELDS | {
    "model",
    "model_reasoning_effort",
}
ALLOWED_MODELS = {"gpt-5.6-sol", "gpt-5.6-terra"}
ALLOWED_EFFORTS = {"low", "medium", "high", "xhigh", "max", "ultra"}


def read_toml(path: pathlib.Path, errors: list[str]) -> dict:
    try:
        return tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as exc:
        errors.append(f"{path}: TOML parse/read failed: {exc}")
        return {}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".", help="repository root")
    args = parser.parse_args()
    root = pathlib.Path(args.repo).resolve()
    errors: list[str] = []

    config_path = root / ".codex" / "config.toml"
    if not config_path.is_file():
        errors.append(f"missing {config_path}")
        config: dict = {}
    else:
        config = read_toml(config_path, errors)

    if set(config) != {"agents"}:
        errors.append(
            "project config must contain only the [agents] table; "
            f"found top-level keys {sorted(config)}"
        )
    agents_config = config.get("agents")
    if not isinstance(agents_config, dict):
        errors.append("[agents] table is missing or invalid")
        agents_config = {}
    if agents_config.get("max_concurrent_threads_per_session") != 3:
        errors.append("agents.max_concurrent_threads_per_session must equal 3")
    if agents_config.get("interrupt_message") is not True:
        errors.append("agents.interrupt_message must be true")

    agents_dir = root / ".codex" / "agents"
    actual_files = {path.name for path in agents_dir.glob("*.toml")} if agents_dir.is_dir() else set()
    missing_files = sorted(set(EXPECTED) - actual_files)
    unexpected_files = sorted(actual_files - set(EXPECTED))
    if missing_files:
        errors.append(f"missing agent files: {missing_files}")
    if unexpected_files:
        errors.append(f"unexpected agent files: {unexpected_files}")

    seen_names: set[str] = set()
    for filename, expected_name in EXPECTED.items():
        path = agents_dir / filename
        if not path.is_file():
            continue
        data = read_toml(path, errors)
        extra = sorted(set(data) - ALLOWED_AGENT_FIELDS)
        missing = sorted(REQUIRED_AGENT_FIELDS - set(data))
        if extra:
            errors.append(f"{path}: unsupported keys {extra}")
        if missing:
            errors.append(f"{path}: missing required keys {missing}")
        name = data.get("name")
        if name != expected_name:
            errors.append(f"{path}: name must be {expected_name!r}, got {name!r}")
        if name in seen_names:
            errors.append(f"duplicate agent name: {name}")
        if isinstance(name, str):
            seen_names.add(name)
        model = data.get("model")
        if model not in ALLOWED_MODELS:
            errors.append(f"{path}: unsupported model {model!r}")
        effort = data.get("model_reasoning_effort")
        if effort not in ALLOWED_EFFORTS:
            errors.append(f"{path}: unsupported reasoning effort {effort!r}")
        if "sandbox_mode" in data:
            errors.append(f"{path}: sandbox_mode must be omitted; parent runtime permissions are authoritative")
        for field in ("description", "developer_instructions"):
            if not isinstance(data.get(field), str) or not data[field].strip():
                errors.append(f"{path}: {field} must be a non-empty string")

    if errors:
        print("CODEX CONFIG FAIL")
        for error in errors:
            print(f"- {error}")
        return 1

    print("CODEX CONFIG PASS")
    print(f"- repository: {root}")
    print(f"- child-agent cap: {agents_config['max_concurrent_threads_per_session']}")
    print(f"- agents: {len(EXPECTED)}")
    print("- sandbox policy: inherited from parent/session runtime")
    return 0


if __name__ == "__main__":
    sys.exit(main())
