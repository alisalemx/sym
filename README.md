# Sym

A native macOS app for making symbolic links by drag and drop.

Drop one or more **Source** files or folders and a **Link** destination folder, and Sym creates absolute symlinks inside the destination — one per source, each named after the source item.

## Features

- **Drag and drop** — drop sources and a destination folder onto the two drop zones.
- **Files and folders** — both are supported as sources.
- **Batch creation** — link many sources at once.
- **Conflict-safe** — Sym refuses to overwrite existing files, folders, or symlinks. The **Create Link** button stays disabled until every source validates.
- **All-or-nothing** — if any link in a batch fails, the links already created are rolled back.
- **Absolute destinations** — symlinks store absolute paths.

## Requirements

- macOS 26.0 or later
- Xcode with a Swift 6 toolchain

The UI is built with [Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/liquid-glass) (`.glassEffect`, `GlassEffectContainer`, `.glass`/`.glassProminent` button styles), which sets the macOS 26 minimum.

## Building

```bash
# Build
xcodebuild build -project Sym.xcodeproj -scheme Sym -destination platform=macOS -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO

# Test
xcodebuild test -project Sym.xcodeproj -scheme Sym -destination platform=macOS -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

## Architecture

Sym is two layers, and the split is the load-bearing design decision:

- **`SymlinkService`** ([Sym/SymlinkService.swift](Sym/SymlinkService.swift)) is the pure, `FileManager`-backed core. It owns all validation and symlink creation and has no UI dependency. `validate(...)` returns one `SourceValidation` per source (carrying a proposed link URL and an optional error); `createLinks(...)` re-validates, then creates links all-or-nothing.
- **`ContentView`** ([Sym/ContentView.swift](Sym/ContentView.swift)) holds all UI state, derives validations from the service each render, and drives the drop zones.

Filesystem behavior lives in `SymlinkService` so it stays unit-testable — see [SymTests/SymlinkServiceTests.swift](SymTests/SymlinkServiceTests.swift).

## Security

The app runs in the macOS App Sandbox with `com.apple.security.files.user-selected.read-write`. File access is tied to user-selected files and folders from drag and drop.

## No dependencies

No third-party dependencies and no Swift Package Manager packages.
