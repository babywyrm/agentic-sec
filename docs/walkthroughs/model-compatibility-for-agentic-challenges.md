# Model Compatibility for Agentic CTF Challenges

AI-backed CTF challenges need model validation that goes beyond "the model
responded." A model can be healthy, fast, and even safer in production terms
while still breaking the intended player experience.

This note defines a general validation pattern for challenges where an LLM
participates in approval, redaction, summarization, escalation, or any other
player-visible behavior.

---

## The Problem

Agentic challenge behavior often depends on a narrow model profile:

- competent enough to follow tool contracts
- consistent enough to approve and deny expected gate cases
- weak, permissive, or literal enough to expose an intentionally vulnerable path
- stable enough to repeat the same outcome across spawned instances

Those requirements can conflict. A model that is "better" at safety may refuse a
leak that the challenge intentionally requires. A model that is "better" at
reasoning may emit extra prose that breaks a strict parser. A smaller model may
be the best challenge model because it preserves the designed vulnerability
while still satisfying the infrastructure gates.

---

## Two-Layer Validation

Use two distinct validation layers.

### Function Compatibility

Function compatibility proves the AI-backed application is wired correctly:

- inference backend is reachable
- model tag and runtime config match expectation
- tool calls return parseable outputs
- security gates approve the intended safe case
- security gates deny obvious malicious cases
- summaries, redactions, or analyses are non-empty and structurally valid

This layer catches runtime and orchestration failures.

### Walkthrough Compatibility

Walkthrough compatibility proves the player-facing chain still works:

- the real HTTP, OAuth, MCP, or tool surfaces are exercised
- the same privilege boundaries a player crosses are validated
- the intended vulnerable AI behavior occurs
- negative controls still hold
- side effects are cleaned up
- the full chain passes repeated rounds

This layer catches solvability failures that function checks cannot see.

---

## Compatibility Labels

Use explicit result labels when evaluating a model/backend/challenge
combination:

| Label | Meaning |
|---|---|
| `UNTESTED` | No evidence for this exact combination. |
| `FUNCTION_COMPATIBLE` | Individual AI-mediated functions and gates pass. |
| `WALKTHROUGH_COMPATIBLE` | The full player-facing chain passes repeated rounds. |
| `TOO_SAFE_FOR_CHAIN` | The model refuses or redacts behavior the challenge intentionally requires. |
| `UNSAFE_GATE_BEHAVIOR` | The model allows malicious actions or blocks the intended safe path. |
| `BROKEN_RUNTIME` | The model times out, emits unparsable output, or breaks orchestration. |

The important distinction is that `FUNCTION_COMPATIBLE` is not enough for
challenge promotion. It means the application can run. It does not prove the
challenge can be solved.

---

## Promotion Rule

Do not promote a model to challenge-compatible until:

1. Function-level checks pass.
2. The full player-facing walkthrough chain passes.
3. The verifier runs repeated rounds, with three as a practical default.
4. Cleanup and post-run stabilization succeed.
5. The evidence packet is sanitized and recorded.

Use five or more rounds when investigating nondeterministic behavior or when
promoting a model as a long-lived default.

---

## Evidence Hygiene

Model-compatibility records should be useful without disclosing challenge
internals.

Record:

- model tag and backend class
- challenge family or generic scenario name
- compatibility labels
- stage names in sanitized form
- pass/fail/skip counts
- redacted snippets when needed
- cleanup and stabilization result

Do not record:

- secrets, tokens, flags, or raw credential values
- private IPs or hostnames
- exact exploit payloads for unreleased boxes
- full raw verifier logs if they expose challenge internals
- machine-specific file paths unless they are already public documentation

---

## Design Implication

AI-backed CTFs should treat model selection as part of challenge design. A
model is not merely a dependency; it is part of the puzzle mechanics. Swapping
the model can change the difficulty, remove the intended vulnerability, or make
the gate unsafe.

The safest operating model is:

```text
model switch -> function verification -> walkthrough verification -> evidence review -> promotion
```

If function verification passes but walkthrough verification fails, preserve the
result. That is useful research data: it tells future operators whether the
model failed because it was unsafe, broken, or simply too safe for the intended
chain.
