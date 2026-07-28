# Approved Figma implementation workflow

Use only when the exact visual/interaction target is authorized.

1. Require the Linear issue, Figma file/frame/node URL, approved revision or
   snapshot, and the approval evidence. Missing revision means `Needs decision`
   and no writer.
2. `opshub_ui_ux_reviewer` records hierarchy, states, interaction, accessibility,
   four shared breakpoints, and platform targets; `opshub_repo_explorer` maps
   reusable Flutter components, routes, state, services, and tests.
3. Preserve business/API/permission/platform behavior. Use shared theme/tokens,
   canonical DateRangePicker, command-input row, modal model, AppLogger and
   Vietnamese-first copy. Be Vietnam Pro is not introduced without the
   approved foundation/license/proof gate.
4. One implementer changes only the approved scope. If implementation needs a
   different behavior or visual target, stop, update the Figma/Linear authority,
   and wait for re-approval.
5. Verify representative compact, medium, expanded, and wide viewports on
   Android/Windows targets (web regression where affected), plus loading,
   empty, error, disabled, long-copy, focus, semantics, and overflow states.
   Record build SHA, viewport, platform, and Figma revision for screenshots.
