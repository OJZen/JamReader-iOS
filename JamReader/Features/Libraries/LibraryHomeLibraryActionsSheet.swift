import SwiftUI

/// Rename form shared by the Library Info sheet and its standalone sheet.
struct LibraryRenameForm: View {
    @Environment(\.dismiss) private var dismiss

    let item: LibraryListItem
    let onSave: (String) -> Bool

    @State private var proposedName: String
    @FocusState private var isFocused: Bool

    init(item: LibraryListItem, onSave: @escaping (String) -> Bool) {
        self.item = item
        self.onSave = onSave
        _proposedName = State(initialValue: item.descriptor.name)
    }

    var body: some View {
        Form {
            Section {
                TextField("Library name", text: $proposedName)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
            } footer: {
                Text("Only changes the name in the app.")
            }
        }
        .navigationTitle("Rename")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .onAppear {
            isFocused = true
        }
    }

    private var trimmedName: String {
        proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedName.isEmpty, onSave(proposedName) else {
            return
        }
        dismiss()
    }
}

struct LibraryRenameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: LibraryListItem
    let onSave: (String) -> Bool

    var body: some View {
        NavigationStack {
            LibraryRenameForm(item: item, onSave: onSave)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
        }
        .adaptiveSheetWidth(520)
        .presentationDetents([.medium])
    }
}

/// Name form for a new, empty in-app library.
struct LibraryCreateForm: View {
    let onCreate: (String) -> Bool

    @State private var proposedName = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Library name", text: $proposedName, prompt: Text("Weekend Reads"))
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(create)
            } header: {
                Text("Name")
            } footer: {
                Text("A new in-app library is created on this device. Import comics into it afterwards.")
            }
        }
        .navigationTitle("New Empty Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Create", action: create)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .onAppear {
            isFocused = true
        }
    }

    private var trimmedName: String {
        proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() {
        guard !trimmedName.isEmpty else {
            return
        }
        _ = onCreate(proposedName)
    }
}

