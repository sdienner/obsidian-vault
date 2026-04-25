# Code Review Process

Working draft of the team's code review practices, following the 2026-04-21 meeting. To be refined with the team during pilot (Jonathan's penny rounding feature) and eventually moved to Confluence or a repo CONTRIBUTING.md.

Related: [[2026-04-21 Dev Team Code Review Process]]

---

## PR Description Template

Drop this in `.github/pull_request_template.md` in the repo so it auto-populates on every PR. The HTML comments (`<!-- ... -->`) appear while the author is editing but are hidden in the rendered description, so links and prompts don't clutter merged PRs.

```markdown
<!--
Before submitting:
- Run the Self-Review Checklist: https://github.com/Cargas/energy-dev-docs/blob/main/docs/code-review/self-review-checklist.md
- Comment conventions (blocking / suggestion / question / praise): https://github.com/Cargas/energy-dev-docs/blob/main/docs/code-review/comment-conventions.md
-->

## What
<!-- 1-2 sentence summary of the change -->

## Why
<!-- Jira link (CAR-XXXXX), or brief context if no ticket -->

## How to test
<!-- Manual steps to verify, or "Covered by test X in file Y" -->

## Risks & notes
<!-- Anything the reviewer should watch for — tricky tradeoffs, follow-ups to file,
areas you're uncertain about, decisions you'd like a second opinion on -->

## Screenshots
<!-- For UI changes — before/after. Delete this section if not applicable. -->
```

**Why this template matters:** Reviewers currently don't know what to look for, so they don't comment. The "Risks & notes" section in particular gives the author a place to pre-flag concerns, which tends to unlock more useful feedback than a blank PR. The HTML-commented links at the top serve as a just-in-time reminder for authors filling in the template, without polluting the rendered PR description after submission.

---

## Self-Review Checklist (Author)

Before you request a review, walk through your own PR on GitHub (not just locally):

- [ ] Read every line of the diff yourself — catch the obvious stuff before the reviewer does
- [ ] No debug code, console.logs, stray `TODO` comments, or commented-out code
- [ ] No secrets, connection strings, or credentials committed
- [ ] Scope is one logical change — not a grab bag of unrelated fixes
- [ ] PR description is filled in (what, why, how to test, risks)
- [ ] Tests pass locally; new behavior has test coverage or a stated reason it doesn't
- [ ] Branch is rebased / up to date with the target branch

If anything in the diff surprises you while reviewing your own work, fix it before assigning a reviewer.

---

## Code Review Checklist (Reviewer)

You don't need to hit every bullet on every PR — use judgment based on scope. These are the things *someone* should verify:

- [ ] **Does it actually solve the stated problem?** Read the "What/Why" in the description first, then check the code against it.
- [ ] **Is the approach sound?** If you'd have done it meaningfully differently, say so now — not after it ships. Architectural concerns are the most expensive to fix later.
- [ ] **Edge cases** — nulls, empty collections, error states, concurrent users, what happens on failure
- [ ] **Security** — SQL injection, authorization checks, input validation, anything touching auth or payments
- [ ] **Consistency** — does this match existing patterns in the same area of the codebase? Deviations should have a reason.
- [ ] **Simplicity** — could this be simpler? Flag it, but defer to the author if it's a judgment call.
- [ ] **Test coverage** — are new paths tested? Are the tests actually meaningful, or just coverage theater?
- [ ] **PR is appropriately sized** — if this is too big to review well, say so and ask for it to be broken up. Pushing back on size is part of the review.

**Things NOT to comment on:**
- Anything covered by linting or auto-formatting
- Personal style preferences not written into team standards
- Don't rewrite the PR in comments — if the change needs a fundamentally different approach, pull the author into a conversation synchronously

---

## Comment Prefix Conventions

Every comment should start with one of these prefixes so the author knows what's required of them.

| Prefix | Meaning | Author action |
|--------|---------|---------------|
| `blocking:` | Must be resolved before merge. Bugs, security issues, significant architectural concerns. | Must address — fix, discuss, or push back with reasoning. |
| `suggestion:` | Recommended change. Author uses judgment. | Consider and respond — either incorporate or reply why not. |
| `question:` | Asking for clarification. Not a change request. | Answer the question. Code change only if the answer reveals an issue. |
| `praise:` | Positive feedback. Call out patterns worth repeating. | No action required. Reply if you want. |

**Rules:**
- Unprefixed comments are treated as `blocking:` by default. Always prefix.
- A reviewer can leave as many `suggestion:` / `question:` / `praise:` comments as they want without holding up the PR.
- Authors must resolve every `blocking:` before merge.
- If author and reviewer disagree on a `blocking:` item, pull it into a synchronous conversation — don't ping-pong in PR comments.

**Why this works:** Resolves the "nits vs. signal" debate without having to define what a nit is. Reviewers can be as thorough as they want; authors have clear guidance on what must change vs. what's advisory.

---

## Open Questions

- [ ] Squash vs. merge commit strategy — do we enforce one?
- [ ] What constitutes a rebase-before-merge requirement?
- [ ] When do we move from this draft to a repo CONTRIBUTING.md / Confluence page?
- [ ] Feature flag strategy for long-running features (separate discussion)
