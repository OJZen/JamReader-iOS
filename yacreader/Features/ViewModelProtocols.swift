import Foundation

/// A ViewModel that supports an `isLoading` / `loadIfNeeded()` / `load()` lifecycle.
///
/// Seven ViewModels share this exact pattern:
///  - `LibraryBrowserViewModel`
///  - `ComicReaderViewModel`
///  - `LibraryOrganizationCollectionDetailViewModel`
///  - `LibrarySpecialCollectionViewModel`
///  - `LibraryOrganizationViewModel`
///  - `ComicOrganizationSheetViewModel`
///  - `ComicMetadataEditorSheetViewModel`
///
/// `RemoteServerBrowserViewModel` uses an async variant of the same pattern and
/// does not conform here to keep the protocol simple and synchronous.
@MainActor
protocol LoadableViewModel: ObservableObject {
    /// Whether content is currently being loaded.
    var isLoading: Bool { get }

    /// Triggers a load only on the first invocation; subsequent calls are no-ops.
    func loadIfNeeded()

    /// Reloads content unconditionally (still guards against concurrent loads).
    func load()
}
