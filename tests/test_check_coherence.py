"""Tests for the cross-repo drift catcher (`scripts/check_coherence.py`).

The script is loaded by path (it is a standalone CLI, not an installed
package). Tests build minimal temp fixtures rather than depending on real
sibling repos, so they are fast and hermetic.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[1]
_SCRIPT = _REPO_ROOT / "scripts" / "check_coherence.py"


def _load_checker() -> ModuleType:
    spec = importlib.util.spec_from_file_location("check_coherence", _SCRIPT)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    # Register before exec: @dataclass resolves cls.__module__ via sys.modules.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


checker = _load_checker()


def _make_truth(**overrides: object):
    """A fully-populated Truth with sensible defaults; override per test."""
    defaults: dict[str, object] = dict(
        lab_modules=52,
        transport_codes=list("ABCDE"),
        lane_slugs=["anonymous", "chain", "delegated", "human-direct", "machine"],
        nullfield_registered_tools=139,
        mcpnuke_registered_checks=10,
        stoneburner_version="0.6.0",
        stoneburner_schema=14,
        mcpnuke_version="6.13.0",
        skillseraph_version="0.2.0",
    )
    defaults.update(overrides)
    return checker.Truth(**defaults)


def _write_stoneburner_ref(root: Path, *, version: str, schema: int,
                           inline_noise: bool = True) -> Path:
    ref = root / "agentic-sec" / "docs" / "reference" / "stoneburner.md"
    ref.parent.mkdir(parents=True, exist_ok=True)
    body = (
        f"# stoneburner Reference\n\n"
        f"[GitHub](https://github.com/babywyrm/stoneburner) · v{version} · "
        f"911 tests · schema v{schema}\n\n"
        f"## Storage\n\nSQLite database (schema v{schema}) with tables:\n"
    )
    if inline_noise:
        # Inline references to *historical* schema versions must NOT trip the
        # header/storage assertions.
        body += (
            "\n`task_results` gained `criteria_coverage` (schema v13) and "
            "`judge_score_stdev` (schema v14); fidelity columns span schema "
            "v12-v14.\n"
        )
    ref.write_text(body)
    return ref


def _write_mcpnuke_ref(root: Path, *, version: str) -> Path:
    ref = root / "agentic-sec" / "docs" / "reference" / "mcpnuke.md"
    ref.parent.mkdir(parents=True, exist_ok=True)
    ref.write_text(
        f"# mcpnuke Reference\n\n"
        f"**Repo:** [github.com/babywyrm/mcpnuke](https://github.com/babywyrm/mcpnuke)"
        f" · v{version} · 671 tests · MIT\n"
    )
    return ref


def _write_skillseraph_ref(root: Path, *, version: str) -> Path:
    ref = root / "agentic-sec" / "docs" / "reference" / "skillseraph.md"
    ref.parent.mkdir(parents=True, exist_ok=True)
    ref.write_text(
        f"# skillseraph Reference\n\n"
        f"[GitHub](https://github.com/babywyrm/skillseraph) · v{version} · "
        f"110 tests · 11 platforms\n"
    )
    return ref


# --------------------------------------------------------------------------
# parsers
# --------------------------------------------------------------------------


def test_read_pyproject_version(tmp_path: Path) -> None:
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "x"\nversion = "1.2.3"\n'
    )
    assert checker._read_pyproject_version(tmp_path, label="x") == "1.2.3"


def test_read_pyproject_version_missing_file(tmp_path: Path) -> None:
    with pytest.raises(SystemExit):
        checker._read_pyproject_version(tmp_path, label="x")


def test_read_stoneburner_schema(tmp_path: Path) -> None:
    schema = tmp_path / "atomics" / "storage" / "schema.py"
    schema.parent.mkdir(parents=True)
    schema.write_text('"""schema."""\nSCHEMA_VERSION = 14\nSCHEMA_SQL = ""\n')
    assert checker._read_stoneburner_schema(tmp_path) == 14


def test_read_stoneburner_schema_missing(tmp_path: Path) -> None:
    with pytest.raises(SystemExit):
        checker._read_stoneburner_schema(tmp_path)


# --------------------------------------------------------------------------
# stoneburner reference assertion
# --------------------------------------------------------------------------


def test_stoneburner_reference_ok(tmp_path: Path) -> None:
    _write_stoneburner_ref(tmp_path, version="0.6.0", schema=14)
    report = checker.Report()
    checker._check_stoneburner_reference(tmp_path / "agentic-sec", _make_truth(), report)
    assert report.ok(), [str(f) for f in report.failures]


def test_stoneburner_reference_stale_schema(tmp_path: Path) -> None:
    _write_stoneburner_ref(tmp_path, version="0.6.0", schema=11)
    report = checker.Report()
    checker._check_stoneburner_reference(tmp_path / "agentic-sec", _make_truth(), report)
    assert not report.ok()
    msg = "\n".join(str(f) for f in report.failures)
    assert "schema v11" in msg and "v14" in msg


def test_stoneburner_reference_stale_version(tmp_path: Path) -> None:
    _write_stoneburner_ref(tmp_path, version="0.5.0", schema=14)
    report = checker.Report()
    checker._check_stoneburner_reference(tmp_path / "agentic-sec", _make_truth(), report)
    assert not report.ok()
    assert "v0.5.0" in "\n".join(str(f) for f in report.failures)


def test_stoneburner_reference_ignores_inline_schema_refs(tmp_path: Path) -> None:
    # Header/storage are v14; inline mentions v12/v13/v14 must not false-trip.
    _write_stoneburner_ref(tmp_path, version="0.6.0", schema=14, inline_noise=True)
    report = checker.Report()
    checker._check_stoneburner_reference(tmp_path / "agentic-sec", _make_truth(), report)
    assert report.ok(), [str(f) for f in report.failures]


def test_stoneburner_reference_missing_file(tmp_path: Path) -> None:
    (tmp_path / "agentic-sec").mkdir()
    report = checker.Report()
    checker._check_stoneburner_reference(tmp_path / "agentic-sec", _make_truth(), report)
    assert not report.ok()


# --------------------------------------------------------------------------
# mcpnuke reference assertion
# --------------------------------------------------------------------------


def test_mcpnuke_reference_ok(tmp_path: Path) -> None:
    _write_mcpnuke_ref(tmp_path, version="6.13.0")
    report = checker.Report()
    checker._check_mcpnuke_reference(tmp_path / "agentic-sec", _make_truth(), report)
    assert report.ok(), [str(f) for f in report.failures]


def test_mcpnuke_reference_stale_version(tmp_path: Path) -> None:
    _write_mcpnuke_ref(tmp_path, version="6.10.0")
    report = checker.Report()
    checker._check_mcpnuke_reference(tmp_path / "agentic-sec", _make_truth(), report)
    assert not report.ok()
    assert "v6.10.0" in "\n".join(str(f) for f in report.failures)


# --------------------------------------------------------------------------
# skillseraph reference assertion
# --------------------------------------------------------------------------


def test_skillseraph_reference_ok(tmp_path: Path) -> None:
    _write_skillseraph_ref(tmp_path, version="0.2.0")
    report = checker.Report()
    checker._check_skillseraph_reference(tmp_path / "agentic-sec", _make_truth(), report)
    assert report.ok(), [str(f) for f in report.failures]


def test_skillseraph_reference_stale_version(tmp_path: Path) -> None:
    _write_skillseraph_ref(tmp_path, version="0.1.0")
    report = checker.Report()
    checker._check_skillseraph_reference(tmp_path / "agentic-sec", _make_truth(), report)
    assert not report.ok()
    assert "v0.1.0" in "\n".join(str(f) for f in report.failures)


def test_skillseraph_reference_missing_file(tmp_path: Path) -> None:
    (tmp_path / "agentic-sec").mkdir()
    report = checker.Report()
    checker._check_skillseraph_reference(tmp_path / "agentic-sec", _make_truth(), report)
    assert not report.ok()


# --------------------------------------------------------------------------
# surface taxonomy assertion
# --------------------------------------------------------------------------


def _write_surface_fixture(root: Path, *, lane_threats: list[str],
                           surface_threats: list[str], vetted_by: str,
                           ref_tools: list[str]) -> None:
    base = root / "agentic-sec" / "docs"
    (base / "taxonomy").mkdir(parents=True, exist_ok=True)
    (base / "reference").mkdir(parents=True, exist_ok=True)
    lanes = "\n".join(f'  - threat_id: "{t}"' for t in lane_threats)
    (base / "taxonomy" / "lanes.yaml").write_text(f"threats:\n{lanes}\n")
    (base / "taxonomy" / "surfaces.yaml").write_text(
        "surfaces:\n"
        "  - id: s1\n"
        f"    threats: [{', '.join(surface_threats)}]\n"
        f"    vetted_by: {vetted_by}\n"
    )
    for tool in ref_tools:
        (base / "reference" / f"{tool}.md").write_text(f"# {tool}\n")


def test_surface_taxonomy_ok(tmp_path: Path) -> None:
    _write_surface_fixture(
        tmp_path, lane_threats=["MCP-T01", "MCP-T02"],
        surface_threats=["MCP-T01"], vetted_by="nullfield + mcpnuke",
        ref_tools=["nullfield", "mcpnuke"],
    )
    report = checker.Report()
    checker._check_surface_taxonomy(tmp_path / "agentic-sec", report)
    assert report.ok(), [str(f) for f in report.failures]


def test_surface_taxonomy_unknown_threat_id(tmp_path: Path) -> None:
    _write_surface_fixture(
        tmp_path, lane_threats=["MCP-T01"],
        surface_threats=["MCP-T01", "MCP-T99"], vetted_by="nullfield",
        ref_tools=["nullfield"],
    )
    report = checker.Report()
    checker._check_surface_taxonomy(tmp_path / "agentic-sec", report)
    assert not report.ok()
    assert "MCP-T99" in "\n".join(str(f) for f in report.failures)


def test_surface_taxonomy_missing_tool_reference(tmp_path: Path) -> None:
    _write_surface_fixture(
        tmp_path, lane_threats=["MCP-T01"],
        surface_threats=["MCP-T01"], vetted_by="nullfield + mcpnuke",
        ref_tools=["nullfield"],  # mcpnuke reference deliberately absent
    )
    report = checker.Report()
    checker._check_surface_taxonomy(tmp_path / "agentic-sec", report)
    assert not report.ok()
    assert "mcpnuke" in "\n".join(str(f) for f in report.failures)


def test_surface_taxonomy_absent_is_noop(tmp_path: Path) -> None:
    (tmp_path / "agentic-sec").mkdir()
    report = checker.Report()
    checker._check_surface_taxonomy(tmp_path / "agentic-sec", report)
    assert report.ok()


# --------------------------------------------------------------------------
# gather_truth layout contract
# --------------------------------------------------------------------------


def test_gather_truth_missing_sibling_exits(tmp_path: Path) -> None:
    # Empty workspace -> the first missing sibling triggers a layout SystemExit.
    with pytest.raises(SystemExit):
        checker.gather_truth(tmp_path)
