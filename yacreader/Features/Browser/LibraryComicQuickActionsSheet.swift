import SwiftUI

struct LibraryComicQuickActionsSheet: View {
    let comic: LibraryComic
    var removeFromContextTitle: String?
    let onDone: () -> Void
    let onEditMetadata: () -> Void
    let onToggleFavorite: () -> Void
    let onToggleReadStatus: () -> Void
    let onSetRating: (Int) -> Void
    let onOpenOrganization: () -> Void
    var onRemoveFromCurrentContext: (() -> Void)?
    var onRemoveFromLibrary: (() -> Void)?

    @State private var selectedRating: Int

    init(
        comic: LibraryComic,
        removeFromContextTitle: String? = nil,
        onDone: @escaping () -> Void,
        onEditMetadata: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onToggleReadStatus: @escaping () -> Void,
        onSetRating: @escaping (Int) -> Void,
        onOpenOrganization: @escaping () -> Void,
        onRemoveFromCurrentContext: (() -> Void)? = nil,
        onRemoveFromLibrary: (() -> Void)? = nil
    ) {
        self.comic = comic
        self.removeFromContextTitle = removeFromContextTitle
        self.onDone = onDone
        self.onEditMetadata = onEditMetadata
        self.onToggleFavorite = onToggleFavorite
        self.onToggleReadStatus = onToggleReadStatus
        self.onSetRating = onSetRating
        self.onOpenOrganization = onOpenOrganization
        self.onRemoveFromCurrentContext = onRemoveFromCurrentContext
        self.onRemoveFromLibrary = onRemoveFromLibrary
        _selectedRating = State(initialValue: Self.normalizedRatingValue(from: comic.rating))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Comic") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(comic.displayTitle)
                            .font(.headline)
                            .lineLimit(2)

                        Text(comic.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        if !comicSummaryText.isEmpty {
                            Text(comicSummaryText)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Actions") {
                    Button(action: onEditMetadata) {
                        Label("Edit Metadata", systemImage: "square.and.pencil")
                    }

                    Button(action: onOpenOrganization) {
                        Label("Tags and Reading Lists", systemImage: "tag")
                    }
                }

                Section("Status") {
                    Button(action: onToggleFavorite) {
                        Label(
                            comic.isFavorite ? "Remove Favorite" : "Add Favorite",
                            systemImage: comic.isFavorite ? "star.slash" : "star"
                        )
                    }

                    Button(action: onToggleReadStatus) {
                        Label(
                            comic.read ? "Mark Unread" : "Mark Read",
                            systemImage: comic.read ? "arrow.uturn.backward.circle" : "checkmark.circle"
                        )
                    }

                    Picker("Rating", selection: $selectedRating) {
                        Text("Unrated").tag(0)
                        ForEach(1...5, id: \.self) { value in
                            Text(value == 1 ? "1 Star" : "\(value) Stars")
                                .tag(value)
                        }
                    }
                }

                if let removeFromContextTitle, let onRemoveFromCurrentContext {
                    Section {
                        Button(role: .destructive) {
                            AppHaptics.warning()
                            onRemoveFromCurrentContext()
                        } label: {
                            Label(removeFromContextTitle, systemImage: "minus.circle")
                        }
                    }
                }

                if let onRemoveFromLibrary {
                    Section {
                        Button(role: .destructive) {
                            AppHaptics.warning()
                            onRemoveFromLibrary()
                        } label: {
                            Label("Delete Comic", systemImage: "trash")
                        }
                    } footer: {
                        Text("This removes the comic file from the library on this device.")
                    }
                }
            }
            .navigationTitle("Comic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .adaptiveSheetWidth(640)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: selectedRating) { _, newValue in
            onSetRating(newValue)
        }
    }

    private static func normalizedRatingValue(from rating: Double?) -> Int {
        guard let rating, rating > 0 else {
            return 0
        }

        return min(max(Int(rating.rounded()), 0), 5)
    }

    private var comicSummaryText: String {
        var parts: [String] = [comic.progressText]

        if let metadataText = comic.browserMetadataText {
            parts.append(metadataText)
        }

        if comic.isFavorite {
            parts.append("Favorite")
        }

        if selectedRating > 0 {
            parts.append(selectedRating == 1 ? "1 star" : "\(selectedRating) stars")
        }

        let bookmarkCount = comic.bookmarkPageIndices.count
        if bookmarkCount > 0 {
            parts.append(bookmarkCount == 1 ? "1 bookmark" : "\(bookmarkCount) bookmarks")
        }

        return parts.joined(separator: " · ")
    }
}

struct LibrarySelectionActionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selectionCount: Int
    var organizeActionTitle = "Tags and Reading Lists"
    var removeFromContextTitle: String?
    var onEditMetadata: (() -> Void)?
    var onImportComicInfo: (() -> Void)?
    var onOpenOrganization: (() -> Void)?
    let onMarkRead: () -> Void
    let onMarkUnread: () -> Void
    let onAddFavorite: () -> Void
    let onRemoveFavorite: () -> Void
    var onRemoveFromCurrentContext: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section("Selection") {
                    Text(selectionSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }

                Section("Status") {
                    actionButton(
                        title: "Mark Read",
                        systemImage: "checkmark.circle",
                        action: onMarkRead
                    )

                    actionButton(
                        title: "Mark Unread",
                        systemImage: "arrow.uturn.backward.circle",
                        action: onMarkUnread
                    )

                    actionButton(
                        title: "Add Favorite",
                        systemImage: "star",
                        action: onAddFavorite
                    )

                    actionButton(
                        title: "Remove Favorite",
                        systemImage: "star.slash",
                        action: onRemoveFavorite
                    )
                }

                if onEditMetadata != nil || onImportComicInfo != nil || onOpenOrganization != nil {
                    Section("Manage") {
                        if let onEditMetadata {
                            actionButton(
                                title: "Edit Metadata",
                                systemImage: "square.and.pencil",
                                action: onEditMetadata
                            )
                        }

                        if let onImportComicInfo {
                            actionButton(
                                title: "Import ComicInfo",
                                systemImage: "square.and.arrow.down",
                                action: onImportComicInfo
                            )
                        }

                        if let onOpenOrganization {
                            actionButton(
                                title: organizeActionTitle,
                                systemImage: "tag",
                                action: onOpenOrganization
                            )
                        }
                    }
                }

                if let removeFromContextTitle, let onRemoveFromCurrentContext {
                    Section {
                        Button(role: .destructive) {
                            AppHaptics.warning()
                            performAction(onRemoveFromCurrentContext)
                        } label: {
                            Label(removeFromContextTitle, systemImage: "minus.circle")
                        }
                    }
                }
            }
            .navigationTitle("Selection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .adaptiveSheetWidth(640)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var selectionSummary: String {
        selectionCount == 1 ? "1 comic selected" : "\(selectionCount) comics selected"
    }

    private func actionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            performAction(action)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func performAction(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.async {
            action()
        }
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: spacing) {
            content()
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
