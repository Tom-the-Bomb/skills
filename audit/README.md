# audit

Round based code auditing, fresh agents each round, but same consistent criteria to avoid undoing edits

1. Find
2. Verify issue
3. fix
4. Verify fix

```
/audit
/audit web/src rounds=5
```

Requires: `git` and `node`
