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
# mcpnuke check registry
# --------------------------------------------------------------------------


def _write_mcpnuke_checks_init(mcpnuke_root: Path, body: str) -> Path:
    """Write a checks/__init__.py; `mcpnuke_root` is the mcpnuke repo root."""
    init = mcpnuke_root / "mcpnuke" / "checks" / "__init__.py"
    init.parent.mkdir(parents=True, exist_ok=True)
    init.write_text(body)
    return init


# Mirrors the real module: typed module-level tuples, plus a run_all_checks
# body that accumulates `total_checks` from their lengths.
_REAL_SHAPE = '''"""Check orchestrator."""

_STATIC_CHECK_NAMES: tuple[str, ...] = (
    "prompt_injection_t01",
    "tool_poisoning",
    "credential_in_schema",
)
_JWT_CHECK_NAMES: tuple[str, ...] = ("jwt_audience", "jwt_replay")
_DPOP_CHECK_NAMES: tuple[str, ...] = ("dpop_not_enforced",)
_AGGREGATE_CHECK_NAMES: tuple[str, ...] = ("multi_vector", "attack_chains")


def run_all_checks(result, session=None):
    total_checks = 0
    if session:
        total_checks = len(_STATIC_CHECK_NAMES)
        total_checks += len(_JWT_CHECK_NAMES)
        total_checks += len(_DPOP_CHECK_NAMES)
    return total_checks
'''


def test_count_mcpnuke_checks_unions_the_registry_tables(tmp_path: Path) -> None:
    _write_mcpnuke_checks_init(tmp_path, _REAL_SHAPE)
    assert checker._count_mcpnuke_checks(tmp_path) == 8


def test_count_mcpnuke_checks_ignores_the_total_checks_accumulator(tmp_path: Path) -> None:
    """Regression: `total_checks = 0` must not be mistaken for the registry size.

    The original regex matched the accumulator's initialiser and reported 0
    registered checks while the suite still passed green.
    """
    _write_mcpnuke_checks_init(tmp_path, _REAL_SHAPE)
    assert "total_checks = 0" in _REAL_SHAPE
    assert checker._count_mcpnuke_checks(tmp_path) != 0


def test_count_mcpnuke_checks_reads_unannotated_tables(tmp_path: Path) -> None:
    _write_mcpnuke_checks_init(
        tmp_path, '_STATIC_CHECK_NAMES = ("a", "b")\n_JWT_CHECK_NAMES = ("c",)\n'
    )
    assert checker._count_mcpnuke_checks(tmp_path) == 3


def test_count_mcpnuke_checks_counts_each_name_once(tmp_path: Path) -> None:
    _write_mcpnuke_checks_init(
        tmp_path,
        '_STATIC_CHECK_NAMES: tuple[str, ...] = ("a", "b")\n'
        '_TELEPORT_ALWAYS_CHECK_NAMES: tuple[str, ...] = ("b", "c")\n',
    )
    assert checker._count_mcpnuke_checks(tmp_path) == 3


def test_count_mcpnuke_checks_missing_file_exits(tmp_path: Path) -> None:
    with pytest.raises(SystemExit):
        checker._count_mcpnuke_checks(tmp_path)


def test_count_mcpnuke_checks_empty_registry_exits_loudly(tmp_path: Path) -> None:
    """No recognisable table is a parser failure, not a zero-check scanner."""
    _write_mcpnuke_checks_init(tmp_path, "def run_all_checks(result):\n    return 0\n")
    with pytest.raises(SystemExit):
        checker._count_mcpnuke_checks(tmp_path)


def test_count_mcpnuke_checks_survives_a_syntax_error(tmp_path: Path) -> None:
    _write_mcpnuke_checks_init(tmp_path, "def broken(:\n")
    with pytest.raises(SystemExit):
        checker._count_mcpnuke_checks(tmp_path)


def test_mcpnuke_check_registry_ok(tmp_path: Path) -> None:
    _write_mcpnuke_checks_init(tmp_path, _REAL_SHAPE)
    report = checker.Report()
    checker._check_mcpnuke_check_registry(tmp_path, _make_truth(), report)
    assert report.ok(), [str(f) for f in report.failures]
    assert report.checks_run == 1


def test_mcpnuke_check_registry_rejects_a_degenerate_count(tmp_path: Path) -> None:
    _write_mcpnuke_checks_init(tmp_path, _REAL_SHAPE)
    report = checker.Report()
    checker._check_mcpnuke_check_registry(
        tmp_path, _make_truth(mcpnuke_registered_checks=0), report
    )
    assert not report.ok()


