---
name: audit
description: Multi-round codebase audit held to one fixed bar so rounds stop flip-flopping. Every round re-reads all code from scratch with fresh subagents and runs find, verify, fix and check as separate agents, backed by the stack's linters, type checkers, dead-code and vulnerability scanners and real-browser UI checks. Simplicity first, no overengineering, and it asks before adopting a library. Run with /audit.
argument-hint: "[paths...] [rounds=N]"
disable-model-invocation: true
---

# Audit

Audit the codebase in rounds until a round finds nothing worth changing. This skill exists to prevent two failures:

- **Inconsistency.** When the bar drifts, one round adds code and the next removes it. So every agent gets the same written bar, [references/bar.md](references/bar.md), and every decision goes into a ledger that later rounds respect.
- **Bias and shallow coverage.** An agent that raised an issue tends to confirm it, and one that fixed it tends to pass it. So find, verify, fix and check are separate fresh agents. Every round re-reads every file, and tools cover all files rather than whatever a reviewer happens to open.

Simplicity matters most. Most good audit changes delete code, and a change that adds code has to fix a real bug.

Arguments: `$ARGUMENTS`. Paths narrow the scope (default: the whole repo). `rounds=N` sets the maximum number of rounds (default 3).

## Your role

You orchestrate and the agents audit. Don't review, verify, fix or check code yourself: you carry this whole conversation, which is the bias the fresh agents are there to avoid. Your jobs are setup, launching agents, deduplicating, asking the user, keeping the ledger and reporting.

Launch every agent with the Agent tool as a new general-purpose agent, never a fork, since a fork inherits this conversation. Every brief has the same shape:

1. "Read `${CLAUDE_SKILL_DIR}/references/bar.md` and `${CLAUDE_SKILL_DIR}/references/<role>.md`, then follow them."
2. The facts for this job: the skill folder (`${CLAUDE_SKILL_DIR}`, written `<skill>` in the briefs), the repo path, the files in scope, the paths of the setup notes, ledger and sweep output, the agent's own output folder, and for verify, fix and check, the findings it handles, copied verbatim.

Leave everything else out: no theories about what's wrong, no earlier rounds' findings, no hint of the result you expect. The briefs in `references/` already say how to work and what to report. Restating them in your own words is how the bar drifts.

## Setup

Do this once per audit.

1. **Scope.** Every tracked and untracked, non-ignored file in scope (`git ls-files -co --exclude-standard`), minus lockfiles, generated files, vendored code and binary assets. Audit the code as it is now, not a diff. Reviewing only recent changes lets older bugs survive. If there are uncommitted changes, tell the user the fixes will land alongside them. Never stage, commit or push.
2. **Output folder.** `<out>` is `audit/` in this session's scratchpad if there is one, otherwise a new `mktemp -d`. Round N writes to `<out>/round-N/`.
3. **Setup notes.** Work out the stack, the build, test and run commands, and the project's instruction files (CLAUDE.md, AGENTS.md, CONTRIBUTING, style guides, DESIGN.md and similar). If there's a UI or a server, work out how to run an isolated copy: its own ports, its own containers or a temp database, and mocks for external services. It must not touch anything the user already has running. Note the routes or entry points, the states worth checking and how to produce or mock them. Write all of this to `<out>/setup.md` so agents don't rediscover it.
4. **Ledger.** Use the project's audit ledger if it has one: look in the project memory folder and the repo for a file of past audit decisions. Otherwise create `audit-ledger.md` in the project memory folder if this session has one, and ask the user where to keep it if not. The format is below.
5. **Slices.** Split the scope into slices that an agent can read in full, by package, folder or feature. Aim for roughly 2,000 to 5,000 lines each, usually 3 to 8 slices. Every file belongs to exactly one slice, including config, CSS, scripts, infra and docs. Save the map to `<out>/slices.md` and reuse it every round, so coverage is comparable between rounds.
6. **Start.** Tell the user the slice count, the round limit and roughly how many agents a round will run, then begin without waiting for a reply.

## Each round

Each round starts from scratch: fresh agents, full reads and a full tool sweep. Only the ledger, the slice map and the setup notes carry over. The eyes are new, but the bar stays the same.

