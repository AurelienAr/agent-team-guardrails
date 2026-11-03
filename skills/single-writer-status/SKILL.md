---
name: single-writer-status
description: Use in a repository where several agents or sessions work in parallel and share a status or handoff file (STATUS.md, PROGRESS.md, HANDOFF.md or similar). Each pull request leaves a one-sentence "For STATUS" line in its description and never edits the file; one designated writer gathers the lines of merged pull requests into a single update. Triggers when opening a pull request, when about to edit the status file, or when running the status roll-up.
---

# Single-writer status

A shared status file is the first thing parallel agents fight over. Every branch adds its line at the top, every merge conflicts, and conflict resolutions quietly drop lines. This skill removes the conflict at its source: **pull requests never touch the status file. They leave one sentence, and a single writer folds those sentences in.**

The status file name below is `STATUS.md`. Use whatever the project calls it.

## Role 1: anyone opening a pull request

1. Do not edit `STATUS.md`. If your branch changed it, revert that part.
2. Add this section to the pull request description:

   ```markdown
   ## For STATUS
   Login by email now works end to end; password reset is still missing (see #88).
   ```

3. Write the sentence well:
   - one or two sentences, saying what is **now true** for the project, not what you did ("Login works", not "I implemented login");
   - name what is still missing, if anything;
   - point to the issue, document or decision record that has the detail;
   - write "Nothing for STATUS" if the change does not affect the project state (a typo, a refactor with no visible effect).

## Role 2: the status writer

Exactly one writer exists per status file: a named person, session or agent. The project instructions say who. If they do not, ask; never become the writer on your own.

**When**: at most once a day, and only if there is something new.

**How**:

1. Find where the last roll-up stopped. Keep a marker at the top of the file:

   ```markdown
   <!-- last-rollup: 2026-11-03T18:00:00Z -->
   ```

   If a roll-up pull request is still open, read the marker from **its** branch, not from the base branch: otherwise you would fold in the same pull requests twice.

2. Gather the sentences with the bundled script. It lists the pull requests merged since the marker, leaves out the roll-up pull requests (label `status-rollup`), extracts each "For STATUS" section and prints the new marker:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/single-writer-status/scripts/rollup.sh" --since 2026-11-03T18:00:00Z --base main
   ```

   (Installed as a plain skill, the script is `scripts/rollup.sh` in this skill's folder.) It does steps 3 and 4 below and prints the marker for step 6; it never edits the status file, which stays your job. By hand, the listing is:

   ```bash
   gh pr list --state merged --base main \
     --search "merged:>2026-11-03T18:00:00Z -label:status-rollup" \
     --json number,title,mergedAt,body --limit 200
   ```

   If the list comes back full (200 results), raise the limit or split the time range: the cut is silent. GitHub's search can lag a few minutes behind a merge, and a pull request it has not indexed yet would fall behind the new marker and be lost. So leave out what was merged in the last ten minutes: the script does it for you (`--settle-minutes`) and lists those pull requests for the next roll-up.

3. Keep only pull requests that were **actually merged**. A closed, unmerged pull request contributes nothing, even if its sentence is good.
4. Extract each "For STATUS" section. Skip "Nothing for STATUS".
5. Fold the sentences into the file: update the existing line on the same topic rather than adding a duplicate; when two sentences disagree, the later merge wins, and you say so in the pull request description.
6. Update the marker to the merge time of the most recent pull request you included.
7. Open **one** pull request with the update, labelled `status-rollup`. It is merged like any documentation change in the project (the project instructions say by whom). Its description lists the pull requests included, and any merged pull request that had no "For STATUS" section, so its author can add the sentence for the next roll-up.

If nothing new was merged, do nothing: no empty update.

## Setting it up in a project

- Name the writer and the file in the project instructions.
- Add the section to the pull request template: `templates/pull_request_template.md` in this skill's folder.
- Optionally, add the check `templates/status-guard.yml` to the project's GitHub workflows: it fails a pull request that edits the status file without the `status-rollup` label, or that has no "For STATUS" section.

## Rules

- One writer, one roll-up pull request at a time. If a roll-up is still open, add to it instead of opening another.
- The status file is a summary. The live state stays in issues and pull requests; the file points to them.
- Never rewrite a past entry to match a newer opinion; add the new fact and its source.
- If someone else edits the status file anyway, do not fight it in a merge: fold their change in at the next roll-up and point them to this rule.
