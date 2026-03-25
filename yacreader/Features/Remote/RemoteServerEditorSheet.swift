import Combine
import SwiftUI

struct RemoteServerEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (RemoteServerEditorDraft) -> Result<Void, RemoteAlertState>

    @State private var draft: RemoteServerEditorDraft
    @State private var alert: RemoteAlertState?
    @FocusState private var isNameFieldFocused: Bool

    init(
        draft: RemoteServerEditorDraft,
        onSave: @escaping (RemoteServerEditorDraft) -> Result<Void, RemoteAlertState>
    ) {
        self.onSave = onSave
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RemoteServerEditorOverviewCard(draft: draft)
                        .listRowInsets(
                            EdgeInsets(
                                top: 6,
                                leading: 12,
                                bottom: 6,
                                trailing: 12
                            )
                        )
                        .listRowBackground(Color.clear)
                }

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
                                ? "Port 445 is the standard SMB port."
                                : "Use a custom port only if this SMB server is configured for one.")
                            : (draft.usesDefaultPort
                                ? "Port \(draft.resolvedPort ?? draft.providerKind.defaultPort) matches the expected WebDAV port for this endpoint."
                                : "Use a custom port only if this WebDAV server is configured for one.")
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
                            ? "Leave Base Directory empty to browse from the share root."
                            : "Use Server Path for the WebDAV collection path. Leave Base Directory empty to browse from that location."
                    )
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Authentication")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Picker("Authentication", selection: $draft.authenticationMode) {
                            ForEach(RemoteServerAuthenticationMode.allCases) { mode in
                                Text(mode.title)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)

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
                        Text("The saved password stays in Keychain until you replace it.")
                    } else if draft.authenticationMode.requiresPassword {
                        Text("Passwords are stored securely in Keychain after you save.")
                    }
                }
            }
            .navigationTitle(draft.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.actionTitle) {
                        switch onSave(draft) {
                        case .success:
                            break
                        case .failure(let alertState):
                            alert = alertState
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
    }
}

private struct RemoteServerEditorOverviewCard: View {
    let draft: RemoteServerEditorDraft

    private var summaryMetrics: [SummaryMetricItem] {
        [
            SummaryMetricItem(
                title: "Protocol",
                value: draft.providerKind.title,
                tint: draft.providerKind.tintColor
            ),
            SummaryMetricItem(
                title: "Port",
                value: draft.resolvedPort.map(String.init) ?? "Required",
                tint: draft.usesDefaultPort ? .blue : .teal
            ),
            SummaryMetricItem(
                title: "Access",
                value: draft.accessSummaryText,
                tint: draft.authenticationMode == .guest ? .orange : .green
            )
        ]
    }

