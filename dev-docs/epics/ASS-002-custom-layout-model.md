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

The current persisted raw style value `manual` remains decodable for backward
compatibility, while the UI calls the feature **Custom**. A profile that contains
`manual` without a saved blueprint preserves its current tree until the user
saves a custom design.

## Scope

- Codable, Equatable and Sendable domain types.
- Validation and normalization with actionable errors.
- Conversion from every built-in preset to an editable blueprint.
- Storage and lookup by stable monitor identity plus window count.
- Migration and recovery from malformed or future-version data.
- Import/export-ready JSON representation.

## Acceptance criteria

- Round-trip tests cover all shapes from 1 through 10 leaves.
- Invalid ratios, duplicate slots, missing slots and cycles are rejected.
- Existing v1 monitor profiles decode without data loss.
- Unknown schema versions fall back safely without overwriting their data.

