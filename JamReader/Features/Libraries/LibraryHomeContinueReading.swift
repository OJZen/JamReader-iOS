import SwiftUI

// Continue reading aggregated across local libraries: the library-home section
// and its "All" page. See docs/design-system/components/ContinueReading.

/// The home's continue-reading block as list sections: a header with "All",
/// the main card as one row (the list cell is its surface) and the shelf as
/// a clear row. Cards name their source library because the block mixes libraries.
struct LibraryHomeContinueReadingSections: View {
    @ObservedObject var model: LibraryContinueReadingViewModel
    let onOpen: (ContinueReadingEntry, CGRect) -> Void
    let onShowAll: () -> Void
    let onShowLibrary: (ContinueReadingEntry) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let first = homeEntries.first {
            Section {
                HeroTapButton { frame in
                    onOpen(first, frame)
                } label: {
                    ContinueReadingCard(
                        comic: first.comic,
                        coverURL: model.coverURL(for: first),
                        heroSourceID: model.heroSourceID(for: first),
                        sourceLibraryName: first.library.displayName,
                        background: .clear
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    showLibraryButton(for: first)
                }
                .listRowInsets(EdgeInsets())
            } header: {
                header
            }
            // Keeps the shelf close to the main card.
            .listSectionSpacing(homeEntries.count > 1 ? Spacing.xs : Spacing.lg)

            if homeEntries.count > 1 {
                Section {
                    shelf
                        .listRowInsets(EdgeInsets(top: Spacing.xxs, leading: 0, bottom: Spacing.sm, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }
        }
    }

    private var homeEntries: ArraySlice<ContinueReadingEntry> {
        model.entries.prefix(LibraryContinueReadingAggregate.homeLimit)
    }

    private var header: some View {
        // Large text puts "All" under the title instead of breaking words.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.sm))
        return layout {
            Text("Continue Reading")
                .font(AppFont.title2(.bold))
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: Spacing.sm)
            }

            Button(action: onShowAll) {
                HStack(spacing: Spacing.xxxs) {
                    Text("All")
                    Image(systemName: "chevron.forward")
                        .font(AppFont.caption(.semibold))
                }
                .font(AppFont.subheadline())
                .foregroundStyle(Color.appAccent)
            }
            .buttonStyle(.plain)
        }
        .textCase(nil)
    }

    private var shelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: Spacing.sm) {
                ForEach(homeEntries.dropFirst()) { entry in
                    HeroTapButton { frame in
                        onOpen(entry, frame)
                    } label: {
                        ContinueReadingShelfCard(
                            comic: entry.comic,
                            coverURL: model.coverURL(for: entry),
                            heroSourceID: model.heroSourceID(for: entry),
                            sourceLibraryName: entry.library.displayName,
                            width: shelfCoverWidth
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        showLibraryButton(for: entry)
                    }
                }
            }
        }
    }

    private var shelfCoverWidth: CGFloat {
        horizontalSizeClass == .regular ? AppLayout.shelfCoverWidthRegular : AppLayout.shelfCoverWidthCompact
    }

    private func showLibraryButton(for entry: ContinueReadingEntry) -> some View {
        Button {
            onShowLibrary(entry)
        } label: {
            Label("Show in Library", systemImage: "books.vertical")
        }
    }
}

/// Shelf card: cover with progress, title, "Read to 42% · Library".
struct ContinueReadingShelfCard: View {
    let comic: LibraryComic
    let coverURL: URL?
    var heroSourceID: String? = nil
    var sourceLibraryName: String? = nil
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            LocalCoverThumbnailView(
                url: coverURL,
                placeholderSystemName: "book.closed",
                transitionKey: heroSourceID,
                heroSourceID: heroSourceID,
                width: width,
                height: width / AppLayout.coverAspectRatio
            )
            .overlay(alignment: .bottom) {
                LibraryCoverProgressBar(fraction: comic.continueReadingFraction)
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.thumbnail, style: .continuous))

            Text(comic.displayTitle)
                .font(AppFont.footnote(.medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Text(statusLine)
                .font(AppFont.caption())
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        let percent = Int((comic.continueReadingFraction * 100).rounded())
        let progress = String(localized: "Read to \(percent)%")
        guard let sourceLibraryName else {
            return progress
        }
        return "\(progress) · \(sourceLibraryName)"
    }
}

