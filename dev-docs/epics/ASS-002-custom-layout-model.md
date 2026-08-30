# ASS-002 — Versioned custom layout model

## Goal

Represent a user-designed layout as a validated native tiling tree that can be
stored independently for every monitor and window count from 1 through 10.

## Architecture

Use a recursive weighted split tree:

- A leaf references exactly one logical window slot.
- A split has a horizontal or vertical axis, two children and a normalized
  ratio in the safe range `0.10 ... 0.90`.
- Every layout contains each slot from `0 ..< windowCount` exactly once.
- The storage envelope has an explicit schema version.

The model deliberately allows **hybrid layouts**. A Dwindle, grid, row or
column arrangement can live inside any selected subtree instead of controlling
the entire monitor. This supports sequences such as:

- 1 window: fullscreen;
- 2 windows: a 50/50 horizontal split;
- 3 windows: preserve the primary half and split the secondary half;
- 4+ windows: start a nested Dwindle only inside the secondary half.

Each window-count blueprint is independent, but it can be derived from the
previous count by inserting the next slot into a selected leaf or subtree.

The current persisted raw style value `manual` remains decodable for backward
compatibility, while the UI calls the feature **Custom**. A profile that contains
`manual` without a saved blueprint preserves its current tree until the user
saves a custom design.

## Scope

- Codable, Equatable and Sendable domain types.
- Validation and normalization with actionable errors.
- Conversion from every built-in preset to an editable blueprint.
- Derivation of the `N`-window blueprint from `N - 1`, with an explicit target
  region, split axis and insertion position.
- Applying a built-in preset to only one subtree while preserving the rest of
  the custom layout.
- Storage and lookup by stable monitor identity plus window count.
- Migration and recovery from malformed or future-version data.
- Import/export-ready JSON representation.

## Acceptance criteria

- Round-trip tests cover all shapes from 1 through 10 leaves.
- Invalid ratios, duplicate slots, missing slots and cycles are rejected.
- Existing v1 monitor profiles decode without data loss.
- Unknown schema versions fall back safely without overwriting their data.
- A mixed tree can contain a fixed primary pane and a nested Dwindle beginning
  at any selected logical window slot.
