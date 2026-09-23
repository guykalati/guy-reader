# Guy Reader (TTS) - Agents Guide

## Agent skills

### Issue tracker

Local markdown files in `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical 5 triage roles (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context repository layout (`CONTEXT.md` + `docs/adr/`). See `docs/agents/domain.md`.

---

## Engineering Workflow (mattpocock/skills)

This repository adheres to Matt Pocock's skills-driven engineering lifecycle:

1. **Specification (`to-spec` / `grill-me`)**: Convert user requirements and bug reports into formal specifications with explicit seams, user stories, and decisions.
2. **Ticket Decomposition (`to-tickets`)**: Break specifications down into ordered, atomic tickets in `.scratch/<feature>/issues/`.
3. **Test-Driven Development (`tdd` / `implement`)**: Write automated unit/integration tests before writing implementation code; verify red -> green -> refactor.
4. **Code Review & Auditing (`code-review` / `diagnosing-bugs`)**: Review against specification constraints and verify quality and reliability.
