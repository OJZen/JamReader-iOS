import SwiftUI

/// The one set of actions for a local comic. The row-end More button, long
/// press and swipe all call these (see docs/design-system/components/MoreMenu).
struct LibraryComicActions {
    var toggleFavorite: (LibraryComic) -> Void
    var toggleRead: (LibraryComic) -> Void
    var organize: (LibraryComic) -> Void
    var setRating: (Int, LibraryComic) -> Void
    var editMetadata: (LibraryComic) -> Void
    var showInfo: (LibraryComic) -> Void
    /// Removes the comic from the current tag or reading list; the file stays.
    var removeFromCollection: ((LibraryComic) -> Void)?
    var removeFromCollectionTitle: String?
    /// `nil` when this library cannot delete comic files.
    var delete: ((LibraryComic) -> Void)?
}

/// Menu content: quick group, rating, edit, info, then delete set apart.
struct LibraryComicMenuContent: View {
    let comic: LibraryComic
    let actions: LibraryComicActions

    var body: some View {
        ControlGroup {
            Button {
                actions.toggleFavorite(comic)
            } label: {
                Label(
                    comic.isFavorite ? "Unfavorite" : "Favorite",
                    systemImage: comic.isFavorite ? "star.slash" : "star"
                )
            }

            Button {
                actions.toggleRead(comic)
            } label: {
                Label(
                    comic.read ? "Mark as Unread" : "Mark as Read",
                    systemImage: comic.read ? "circle" : "checkmark.circle"
                )
            }

            Button {
                actions.organize(comic)
            } label: {
                Label("Tags & Lists", systemImage: "tag")
            }
        }

        Menu {
            ForEach((1...5).reversed(), id: \.self) { value in
                Button {
                    actions.setRating(value, comic)
                } label: {
                    if currentRating == value {
                        Label(Self.ratingTitle(value), systemImage: "checkmark")
                    } else {
                        Text(Self.ratingTitle(value))
                    }
                }
            }

            Divider()

            Button {
                actions.setRating(0, comic)
            } label: {
                Text("Clear Rating")
            }
            .disabled(currentRating == 0)
        } label: {
            // Title, subtitle and icon as direct children show the subtitle in menus.
            Text("Rating")
            Text(currentRating == 0 ? String(localized: "Unrated") : Self.ratingTitle(currentRating))
            Image(systemName: "star")
        }

        Button {
            actions.editMetadata(comic)
        } label: {
            Label("Edit Metadata", systemImage: "square.and.pencil")
        }

        Button {
            actions.showInfo(comic)
        } label: {
            Label("Info", systemImage: "info.circle")
        }

        if let removeFromCollection = actions.removeFromCollection,
           let title = actions.removeFromCollectionTitle {
            Section {
                Button {
                    removeFromCollection(comic)
                } label: {
                    Text(title)
                    Text("The comic stays in the library")
                    Image(systemName: "minus.circle")
                }
            }
        }

        if let delete = actions.delete {
            Section {
                Button(role: .destructive) {
                    delete(comic)
                } label: {
                    Text("Delete Comic")
                    Text("Deletes the file from this device")
                    Image(systemName: "trash")
                }
            }
        }
    }

    private var currentRating: Int {
        guard let rating = comic.rating, rating > 0 else {
            return 0
        }
        return min(max(Int(rating.rounded()), 0), 5)
    }

    static func ratingTitle(_ value: Int) -> String {
        value == 1 ? String(localized: "1 Star") : String(localized: "\(value) Stars")
    }
}

/// 44×44 row-end More button that opens the same menu as long press.
struct LibraryComicMoreButton: View {
    let comic: LibraryComic
    let actions: LibraryComicActions

    var body: some View {
        Menu {
            LibraryComicMenuContent(comic: comic, actions: actions)
        } label: {
            PersistentRowActionButtonLabel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("More Actions for \(comic.displayTitle)"))
    }
}

