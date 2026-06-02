# AGENTS.md - Sym

Compact guide for agents working in this repo.

## Project

- **Type**: Native macOS SwiftUI app in an Xcode project.
- **Platform**: macOS 14.0+, Swift 6.
- **Purpose**: Drag-and-drop symbolic link maker. Users drop one or more `Source` files/folders and a `Link` destination folder; Sym creates absolute symlinks inside the destination using each source name.
- **Dependencies**: No third-party dependencies, no Swift Package Manager packages.

## Build And Test

Use a workspace-local DerivedData path so build products stay inside the repo and remain ignored by Git.

```bash
xcodebuild test -project Sym.xcodeproj -scheme Sym -destination platform=macOS -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

If this fails inside a sandbox with `testmanagerd` or XCTest communication errors, rerun outside the sandbox. The normal macOS XCTest runner needs access to system test services.

## Architecture

- **Entry point**: `Sym/SymApp.swift`.
- **UI**: `Sym/ContentView.swift` owns the SwiftUI drag/drop state, validation display, and create action.
- **Filesystem logic**: `Sym/SymlinkService.swift` validates sources/destination conflicts and creates symlinks with `FileManager.createSymbolicLink`.
- **Tests**: `SymTests/SymlinkServiceTests.swift` covers file/folder sources, batch creation, conflicts, missing sources, no partial batch creation, and absolute symlink destinations.

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
