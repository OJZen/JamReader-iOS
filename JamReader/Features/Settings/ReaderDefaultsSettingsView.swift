import SwiftUI

struct ReaderDefaultsSettingsView: View {
    let profile: ReaderDefaultProfile
    let preferencesStore: ReaderLayoutPreferencesStore

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var layout: ReaderDisplayLayout
    @State private var suppressNextSave = false

    private var isVerticalContinuous: Bool {
        layout.pagingMode == .verticalContinuous
    }

    init(
        profile: ReaderDefaultProfile,
        preferencesStore: ReaderLayoutPreferencesStore
    ) {
        self.profile = profile
        self.preferencesStore = preferencesStore
        _layout = State(
            initialValue: preferencesStore.loadLayout(for: profile.fileType)
        )
    }

    var body: some View {
        Form {
            Section {
                readingModePicker

                if isVerticalContinuous {
                    LabeledContent("Fit Mode", value: layout.fitMode.title)
                } else {
                    Picker("Fit Mode", selection: $layout.fitMode) {
                        ForEach(ReaderFitMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    pageLayoutPicker

                    Picker(
                        "Reading Direction",
                        selection: $layout.readingDirection
                    ) {
                        ForEach(ReaderReadingDirection.allCases, id: \.self) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }

                    if layout.spreadMode == .doublePage {
                        Toggle(
                            "Show Covers as Single Page",
                            isOn: $layout.coverAsSinglePage
                        )
                    }
                }
            } header: {
                Text("Display")
            }

            Section {
                Button(action: resetToRecommendedDefaults) {
                    Label(
                        "Reset to Recommended Defaults",
                        systemImage: "arrow.counterclockwise"
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.surfaceGrouped)
        .navigationTitle(profile.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: layout) { oldValue, newValue in
            persistLayout(oldValue: oldValue, newValue: newValue)
        }
    }

    @ViewBuilder
    private var readingModePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            readingModePickerContent
                .pickerStyle(.menu)
        } else {
            readingModePickerContent
                .pickerStyle(.segmented)
        }
    }

    private var readingModePickerContent: some View {
        Picker("Reading Mode", selection: $layout.pagingMode) {
            ForEach(ReaderPagingMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
    }

    @ViewBuilder
    private var pageLayoutPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            pageLayoutPickerContent
                .pickerStyle(.menu)
        } else {
            pageLayoutPickerContent
                .pickerStyle(.segmented)
        }
    }

    private var pageLayoutPickerContent: some View {
        Picker("Page Layout", selection: $layout.spreadMode) {
            ForEach(ReaderSpreadMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
    }

    private func persistLayout(
        oldValue _: ReaderDisplayLayout,
        newValue: ReaderDisplayLayout
    ) {
        if suppressNextSave {
            suppressNextSave = false
            return
        }

        let normalizedLayout = newValue.normalized(
            allowingDoublePageSpread: true
        )
        if normalizedLayout != newValue {
            layout = normalizedLayout
            return
        }

        preferencesStore.saveLayout(
            normalizedLayout,
            for: profile.fileType
        )
    }

    private func resetToRecommendedDefaults() {
        let defaultLayout = ReaderDisplayLayout(defaultsFor: profile.fileType)
        preferencesStore.resetLayout(for: profile.fileType)
        guard layout != defaultLayout else {
            return
        }

        suppressNextSave = true
        layout = defaultLayout
    }
}
