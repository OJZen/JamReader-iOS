import Combine
import Foundation

@MainActor
final class LibraryOrganizationViewModel: ObservableObject, LoadableViewModel {
    @Published private(set) var collections: [LibraryOrganizationCollection] = []
    @Published private(set) var isLoading = false
    @Published var isShowingCreateSheet = false
    @Published var pendingCollectionName = ""
    @Published var selectedLabelColor: LibraryLabelColor = .blue
    @Published var alert: LibraryAlertState?

    let descriptor: LibraryDescriptor
    let sectionKind: LibraryOrganizationSectionKind

    private let databaseReader: LibraryDatabaseReader
    private let databaseWriter: LibraryDatabaseWriter
    private let storageManager: LibraryStorageManager
    private let databaseURL: URL
    private var hasLoaded = false

    init(
        descriptor: LibraryDescriptor,
        sectionKind: LibraryOrganizationSectionKind,
        databaseReader: LibraryDatabaseReader,
        databaseWriter: LibraryDatabaseWriter,
        storageManager: LibraryStorageManager
    ) {
        self.descriptor = descriptor
        self.sectionKind = sectionKind
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.storageManager = storageManager
        self.databaseURL = storageManager.databaseURL(for: descriptor)
    }

    var navigationTitle: String {
        sectionKind.navigationTitle
    }

    var summaryText: String {
        sectionKind.summaryText(count: collections.count)
    }

    var supportsLabelColorSelection: Bool {
        sectionKind == .labels
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        load()
    }

    func load() {
        guard !isLoading else {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            let snapshot = try databaseReader.loadOrganizationSnapshot(databaseURL: databaseURL)
            collections = snapshot.collections(for: sectionKind)
        } catch {
            collections = []
            alert = LibraryAlertState(
                title: "Failed to Load \(sectionKind.title)",
                message: error.localizedDescription
            )
        }
    }

    func presentCreateSheet() {
        pendingCollectionName = ""
        selectedLabelColor = .blue
        isShowingCreateSheet = true
    }

    func dismissCreateSheet() {
        isShowingCreateSheet = false
    }

    func createCollection() {
        let trimmedName = pendingCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            alert = LibraryAlertState(
                title: "Name Required",
                message: "Enter a name before creating a new \(sectionKind == .labels ? "tag" : "reading list")."
            )
            return
        }

        do {
            switch sectionKind {
            case .labels:
                try databaseWriter.createLabel(
                    named: trimmedName,
                    color: selectedLabelColor,
                    in: databaseURL
                )
            case .readingLists:
                try databaseWriter.createReadingList(
                    named: trimmedName,
                    in: databaseURL
                )
            }

            isShowingCreateSheet = false
            load()
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Create \(sectionKind == .labels ? "Tag" : "Reading List")",
                message: error.localizedDescription
            )
        }
    }

    func updateCollection(
        _ collection: LibraryOrganizationCollection,
        name: String,
        labelColor: LibraryLabelColor?
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            alert = LibraryAlertState(
                title: "Name Required",
                message: "Enter a name before saving this \(collection.type == .label ? "tag" : "reading list")."
            )
            return false
        }

        if collections.contains(where: {
            $0.id != collection.id && $0.displayTitle.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            alert = LibraryAlertState(
                title: "Name Already Used",
                message: trimmedName
            )
            return false
        }

        do {
            switch collection.type {
            case .label:
                try databaseWriter.updateLabel(
                    id: collection.id,
                    named: trimmedName,
                    color: labelColor ?? collection.labelColor ?? .blue,
                    in: databaseURL
                )
            case .readingList:
                try databaseWriter.updateReadingList(
                    id: collection.id,
                    named: trimmedName,
                    in: databaseURL
                )
            }

            collections = collections.map { currentCollection in
                guard currentCollection.id == collection.id else {
                    return currentCollection
                }

                return currentCollection.updatingDetails(
                    name: trimmedName,
                    labelColor: labelColor
                )
            }
            return true
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update \(collection.type == .label ? "Tag" : "Reading List")",
                message: error.localizedDescription
            )
            return false
        }
    }

    func deleteCollection(_ collection: LibraryOrganizationCollection) -> Bool {
        do {
            switch collection.type {
            case .label:
                try databaseWriter.deleteLabel(
                    id: collection.id,
                    in: databaseURL
                )
            case .readingList:
                try databaseWriter.deleteReadingList(
                    id: collection.id,
                    in: databaseURL
                )
            }

            collections.removeAll { $0.id == collection.id }
            return true
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Delete \(collection.type == .label ? "Tag" : "Reading List")",
                message: error.localizedDescription
            )
            return false
        }
    }
}
