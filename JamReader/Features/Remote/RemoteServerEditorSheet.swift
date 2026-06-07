import SwiftUI

struct RemoteServerEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let onSave: (RemoteServerEditorDraft) -> AppAlertState?
    private let appliesSwiftUIPresentationModifiers: Bool

    @State private var draft: RemoteServerEditorDraft
    @State private var alert: AppAlertState?
    @State private var containerWidth: CGFloat = 0
    @State private var isShowingInputHelp = false
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
        .alert(inputHelpTitle, isPresented: $isShowingInputHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(inputHelpMessage)
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
                TextField("Display Name", text: $draft.name, prompt: Text(displayNamePrompt))
                    .focused($isNameFieldFocused)

                TextField(hostFieldTitle, text: $draft.host, prompt: Text(hostPrompt))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                TextField("Port", text: $draft.portText, prompt: Text(portPrompt))
                    .keyboardType(.numberPad)
            } header: {
                Text("Connection")
            } footer: {
                Text(connectionFooter)
            }

            Section {
                TextField(
                    providerRootFieldTitle,
                    text: $draft.shareName,
                    prompt: Text(providerRootPrompt)
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField(
                    "Start Folder",
                    text: $draft.baseDirectoryPath,
                    prompt: Text(startFolderPrompt)
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Location")
            } footer: {
                Text(locationFooter)
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

        ToolbarItem(placement: .topBarLeading) {
            Button {
                isShowingInputHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .accessibilityLabel("Server Field Help")
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

    private var displayNamePrompt: String {
        switch draft.providerKind {
        case .smb:
            return "Home NAS"
        case .webdav:
            return "Cloud Comics"
        }
    }

    private var hostFieldTitle: String {
        switch draft.providerKind {
        case .smb:
            return "Server Address"
        case .webdav:
            return "Server URL"
        }
    }

    private var hostPrompt: String {
        switch draft.providerKind {
        case .smb:
            return "nas.local or 192.168.1.20"
        case .webdav:
            return "https://cloud.example.com"
        }
    }

    private var portPrompt: String {
        String(draft.providerKind.defaultPort)
    }

    private var providerRootFieldTitle: String {
        switch draft.providerKind {
        case .smb:
            return "Share Name"
        case .webdav:
            return "WebDAV Path"
        }
    }

    private var providerRootPrompt: String {
        switch draft.providerKind {
        case .smb:
            return "Comics"
        case .webdav:
            return "/remote.php/dav/files/you/Comics"
        }
    }

    private var startFolderPrompt: String {
        switch draft.providerKind {
        case .smb:
            return "/Manga/Weekly"
        case .webdav:
            return "/Weekly"
        }
    }

    private var connectionFooter: String {
        switch draft.providerKind {
        case .smb:
            return draft.usesDefaultPort
                ? "Address only. Share and start folder go below."
                : "Use a custom port only if your SMB server does not use 445."
        case .webdav:
            return draft.usesDefaultPort
                ? "Use https://. Use http:// only for local servers that require it."
                : "Use a custom port only if your WebDAV server does not use 443 or 80."
        }
    }

    private var locationFooter: String {
        switch draft.providerKind {
        case .smb:
            return "Leave Start Folder empty to open the share root."
        case .webdav:
            return "Leave Start Folder empty to open the WebDAV path."
        }
    }

    private var inputHelpTitle: String {
        switch draft.providerKind {
        case .smb:
            return "SMB Field Help"
        case .webdav:
            return "WebDAV Field Help"
        }
    }

    private var inputHelpMessage: String {
        switch draft.providerKind {
        case .smb:
            return """
            Paste smb://nas.local/Comics/Manga into Server Address, or split it as:
            Server Address: nas.local
            Share Name: Comics
            Start Folder: /Manga
            """
        case .webdav:
            return """
            Paste the full WebDAV URL into Server URL, or split it as:
            Server URL: https://cloud.example.com
            WebDAV Path: /remote.php/dav/files/you/Comics
            Start Folder: optional subfolder, such as /Weekly
            """
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
