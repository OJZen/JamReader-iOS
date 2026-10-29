import SwiftUI

/// Favorites, Recently Added and Continue Reading, on the shared collection page.
struct LibrarySpecialCollectionView: View {
    private let dependencies: AppDependencies

    @AppStorage(LibraryPreferencesStore.recentWindowStorageKey) private var recentWindowRawValue = LibraryRecentWindowOption.defaultOption.rawValue
    @StateObject private var viewModel: LibrarySpecialCollectionViewModel

    init(
        descriptor: LibraryDescriptor,
        kind: LibrarySpecialCollectionKind,
        dependencies: AppDependencies
    ) {
        self.dependencies = dependencies
        _viewModel = StateObject(
            wrappedValue: LibrarySpecialCollectionViewModel(
                descriptor: descriptor,
                kind: kind,
                databaseReader: dependencies.libraryDatabaseReader,
                databaseWriter: dependencies.libraryDatabaseWriter,
                storageManager: dependencies.libraryStorageManager,
                coverLocator: dependencies.libraryCoverLocator,
                comicRemovalService: dependencies.libraryComicRemovalService,
                remoteBackgroundImportController: dependencies.remoteBackgroundImportController
            )
        )
    }

    var body: some View {
        LibraryComicCollectionPage(
            model: viewModel,
            dependencies: dependencies,
            title: viewModel.kind.title,
            subtitle: LibraryCollectionCopy.subtitle(
                libraryName: viewModel.descriptor.displayName,
                comicCount: viewModel.comics.count
            ),
            emptyStateSystemImage: viewModel.kind.collectionSystemImageName,
            emptyStateTitle: viewModel.kind.emptyStateTitle,
            emptyStateDescription: viewModel.kind.emptyStateDescriptionText(recentDays: viewModel.currentRecentDays),
            sortStorageKey: "librarySpecialCollectionSortMode.\(viewModel.kind.rawValue)",
            displayStorageKey: "librarySpecialCollectionDisplayMode.\(viewModel.kind.rawValue)",
            defaultSortMode: Self.defaultSortMode(for: viewModel.kind),
            showsQuickFilters: viewModel.kind != .reading
        ) {
            if viewModel.kind == .recent {
                // The same preference as Settings › Library.
                Section {
                    Picker(selection: recentWindowBinding) {
                        ForEach(LibraryRecentWindowOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    } label: {
                        Label("Time Range", systemImage: "calendar")
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .onAppear {
            viewModel.setRecentDays(recentWindowOption.dayCount)
        }
        .onChange(of: recentWindowRawValue) { _, _ in
            viewModel.setRecentDays(recentWindowOption.dayCount)
        }
    }

    private var recentWindowOption: LibraryRecentWindowOption {
        LibraryRecentWindowOption(rawValue: recentWindowRawValue) ?? .defaultOption
    }

    private var recentWindowBinding: Binding<LibraryRecentWindowOption> {
        Binding(
            get: { recentWindowOption },
            set: { recentWindowRawValue = $0.rawValue }
        )
    }

    private static func defaultSortMode(for kind: LibrarySpecialCollectionKind) -> LibraryComicSortMode {
        switch kind {
        case .reading:
            return .recentlyOpened
        case .favorites:
            return .sourceOrder
        case .recent:
            return .recentlyAdded
        }
    }
}

enum LibraryCollectionCopy {
    /// "My Comics · 24 comics" under a collection title.
    static func subtitle(libraryName: String, comicCount: Int) -> String {
        let countText = comicCount == 1
            ? String(localized: "1 comic")
            : String(localized: "\(comicCount) comics")
        return "\(libraryName) · \(countText)"
    }
}
