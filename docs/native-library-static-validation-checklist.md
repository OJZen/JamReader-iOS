# Native Library Static Validation Checklist

Use this checklist after changes to the app-owned library database layer when no XCTest target is available.

## Build

- Run:

```bash
xcodebuild -project yacreader.xcodeproj -scheme yacreader -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .xcodebuild build
```

- Expect `BUILD SUCCEEDED`.

## Legacy Compatibility Sweep

- Run:

```bash
rg -n "library\\.ydb|\\.yacreaderlibrary|storageMode|Desktop Compatible|Browse Only|mirrored" yacreader
```

- Expect no runtime compatibility hits.
- The only acceptable result is the scanner ignore rule for historical `.yacreaderlibrary` residue.

## Library Isolation Sweep

- Run:

```bash
rg -n "WHERE id = \\?|DELETE FROM [a-z_]+ WHERE id = \\?|UPDATE [a-z_]+.*WHERE id = \\?" yacreader/Data/Libraries/NativeLibraryState.swift
```

- Verify mutating SQL in `NativeLibraryState.swift` is scoped with `library_id`.
- Verify helper queries that intentionally use raw `id` are read-only and validated by active library context.

## Foreign Key Safety

- Confirm `AppLibraryDatabase.withConnection` executes `PRAGMA foreign_keys = ON` for every connection.
- Confirm delete paths that rely on cascade still go through `withConnection`.

## High-Risk Manual Scenarios

- Delete a comic and verify tag counts and reading list counts drop with it.
- Remove a library and verify DB rows and asset directories are cleaned up.
- Try mutating a comic, tag, or reading list with an ID from another library and verify the operation is rejected.
- Corrupt or block database access and verify the library list surfaces an error instead of showing an empty library list.
