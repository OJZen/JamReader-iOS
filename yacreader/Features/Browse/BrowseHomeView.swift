import SwiftUI

struct BrowseHomeView: View {
    let dependencies: AppDependencies

    @StateObject private var viewModel: RemoteServerListViewModel
    @State private var editorDraft: RemoteServerEditorDraft?
    @State private var pendingDeletionProfile: RemoteServerProfile?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(
            wrappedValue: RemoteServerListViewModel(
                profileStore: dependencies.remoteServerProfileStore,
                folderShortcutStore: dependencies.remoteFolderShortcutStore,
                credentialStore: dependencies.remoteServerCredentialStore,
                browsingService: dependencies.remoteServerBrowsingService,
                readingProgressStore: dependencies.remoteReadingProgressStore
            )
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.profiles.isEmpty {
                    ContentUnavailableView(
                        "No SMB Servers",
                        systemImage: "server.rack",
                        description: Text("Tap + to add an SMB server and start browsing remote comics.")
                    )
                    .padding(.vertical, 36)
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(viewModel.profiles) { profile in
                            NavigationLink {
                                RemoteServerDetailView(
                                    profile: profile,
                                    dependencies: dependencies
                                )
                            } label: {
                                RemoteServerRow(
                                    profile: profile,
                                    latestSession: viewModel.latestSession(for: profile),
                                    savedFolderCount: viewModel.shortcutCount(for: profile),
                                    offlineCopyCount: viewModel.cacheSummary(for: profile).fileCount
                                )
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    editorDraft = viewModel.makeEditDraft(for: profile)
                                } label: {
                                    Label("Edit", systemImage: "square.and.pencil")
                                }
                                .tint(.blue)

                                Button(role: .destructive) {
                                    pendingDeletionProfile = profile
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorDraft = viewModel.makeCreateDraft()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add SMB Server")
                }
            }
            .task {
                viewModel.loadIfNeeded()
            }
            .onAppear {
                viewModel.load()
            }
            .refreshable {
                viewModel.load()
            }
            .sheet(item: $editorDraft) { draft in
                RemoteServerEditorSheet(draft: draft) { updatedDraft in
                    let result = viewModel.save(draft: updatedDraft)
                    if case .success = result {
                        editorDraft = nil
                    }
                    return result
                }
            }
            .alert(item: $viewModel.alert) { alert in
                makeRemoteAlert(for: alert)
            }
            .confirmationDialog(
                "Delete SMB Server?",
                isPresented: Binding(
                    get: { pendingDeletionProfile != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingDeletionProfile = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                if let pendingDeletionProfile {
                    Button("Delete \(pendingDeletionProfile.name)", role: .destructive) {
                        viewModel.delete(pendingDeletionProfile)
                        self.pendingDeletionProfile = nil
                    }
                }

                Button("Cancel", role: .cancel) {
                    pendingDeletionProfile = nil
                }
            } message: {
                if let pendingDeletionProfile {
                    Text("This removes \(pendingDeletionProfile.name) and clears its local offline data on this device.")
                }
            }
        }
    }
}
