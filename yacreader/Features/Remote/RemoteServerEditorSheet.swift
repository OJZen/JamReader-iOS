import SwiftUI

struct RemoteServerEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let onSave: (RemoteServerEditorDraft) -> AppAlertState?
    private let appliesSwiftUIPresentationModifiers: Bool

    @State private var draft: RemoteServerEditorDraft
    @State private var alert: AppAlertState?
    @State private var containerWidth: CGFloat = 0
    @FocusState private var isNameFieldFocused: Bool

    init(
        draft: RemoteServerEditorDraft,
        appliesSwiftUIPresentationModifiers: Bool = true,
        onSave: @escaping (RemoteServerEditorDraft) -> AppAlertState?
    ) {
        self.appliesSwiftUIPresentationModifiers = appliesSwiftUIPresentationModifiers
        self.onSave = onSave
        _draft = State(initialValue: draft)
    }

    var body: some View {
        let content = NavigationStack {
            editorForm
                .navigationTitle(draft.navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { sheetToolbar }
        }
        .readContainerWidth(into: $containerWidth)
        .alert(item: $alert) { alert in
            makeRemoteAlert(for: alert)
        }
        .task {
            guard !Task.isCancelled else {
                return
            }

            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else {
                return
            }

            guard !usesExpandedSheetLayout else {
                return
            }

            isNameFieldFocused = true
        }
        .onChange(of: draft.providerKind) { oldValue, newValue in
            guard oldValue != newValue else {
                return
            }

            if draft.trimmedPortText.isEmpty || draft.resolvedPort == oldValue.defaultPort {
                draft.portText = String(newValue.defaultPort)
            }
        }

        if appliesSwiftUIPresentationModifiers {
            content
                .modifier(
                    RemoteServerEditorPresentationModifier(
                        horizontalSizeClass: horizontalSizeClass,
                        containerWidth: containerWidth
                    )
                )
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }

    private var usesExpandedSheetLayout: Bool {
        AppLayout.usesRegularWidthLayout(
            horizontalSizeClass: horizontalSizeClass,
            containerWidth: containerWidth
        )
    }

    private var editorForm: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $draft.providerKind) {
                    ForEach(RemoteProviderKind.allCases) { providerKind in
                        Text(providerKind.title)
                            .tag(providerKind)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                TextField("Display Name", text: $draft.name)
                    .focused($isNameFieldFocused)

                TextField("Host", text: $draft.host, prompt: Text("nas.local"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                TextField("Port", text: $draft.portText)
                    .keyboardType(.numberPad)
            } header: {
                Text("Connection")
            } footer: {
                Text(
                    draft.providerKind == .smb
                        ? (draft.usesDefaultPort
                            ? "SMB uses 445."
                            : "Use a custom port only if needed.")
                        : (draft.usesDefaultPort
                            ? "WebDAV uses 443 for HTTPS or 80 for HTTP."
                            : "Use a custom port only if needed.")
                )
            }

            Section {
                TextField(
                    draft.providerKind == .smb ? "Share" : "Server Path",
                    text: $draft.shareName,
                    prompt: Text(draft.providerKind == .smb ? "Comics" : "/remote.php/dav/files/you/Comics")
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField(
                    "Base Directory",
                    text: $draft.baseDirectoryPath,
                    prompt: Text(draft.providerKind == .smb ? "/Manga/Weekly" : "/Weekly")
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Location")
            } footer: {
                Text(
                    draft.providerKind == .smb
                        ? "Leave Base Directory empty to start at the root."
                        : "Leave Base Directory empty to start at Server Path."
                )
            }

            Section {
                Picker("Authentication", selection: $draft.authenticationMode) {
                    ForEach(RemoteServerAuthenticationMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if draft.authenticationMode.requiresUsername {
                    TextField("Username", text: $draft.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if draft.authenticationMode.requiresPassword {
                    SecureField("Password", text: $draft.password)
                        .textContentType(.password)

                    if draft.hasStoredPassword {
                        LabeledContent("Saved Password") {
                            Text(draft.savedPasswordStatusText)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Access")
            } footer: {
                if draft.authenticationMode.requiresPassword, draft.hasStoredPassword {
                    Text("Keeps the current password.")
                } else if draft.authenticationMode.requiresPassword {
                    Text("Saved in Keychain.")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                dismiss()
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button(draft.actionTitle) {
                handleSave()
            }
        }
    }

    private func handleSave() {
        if let alertState = onSave(draft) {
            alert = alertState
        }
    }
}

private struct RemoteServerEditorPresentationModifier: ViewModifier {
    let horizontalSizeClass: UserInterfaceSizeClass?
    let containerWidth: CGFloat
    @State private var selectedDetent: PresentationDetent = .large

    private var usesExpandedSheetLayout: Bool {
        AppLayout.usesRegularWidthLayout(
            horizontalSizeClass: horizontalSizeClass,
            containerWidth: containerWidth
        )
    }

    func body(content: Content) -> some View {
        if usesExpandedSheetLayout {
            if #available(iOS 18.0, *) {
                content.presentationSizing(.page)
            } else {
                content
            }
        } else {
            content.presentationDetents([.medium, .large], selection: $selectedDetent)
        }
    }
}

private extension RemoteServerEditorDraft {
    var normalizedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedPortText: String {
        portText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedPort: Int? {
        Int(trimmedPortText)
    }

    var usesDefaultPort: Bool {
        let port = resolvedPort ?? providerKind.defaultPort
        switch providerKind {
        case .smb:
            return port == RemoteProviderKind.smb.defaultPort
        case .webdav:
            let scheme = URLComponents(string: normalizedHost)?.scheme?.lowercased() ?? "https"
            let defaultPort = scheme == "http" ? 80 : 443
            return port == defaultPort
        }
    }

    var savedPasswordStatusText: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Keep current"
            : "Replace on save"
    }
}
