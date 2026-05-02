#!/usr/bin/env python3
"""Assert cross-repo facts that the four-repo MCP security ecosystem depends on.

This script is the drift catcher. It reads authoritative sources from each
repo (`camazotz_modules/*/scenario.yaml`, `nullfield/integrations/camazotz/
tools.yaml`, `mcpnuke/checks/__init__.py`, ADR 0001) and asserts that every
downstream doc and number agrees. When it fails, the failure message names
the exact file and the exact stale assertion.

Designed to be run from CI on a workspace that has all four repos checked
out side-by-side as siblings:

    workspace/
      agentic-sec/   (this script lives here)
      camazotz/
      mcpnuke/
      nullfield/

Override the workspace root with the env var ECOSYSTEM_ROOT, or pass
--root <path>. Default is the parent of this script's repo.

Exit codes:
    0   all assertions pass
    1   one or more drift assertions failed (details printed)
    2   layout error — could not find one of the sibling repos
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path


# --------------------------------------------------------------------------
# Truth sources — read live, never hard-coded
# --------------------------------------------------------------------------


@dataclass
class Truth:
    lab_modules: int           # camazotz_modules/*/scenario.yaml count
    transport_codes: list[str] # ADR 0001 transport letters in declared order
    lane_slugs: list[str]      # camazotz frontend/lane_taxonomy.py canonical slugs
    nullfield_registered_tools: int  # entries in nullfield's integrations/camazotz/tools.yaml
    mcpnuke_registered_checks: int   # registered in mcpnuke/checks/__init__.py


def _count_scenario_yamls(camazotz_root: Path) -> int:
    return sum(1 for _ in camazotz_root.glob("camazotz_modules/*/scenario.yaml"))


def _read_adr_transports(camazotz_root: Path) -> list[str]:
    adr = camazotz_root / "docs/adr/0001-five-transport-taxonomy.md"
    if not adr.exists():
        raise SystemExit(f"coherence: ADR not found: {adr}")
    text = adr.read_text()
    codes = sorted(set(re.findall(r"^\s*\|\s*\*?\*?([A-E])\*?\*?\s*\|", text, re.M)))
    if len(codes) < 5:
        codes = sorted(set(re.findall(r"\b([A-E])\s*=", text)))
    return codes


def _read_lane_slugs(camazotz_root: Path) -> list[str]:
    src = camazotz_root / "frontend/lane_taxonomy.py"
    if not src.exists():
        raise SystemExit(f"coherence: lane taxonomy not found: {src}")
    text = src.read_text()
    return sorted(set(re.findall(r'slug=["\']([a-z][a-z0-9-]+)["\']', text)))


def _count_nullfield_tools(nullfield_root: Path) -> int:
    reg = nullfield_root / "integrations/camazotz/tools.yaml"
    if not reg.exists():
        raise SystemExit(f"coherence: tool registry not found: {reg}")
    return sum(
        1
        for line in reg.read_text().splitlines()
        if re.match(r"^\s*-\s*name:\s*[a-z_][\w.]+", line)
    )


def _count_mcpnuke_checks(mcpnuke_root: Path) -> int:
    init = mcpnuke_root / "mcpnuke/checks/__init__.py"
    if not init.exists():
        raise SystemExit(f"coherence: mcpnuke checks/__init__.py not found: {init}")
    text = init.read_text()
    m = re.search(r"total_checks\s*=\s*(\d+)", text)
    if m:
        return int(m.group(1))
    # Fall back to counting CHECK_FUNCS / register() / appended check refs
    candidates = [
        len(re.findall(r"^\s*register\s*\(", text, re.M)),
        len(re.findall(r"^\s*[A-Z_]+_CHECKS\s*=", text, re.M)),
        len(re.findall(r"\bcheck_[a-z_]+\b", text)),
    ]
    return max(candidates)


def gather_truth(root: Path) -> Truth:
    cam = root / "camazotz"
    nul = root / "nullfield"
    mcp = root / "mcpnuke"
    for repo in (cam, nul, mcp, root / "agentic-sec"):
        if not repo.exists():
            raise SystemExit(
                f"coherence: expected sibling repo not found: {repo} "
                "(set ECOSYSTEM_ROOT or pass --root)"
            )
    return Truth(
        lab_modules=_count_scenario_yamls(cam),
        transport_codes=_read_adr_transports(cam),
        lane_slugs=_read_lane_slugs(cam),
        nullfield_registered_tools=_count_nullfield_tools(nul),
        mcpnuke_registered_checks=_count_mcpnuke_checks(mcp),
    )


# --------------------------------------------------------------------------
# Drift assertions
# --------------------------------------------------------------------------


@dataclass
class Failure:
    file: Path
    message: str

    def __str__(self) -> str:
        return f"  {self.file}: {self.message}"


@dataclass
class Report:
    checks_run: int = 0
    failures: list[Failure] = field(default_factory=list)

    def fail(self, file: Path, message: str) -> None:
        self.failures.append(Failure(file, message))

    def ok(self) -> bool:
        return not self.failures


# Patterns that look like a stale lab count anywhere in prose.
# Examples this catches: "32 labs", "28 vulnerability patterns", "31 modules".
# The leading whitespace requirement avoids matching URL-encoded "%20labs"
# inside shields.io badge URLs (those use the URL-escaped space, not a
# literal space).
_STALE_LAB_COUNT_RE = re.compile(
    r"(?:^|[\s(])(2[0-9]|3[0-46-9])\s+"
    r"(?:intentionally\s+)?(?:vulnerable\s+|distinct\s+vulnerability\s+)?"
    r"(?:lab(?:s|\s*modules)?|vulnerability\s+patterns|modules)\b",
    re.IGNORECASE,
)


# Files / directory fragments to skip when scanning prose. Vendored content,
# gitignored work-in-progress (docs/superpowers/), CHANGELOG history, and the
# ADR itself (which legitimately describes the 3 -> 5 transport transition).
_DOC_SCAN_SKIP_FRAGMENTS = (
    ".venv",
    "node_modules",
    "site-packages",
    "/1/lib/",
    "/docs/superpowers/",
    "CHANGELOG.md",
    "/docs/adr/",
)


def _should_skip_doc(path: Path) -> bool:
    s = str(path)
    return any(frag in s for frag in _DOC_SCAN_SKIP_FRAGMENTS)


def _check_doc_lab_counts(repo_root: Path, truth: Truth, report: Report,
                          *, label: str) -> None:
    """Walk repo_root for stale lab-count claims in shipped prose docs."""
    target = str(truth.lab_modules)
    for doc in repo_root.rglob("*.md"):
        if _should_skip_doc(doc):
            continue
        text = doc.read_text(errors="replace")
        for m in _STALE_LAB_COUNT_RE.finditer(text):
            number = m.group(1)
            if number == target:
                continue
            # Allow historical references that explicitly mark the old number
            # as historical (e.g. "(was 32)", "from 28 to 35", "previously 31").
            ctx_start = max(0, m.start() - 25)
            ctx = text[ctx_start : m.end() + 25].lower()
            if any(
                w in ctx
                for w in (
                    "was ",
                    "previously",
                    "earlier",
                    "from ",
                    "original",
                    "initial",
                    "→",
                    "->",
                )
            ):
                continue
            report.fail(
                doc,
                f"asserts '{m.group(0).strip()}' but truth source has {target} labs "
                f"(camazotz_modules/*/scenario.yaml count) [{label}]",
            )
        report.checks_run += 1


def _check_three_transport_drift(repo_root: Path, report: Report,
                                 *, label: str) -> None:
    """ADR 0001 says A-E. Catch any 'three transports' phrasing in shipped docs."""
    bad_phrases = [
        re.compile(r"\bthree\s+transports?\b", re.IGNORECASE),
        # Only flag "3 transports" when it is NOT preceded by the lane
        # vocabulary (e.g. "Lane 3 Transport C", "lane-3 Transport B").
        # Both spaces and hyphens between "lane" and the digit are valid
        # in the canonical vocabulary.
        re.compile(r"(?<![Ll]ane[\s-])\b3\s+transports?\b", re.IGNORECASE),
        re.compile(r"\btransports?\s*\(?[Aa]\s*[-–]\s*[Cc]\)?", re.IGNORECASE),
        re.compile(r"5\s*[x×]\s*3\b"),
    ]
    for doc in repo_root.rglob("*.md"):
        if _should_skip_doc(doc):
            continue
        text = doc.read_text(errors="replace")
        for pat in bad_phrases:
            for m in pat.finditer(text):
                ctx_start = max(0, m.start() - 35)
                ctx = text[ctx_start : m.end() + 35].lower()
                if any(w in ctx for w in ("was ", "previously", "from ", "→", "->", "expanded")):
                    continue
                report.fail(
                    doc,
                    f"references {m.group(0)!r} — ADR 0001 has 5 transports A-E "
                    f"[{label}]",
                )
        report.checks_run += 1


def _check_nullfield_tool_count_consistency(nullfield_root: Path, truth: Truth,
                                            report: Report) -> None:
    """The nullfield camazotz README must agree with its own tools.yaml count."""
    readme = nullfield_root / "integrations/camazotz/README.md"
    if not readme.exists():
        report.fail(readme, "missing")
        return
    text = readme.read_text()
    target = str(truth.nullfield_registered_tools)
    m = re.search(r"\ball\s+\*?\*?(\d+)\*?\*?\s+tools\b", text, re.I)
    if not m:
        report.fail(
            readme,
            f"could not find an 'all N tools' assertion to verify against "
            f"tools.yaml count of {target}",
        )
    elif m.group(1) != target:
        report.fail(
            readme,
            f"asserts 'all {m.group(1)} tools' but tools.yaml registers {target}",
        )
    report.checks_run += 1


def _check_lane_slugs(camazotz_root: Path, truth: Truth, report: Report) -> None:
    """Lane taxonomy must define exactly the canonical 5 slugs."""
    expected = {"human-direct", "delegated", "machine", "chain", "anonymous"}
    actual = set(truth.lane_slugs)
    missing = expected - actual
    extra = actual - expected
    src = camazotz_root / "frontend/lane_taxonomy.py"
    if missing:
        report.fail(src, f"missing canonical lane slugs: {sorted(missing)}")
    if extra:
        report.fail(src, f"extra lane slugs not in canonical set: {sorted(extra)}")
    report.checks_run += 1


def _check_adr_transports(camazotz_root: Path, truth: Truth, report: Report) -> None:
    expected = ["A", "B", "C", "D", "E"]
    if truth.transport_codes != expected:
        report.fail(
            camazotz_root / "docs/adr/0001-five-transport-taxonomy.md",
            f"declares transports {truth.transport_codes}, expected {expected}",
        )
    report.checks_run += 1


# --------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    default_root = Path(os.environ.get("ECOSYSTEM_ROOT", Path(__file__).resolve().parents[2]))
    p.add_argument("--root", type=Path, default=default_root,
                   help=f"Workspace root containing the 4 sibling repos "
                        f"(default: {default_root})")
    args = p.parse_args()

    print(f"check_coherence: ECOSYSTEM_ROOT = {args.root}")
    truth = gather_truth(args.root)
    print(f"  truth: {truth.lab_modules} labs, transports={truth.transport_codes}, "
          f"lanes={len(truth.lane_slugs)}, nullfield_tools={truth.nullfield_registered_tools}, "
          f"mcpnuke_checks={truth.mcpnuke_registered_checks}")
    print()

    report = Report()
    _check_adr_transports(args.root / "camazotz", truth, report)
    _check_lane_slugs(args.root / "camazotz", truth, report)
    _check_nullfield_tool_count_consistency(args.root / "nullfield", truth, report)
    for repo, label in [
        (args.root / "camazotz", "camazotz"),
        (args.root / "agentic-sec", "agentic-sec"),
        (args.root / "mcpnuke", "mcpnuke"),
        (args.root / "nullfield", "nullfield"),
    ]:
        _check_doc_lab_counts(repo, truth, report, label=label)
        _check_three_transport_drift(repo, report, label=label)

    print(f"checks executed: {report.checks_run}")
    if report.ok():
        print("OK — no cross-repo drift detected")
        return 0

    print(f"FAIL — {len(report.failures)} drift finding(s):\n")
    for f in report.failures:
        print(f)
    return 1


if __name__ == "__main__":
    sys.exit(main())
