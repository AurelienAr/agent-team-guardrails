---
name: blind-spot-advisor
description: Keeps a topic map of everything a project will have to decide (decided, proposal, mentioned but empty, never discussed) and flags, unprompted, what nobody has asked about yet, including the standard topics of the field. Use at the end of a decision, at a milestone, before starting work in a new area, or when someone asks "what are we forgetting?". The review is read-only: it reports and proposes map updates, it never decides.
---

# Blind-spot advisor

Projects rarely fail on the questions people argue about. They fail on the ones nobody raised: the backup policy, the refund rule, the age limit, the thing every product in the field has and this one forgot. This skill keeps a map of every topic the project must eventually settle, and reviews the project against it so that gaps are raised by the advisor, not discovered later by the owner.

Two jobs:
1. **Keep the map** (`TOPICS.md` by default, or the file the project already uses).
2. **Review against the map** and report a short, ranked list.

## 1. The topic map

One table per area. Every topic a project of this kind will need to settle gets a row, whether or not anyone has mentioned it.

```markdown
## Billing

| Topic | Status | Source | Who decides | Urgency |
|---|---|---|---|---|
| Refund policy | never discussed | — | owner | before launch |
| Prices and currency | decided | docs/decisions/0007-pricing.md | owner | — |
| Trial length | proposal | PR #41 (written by the assistant) | owner | before beta |
| Invoices for companies | mentioned but empty | README, "later" | owner | before launch |
```

Statuses, and only these four:

| Status | Meaning |
|---|---|
| **decided** | A person with authority settled it, and the source shows where. |
| **proposal** | Someone suggested an answer, often the assistant. Not a decision yet. |
| **mentioned but empty** | The topic appears somewhere, but nothing was settled. |
| **never discussed** | Nothing in the project addresses it. |

**Building the map the first time.**
- Start from the field, not from the repository. Begin with `references/topic-maps/common.md` in this skill's folder, then add the starter list for the project's kind: `mobile-app.md`, `saas.md`, `game.md`, `marketplace.md`, `api.md` or `open-source-library.md`. These lists are a floor, not a ceiling: add what this particular project has that they miss. For a kind with no list, write one from what every serious project of that kind must settle.
- Use `templates/TOPICS.md` as the file's skeleton.
- Then search the repository and its decision records for each topic, and set the status from what you actually find.
- Include the obvious standards of the field. "Everyone knows that" is exactly how a topic gets skipped.
- Group the open topics into sessions the owner can decide in one sitting.

**Keeping it current.** Writing the map is the job of whoever records the decision: every decision updates its rows in the same change that records it. The review itself never edits the map; it lists the updates it proposes. If a change settles or proposes a topic and the map is not touched, say so.

## 2. Proposal is not decision

The most frequent silent error is a proposal turning into a decision by repetition. An assistant suggests a number, it gets written into a document, other work builds on it, and three weeks later everyone treats it as settled.

- Anything the assistant wrote stays **proposal** until a person with authority validates it. Record where that validation is (a message, a review, a signed-off decision record).
- A proposal that other work already depends on is reported with high urgency.
- Never upgrade a status yourself because the content "looks agreed".

## 3. The review

Run it at the end of a decision, at each milestone, before starting a new area of work, or on request. One review can cover several decisions of the same milestone. If you can, run it in a read-only subagent, so the review is not anchored on the reasoning of the session that did the work.

Compare the current state of the project (decision records, docs, open issues, recent changes) with the map, and look for:

1. **Never discussed** topics that are about to matter: the upcoming work depends on them, or they are a standard of the field.
2. **Proposals presented as decisions**: in docs, code constants, summaries or plans.
3. **Contradictions**: two documents, or a document and the code, that disagree.
4. **Stale map rows**: a decision exists but the map still says open, or the reverse.
5. **Topics outside the map**: something in the project that has no row at all.

## 4. The report

Short, ranked, and actionable. At most ten items; group the rest under "later".

```markdown
## Blind-spot review — <date>, <trigger>

### Before the next step
1. **Refund policy** (never discussed). The checkout lands in the next milestone and every store requires one. Owner decides. Suggested: add it to the next decision session.
2. **Trial length** (proposal shown as decided). docs/pricing.md states "14 days" as fact; it comes from the assistant's PR #41. Owner decides: validate or change.

### Soon
3. ...

### Later
- Invoices for companies, account deletion.

### Proposed map updates
- "Prices and currency": move to decided (docs/decisions/0007-pricing.md).
```

Each item says: the topic, its status, why it matters **now**, who decides, and one suggested next step.

## Rules

- **The review is read-only.** Report and propose, never decide, and never rewrite a decision. The owner or the person with authority settles the topic; the map is then updated with the source.
- **Speak up unprompted.** The whole point is to raise what nobody asked about. Report standard topics even when they seem obvious.
- **No flood.** One grouped report per trigger, not a stream of alerts. Urgent items (money, legal, user data) go first.
- **Do not reopen settled topics** without a new fact. If there is one, name it.
- **Evidence over memory.** Every status points to a source the reader can open.
