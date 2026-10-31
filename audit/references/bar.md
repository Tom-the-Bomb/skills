# The bar

Every agent in every round applies this bar unchanged. Its job is consistency. An item rejected in round 1 must be rejected in round 5, and a fix applied in round 2 must not be undone in round 3. If you think the bar is wrong somewhere, say so in your report, but don't apply a different one.

The project's own instructions (CLAUDE.md, AGENTS.md, style guides, design docs) apply on top of this bar. Where they're stricter, follow them.

## What qualifies

A change qualifies only if it's one of these. Every change except a bug or tool-error fix removes more lines than it adds.

1. **Bug.** Wrong behaviour that a user or operator hits in normal use, or docs and UI copy that state something false. It must be reproduced before the fix and verified after. Rare races, contrived input and "could in theory" don't count.
2. **Removal.**
   - Dead code: unused files, exports, parameters, props, CSS, dependencies and translations, and unreachable branches.
   - Memoization or guards that nothing depends on.
   - Debug or temporary files.
   - Comments that restate the code or no longer match it.
   - Text that can be cut without changing what it tells the reader.
3. **Replacement.** Hand-rolled code swapped for what the language, the framework, an existing dependency or an existing shared helper already provides. Adopting a new dependency also needs the owner's approval (see Libraries).
4. **De-duplication.** Meaningful logic or markup repeated 3 or more times, or a substantial block repeated twice. The shared form must have a name that means something. A shared class or helper that exists only to save characters makes the code harder to read, not easier.
5. **Tool error.** A lint, type, accessibility or vulnerability finding that is real, not style noise. A vulnerable dependency counts if its vulnerable code is reachable, or if it's a direct dependency with a fixed release.

A change must remove at least a line, a branch or a layer of indirection. Token-level tweaks, such as a redundant `?.` or a fallback that can't trigger, aren't worth the churn.

## Never

- **Code for rare edge cases, hypothetical states or "hardening."** Earlier audits that did this added hundreds of lines that a later round removed, and several of those "hardening" fixes were themselves buggy.
- **Memoization without a measured problem**, meaning over 16 ms per interaction at 4x CPU throttle. Remove an existing memo only when nothing depends on it:
  - its result isn't in another hook's dependencies, a memoized child's props, a context value or an effect;
  - and it isn't recomputing on a per-pointer-move or per-keystroke render.
- **Restructuring to raise a tool score.** Tool findings are hypotheses to check.
- **Splitting out a fragment of a parent.** A one-use component whose props are just the parent's own state and setters passed back in gets inlined. Self-contained units stay components even when used once: UI primitives, page sections, toasts, menus and list items.
- **Visible UI or behaviour changes**, except to fix a bug. Check parity with before and after screenshots.
- **Churning many files for a few lines**: about 5 or more files for 20 or fewer lines saved.
- **New comments**, except a non-obvious why: a constraint, an invariant or a workaround. Prefer deleting a comment to rewording it.
- **Preferences and equivalent alternatives** ("could also use X"), **new features**, or **style** the project's formatter or linter already settles.
- **Rewriting vendored or generated code for style.** Code copied in from a component kit (for example shadcn/ui) or produced by a generator follows its upstream. Raise only bugs in it, or unused files.

Ties go to the status quo. If a change is debatable, leave the code alone.

## Settled decisions

The ledger lists earlier decisions. An entry is reversed only with new evidence: a reproduced failure or a measurement, plus an explanation of why the earlier decision was wrong. A different opinion isn't new evidence.

## Libraries

Use what the project already has before writing code: language and framework built-ins, existing dependencies, and existing shared helpers and components. Check a library's current docs rather than relying on memory, because APIs change.

A new dependency is worth proposing only if all of these hold:

- It's big, popular and well maintained. No niche single-purpose packages.
- It replaces hand-written code in more than one place.
- The total code the project maintains goes down.
- It fits without patches or overrides to make it look or behave like the current code.

Component code copied in from an established kit, such as shadcn/ui, counts as library code rather than code the project wrote. Restyling some components is fine when the library brings real benefits, such as accessibility, responsiveness or interaction logic handled for you. "Adopt nothing" is a valid outcome. Every new dependency needs the owner's approval.

## Verification

- **Reproduce a bug before fixing it**, in the real scenario: a test, a script against the actual code, the running app in a browser, or an isolated backend stack. Reasoning about code alone gives you a hypothesis, not a reproduction.
- **After a fix, confirm it in the same scenario**, and confirm nothing regressed: run the tests, build, type check and lint, and take before and after screenshots of anything that renders.
- **"Fixed" means seen working.** If you couldn't run something, say so instead of calling it verified.

## Scenarios

Cover every row that applies to your files and report coverage row by row, so thoroughness doesn't depend on what you happen to try.

**UI**
- Widths 320, 390, 768 and 1280 px.
- Browser text size 16 and 32 px, set with the browser's real font setting rather than CSS zoom.
- Light, dark and forced colours (forced colours in both light and dark), and reduced motion.
- States: loading (slow API), error and offline, not found, empty, one item and very many items; long, non-ASCII and percent-encoded text; logged out and logged in.
- Interaction: keyboard only (tab order, a visible focus ring, focus returning after dialogs and menus), Esc, hover, and touch.
- Behaviour over time: watch transitions, animations and multi-step flows while they run, not only the settled end state. Look for flashes, jumps and wrong intermediate states.
- Every control stays usable in every cell: inputs wide enough to type in, labels not clipped, nothing overflowing the page.
- Third-party UI such as toasts, popovers and portals brings its own CSS. Check the rendered styles, because cascade bugs don't show up in source.

**Backend, CLI and libraries**
- Malformed, empty, huge and non-UTF-8 input, and IDs that don't exist.
- External failures: timeouts, TLS errors, 4xx and 5xx responses, redirects and redirect loops.
- Retries, redelivery and duplicates; cancelling mid-way; an outage of each service the code depends on; restarts with work in flight.
- Concurrency only where normal use produces it.
- API responses match what their clients read.

## Safety

- Never write to services, databases or containers the user is running, and never start real jobs on them. Use an isolated copy (your own ports, containers or temp database) or mocks, and tear down only what you created.
- Only fixers edit project files, and only the files they were given. Everyone else writes only inside their output folder.
- Throwaway tests and scripts go in your output folder, not the repo. For example, use `go test -overlay`, or a script in your folder that imports the project's modules.
- Nobody stages, commits or pushes.
