import Combine
import SwiftUI

enum BatchOrganizationMode: String, CaseIterable, Identifiable {
    case add
    case remove

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .add:
            return "Add"
        case .remove:
            return "Remove"
        }
    }

    var description: String {
        switch self {
        case .add:
            return "Add the selected comics to tags and reading lists."
        case .remove:
            return "Remove the selected comics from tags and reading lists."
        }
    }

    var actionTint: Color {
        switch self {
        case .add:
            return .blue
        case .remove:
            return .red
        }
    }

    var isAssigned: Bool {
        switch self {
        case .add:
            return true
        case .remove:
            return false
        }
    }
}

enum BatchComicInfoImportScope {
    case selected
    case visible

    func summaryText(for comicCount: Int) -> String {
        let label: String
        switch self {
        case .selected:
            label = comicCount == 1 ? "1 selected comic" : "\(comicCount) selected comics"
        case .visible:
            label = comicCount == 1 ? "1 visible comic" : "\(comicCount) visible comics"
        }

        return "\(label). Embedded ComicInfo.xml metadata will be imported from supported archives."
    }
}

@MainActor
final class BatchComicOrganizationSheetViewModel: ObservableObject {
    @Published private(set) var snapshot: LibraryOrganizationSnapshot = .empty
    @Published private(set) var isLoading = false
    @Published var mode: BatchOrganizationMode = .add
    @Published var alert: LibraryAlertState?

    let selectedComicCount: Int

    private let selectedComicIDs: [Int64]
    private let databaseReader: LibraryDatabaseReader
    private let databaseWriter: LibraryDatabaseWriter
    private let storageManager: LibraryStorageManager
    private let databaseURL: URL
    private var hasLoaded = false

    init(
        descriptor: LibraryDescriptor,
        comicIDs: [Int64],
        databaseReader: LibraryDatabaseReader,
        databaseWriter: LibraryDatabaseWriter,
        storageManager: LibraryStorageManager
    ) {
        self.selectedComicIDs = Array(Set(comicIDs))
        self.selectedComicCount = Set(comicIDs).count
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.storageManager = storageManager
        self.databaseURL = storageManager.databaseURL(for: descriptor)
    }

    var labels: [LibraryOrganizationCollection] {
        snapshot.labels
    }

    var readingLists: [LibraryOrganizationCollection] {
        snapshot.readingLists
    }

    var summaryText: String {
        let comicsText = selectedComicCount == 1 ? "1 selected comic" : "\(selectedComicCount) selected comics"
        return "\(comicsText). \(mode.description)"
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
            snapshot = try databaseReader.loadOrganizationSnapshot(databaseURL: databaseURL)
        } catch {
            snapshot = .empty
            alert = LibraryAlertState(
                title: "Failed to Load Organization",
                message: error.localizedDescription
            )
        }
    }

    func applyMode(to collection: LibraryOrganizationCollection) -> Bool {
        guard !selectedComicIDs.isEmpty else {
            return false
        }

        do {
            switch collection.type {
            case .label:
                try databaseWriter.setLabelMembership(
                    mode.isAssigned,
                    comicIDs: selectedComicIDs,
                    labelID: collection.id,
                    in: databaseURL
                )
            case .readingList:
                try databaseWriter.setReadingListMembership(
                    mode.isAssigned,
                    comicIDs: selectedComicIDs,
                    readingListID: collection.id,
                    in: databaseURL
                )
            }

            return true
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update Organization",
                message: error.localizedDescription
            )
            return false
        }
    }
}

