# Taxonomy

Machine-readable and human-readable taxonomies for the agentic-sec ecosystem.
This directory is the shared vocabulary every tool and doc maps back to.

## The four lenses

The ecosystem is described through four complementary lenses. Each answers a
different question; none replaces the others.

| Lens | Question it answers | Home |
|------|---------------------|------|
| **Identity** | Who is calling, and over what transport? | [`lanes.yaml`](lanes.yaml) — 5 lanes × 5 transports (A–E) × MCP-T threat IDs |
| **Attack** | What can go wrong? | [`../attack-path-atlas.md`](../attack-path-atlas.md) — attack paths across domains A–K |
| **Surface** | What artifacts exist in an agentic workspace, and how do I vet each? | [`surfaces.md`](surfaces.md) + [`surfaces.yaml`](surfaces.yaml) |
| **Tool** | What finds / enforces / measures each? | [`../ecosystem.md`](../ecosystem.md) + [`../reference/`](../reference/) |

## When to use each

- Onboarding a new engineer to the agentic threat model → start with the
  **surface** lens (`surfaces.md`): it names the things they can actually see in
  a repo or cluster and tells them what each is for.
- Deciding which control blocks a specific attack → **attack** lens (atlas).
- Writing policy or reasoning about credential flow → **identity** lens
  (`lanes.yaml`).
- Choosing which tool to run and when → **tool** lens (`reference/`).

## Cross-referencing contract

`surfaces.yaml` reuses IDs defined elsewhere rather than minting new ones:

- `atlas_domains` reference domains in [`../attack-path-atlas.md`](../attack-path-atlas.md).
- `threats` reference `threat_id`s in [`lanes.yaml`](lanes.yaml).
- `vetted_by` names a tool documented in [`../reference/`](../reference/).

Keeping these as references (not restatements) is deliberate: it prevents the
taxonomy from drifting out of sync with the truth sources that
[`../../scripts/check_coherence.py`](../../scripts/check_coherence.py) gates.