1. **Sweep.** Run `bash ${CLAUDE_SKILL_DIR}/scripts/sweep.sh <repo> <out>/round-N/sweep`.
   - It finds each package (Go, JS/TS, React, CSS, Tailwind 4, Python, Rust, shell) and runs its format check, linter, type checker, dead-code finder and vulnerability scanner. It uses the project's own config where there is one.
   - It writes a summary line per tool, saves each tool's full output to its own file, and lists any languages it doesn't cover. For those, look up that ecosystem's standard tools, run them and save their output next to the rest.
   - A tool that fails to run is a gap to fix or report, not a pass.
2. **Find.** Run one reviewer per slice ([find.md](references/find.md)), all in parallel. Round 1 also runs one library researcher ([libraries.md](references/libraries.md)) over the whole scope. Later rounds rerun the researcher only if dependencies changed.
3. **Triage.** You do this step. Merge the reports and drop duplicates (the same line or the same mechanism). Also drop anything the ledger already settled, unless the finding brings new evidence: a reproduced failure or a measurement. Don't judge merit, because that's the verifier's job. Add each reviewer's "considered and rejected" items to the ledger as they are.
4. **Verify.** Run one verifier per finding ([verify.md](references/verify.md)), in parallel. Findings about the same mechanism can share a verifier. Each verdict is CONFIRMED, REJECTED or NEEDS OWNER.
5. **Ask.** Put NEEDS OWNER items, the reviewers' "needs the owner" items and library proposals to the user with AskUserQuestion.
   - Use at most 4 questions per call. Put your recommended option first, and state the cost in the option descriptions: lines added and removed, any new dependency, any visible change.
   - Only three kinds of question go to the user: new dependencies, visible changes, and decisions with more than one reasonable answer, such as what a fixed behaviour should be.
   - A debatable change with no clear win isn't a question. Ties go to the status quo.
   - Record every answer in the ledger.
6. **Fix.** Group the confirmed findings and approved proposals by the files they touch, and run one fixer per group ([fix.md](references/fix.md)). Groups that share no files run in parallel; overlapping groups run one after another. Give each group its own folder, `<out>/round-N/fix-<group>/`, with a `backup/` inside it.
7. **Check.** Run one checker per fix group ([check.md](references/check.md)). It must not be the agent that made the fix.
   - On FAIL, give the checker's report to a new fixer for one more attempt, then run a new checker.
   - If it fails again, restore the group's files from its backup. Record the finding as skipped, with the reason. It stays settled for the rest of this audit, and the final report lists it.
8. **Record.** Every finding goes into the ledger as fixed (with how the fix was verified), rejected (with the rule that rejects it), skipped, or the owner's call. Rejected entries matter most: they stop the next round from raising the same items again.
9. **Next round or stop.** Stop when no verifier confirms anything new, or when you reach the round limit. Otherwise start the next round at step 1. Don't tell the next round's reviewers what this round found. If a fix was wrong, fresh eyes should catch it on its own merits.

## Ledger format

Keep each entry to one line.

```markdown
# Audit ledger

Settled audit decisions for this project. An entry is reversed only with new evidence, meaning a reproduced failure or a measurement. A different opinion doesn't count.

## Settled
- `path:line` or area: the decision and the rule or reason behind it. (round N, YYYY-MM-DD)

## Owner's calls
- The question: what the owner decided, and why. (YYYY-MM-DD)

## Fixed
- `path:line`: what was wrong, and how the fix was verified. (round N, YYYY-MM-DD)

## Skipped
- `path:line`: what couldn't be fixed cleanly, and why. (round N, YYYY-MM-DD)
```

## Final report

When the last round ends, tell the user:

- for each round: how many findings were raised, confirmed, fixed, rejected and skipped;
- for each fix: the file, what was wrong, how it was verified, and the net line change;
- the owner's decisions, and the skipped items with the reason for each;
- the final sweep's state, and the net lines the audit changed.

Leave every change uncommitted.

## When the user questions a decision

Give your own reasoned answer against the bar: the evidence on both sides and a recommendation. Then wait for their call. Don't revert or concede just because they asked. A verdict that folds under a question is worthless, and flip-flopping is the failure this skill exists to prevent. Record their decision in the ledger.
