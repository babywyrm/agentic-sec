# Contributing to agentic-security

Thanks for your interest. This repo is a documentation and architecture hub — contributions are primarily walkthroughs, campaign scenarios, reference improvements, and cross-project vocabulary alignment.

---

## What Lives Here

`agentic-sec` is the connective tissue between three independent tools:

- **camazotz** — the vulnerable target (labs, transports, API surface)
- **nullfield** — the policy arbiter (actions, CRDs, policy templates)
- **mcpnuke** — the scanner (scan modes, findings schema, policy generation)

If your contribution is a bug fix or feature in one of those tools, open a PR in that repo. If it's cross-cutting — a new walkthrough, a new campaign scenario, a vocabulary change, a new identity lane — it belongs here.

---

## Types of Contributions

### Walkthroughs

A walkthrough is a step-by-step guide that uses the real tools against a real target. Good walkthroughs:

- Use actual commands with actual output (not pseudocode)
- Cover one specific attack/defense pattern end-to-end
- State prerequisites and expected time upfront
- Connect findings to the identity lane taxonomy

Place new walkthroughs in `docs/walkthroughs/` and add a row to the table in `README.md` and `docs/learning-path.md`.

### Campaign Scenarios

A campaign is a named deployment persona (e.g. "CI/CD Pipeline Agent") that chains multiple labs into a full attack → scan → defend → validate narrative. Campaigns live in `docs/campaigns/`.

Follow the format in any existing campaign — each section (Deployment Context, Architecture, Threat Model, Attack, Scan, Defend, Validate, Takeaways) should be present.

### Reference Updates

Tool reference docs (`docs/reference/`) should stay in sync with the tool repos. If you notice drift — a flag that exists in mcpnuke but isn't in `docs/reference/mcpnuke.md`, for example — a PR fixing that is very welcome.

### Vocabulary / Taxonomy

The identity lane framework (`docs/identity-flows.md`) and the OWASP MCP Top 10 mapping in `docs/bridge.md` are living documents. If the threat landscape shifts or a new lane/transport pattern emerges, open an issue first to discuss before editing the taxonomy.

---

## Process

1. **Open an issue** for anything non-trivial — walkthroughs, new campaigns, taxonomy changes. Describe what you're adding and why.
2. **Fork and branch** off `main`.
3. **Write the doc / walkthrough** — plain Markdown, real commands, real output.
4. **Open a PR** with a clear description of what changed and why.

No CLA. No DCO. Just keep it accurate and useful.

---

## Style

- Use real commands, not pseudocode — `mcpnuke --targets http://localhost:8080/mcp --fast`, not `run scanner against target`
- Keep tables tight — if a column isn't adding information, drop it
- Link generously to sibling docs — readers should be able to navigate without knowing the repo structure
- Don't duplicate content that already exists — link to it instead
- Plain English over jargon — the audience knows security; they may not know MCP yet

---

## Questions

Open a GitHub issue. Tag it `question`.
