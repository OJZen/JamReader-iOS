# NavigationBar

Page header: large title, location, and clearly scoped search. Use system navigation bars and `.searchable`.

## Rules
- Top-level pages and library roots use large titles. Subfolders use the folder name as their large title, with breadcrumbs at the top of content after search (Library › … › Current); tap any level to jump. System search appears on pull-down by default; see [implementation limits](../../05-batches.md#library-and-import) for placement decisions.
- Search placeholders state scope: “Search in ‘My Comics’”. Remote directories use inline titles and a fixed location bar without search.
- Library contents use the same buttons at root and subfolders: Select + `ellipsis`. Import Here, View As, Import Comic Info, Refresh & Scan, and Library Info all live in `ellipsis`, without changing position by level.
- Other pages have at most 2 trailing buttons: one primary action, with the rest in `ellipsis`. iOS 26 groups them into glass capsules.
