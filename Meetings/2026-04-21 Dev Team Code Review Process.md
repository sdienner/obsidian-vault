# Dev Team — Code Review Process for Features

**Date:** 2026-04-21
**Attendees:** Scott Dienner, Tom Groff, Casey Holland, Ryan Schubert, Justin Madilia, Jonathan (listen-only)

---

## Context

The team doesn't have a real code review process for feature work. PRs are too large to meaningfully review, so they effectively get skipped. This meeting was called to define a process — branching strategy, PR sizing, reviewer assignment, and design reviews.

---

## The Core Problem

- Big features aren't getting code-reviewed
- PRs that do exist are too large (thousands of lines) — reviewers give up or rubber-stamp
- Individual developers are making decisions in isolation without a second set of eyes
- No design review happens before development starts, leading to rework later

---

## Decisions Made

### 1. Protect Feature Branches
- Feature branches will be **branch-protected** — no direct commits
- All code must come in via PR
- This applies to epics/feature branches; tasks in sprints already flow into sprint branches

### 2. Branching Strategy for Dev Tasks
- Dev tasks branch off the feature branch
- When a chunk is ready, open a PR back to the feature branch
- To keep working while review is pending: branch off your own dev task branch (stacking) rather than pushing more commits to the open PR
- The "PR stacks" GitHub feature would help here but isn't required — you can stack manually today

### 3. PR Sizing
- **Err on the side of small.** Smaller PRs are easier to review and faster to approve.
- No hard line size rule (hours aren't a good limiter), but the "golden rule" applies: **would you want to review this?** A 600-file, 6000-line PR = no, try again.
- The propensity will be to make PRs too large — dev tasks need to be scoped well up front to prevent this
- Ryan noted PRs should be sized more like a "robust commit" or a few commits squashed together

### 4. Design Reviews (Tech Design)
- Currently, design review doesn't happen — everyone jumps straight to code
- Going forward: tech designs should be reviewed **before development starts**
- Jira: add an **"In Review" status** to the tech design task type so review can be tracked
- Design review catches architectural decisions early (e.g., "should we use a form provider here?") vs. discovering them mid-feature in a PR

### 5. Reviewer Hierarchy
Priority order for who reviews your PR:
1. **Another developer on the same feature** (best — already has context)
2. **Domain expert** (next best — knows the codebase area)
3. **Buddy** (fallback if working solo)

- Keep the same reviewer for an entire feature to avoid ramp-up overhead each time
- Exception: cross-domain PRs (e.g., mobile + back office) may warrant different reviewers per area

### 6. Nits / Feedback Style
- Ryan: currently PRs get dead silence — all feedback is welcome as we start this process
- Scott: prefers not to use "nit" labeling, as nits clutter real blocking issues; would rather establish coding standards
- Agreed to revisit and establish PR feedback guidelines once the process is running

### 7. Tasks vs. Epics
- If a task is **too big for one sprint**, it should be an **Epic** (not a separate feature branch living outside the sprint workflow)
- Tasks that don't fit a sprint but are sprint-sized in effort should use **overflow sprint branches** (already exist)
- Ryan's proposal: use overflow branches more intentionally rather than creating ad hoc task branches; overflow branches are off-sprint so QA capacity concerns don't block them
- Agreed to leave the overflow branch / task classification question partially open — needs a broader conversation with PMs/QA

---

## Next Steps

| Action | Owner |
|--------|-------|
| Get penny rounding + point of sale tech design reviewed | Jonathan |
| Review Jonathan's tech design; confirm dev tasks are chunked for PRs | Tony (volunteered) |
| Lock down feature branches (branch protection) | Scott / team |
| Add "In Review" status to tech design Jira task type | Scott (follow up with Jira admin) |
| Establish PR feedback guidelines (nit policy, coding standards) | Future discussion |
| Broader discussion on overflow sprint branch prioritization | Scott + PMs/QA |

---

## Notes

- Ryan and Nate have already done this stacked-PR workflow for service work and reported it went well
- Scott acknowledged there will be growing pains and some delay visible to external stakeholders — his approach is "ask forgiveness, not permission" from Fred on timing impact
- The goal isn't just catching bugs — it's knowledge sharing, consistent patterns, and preventing one person making architectural decisions alone