/// "All" from the home section: every in-progress comic, grouped by library.
struct LibraryContinueReadingAllView: View {
    @Environment(\.appPresenter) private var appPresenter
    @Environment(\.appNavigator) private var appNavigator
    @Environment(\.libraryListViewModel) private var libraryListViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var model: LibraryContinueReadingViewModel

    init(dependencies: AppDependencies) {
        _model = StateObject(wrappedValue: LibraryContinueReadingViewModel(dependencies: dependencies))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg, pinnedViews: []) {
                Text(subtitle)
                    .font(AppFont.subheadline().monospacedDigit())
                    .foregroundStyle(Color.textSecondary)

                if model.entries.isEmpty {
                    ContentUnavailableView(
                        LibrarySpecialCollectionKind.reading.emptyStateTitle,
                        systemImage: "book",
                        description: Text(LibrarySpecialCollectionKind.reading.emptyStateDescription)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.xxl)
                } else {
                    ForEach(model.groups, id: \.library.id) { group in
                        librarySection(group.library, entries: group.entries)
                    }
                }
            }
            .containerHorizontalMargins()
            .padding(.vertical, Spacing.sm)
        }
        .background(Color.surfacePrimary)
        .navigationTitle(String(localized: "Continue Reading"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .libraryPreferencesDidChange)) { _ in
            reload()
        }
    }

    private func librarySection(_ library: LibraryDescriptor, entries: [ContinueReadingEntry]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(library.displayName)
                    .font(AppFont.title2(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(entries.count)")
                    .font(AppFont.subheadline().monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Spacing.md) {
                ForEach(entries) { entry in
                    HeroTapButton { frame in
                        open(entry, frame: frame)
                    } label: {
                        LibraryComicCard(
                            comic: entry.comic,
                            coverURL: model.coverURL(for: entry),
                            heroSourceID: model.heroSourceID(for: entry)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            appNavigator?.navigate(.library(.openLibrary(entry.library.id, folderID: 1)))
                        } label: {
                            Label("Show in Library", systemImage: "books.vertical")
                        }
                    }
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return Array(repeating: GridItem(.flexible(), spacing: Spacing.sm, alignment: .top), count: 2)
        }
        let minimum = horizontalSizeClass == .regular ? AppLayout.gridItemMinWidth : AppLayout.gridItemMinWidthCompact
        return [GridItem(.adaptive(minimum: minimum, maximum: AppLayout.gridItemMaxWidth), spacing: Spacing.sm, alignment: .top)]
    }

    private var subtitle: String {
        let comics = model.entries.count
        let libraries = model.groups.count
        let comicText = comics == 1 ? String(localized: "1 comic") : String(localized: "\(comics) comics")
        let libraryText = libraries == 1 ? String(localized: "1 library") : String(localized: "\(libraries) libraries")
        return "\(comicText) · \(libraryText)"
    }

    private func reload() {
        model.reload(items: libraryListViewModel?.items ?? [])
    }

    private func open(_ entry: ContinueReadingEntry, frame: CGRect) {
        LibraryContinueReadingPresenter.open(
            entry,
            in: model.entries,
            sourceFrame: frame,
            heroSourceID: model.heroSourceID(for: entry),
            presenter: appPresenter,
            onComicUpdated: reload
        )
    }
}

enum LibraryContinueReadingPresenter {
    static func open(
        _ entry: ContinueReadingEntry,
        in entries: [ContinueReadingEntry],
        sourceFrame: CGRect,
        heroSourceID: String,
        presenter: UIKitPresentationCoordinator?,
        onComicUpdated: @escaping () -> Void
    ) {
        let registeredFrame = HeroSourceRegistry.shared.frame(for: heroSourceID)
        presenter?.presentReader(
            .local(
                LocalReaderPresentation(
                    descriptor: entry.library,
                    comic: entry.comic,
                    navigationContext: ReaderNavigationContext(
                        title: String(localized: "Continue Reading"),
                        comics: LibraryContinueReadingAggregate.navigationComics(for: entry, in: entries)
                    ),
                    heroSourceID: heroSourceID,
                    sourceFrame: registeredFrame == .zero ? sourceFrame : registeredFrame,
                    previewImage: LocalCoverTransitionCache.shared.image(for: heroSourceID),
                    onComicUpdated: { _ in onComicUpdated() },
                    onDismiss: nil
                )
            )
        )
    }
}
