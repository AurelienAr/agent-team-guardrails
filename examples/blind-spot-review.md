# Example: a blind-spot review

_Illustrative project: a small mobile app that sells a monthly subscription, built by one founder with a team of agents. Six weeks in, the agents are about to start on payments._

**Before.** Every session asked "what should we build next?". Nobody asked about refunds, account deletion or what happens to subscribers if the app stops. The assistant had picked a 14-day trial in a pull request, and three other documents now quoted it as fact.

**After.** The founder says "we start payments tomorrow, anything we're forgetting?". The advisor builds the map from `common.md` and `mobile-app.md`, checks the repository, and reports:

```markdown
## Blind-spot review — 2026-11-03, before starting payments

### Before the next step
1. **In-app purchase versus outside payment** (never discussed). Store rules decide which one is
   allowed for a subscription, and the fees differ. Founder decides. Suggested: settle it before
   any payment code.
2. **Trial length** (proposal shown as decided). docs/pricing.md and two specs state "14 days";
   it comes from the assistant's PR #41 and was never validated. Founder decides: keep or change.
3. **Account deletion from inside the app** (never discussed). Required by both stores; the
   account screen has no such option. Founder decides the grace period; the agents build it.

### Soon
4. **Refund policy** (mentioned but empty). README says "refunds: later".
5. **Age rating questionnaire** (never discussed). Needed for the first store submission.

### Later
- Forced updates, end of life of the service.

### Proposed map updates
- "Sign-in methods": move to decided (docs/decisions/0003-sign-in.md).
```

The founder settles 1 to 3 in one sitting. The person who records those decisions updates the map in the same change.
