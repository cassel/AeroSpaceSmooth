# ASS-004 — Custom layout runtime

## Goal

Apply a saved custom blueprint through the native AeroSpace tiling tree with the
same stability and animation guarantees as built-in layouts.

## Scope

- Build native tiling containers recursively from the blueprint.
- Apply split ratios as adaptive weights.
- Preserve mixed subtree strategies; normalization must not flatten away the
  boundary between a fixed primary pane and its nested Dwindle region.
- Preserve logical window order when windows close and reopen.
- Reconcile only when membership, monitor, window count or blueprint revision
  changes.
- Animate the whole layout as one coordinated transaction.
- Keep focus, fullscreen and cross-monitor navigation semantics unchanged.
- Respect each monitor's tile limit and workspace assignment.

## Acceptance criteria

- Golden tree tests cover 1 through 10 windows and both monitor orientations.
- Golden tests cover Dwindle starting at slots 3 and 4 inside a secondary pane.
- Repeated refreshes are idempotent and cannot enter a feedback loop.
- Closing a window and returning to the configured count restores the saved
  blueprint predictably.
- Resize, focus, move, swap, fullscreen and workspace commands pass regression
  tests.
- A custom layout never moves a workspace to another monitor.
