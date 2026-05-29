# PAYMENT-STATEMENT-001 Execution Plan

## Checkpoint

- Branch: `main`
- HEAD: `b2992ebe8866c35004d71dddf18f47693956546c`
- Dirty worktree: clean before this implementation; feature diff introduced in
  the current patch.

## Steps

1. Add Prisma order fields, audit table, indexes, migration, and generated
   client.
2. Update MAP sync normalization, manual-preserve behavior, statement API,
   export CSV, audit history, and focused backend tests.
3. Add Flutter bank statement repository/provider/screen, home route/tile,
   AppLogger events, and payment monitor order-border behavior.
4. Update product docs, story packet, and test matrix.
5. Run targeted backend tests, backend build, Flutter analysis/tests, Prisma
   validation/generation, and `git diff --check`.

## Stop Conditions

- Prisma migration or generated client fails.
- Role/scope enforcement cannot be validated in tests.
- Existing payment monitor behavior breaks at compile/test time.
- CSV export cannot preserve selected-row vs filtered-result behavior.

## Ownership

- Files/modules: `backend-nest/prisma`, `backend-nest/src/map-vietin`,
  `lib/features/bank_statement`, home navigation, and payment monitor cards.
- Out of scope: real region/multi-store hierarchy, MAP portal UI automation,
  and showing auto extraction as manual history.
