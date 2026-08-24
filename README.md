# NeoGlossa

An offline iPhone app for drilling German nouns (word + gender + plural), irregular verbs
(Partizip II + auxiliary) and prepositions (governed case) with FSRS-5 spaced repetition.

Design working title: **Artikel**. SwiftUI, iOS 26+, single user, no network at runtime.

## Status

Planning. No application code yet.

- [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) — the full build plan:
  open decisions, repository layout, and the four phases (dataset, design system, core
  engine, app) with acceptance criteria and a test checklist.

## Principles

- The dataset is the risk. It is built, cross-verified and reviewed before any app code.
- Every fact the app teaches — gender, plural, auxiliary, governed case — comes from the
  bundled read-only dataset. Never from a language model.
- Grading is strict: capitalisation is enforced, `ae` is not `ä`, the article is required.
- Colour is never the only signal. Each gender carries a rule cue as well as a colour, and
  red means one thing only: wrong.