struct BatchComicOrganizationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: BatchComicOrganizationSheetViewModel

    private let onCommit: () -> Void

    init(
        descriptor: LibraryDescriptor,
        comicIDs: [Int64],
        dependencies: AppDependencies,
        onCommit: @escaping () -> Void
    ) {
        self.onCommit = onCommit
        _viewModel = StateObject(
            wrappedValue: BatchComicOrganizationSheetViewModel(
                descriptor: descriptor,
                comicIDs: comicIDs,
                databaseReader: dependencies.libraryDatabaseReader,
                databaseWriter: dependencies.libraryDatabaseWriter,
                storageManager: dependencies.libraryStorageManager
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading Organization")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Batch Organize")
                                    .font(.headline)

                                Text(viewModel.summaryText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Picker("Mode", selection: $viewModel.mode) {
                                    ForEach(BatchOrganizationMode.allCases) { mode in
                                        Text(mode.title)
                                            .tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            .padding(.vertical, 8)
                        }

                        Section("Tags") {
                            if viewModel.labels.isEmpty {
                                Text("No tags yet. Create one from the library root.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(viewModel.labels) { collection in
                                    Button {
                                        applyMode(to: collection)
                                    } label: {
                                        LibraryOrganizationCollectionRow(
                                            collection: collection,
                                            trailingLabel: viewModel.mode.title,
                                            trailingTint: viewModel.mode.actionTint
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Section("Reading Lists") {
                            if viewModel.readingLists.isEmpty {
                                Text("No reading lists yet. Create one from the library root.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(viewModel.readingLists) { collection in
                                    Button {
                                        applyMode(to: collection)
                                    } label: {
                                        LibraryOrganizationCollectionRow(
                                            collection: collection,
                                            trailingLabel: viewModel.mode.title,
                                            trailingTint: viewModel.mode.actionTint
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Organize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            viewModel.loadIfNeeded()
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func applyMode(to collection: LibraryOrganizationCollection) {
        if viewModel.applyMode(to: collection) {
            onCommit()
            dismiss()
        }
    }
}

@MainActor
final class BatchComicMetadataSheetViewModel: ObservableObject {
    @Published var patch = BatchComicMetadataPatch()
    @Published private(set) var isSaving = false
    @Published var alert: LibraryAlertState?

    let selectedComicCount: Int

    private let selectedComicIDs: [Int64]
    private let databaseWriter: LibraryDatabaseWriter
    private let databaseURL: URL

    init(
        descriptor: LibraryDescriptor,
        comicIDs: [Int64],
        databaseWriter: LibraryDatabaseWriter,
        storageManager: LibraryStorageManager
    ) {
        self.selectedComicIDs = Array(Set(comicIDs))
        self.selectedComicCount = Set(comicIDs).count
        self.databaseWriter = databaseWriter
        self.databaseURL = storageManager.databaseURL(for: descriptor)
    }

    var summaryText: String {
        let comicsText = selectedComicCount == 1 ? "1 selected comic" : "\(selectedComicCount) selected comics"
        return "\(comicsText). Enable the fields you want to overwrite."
    }

    var helperText: String {
        "Enabled fields will be applied to every selected comic. Leaving a text field empty will clear that value, and Rating supports Unrated or 1-5 stars."
    }

    var canApply: Bool {
        patch.hasChanges && !selectedComicIDs.isEmpty && !isSaving
    }

    func apply() -> Bool {
        guard canApply else {
            return false
        }

        isSaving = true
        defer {
            isSaving = false
        }

        do {
            try databaseWriter.updateComicMetadata(
                patch,
                for: selectedComicIDs,
                in: databaseURL
            )
            return true
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update Metadata",
                message: error.localizedDescription
            )
            return false
        }
    }
}

struct BatchComicMetadataSheet: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: BatchComicMetadataSheetViewModel

    private let onCommit: () -> Void

    init(
        descriptor: LibraryDescriptor,
        comicIDs: [Int64],
        dependencies: AppDependencies,
        onCommit: @escaping () -> Void
    ) {
        self.onCommit = onCommit
        _viewModel = StateObject(
            wrappedValue: BatchComicMetadataSheetViewModel(
                descriptor: descriptor,
                comicIDs: comicIDs,
                databaseWriter: dependencies.libraryDatabaseWriter,
                storageManager: dependencies.libraryStorageManager
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Batch Metadata")
                            .font(.headline)

                        Text(viewModel.summaryText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(viewModel.helperText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("Classification") {
                    BatchMetadataFieldToggle(title: "Type", isEnabled: $viewModel.patch.shouldUpdateType) {
                        Picker("Type", selection: $viewModel.patch.type) {
                            ForEach(LibraryFileType.allCases) { type in
                                Text(type.title).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    BatchMetadataFieldToggle(title: "Rating", isEnabled: $viewModel.patch.shouldUpdateRating) {
                        Picker("Rating", selection: $viewModel.patch.rating) {
                            Text("Unrated").tag(0)
                            ForEach(1...5, id: \.self) { value in
                                Text(value == 1 ? "1 Star" : "\(value) Stars")
                                    .tag(value)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    BatchMetadataFieldToggle(title: "Series", isEnabled: $viewModel.patch.shouldUpdateSeries) {
                        TextField("Series", text: $viewModel.patch.series)
                    }

                    BatchMetadataFieldToggle(title: "Volume", isEnabled: $viewModel.patch.shouldUpdateVolume) {
                        TextField("Volume", text: $viewModel.patch.volume)
                    }

                    BatchMetadataFieldToggle(title: "Story Arc", isEnabled: $viewModel.patch.shouldUpdateStoryArc) {
                        TextField("Story Arc", text: $viewModel.patch.storyArc)
                    }
                }

                Section("Publishing") {
                    BatchMetadataFieldToggle(title: "Publisher", isEnabled: $viewModel.patch.shouldUpdatePublisher) {
                        TextField("Publisher", text: $viewModel.patch.publisher)
                    }

                    BatchMetadataFieldToggle(title: "Language ISO", isEnabled: $viewModel.patch.shouldUpdateLanguageISO) {
                        TextField("Language ISO", text: $viewModel.patch.languageISO)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }

                    BatchMetadataFieldToggle(title: "Format", isEnabled: $viewModel.patch.shouldUpdateFormat) {
                        TextField("Format", text: $viewModel.patch.format)
                    }
                }

                Section("Tags") {
                    BatchMetadataFieldToggle(title: "Tags", isEnabled: $viewModel.patch.shouldUpdateTags) {
                        TextField("Tags", text: $viewModel.patch.tags, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
            }
            .navigationTitle("Batch Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if viewModel.apply() {
                            onCommit()
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.canApply)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(viewModel.isSaving)
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

@MainActor
final class BatchComicInfoImportSheetViewModel: ObservableObject {
    @Published private(set) var isImporting = false
    @Published var policy: ComicInfoImportPolicy = .fillMissing
    @Published var alert: LibraryAlertState?

    let selectedComics: [LibraryComic]
    let importScope: BatchComicInfoImportScope

    private let descriptor: LibraryDescriptor
    private let comicInfoImportService: ComicInfoImportService

    init(
        descriptor: LibraryDescriptor,
        comics: [LibraryComic],
        scope: BatchComicInfoImportScope,
        comicInfoImportService: ComicInfoImportService
    ) {
        self.descriptor = descriptor
        self.selectedComics = comics
        self.importScope = scope
        self.comicInfoImportService = comicInfoImportService
    }

    var selectedComicCount: Int {
        selectedComics.count
    }

    var summaryText: String {
        importScope.summaryText(for: selectedComicCount)
    }

    var helperText: String {
        switch policy {
        case .fillMissing:
            return "Comics without embedded ComicInfo.xml will be skipped. Existing non-empty library fields stay untouched, while empty fields are filled from XML."
        case .overwriteExisting:
            return "Comics without embedded ComicInfo.xml will be skipped. Existing fields in the library will be overwritten by imported values."
        }
    }

    func apply() async -> ComicInfoImportBatchResult? {
        guard !selectedComics.isEmpty, !isImporting else {
            return nil
        }

        isImporting = true
        defer {
            isImporting = false
        }

        do {
            return try await comicInfoImportService.importEmbeddedComicInfo(
                for: descriptor,
                comics: selectedComics,
                policy: policy
            )
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Import ComicInfo",
                message: error.localizedDescription
            )
            return nil
        }
    }
}

struct BatchComicInfoImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: BatchComicInfoImportSheetViewModel

    private let onComplete: (ComicInfoImportBatchResult) -> Void

    init(
        descriptor: LibraryDescriptor,
        comics: [LibraryComic],
        scope: BatchComicInfoImportScope,
        dependencies: AppDependencies,
        onComplete: @escaping (ComicInfoImportBatchResult) -> Void
    ) {
        self.onComplete = onComplete
        _viewModel = StateObject(
            wrappedValue: BatchComicInfoImportSheetViewModel(
                descriptor: descriptor,
                comics: comics,
                scope: scope,
                comicInfoImportService: dependencies.comicInfoImportService
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Import ComicInfo")
                            .font(.headline)

                        Text(viewModel.summaryText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(viewModel.helperText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("Import Strategy") {
                    Picker("Strategy", selection: $viewModel.policy) {
                        ForEach(ComicInfoImportPolicy.allCases) { policy in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(policy.title)
                                Text(policy.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(policy)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("What Will Be Imported") {
                    Text("Title, series, issue number, volume, story arc, credits, publisher, format, language, characters, teams, locations, review and tags.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("ComicInfo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isImporting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isImporting {
                        ProgressView()
                    } else {
                        Button("Import") {
                            Task {
                                if let result = await viewModel.apply() {
                                    onComplete(result)
                                    dismiss()
                                }
                            }
                        }
                        .disabled(viewModel.selectedComics.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(viewModel.isImporting)
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

private struct BatchMetadataFieldToggle<Editor: View>: View {
    let title: String
    @Binding var isEnabled: Bool
    @ViewBuilder let editor: () -> Editor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(title, isOn: $isEnabled)

            if isEnabled {
                editor()
                    .padding(.leading, 4)
            }
        }
        .padding(.vertical, 2)
    }
}
