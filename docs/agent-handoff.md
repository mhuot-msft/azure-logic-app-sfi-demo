# Agent Handoff

Use this file as the single coordination point for multi-agent work.

## Coordination Rules

- One owner agent at a time controls integration decisions.
- Each agent works in its own branch: `agent/<name>/<task>`.
- Before editing files, claim them in **Active File Locks**.
- Keep commits atomic and scoped to one logical change.
- Update this file at the start and end of each work burst.

## Current Owner

- Owner agent: GitHub Copilot
- Owner branch: main
- Since (UTC): 2026-02-27
- Ownership reason: Primary integration and merge coordination

## Active Work Queue

| Item | Priority | Owner | Branch | Status | Notes |
|---|---|---|---|---|---|
| Dashboard reliability and demo flow | High | GitHub Copilot | main | In progress | Stabilize Grafana panel behavior |

## Active File Locks

| File | Locked By | Started (UTC) | Purpose |
|---|---|---|---|
| docs/grafana-dashboard.json | GitHub Copilot | 2026-02-27 | Panel query/reducer stability |

## Last Completed Changes

| UTC | Agent | Branch | Commit | Summary |
|---|---|---|---|---|
| 2026-02-27 | GitHub Copilot | main | c6cd68a | Enforced Grafana time window in Log Analytics panels |
| 2026-02-27 | GitHub Copilot | main | c2ace04 | Added referral load test helper script |

## Validation Log

| UTC | Agent | What Ran | Result |
|---|---|---|---|
| 2026-02-27 | GitHub Copilot | deploy.ps1 full run | Passed |
| 2026-02-27 | GitHub Copilot | test-referral.ps1 | Passed (202,202,400 expected) |
| 2026-02-27 | GitHub Copilot | Service Bus queue sampling | urgent=8, standard=8, incoming=0 stable |

## Next Intended Commit

- Scope: Grafana panel smoothing for Active Messages
- Planned message: `dashboard: stabilize active queue gauge against delayed metric buckets`

## Handoff Checklist

- [ ] Claimed files in Active File Locks
- [ ] Added/updated validation evidence
- [ ] Updated Next Intended Commit
- [ ] Released locks for completed work
