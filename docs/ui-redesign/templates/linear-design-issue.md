# [Design] <Feature or Screen>

## Goal and user outcome

Mục tiêu của screen/flow và tác vụ chính người dùng cần hoàn thành.

## Product authority

- Product docs and decision:
- Business/API/permission/platform constraints:
- Current behavior that must remain:

## Scope

- Screens/flows:
- Breakpoints:
- States/interactions:

## Out of scope

Những behavior, screens và systems không thay đổi.

## Current baseline

- Runtime route/component:
- Existing Figma/history:
- Known UX/accessibility gaps:

## Target requirements

- Information hierarchy and primary action:
- Responsive behavior:
- Content/data requirements:
- Reusable shared components:
- Vietnamese-first copy requirements:

## Required states

- Loading/refreshing
- Empty/filtered empty
- Error/retry/offline/partial
- Success/disabled/validation
- Permission denied/session expired
- Domain-specific states

## Responsive and accessibility

- Compact `<600`
- Medium `600–899`
- Expanded `900–1199`
- Wide `>=1200` when applicable
- Keyboard/focus/semantics/contrast/touch target/text scaling/reduced motion

## Deliverables

- Exact Figma file/page/frame/node/revision links
- Interaction/responsive/accessibility notes
- Component/token mapping
- Design decisions/trade-offs/open questions
- Proposed implementation and QA proof

## Approval gate

Implementation remains blocked until Đại Ca explicitly approves the exact
Figma frame/revision. Figma cannot add business/API/permission behavior without
separate product authority.