struct LibraryCreateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onCreate: (String) -> Bool

    var body: some View {
        NavigationStack {
            LibraryCreateForm(onCreate: onCreate)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
        }
        .adaptiveSheetWidth(520)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

/// Library Info: name, storage, access, last scan and removal in one place.
/// Opened from the library page More menu and from a library row's long press.
struct LibraryInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var listViewModel: LibraryListViewModel
    let libraryID: UUID
    var onRemoved: () -> Void = {}

    @State private var pendingRemoval: LibraryRemovalRequest?

    private var item: LibraryListItem? {
        listViewModel.items.first { $0.id == libraryID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let item {
                    form(for: item)
                } else {
                    ContentUnavailableView(
                        "Library Unavailable",
                        systemImage: "books.vertical",
                        description: Text("This library is no longer available on this device.")
                    )
                }
            }
            .navigationTitle("Library Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .adaptiveFormSheet(720)
        .presentationDragIndicator(.visible)
        .confirmationDialog(
            pendingRemoval?.title ?? "",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingRemoval = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { request in
            Button(request.actionTitle, role: .destructive) {
                pendingRemoval = nil
                AppHaptics.warning()
                if listViewModel.removeLibraries(ids: request.items.map(\.id)) {
                    dismiss()
                    onRemoved()
                }
            }
        } message: { request in
            Text(request.message)
        }
    }

    private func form(for item: LibraryListItem) -> some View {
        Form {
            Section {
                NavigationLink {
                    LibraryRenameForm(item: item) { proposedName in
                        listViewModel.renameLibrary(id: item.id, to: proposedName)
                    }
                } label: {
                    LabeledContent("Name", value: item.descriptor.displayName)
                }
            }

            Section("Storage") {
                LabeledContent("Type", value: item.descriptor.kind.title)
                LabeledContent("Contents", value: item.contentsSummary)
                // Only a linked folder has a location the person chose and can find in Files.
                if item.descriptor.kind == .linkedFolder {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Location")
                        Text(item.descriptor.sourcePath)
                            .font(AppFont.footnote())
                            .foregroundStyle(Color.textSecondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, Spacing.xxxs)
                } else {
                    LabeledContent("Location", value: item.descriptor.kind.storageDescription)
                }
            }

            accessSection(for: item)

            if let record = item.maintenanceRecord {
                Section {
                    LabeledContent(record.localizedTitle, value: record.formattedTimestampLine)
                } header: {
                    Text("Last Scan")
                } footer: {
                    let detailText = record.detailLine ?? record.summary.summaryLine
                    if !detailText.isEmpty {
                        Text(detailText)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    pendingRemoval = LibraryRemovalRequest(items: [item])
                } label: {
                    Label(item.removalButtonTitle, systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func accessSection(for item: LibraryListItem) -> some View {
        let access = item.accessSnapshot
        Section {
            if let status = item.accessStatus {
                StatusBadge(status: status)
                    .padding(.vertical, Spacing.xxxs)
            } else {
                LabeledContent("Status", value: String(localized: "Read & Write"))
            }
        } header: {
            Text("Access")
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                switch item.accessStatus {
                case .needsReauthorization:
                    // The app has no in-place reauthorization yet, so this only explains.
                    Text("JamReader can’t open this folder. It may have been moved or renamed, or its permission expired. The library and reading progress are kept.")
                case .readOnly:
                    Text("Comics in this folder can be read, but JamReader can’t import into it or delete from it.")
                default:
                    EmptyView()
                }

                if let error = access.lastError ?? access.database.lastError {
                    Text(error)
                }
            }
        }
    }
}

/// Removal and deletion wording follows docs/design-system/02-architecture.md.
struct LibraryRemovalRequest {
    let items: [LibraryListItem]

    private var managedCount: Int {
        items.count { $0.descriptor.kind.isManagedByApp }
    }

    var title: String {
        if items.count == 1 {
            return managedCount == 1
                ? String(localized: "Delete Library from Device?")
                : String(localized: "Remove Library from App?")
        }

        return managedCount == items.count
            ? String(localized: "Delete Libraries from Device?")
            : String(localized: "Remove Libraries?")
    }

    var actionTitle: String {
        if items.count == 1 {
            return managedCount == 1
                ? String(localized: "Delete from Device")
                : String(localized: "Remove from App")
        }

        return managedCount == items.count
            ? String(localized: "Delete \(items.count) Libraries")
            : String(localized: "Remove \(items.count) Libraries")
    }

    var message: String {
        if items.count == 1, let item = items.first {
            if item.descriptor.kind.isManagedByApp {
                return String(
                    localized: "This permanently deletes \(item.descriptor.displayName) and its files from this device."
                )
            }

            return String(
                localized: "This removes \(item.descriptor.displayName) from JamReader. Files remain in the original folder."
            )
        }

        if managedCount == items.count {
            return String(localized: "This permanently deletes the selected libraries and their files from this device.")
        }

        if managedCount == 0 {
            return String(localized: "This removes the selected libraries from JamReader. Files remain in their original folders.")
        }

        return String(localized: "App-managed library files will be deleted from this device. Files in linked folders will remain in place.")
    }
}

extension LibraryListItem {
    var removalActionTitle: String {
        descriptor.kind.isManagedByApp
            ? String(localized: "Delete")
            : String(localized: "Remove")
    }

    var removalButtonTitle: String {
        descriptor.kind.isManagedByApp
            ? String(localized: "Delete Library…")
            : String(localized: "Remove Library…")
    }

    /// Read-only or lost access, shown with `StatusBadge`; `nil` when usable.
    var accessStatus: StatusBadge.Status? {
        if !accessSnapshot.sourceExists || !accessSnapshot.sourceReadable {
            return .needsReauthorization
        }
        if !accessSnapshot.sourceWritable {
            return .readOnly
        }
        return nil
    }

    /// "312 comics · 24 folders", or that the library is not indexed yet.
    var contentsSummary: String {
        let database = accessSnapshot.database
        guard database.exists else {
            return String(localized: "Not indexed yet")
        }

        let comics = database.comicCount == 1
            ? String(localized: "1 comic")
            : String(localized: "\(database.comicCount) comics")
        let folders = database.folderCount == 1
            ? String(localized: "1 folder")
            : String(localized: "\(database.folderCount) folders")
        return "\(comics) · \(folders)"
    }

    /// "312 comics · In-app library" for the library list.
    var storageSummary: String {
        let countText: String
        if accessSnapshot.database.exists {
            let comics = accessSnapshot.database.comicCount
            countText = comics == 1
                ? String(localized: "1 comic")
                : String(localized: "\(comics) comics")
        } else {
            countText = String(localized: "Not indexed yet")
        }

        return "\(countText) · \(descriptor.kind.storageDescription)"
    }
}

extension LibraryKind {
    /// Where the files live, in the fixed vocabulary of the design system.
    var storageDescription: String {
        switch self {
        case .appManaged:
            return String(localized: "In App")
        case .linkedFolder:
            return String(localized: "Folder in Files")
        case .importedComics:
            return String(localized: "Default Import Location")
        }
    }
}

/// The shared library list for pages that manage a library outside the home list.
private struct LibraryListViewModelKey: EnvironmentKey {
    static let defaultValue: LibraryListViewModel? = nil
}

extension EnvironmentValues {
    var libraryListViewModel: LibraryListViewModel? {
        get { self[LibraryListViewModelKey.self] }
        set { self[LibraryListViewModelKey.self] = newValue }
    }
}
