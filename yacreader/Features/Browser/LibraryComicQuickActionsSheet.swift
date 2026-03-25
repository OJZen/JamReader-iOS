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
        onRemoveFromCurrentContext: (() -> Void)? = nil
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
        _selectedRating = State(initialValue: Self.normalizedRatingValue(from: comic.rating))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(comic.displayTitle)
                            .font(.headline)
                            .lineLimit(2)

                        Text(comic.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        FlowLayout(spacing: 8) {
                            StatusBadge(title: comic.progressText, tint: comic.read ? .green : .orange)
                            StatusBadge(title: comic.type.title, tint: .gray)

                            if comic.isFavorite {
                                StatusBadge(title: "Favorite", tint: .yellow)
                            }

                            if selectedRating > 0 {
                                StatusBadge(
                                    title: selectedRating == 1 ? "1 star" : "\(selectedRating) stars",
                                    tint: .orange
                                )
                            }

                            if !comic.bookmarkPageIndices.isEmpty {
                                StatusBadge(title: "\(comic.bookmarkPageIndices.count) bookmarks", tint: .blue)
                            }
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
            }
            .navigationTitle("Comic Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
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
}

struct LibraryComicQuickActionButton: View {
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis.circle")
                .font(compact ? .title3 : .title2)
                .foregroundStyle(.secondary)
                .padding(compact ? 4 : 6)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Comic Actions")
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
                Section {
                    Text(selectionSummary)
                        .font(.headline)
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
            .navigationTitle("Selection Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
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
