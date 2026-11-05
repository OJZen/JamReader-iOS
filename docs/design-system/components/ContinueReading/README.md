# ContinueReading

Continue Reading uses covers, names, and progress to help users resume.

## Structure

- The local hero card uses an 84pt cover, title, progress, and Continue hint. The whole card is one button without a second tap target.
- Other comics in the home summary use a horizontal strip with `size-shelf-cover` cover widths. Cards identify the source library; a hero card within a library does not repeat its source name.
- All to the right of the section title opens the Continue Reading page. Long library names may truncate in the strip; the hero card has a separate source line.

## Placement and Scope

- Settings → Library → Show Continue Reading offers two choices: combined on Library Home by default, or at each library root. It appears in only one location at a time. At regular width, the home sidebar's Continue Reading row opens the combined page.
- All within a library reuses the single-library collection page. All on home groups by library and offers only reading and Show in Library. See [implementation decisions](../../05-batches.md#library-and-import) for reasons and cover limits.
- Server details use their own remote-history strip, unaffected by local placement settings.
- See [local-library capabilities](../../../design-requirements.md#local-libraries) for the Continue Reading definition, query limits, and cross-comic scope.

Do not merge local and remote progress or claim progress sync after import. Tapping a comic enters the reader; exiting preserves the original location.