def test_mcpnuke_check_registry_flags_a_name_in_two_tables(tmp_path: Path) -> None:
    _write_mcpnuke_checks_init(
        tmp_path,
        '_STATIC_CHECK_NAMES: tuple[str, ...] = ("a", "b")\n'
        '_JWT_CHECK_NAMES: tuple[str, ...] = ("b",)\n',
    )
    report = checker.Report()
    checker._check_mcpnuke_check_registry(
        tmp_path, _make_truth(mcpnuke_registered_checks=2), report
    )
    assert not report.ok()
    assert "b" in str(report.failures[0])


@pytest.mark.skipif(
    not (_REPO_ROOT.parent / "mcpnuke" / "mcpnuke" / "checks" / "__init__.py").exists(),
    reason="mcpnuke sibling checkout not present",
)
def test_count_mcpnuke_checks_against_the_live_sibling() -> None:
    """The live repo must yield a plausible count, not a silent zero."""
    assert checker._count_mcpnuke_checks(_REPO_ROOT.parent / "mcpnuke") > 20


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
# OWASP MCP Top 10 bridge assertion
# --------------------------------------------------------------------------


def _write_owasp_bridge_fixture(root: Path, *, lanes: dict[str, str],
                                bridge_top10: dict[str, list[str]],
                                bridge_beyond: list[str]) -> None:
    base = root / "agentic-sec" / "docs" / "taxonomy"
    base.mkdir(parents=True, exist_ok=True)
    lane_blocks = "".join(
        f'  - threat_id: "{tid}"\n    owasp_mcp: "{ow}"\n'
        for tid, ow in lanes.items()
    )
    (base / "lanes.yaml").write_text(f"threats:\n{lane_blocks}")
    cats = "".join(
        f"  - id: {cid}\n    title: \"{cid} category\"\n"
        f"    threats: [{', '.join(bridge_top10.get(cid, []))}]\n"
        for cid in [f"MCP{i:02d}" for i in range(1, 11)]
    )
    beyond = "".join(f"  - threat: {t}\n" for t in bridge_beyond)
    (base / "owasp-bridge.yaml").write_text(
        f"owasp_mcp_top10:\n{cats}beyond_top10:\n{beyond}"
    )


def test_owasp_bridge_ok(tmp_path: Path) -> None:
    lanes = {"MCP-T01": "MCP01", "MCP-T06": "MCP06", "MCP-T21": "MCP21"}
    top10 = {"MCP01": ["MCP-T01"], "MCP06": ["MCP-T06"]}
    _write_owasp_bridge_fixture(
        tmp_path, lanes=lanes, bridge_top10=top10, bridge_beyond=["MCP-T21"],
    )
    report = checker.Report()
    checker._check_owasp_bridge(tmp_path / "agentic-sec", report)
    assert report.ok(), [str(f) for f in report.failures]


def test_owasp_bridge_category_drift(tmp_path: Path) -> None:
    lanes = {"MCP-T01": "MCP01", "MCP-T02": "MCP01"}
    # bridge omits MCP-T02 from MCP01 -> drift
    top10 = {"MCP01": ["MCP-T01"]}
    _write_owasp_bridge_fixture(
        tmp_path, lanes=lanes, bridge_top10=top10, bridge_beyond=[],
    )
    report = checker.Report()
    checker._check_owasp_bridge(tmp_path / "agentic-sec", report)
    assert not report.ok()
    assert "MCP01" in "\n".join(str(f) for f in report.failures)


def test_owasp_bridge_beyond_drift(tmp_path: Path) -> None:
    lanes = {"MCP-T01": "MCP01", "MCP-T21": "MCP21"}
    # lanes says MCP-T21 is beyond, but bridge forgets it
    _write_owasp_bridge_fixture(
        tmp_path, lanes=lanes, bridge_top10={"MCP01": ["MCP-T01"]},
        bridge_beyond=[],
    )
    report = checker.Report()
    checker._check_owasp_bridge(tmp_path / "agentic-sec", report)
    assert not report.ok()
    assert "MCP-T21" in "\n".join(str(f) for f in report.failures)


def test_owasp_bridge_absent_is_noop(tmp_path: Path) -> None:
    (tmp_path / "agentic-sec").mkdir()
    report = checker.Report()
    checker._check_owasp_bridge(tmp_path / "agentic-sec", report)
    assert report.ok()


# --------------------------------------------------------------------------
# gather_truth layout contract
# --------------------------------------------------------------------------


def test_gather_truth_missing_sibling_exits(tmp_path: Path) -> None:
    # Empty workspace -> the first missing sibling triggers a layout SystemExit.
    with pytest.raises(SystemExit):
        checker.gather_truth(tmp_path)
