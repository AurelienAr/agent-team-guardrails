# Example: three parallel pull requests, one status update

**Before.** Three agents finish work the same day. Each adds its line at the top of `STATUS.md`. The second and third merges conflict on that file; one resolution drops a line, and nobody notices for a week.

**After.** None of the three pull requests touches `STATUS.md`. Each description ends with a sentence:

```markdown
## For STATUS
Login by email works end to end; password reset is still missing (see #88).
```

In the evening, the status writer runs:

```bash
bash skills/single-writer-status/scripts/rollup.sh --since 2026-02-28T18:00:00Z --base main
```

and gets:

```text
<!-- last-rollup: 2026-03-01T12:00:00Z -->

## Merged into main since 2026-02-28T18:00:00Z
- #21 Login by email: Login by email works end to end; password reset is still missing (see #88).
- #24 Export to CSV: Users can export their data to CSV.

### No "For STATUS" section
- #23 Refactor storage

### Nothing for STATUS
- #22 Fix typo
```

The writer folds the two sentences into `STATUS.md`, moves the marker, and opens one pull request labelled `status-rollup`. Its description asks the author of #23 for the missing sentence. Zero conflicts on the status file, because only one writer ever edits it.

The output above is the real output of `rollup.sh` on the fixtures of `tests/run.sh`.
