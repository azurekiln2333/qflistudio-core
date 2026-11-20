# Quality Guidelines

> Code quality standards for frontend development.

---

## Overview

<!--
Document your project's quality standards here.

Questions to answer:
- What patterns are forbidden?
- What linting rules do you enforce?
- What are your testing requirements?
- What code review standards apply?
-->

(To be filled by the team)

---

## Forbidden Patterns

<!-- Patterns that should never be used and why -->

(To be filled by the team)

---

## Required Patterns

<!-- Patterns that must always be used -->

(To be filled by the team)

### Widget-test route inspection

Use inherited dependency lookups such as `ModalRoute.of(context)` only from an
ordinary descendant context. Do not run them on every element returned by
`visitAncestorElements`: an `InheritedElement` includes itself in its inherited
lookup map and can register an illegal self-dependency. Later route changes then
fail the framework's descendant assertion and can corrupt subsequent tests.

For nested route checks, read the page's context and enclosing `Navigator`
`StatefulElement` contexts only. Keep route animation and application readiness
assertions when replacing `pumpAndSettle` for screens with persistent spinners.
See `test/support/remote_control_app.dart`.

---

## Testing Requirements

<!-- What level of testing is expected -->

(To be filled by the team)

---

## Code Review Checklist

<!-- What reviewers should check -->

(To be filled by the team)
