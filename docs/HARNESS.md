# Harness

The app is what staff use. The harness is what keeps human and agent work safe,
small, and verifiable.

## Work Loop

```text
Human intent
  -> feature intake
  -> lane selection
  -> product/story update when needed
  -> implementation
  -> validation proof
  -> decision or backlog update when needed
  -> concise report
```

Every meaningful task can produce two kinds of output:

1. Product delta: app code, API behavior, data model, tests, or product docs.
2. Harness delta: story evidence, test matrix rows, decisions, templates, or
   clearer agent instructions.

## When To Create Story Packets

Create or update a story packet when work changes behavior, API contracts, data
rules, auth, deployment, or more than one product domain.

Skip story packets for tiny documentation edits, local cleanup, or narrow fixes
where the final diff and validation are self-explanatory.

## Validation Rule

Validation is part of the work, not a footer. Select the smallest useful proof
before editing, then state exactly what was run.

If proof is missing or blocked, report:

- what is verified
- what is unverified
- remaining risk
- the next command or setup needed

## Growth Rule

If a task exposes repeated confusion, missing proof, unclear ownership, or a
manual checklist worth preserving, update this harness directly or add a note to
`docs/HARNESS_BACKLOG.md`.
