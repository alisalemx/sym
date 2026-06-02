# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

- **Type**: Native macOS SwiftUI app in an Xcode project.
- **Platform**: macOS 26.0+, Swift 6. The UI uses Liquid Glass (`.glassEffect`, `GlassEffectContainer`, `.glass`/`.glassProminent` button styles), which sets the macOS 26 minimum.
- **Purpose**: Drag-and-drop symbolic link maker. Users drop one or more `Source` files/folders and a `Link` destination folder; Sym creates absolute symlinks inside the destination using each source name.
- **Dependencies**: No third-party dependencies, no Swift Package Manager packages.

## Commands

Build and test (workspace-local DerivedData keeps build products inside the repo and Git-ignored):

```bash
xcodebuild test -project Sym.xcodeproj -scheme Sym -destination platform=macOS -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

Build only (no tests):

```bash
xcodebuild build -project Sym.xcodeproj -scheme Sym -destination platform=macOS -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

Run a single test or test case by appending `-only-testing:`:

```bash
# one method
xcodebuild test -project Sym.xcodeproj -scheme Sym -destination platform=macOS -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:SymTests/SymlinkServiceTests/testCreatesSymlinkForFileSource
# whole class
xcodebuild test ... -only-testing:SymTests/SymlinkServiceTests
```

If a sandboxed run fails with `testmanagerd`/XCTest communication errors, rerun outside the sandbox — the macOS XCTest runner needs system test services.

## Architecture

The app is two layers, and the split is the load-bearing design decision:

- **`SymlinkService` ([Sym/SymlinkService.swift](Sym/SymlinkService.swift))** is the pure, `FileManager`-backed core: it owns all validation and symlink creation and has no UI or SwiftUI dependency. `validate(...)` returns a `[SourceValidation]` (one per source, each carrying a proposed link URL and an optional error message); `createLinks(...)` re-validates, then creates links **all-or-nothing** — on any failure it removes the links it already made and rethrows. This is what the tests in [SymTests/SymlinkServiceTests.swift](SymTests/SymlinkServiceTests.swift) exercise, so keep filesystem behavior here rather than in the view.
- **`ContentView` ([Sym/ContentView.swift](Sym/ContentView.swift))** holds all UI state (`sources`, `destinationFolder`, status messages) as local `@State`, derives `validations` and `canCreateLinks` from the service each render, and drives the drag/drop drop zones. The `Create Link` button stays disabled until every source validates.
- **Entry point**: [Sym/SymApp.swift](Sym/SymApp.swift).

When changing link-creation or validation rules, change `SymlinkService` and its tests; the view should only reflect the service's output.

## Product Rules

- Use the labels `Source` and `Link` in user-facing UI.
- Support files and folders as sources.
- The `Link` drop zone represents a destination folder, not an exact symlink path.
- Create one symlink per source, named after the source item.
- Store absolute symlink destinations.
- Refuse conflicts. Do not replace existing files, folders, or symlinks unless the user explicitly asks for replacement behavior.
- For batches, validate first and disable creation while any item has a conflict or error.

## Security And Sandbox

- App Sandbox is enabled in `Sym/Sym.entitlements`.
- The app uses `com.apple.security.files.user-selected.read-write`.
- Keep file access tied to user-selected files/folders from drag/drop or future picker UI. Do not add persistent security-scoped bookmarks unless the product explicitly needs paths to survive relaunch.

## Conventions

- Keep filesystem behavior in `SymlinkService` so it remains unit-testable.
- Keep SwiftUI state local unless shared app-level state becomes necessary.
- Avoid `#Preview` macros unless command-line builds are known to support the required Xcode macro plugin in the current environment.
- Do not commit `DerivedData/`, build products, or `.xcresult` bundles.
- Commit messages should be short imperative sentences, capitalized, with no conventional-commit prefix.
