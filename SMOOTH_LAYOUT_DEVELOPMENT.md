# AeroSpace Smooth development

This fork experiments with coordinated native macOS window reflow animations.
It keeps AeroSpace's workspace and tree model while replacing immediate,
window-by-window layout writes with a single layout transaction.

## Current milestone

- Collect target frames for every visible monitor before applying them.
- Animate local reflows with a cubic ease-out curve at approximately 60 FPS.
- Cancel and rebase when a different layout arrives during an animation.
- Ignore duplicate refreshes that have the same target frames.
- Apply cross-monitor and workspace transitions immediately.
- Respect the macOS Reduce Motion preference.

## Configuration

```toml
# 0 disables layout animations. Accepted range: 0...1000.
layout-animation-duration-ms = 160

layout-animation-respect-reduce-motion = true
```

## Build

```sh
cd /Users/cassel/app/AeroSpaceSmooth
./build-debug.sh -Xswiftc -warnings-as-errors
./swift-test.sh
./lint.sh
./generate.sh
xcodebuild \
  -project xcode/AeroSpace.xcodeproj \
  -scheme AeroSpace \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath xcode/.xcode-build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The generated app is:

```text
/Users/cassel/app/AeroSpaceSmooth/xcode/.xcode-build/Build/Products/Debug/AeroSpace-Debug.app
```

## Manual test safety

Do not run the installed AeroSpace and AeroSpace-Debug simultaneously. They
both manage the same windows, shortcuts, and server resources. Quit the
installed app first, open the debug build, and grant AeroSpace-Debug
Accessibility permission when macOS asks.

The first manual test should cover:

1. Close one of five tiled windows and verify that the remaining tree reflows
   once without flattening.
2. Open a window and verify that all affected windows arrive together.
3. Switch workspaces and move a window to another monitor; these transitions
   must snap rather than travel across displays.
4. Trigger repeated focus commands during an active animation and verify that
   the motion does not restart or oscillate.
