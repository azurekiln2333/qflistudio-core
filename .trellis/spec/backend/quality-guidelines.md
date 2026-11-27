# Quality Guidelines

> Code quality standards for backend development.

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

## Verification environment

Follow the repository-wide [Cloud-Only Verification](../guides/cloud-only-verification.md)
contract: run builds, tests, analysis, formatting, SDK setup and dependency
restoration only through GitHub-hosted workflows. Keep generated output and raw
reproducible captures out of Git; record immutable cloud evidence instead.


<!-- Patterns that should never be used and why -->

(To be filled by the team)

---

## Required Patterns

<!-- Patterns that must always be used -->

(To be filled by the team)

---

## Testing Requirements

<!-- What level of testing is expected -->

(To be filled by the team)

### Cloud-only validation

Follow [Cloud-Only Verification](../guides/cloud-only-verification.md). Run
formatting, analysis, tests and build verification through GitHub-hosted Actions;
do not create local verification output or restore/install dependencies.

---

## Code Review Checklist

<!-- What reviewers should check -->

(To be filled by the team)
