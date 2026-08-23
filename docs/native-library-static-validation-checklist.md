# Native Library Validation Checklist

Use this focused supplement after changes to the app-owned library database, indexing, import, or removal paths. Build and test commands live only in `development-workflow.md`.

## Automated Baseline

- Run the relevant library tests, normally including `LibraryScannerDatabaseTests`, `LibraryComicDeletionTransactionTests`, `LibraryComicRemovalServiceTests`, and `LibraryListViewModelPersistenceTests`.
- Run the project static guards and generic iOS build from `development-workflow.md`.
- Add a regression test for every fixed persistence, isolation, rollback, or deletion bug.

## Legacy Compatibility Sweep

- Run:

```bash
rg -n "library\\.ydb|\\.jamreaderlibrary|storageMode|Desktop Compatible|Browse Only|mirrored" JamReader
```

- Expect no runtime compatibility hits.

## Library Isolation Sweep

- Run:

```bash
rg -n "WHERE id = \\?|DELETE FROM [a-z_]+ WHERE id = \\?|UPDATE [a-z_]+.*WHERE id = \\?" JamReader/Data/Libraries
```

- Public repository mutations must validate the `libraryID` carried by the contextual database URL.
- A private indexer may mutate by raw row ID only when that ID came from the same library-scoped snapshot and transaction; document and test any new exception.
- Verify comic, folder, tag, and reading-list relationships cannot cross library boundaries.

## Foreign Key Safety

- Confirm `AppLibraryDatabase.withConnection` executes `PRAGMA foreign_keys = ON` for every connection.
- Confirm delete paths that rely on cascade still go through `withConnection`.

## High-Risk Manual Scenarios

- Delete a comic and verify tag counts and reading list counts drop with it.
- Remove a library and verify DB rows and asset directories are cleaned up.
- Try mutating a comic, tag, or reading list with an ID from another library and verify the operation is rejected.
- Corrupt or block database access and verify the library list surfaces an error instead of showing an empty library list.
