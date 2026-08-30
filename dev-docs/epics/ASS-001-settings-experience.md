# ASS-001 — Settings experience foundation

**Status:** Complete

## Goal

Make Settings coherent, English-only, self-explanatory and safe to extend with
the custom layout editor.

## Scope

- Translate every user-facing Settings label, status and validation message to
  English. Persisted TOML keys and command names remain unchanged.
- Add one reusable native info-button component with a popover, tooltip and
  VoiceOver label.
- Give every non-obvious control contextual help that explains its effect,
  valid range and whether it applies immediately or after saving.
- Use consistent names: **Custom**, **Window count**, **Tile limit** and
  **Reset to defaults**.
- Keep layout-profile changes immediate and TOML changes explicit with
  **Save & Apply**.

## Acceptance criteria

- No Portuguese copy remains in the Settings window or its error/status text.
- Every settings group and each potentially destructive or technical control
  exposes an info button.
- Keyboard focus and VoiceOver can reach every info button.
- Info popovers never change a value or steal the active workspace.
- Existing settings tests, the complete test suite and lint pass.

## Out of scope

The visual custom-layout canvas is delivered by ASS-003.