extension View {
    /// Swipe shortcuts for the same actions: read state on the leading edge,
    /// favorite and delete on the trailing edge. Delete still asks first.
    func libraryComicSwipeActions(
        for comic: LibraryComic,
        actions: LibraryComicActions,
        isEnabled: Bool = true
    ) -> some View {
        self
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if isEnabled {
                    Button {
                        actions.toggleRead(comic)
                    } label: {
                        Label(
                            comic.read ? "Mark as Unread" : "Mark as Read",
                            systemImage: comic.read ? "circle" : "checkmark.circle"
                        )
                    }
                    .tint(comic.read ? Color(.systemGray) : .appSuccess)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if isEnabled {
                    if let delete = actions.delete {
                        Button(role: .destructive) {
                            delete(comic)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                    Button {
                        actions.toggleFavorite(comic)
                    } label: {
                        Label(
                            comic.isFavorite ? "Unfavorite" : "Favorite",
                            systemImage: comic.isFavorite ? "star.slash" : "star"
                        )
                    }
                    .tint(.appFavorite)
                }
            }
    }

    /// Delete confirmation that names the comic and what happens to the file.
    func libraryComicDeletionConfirmation(
        _ comic: Binding<LibraryComic?>,
        libraryKind: LibraryKind,
        onConfirm: @escaping (LibraryComic) -> Void
    ) -> some View {
        confirmationDialog(
            comic.wrappedValue.map { String(localized: "Delete “\($0.displayTitle)”?") } ?? "",
            isPresented: Binding(
                get: { comic.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        comic.wrappedValue = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: comic.wrappedValue
        ) { presentedComic in
            Button("Delete Comic", role: .destructive) {
                onConfirm(presentedComic)
            }
        } message: { _ in
            Text(LibraryComicDeletionCopy.message(for: libraryKind, count: 1))
        }
    }
}

enum LibraryComicDeletionCopy {
    /// Consequences follow docs/design-system/02-architecture.md.
    static func message(for libraryKind: LibraryKind, count: Int) -> String {
        let fileLine: String
        if libraryKind == .linkedFolder {
            fileLine = count == 1
                ? String(localized: "The file is deleted from the linked folder on this device.")
                : String(localized: "The files are deleted from the linked folder on this device.")
        } else {
            fileLine = count == 1
                ? String(localized: "The file is deleted from this device.")
                : String(localized: "The files are deleted from this device.")
        }

        return fileLine + "\n" + String(localized: "Reading progress, bookmarks, tags and reading list entries are removed too.")
    }
}

/// Read-only details for a local comic, opened from the More menu.
struct LibraryComicInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let comic: LibraryComic
    let libraryName: String
    let coverURL: URL?
    var coverSource: LocalComicCoverSource?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .padding(.vertical, Spacing.xxs)
                }

                Section("Reading") {
                    LabeledContent("Status", value: comic.coverStatusText)
                    if comic.hasBeenOpened, comic.currentPage > 0 {
                        LabeledContent("Current Page", value: "\(comic.currentPage)")
                    }
                    if let pageCount = comic.pageCount, pageCount > 0 {
                        LabeledContent("Pages", value: "\(pageCount)")
                    }
                    if !comic.bookmarkPageIndices.isEmpty {
                        LabeledContent("Bookmarks", value: "\(comic.bookmarkPageIndices.count)")
                    }
                    if let lastOpenedAt = comic.lastOpenedAt {
                        LabeledContent(
                            "Last Opened",
                            value: lastOpenedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }

                Section("File") {
                    LabeledContent("Name") {
                        Text(comic.fileName)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Type", value: comic.type.title)
                    if let fileSizeText = comic.fileSizeText {
                        LabeledContent("Size", value: fileSizeText)
                    }
                    if let addedAt = comic.addedAt {
                        LabeledContent(
                            "Added",
                            value: addedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }

                Section("Location") {
                    LabeledContent("Library", value: libraryName)
                    if let path = comic.path, !path.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Path")
                                .font(AppFont.footnote())
                                .foregroundStyle(Color.textSecondary)
                            Text(path)
                                .font(AppFont.body())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .adaptiveSheetWidth(720)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.md))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.md))

        return layout {
            LocalCoverThumbnailView(
                url: coverURL,
                fallbackSource: coverSource,
                placeholderSystemName: "book.closed",
                width: 84,
                height: 126
            )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(comic.displayTitle)
                    .font(AppFont.title3(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if comic.subtitle != comic.fileName {
                    Text(comic.subtitle)
                        .font(AppFont.subheadline())
                        .foregroundStyle(Color.textSecondary)
                }

                LibraryComicStatusLine(comic: comic)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
