# 0008 Finance Filter Actions

Date: 2026-06-26

## Status

accepted

## Context

Finance list screens were drifting in layout: `Sao kê` placed export in the list
toolbar, while `Cấn trừ` placed export beside the filter actions. Staff read
both as filtered-result workflows, so the action placement must stay consistent.

## Decision

For finance list screens with a filter panel, query-dependent actions belong in
the filter panel action area. `Tìm`, `Xuất file`, export menus, and similar
commands that use the current filter or selected result scope should sit beside
the filter controls.

Action buttons should be grouped as one compact row with shared layout spacing
tokens, so search/export actions scan as one control cluster. Avoid stretching a
single action across an oversized filter column when two balanced buttons make
the panel easier to read.

The toolbar below the filter should stay focused on list state: selection count,
pagination, refresh, and row/list navigation. If the filter action row cannot fit
on a narrow viewport, move the whole action group to its own line inside the
filter panel instead of moving it to the list toolbar.

Visible labels must be Vietnamese-first and consistent across screens, using
labels such as `Tìm`, `Xuất file`, and `Đang xuất`.

## Consequences

- `Sao kê` and `Cấn trừ` keep the same action hierarchy.
- New finance screens have one rule for where export/search actions live.
- Reviewers can catch layout drift by checking the filter panel before release.

## Validation Impact

When moving finance filter actions, run the narrow widget/provider tests for the
affected screen plus `flutter analyze` and `git diff --check`.
