import SwiftUI

struct RemoteServerEditorSheet: View {
    private enum Field: Hashable {
        case name
        case host
        case port
        case share
        case baseDirectory
        case username
        case password
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let onSave: (RemoteServerEditorDraft) -> AppAlertState?
    private let appliesSwiftUIPresentationModifiers: Bool
    private let initialDraft: RemoteServerEditorDraft

    @State private var draft: RemoteServerEditorDraft
    @State private var containerWidth: CGFloat = 0
    @State private var isShowingDiscardConfirmation = false
    @State private var isShowingScopeChangeConfirmation = false
    /// Shown in the footer of the section with the field to fix; input stays.
    @State private var saveError: AppAlertState?
    @FocusState private var focusedField: Field?

    init(
        draft: RemoteServerEditorDraft,
        appliesSwiftUIPresentationModifiers: Bool = true,
        onSave: @escaping (RemoteServerEditorDraft) -> AppAlertState?
    ) {
        self.appliesSwiftUIPresentationModifiers = appliesSwiftUIPresentationModifiers
        self.onSave = onSave
        self.initialDraft = draft
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

            focusedField = .name
        }
        .onChange(of: draft.providerKind) { oldValue, newValue in
            guard oldValue != newValue else {
                return
            }

            if draft.trimmedPortText.isEmpty || draft.resolvedPort == oldValue.defaultPort {
                draft.portText = String(newValue.defaultPort)
            }
        }
        .confirmationDialog(
            "Discard Changes?",
            isPresented: $isShowingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                dismiss()
            }

            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your changes to this server have not been saved.")
        }
        .confirmationDialog(
            "Save New Location?",
            isPresented: $isShowingScopeChangeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save and Clear", role: .destructive) {
                save()
            }

            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Changing the address, share, start folder or sign-in clears this server's reading history, saved folders and downloaded comics on this device. Files on the server are not affected.")
        }
        .interactiveDismissDisabled(hasUnsavedChanges)

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
            Section {
                providerPicker
            }

            Section {
                RemoteServerFormField("Name", isInvalid: false) {
                    TextField("Name", text: $draft.name, prompt: Text("e.g. Home NAS"))
                        .focused($focusedField, equals: .name)
                }

                RemoteServerFormField("Address", isInvalid: invalidFields.contains(.host)) {
                    TextField(
                        "Address",
                        text: $draft.host,
                        prompt: draft.providerKind == .smb
                            ? Text("192.168.1.20 or nas.local")
                            : Text(verbatim: "https://nas.local")
                    )
                    .focused($focusedField, equals: .host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                }

                RemoteServerFormField("Port", isInvalid: invalidFields.contains(.port)) {
                    TextField("Port", text: $draft.portText, prompt: Text(verbatim: String(draft.providerKind.defaultPort)))
                        .focused($focusedField, equals: .port)
                        .keyboardType(.numberPad)
                }

                RemoteServerFormField(
                    draft.providerKind == .smb ? "Share" : "Server Path",
                    isInvalid: invalidFields.contains(.share)
                ) {
                    TextField(
                        draft.providerKind == .smb
                            ? String(localized: "Share")
                            : String(localized: "Server Path"),
                        text: $draft.shareName,
                        prompt: draft.providerKind == .smb
                            ? Text("e.g. Comics")
                            : Text(verbatim: "/remote.php/dav/files/you")
                    )
                    .focused($focusedField, equals: .share)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }

                RemoteServerFormField("Start Folder", isInvalid: false) {
                    TextField("Start Folder", text: $draft.baseDirectoryPath, prompt: Text("e.g. /Comics (optional)"))
                        .focused($focusedField, equals: .baseDirectory)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Server")
            } footer: {
                if let saveError, !errorBelongsToSignIn {
                    saveErrorText(saveError)
                }
            }

            Section {
                RemoteServerFormField("Method", isInvalid: false) {
                    authenticationPicker
                }

                if draft.authenticationMode.requiresUsername {
                    RemoteServerFormField("Username", isInvalid: invalidFields.contains(.username)) {
                        TextField("Username", text: $draft.username)
                            .focused($focusedField, equals: .username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                if draft.authenticationMode.requiresPassword {
                    RemoteServerFormField("Password", isInvalid: invalidFields.contains(.password)) {
                        SecureField("Password", text: $draft.password)
                            .focused($focusedField, equals: .password)
                            .textContentType(.password)
                    }

                    if draft.hasStoredPassword {
                        LabeledContent("Saved Password") {
                            Text(draft.savedPasswordStatusText)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Sign In")
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let saveError, errorBelongsToSignIn {
                        saveErrorText(saveError)
                    }
                    // Saving does not connect; say so instead of implying a check.
                    Text("Servers connect when you open them after saving.")
                }
            }
        }
    }

    private func saveErrorText(_ error: AppAlertState) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxxs) {
            Text(error.title)
                .bold()
            Text(error.message)
        }
        .foregroundStyle(Color.appDanger)
    }

    /// Fields to mark after a rejected save, worked out from the draft.
    private var invalidFields: Set<Field> {
        guard saveError != nil else {
            return []
        }

        var fields = Set<Field>()
        if draft.normalizedHost.isEmpty {
            fields.insert(.host)
        }
        if draft.resolvedPort == nil {
            fields.insert(.port)
        }
        if draft.providerKind == .smb,
           draft.shareName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.insert(.share)
        }
        if draft.authenticationMode.requiresUsername,
           draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.insert(.username)
        }
        if draft.authenticationMode.requiresPassword,
           draft.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !draft.hasStoredPassword {
            fields.insert(.password)
        }
        return fields
    }

    private var errorBelongsToSignIn: Bool {
        let fields = invalidFields
        return !fields.isEmpty && fields.isSubset(of: [.username, .password])
    }

    @ViewBuilder
    private var providerPicker: some View {
        let picker = Picker("Provider", selection: $draft.providerKind) {
            ForEach(RemoteProviderKind.allCases) { providerKind in
                Text(providerKind.title)
                    .tag(providerKind)
            }
        }

        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var authenticationPicker: some View {
        let picker = Picker("Method", selection: $draft.authenticationMode) {
            ForEach(RemoteServerAuthenticationMode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
            }
        }

        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker
                .pickerStyle(.segmented)
                .labelsHidden()
        }
    }

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                requestDismissal()
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button(draft.actionTitle) {
                handleSave()
            }
        }

        ToolbarItemGroup(placement: .keyboard) {
            Spacer()

            Button("Done") {
                focusedField = nil
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        draft != initialDraft
    }

    private func requestDismissal() {
        if hasUnsavedChanges {
            isShowingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func handleSave() {
        if changesServerScope {
            isShowingScopeChangeConfirmation = true
        } else {
            save()
        }
    }

    private func save() {
        saveError = onSave(draft)
    }

    /// Location or sign-in changes clear the server's local history, saved
    /// folders and downloads when saved (`02-architecture` deletion table).
    private var changesServerScope: Bool {
        guard initialDraft.existingProfileID != nil else {
            return false
        }

        func trimmed(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return draft.providerKind != initialDraft.providerKind
            || trimmed(draft.host) != trimmed(initialDraft.host)
            || trimmed(draft.portText) != trimmed(initialDraft.portText)
            || trimmed(draft.shareName) != trimmed(initialDraft.shareName)
            || trimmed(draft.baseDirectoryPath) != trimmed(initialDraft.baseDirectoryPath)
            || draft.authenticationMode != initialDraft.authenticationMode
            || trimmed(draft.username) != trimmed(initialDraft.username)
    }
}

/// Label column on the left, input on the right (`FormField`); stacked at
/// accessibility sizes. The input keeps the label for VoiceOver.
private struct RemoteServerFormField<Input: View>: View {
    let title: LocalizedStringKey
    let isInvalid: Bool
    @ViewBuilder let input: () -> Input

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var labelWidth: CGFloat = 92

    init(_ title: LocalizedStringKey, isInvalid: Bool, @ViewBuilder input: @escaping () -> Input) {
        self.title = title
        self.isInvalid = isInvalid
        self.input = input
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
            : AnyLayout(HStackLayout(spacing: Spacing.sm))
        layout {
            Text(title)
                .foregroundStyle(isInvalid ? Color.appDanger : Color.textPrimary)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : labelWidth, alignment: .leading)
                .accessibilityHidden(true)
            input()
                .frame(maxWidth: .infinity, alignment: .leading)
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
            ? String(localized: "Keep current")
            : String(localized: "Replace on save")
    }
}
