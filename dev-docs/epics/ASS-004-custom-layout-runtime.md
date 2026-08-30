# ASS-004 — Custom layout runtime

## Goal

Apply a saved custom blueprint through the native AeroSpace tiling tree with the
same stability and animation guarantees as built-in layouts.

## Scope

- Build native tiling containers recursively from the blueprint.
- Apply split ratios as adaptive weights.
- Preserve logical window order when windows close and reopen.
- Reconcile only when membership, monitor, window count or blueprint revision
  changes.
- Animate the whole layout as one coordinated transaction.
- Keep focus, fullscreen and cross-monitor navigation semantics unchanged.
- Respect each monitor's tile limit and workspace assignment.

## Acceptance criteria

- Golden tree tests cover 1 through 10 windows and both monitor orientations.
- Repeated refreshes are idempotent and cannot enter a feedback loop.
- Closing a window and returning to the configured count restores the saved
  blueprint predictably.
- Resize, focus, move, swap, fullscreen and workspace commands pass regression
  tests.
- A custom layout never moves a workspace to another monitor.

