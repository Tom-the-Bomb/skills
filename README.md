# skills

My agent skills

## audit

Audits a codebase in rounds until a round finds nothing worth changing. Every round starts from scratch with fresh agents, but they all follow the same written bar, so one round doesn't undo what the last one did.

Each issue goes through four separate agents. One finds it, one checks it's real and worth fixing, one fixes it, and one checks the fix. Linters, type checkers, dead code finders and vulnerability scanners run over every file, and UI gets checked in a real browser at different widths, text sizes and color modes. Simple code wins, overengineering gets cut, and it asks before adding a library.

```
/audit
/audit web/src rounds=5
```

It needs git and node. Go, Python and Rust checks run when the repo has them.

## Install

```sh
git clone https://github.com/Tom-the-Bomb/skills ~/Projects/skills
ln -s ~/Projects/skills/audit ~/.claude/skills/audit
```
