# AeroSpaceSmooth product roadmap

This directory is the source of truth for product epics that are specific to the
AeroSpaceSmooth fork. Upstream AeroSpace does not accept regular GitHub issues,
and this checkout currently has only the upstream remote, so the roadmap lives
in the repository until a writable fork remote and project board are connected.

## Product principles

1. Settings are written in English and use native macOS interaction patterns.
2. Every non-obvious setting has contextual help available from an info button.
3. Layouts are deterministic per monitor and window count.
4. Custom layouts use the native tiling tree; they do not emulate tiling with
   floating windows.
5. A settings change must never create a refresh loop or move a workspace to a
   different monitor.
6. Existing configuration and stored layout profiles remain recoverable.

## Delivery order

| Epic | Outcome | Depends on | Status |
| --- | --- | --- | --- |
| [ASS-001](ASS-001-settings-experience.md) | English Settings and contextual help | — | Complete |
| [ASS-002](ASS-002-custom-layout-model.md) | Versioned custom-layout data model | ASS-001 | Ready |
| [ASS-003](ASS-003-custom-layout-editor.md) | Visual editor inside Settings | ASS-002 | Planned |
| [ASS-004](ASS-004-custom-layout-runtime.md) | Reliable runtime application | ASS-002 | Planned |
| [ASS-005](ASS-005-reliability-and-release.md) | Regression, migration and release safety | ASS-003, ASS-004 | Planned |

ASS-003 and ASS-004 can proceed in parallel after the model in ASS-002 is
stable. ASS-005 is the release gate.

## Definition of done

An epic is complete only when its acceptance criteria are automated where
possible, the full Swift test suite and lint pass, accessibility labels exist,
and the installed application has been smoke-tested with one running instance.
