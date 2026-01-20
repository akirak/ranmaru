---
name: adr-from-template
description: Create a new Architecture Decision Record (ADR) from `docs/adrs/0000-template.md`. Use when asked to add or document ADRs, record architecture decisions, or formalize technical choices in this repo.
---

# ADR From Template

## Workflow

1. List existing ADRs in `docs/adrs/` and identify the highest numbered ADR.
2. Choose the next number (4 digits). If only the template exists, start at `0001`.
3. Create `docs/adrs/NNNN-<short-title-slug>.md` by copying `docs/adrs/0000-template.md`.
4. Update the title line, `Status`, and `Date` in the new ADR.
5. Fill in Context, Decision, Consequences, Alternatives Considered, and Related ADRs.

## Naming

- Use `NNNN-<short-title-slug>.md` with a lowercase, hyphenated slug.
- Example: `0002-adopt-foo-bar.md`.

## Content notes

- Keep Status as Draft until the decision is accepted.
- Keep the template sections, adding subsections only when needed.
- Write in a concise, factual tone.