    private var metadataItems: [RemoteInlineMetadataItem] {
        var items = [
            RemoteInlineMetadataItem(
                systemImage: "server.rack",
                text: draft.endpointDisplaySummary,
                tint: .blue
            ),
            RemoteInlineMetadataItem(
                systemImage: "folder",
                text: draft.shareDisplaySummary,
                tint: .teal
            ),
            RemoteInlineMetadataItem(
                systemImage: draft.authenticationMode == .guest ? "person.fill" : "lock.fill",
                text: draft.accessDetailText,
                tint: draft.authenticationMode == .guest ? .orange : .green
            )
        ]

        if draft.authenticationMode.requiresPassword, draft.hasStoredPassword {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "key.fill",
                    text: "Password in Keychain",
                    tint: .green
                )
            )
        }

        return items
    }

    var body: some View {
        InsetCard(
            cornerRadius: 20,
            contentPadding: 14,
            backgroundColor: Color(.systemBackground),
            strokeOpacity: 0.04
        ) {
            HStack(alignment: .center, spacing: 12) {
                RemoteServerEditorGlyph(draft: draft)

                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.displayTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(draft.existingProfileID == nil ? "New remote connection" : "Update remote connection")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            SummaryMetricGroup(
                metrics: summaryMetrics,
                style: .compactValue,
                horizontalSpacing: 8,
                verticalSpacing: 8
            )

            RemoteInlineMetadataLine(
                items: metadataItems,
                horizontalSpacing: 8,
                verticalSpacing: 4
            )

            Label(
                draft.locationDescription,
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
    }
}

private struct RemoteServerEditorGlyph: View {
    let draft: RemoteServerEditorDraft

    private var authenticationTint: Color {
        draft.authenticationMode == .guest ? .orange : .green
    }

    private var authenticationSystemImage: String {
        draft.authenticationMode == .guest ? "person.fill" : "lock.fill"
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        draft.providerKind.tintColor.opacity(0.22),
                        draft.providerKind.tintColor.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 52, height: 52)
            .overlay {
                Image(systemName: draft.providerKind.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(draft.providerKind.tintColor)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: authenticationSystemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(authenticationTint, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color(.secondarySystemBackground), lineWidth: 2)
                    }
                    .offset(x: 5, y: 5)
            }
    }
}

private extension RemoteServerEditorDraft {
    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedShareName: String {
        shareName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedBaseDirectoryPath: String {
        let trimmedPath = baseDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return ""
        }

        let collapsedPath = trimmedPath
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        return collapsedPath.isEmpty ? "" : "/" + collapsedPath
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

    var displayTitle: String {
        normalizedName.isEmpty
            ? (existingProfileID == nil ? "New \(providerKind.title) Server" : "\(providerKind.title) Server")
            : normalizedName
    }

    var endpointDisplaySummary: String {
        let hostSummary = normalizedHost.isEmpty ? "Host not set" : normalizedHost
        guard let resolvedPort else {
            return hostSummary
        }

        switch providerKind {
        case .smb:
            return resolvedPort == RemoteProviderKind.smb.defaultPort ? hostSummary : "\(hostSummary):\(resolvedPort)"
        case .webdav:
            let scheme = URLComponents(string: normalizedHost)?.scheme?.lowercased() ?? "https"
            let defaultPort = scheme == "http" ? 80 : 443
            return resolvedPort == defaultPort ? hostSummary : "\(hostSummary):\(resolvedPort)"
        }
    }

    var shareDisplaySummary: String {
        switch providerKind {
        case .smb:
            let shareComponent = normalizedShareName.isEmpty ? "" : "/\(normalizedShareName)"
            let combinedPath = "\(shareComponent)\(normalizedBaseDirectoryPath)"
            return combinedPath.isEmpty ? "/" : combinedPath
        case .webdav:
            let pathComponent = normalizedShareName.isEmpty ? "/" : normalizedShareName
            let combinedPath = normalizeRemotePath("\(pathComponent)\(normalizedBaseDirectoryPath)")
            return combinedPath.isEmpty ? "/" : combinedPath
        }
    }

    var accessSummaryText: String {
        authenticationMode == .guest ? "Guest" : "Account"
    }

    var accessDetailText: String {
        if authenticationMode == .guest {
            return "Guest access"
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedUsername.isEmpty ? "Username required" : trimmedUsername
    }

    var locationDescription: String {
        switch providerKind {
        case .smb:
            guard !normalizedShareName.isEmpty else {
                return "Choose the SMB share that should open from this connection."
            }

            if normalizedBaseDirectoryPath.isEmpty {
                return "Browsing starts at /\(normalizedShareName)."
            }

            return "Browsing starts at \(shareDisplaySummary)."
        case .webdav:
            if normalizedShareName.isEmpty {
                return "Enter the WebDAV collection path to browse from this connection."
            }

            return "Browsing starts at \(shareDisplaySummary)."
        }
    }

    var savedPasswordStatusText: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Keep current"
            : "Replace on save"
    }

    private func normalizeRemotePath(_ rawPath: String) -> String {
        let collapsedPath = rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        guard !collapsedPath.isEmpty else {
            return ""
        }

        return "/" + collapsedPath
    }
}
