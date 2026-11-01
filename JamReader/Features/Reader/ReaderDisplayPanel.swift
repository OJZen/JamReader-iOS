import SwiftUI

/// The display controls that take effect for the open document. See
/// docs/design-system/03-reader.md, "显示面板的控件可见性".
struct ReaderDisplayPanelControls: Equatable {
    var showsReadingMode = false
    var showsSpreadMode = false
    /// Spread order and "show first page alone", only for double pages.
    var showsSpreadOptions = false
    var showsFitMode = false
    var showsPageSpacing = false
    var showsRotation = false

    /// `layout` is the effective layout, so a compact window never reports
    /// double pages.
    init(
        layout: ReaderDisplayLayout,
        supportsImageLayoutControls: Bool,
        supportsDoublePageSpread: Bool,
        supportsRotation: Bool
    ) {
        let isPaged = layout.pagingMode == .paged
        showsReadingMode = supportsImageLayoutControls
        showsSpreadMode = supportsImageLayoutControls && isPaged && supportsDoublePageSpread
        showsSpreadOptions = showsSpreadMode && layout.spreadMode == .doublePage
        showsFitMode = supportsImageLayoutControls && isPaged
        // Spacing only separates pages shown together.
        showsPageSpacing = supportsImageLayoutControls && layout.canConfigurePageSpacing
        showsRotation = supportsRotation
    }

    var isEmpty: Bool {
        !showsReadingMode && !showsRotation
    }

    /// Everything but rotation is saved as the default for later comics.
    var footnote: String? {
        guard showsReadingMode else {
            return nil
        }
        return showsRotation
            ? String(localized: "Everything except rotation becomes the default for comics you open later.")
            : String(localized: "These settings become the default for comics you open later.")
    }
}

struct ReaderDisplayPanelActions {
    let setPagingMode: (ReaderPagingMode) -> Void
    let setSpreadMode: (ReaderSpreadMode) -> Void
    let setReadingDirection: (ReaderReadingDirection) -> Void
    let setCoverAsSinglePage: (Bool) -> Void
    let setFitMode: (ReaderFitMode) -> Void
    let setPageSpacingEnabled: (Bool) -> Void
    let rotateCounterClockwise: () -> Void
    let rotateClockwise: () -> Void
    let resetRotation: () -> Void
}

/// Aa: a floating panel at the bottom of a compact window, a popover in a
/// regular one. Changes apply to the page behind it as they are made.
struct ReaderDisplayPanel: View {
    let layout: ReaderDisplayLayout
    let controls: ReaderDisplayPanelControls
    let presentsAsPopover: Bool
    let actions: ReaderDisplayPanelActions
    let onClose: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header

                if controls.showsReadingMode {
                    section("Reading Mode") {
                        readingModeCards
                    }
                }

                if controls.showsSpreadMode {
                    section("Page Layout") {
                        choicePicker("Page Layout", selection: spreadModeBinding) {
                            ForEach(ReaderSpreadMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                    }
                }

                if controls.showsSpreadOptions {
                    // Only orders the two pages of a spread; paging is unchanged.
                    section("Spread Order") {
                        choicePicker("Spread Order", selection: readingDirectionBinding) {
                            ForEach(ReaderReadingDirection.allCases, id: \.self) { direction in
                                Text(direction.title).tag(direction)
                            }
                        }
                    }

                    Toggle("Show First Page Alone", isOn: coverAsSinglePageBinding)
                }

                if controls.showsFitMode {
                    section("Fit Mode") {
                        choicePicker("Fit Mode", selection: fitModeBinding) {
                            ForEach(ReaderFitMode.allCases, id: \.self) { fitMode in
                                Text(usesMenuPickers ? fitMode.title : fitMode.shortTitle).tag(fitMode)
                            }
                        }
                    }
                }

                if controls.showsPageSpacing {
                    Toggle("Page Spacing", isOn: pageSpacingBinding)
                }

                if controls.showsRotation {
                    rotationRow
                }

                if let footnote = controls.footnote {
                    Text(footnote)
                        .font(AppFont.footnote())
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.lg)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                contentHeight = height
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // The panel is attached inside the reader's white top bar.
        .foregroundStyle(Color.textPrimary)
        // The sheet leaves the page usable, so VoiceOver does not treat it as
        // modal and needs its own way out.
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onClose)
        .modifier(
            ReaderDisplayPanelSizing(
                contentHeight: contentHeight,
                presentsAsPopover: presentsAsPopover,
                popoverWidth: dynamicTypeSize.isAccessibilitySize ? 520 : 380
            )
        )
    }

    private var usesMenuPickers: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var header: some View {
        ZStack {
            Text("Display")
                .font(AppFont.headline())
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color(.tertiarySystemFill), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
        }
    }

    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(AppFont.footnote())
                .foregroundStyle(Color.textSecondary)
            content()
        }
    }

    /// Segmented by default; a menu at accessibility sizes, where segments
    /// cut off their titles.
    @ViewBuilder
    private func choicePicker<Value: Hashable, Options: View>(
        _ title: LocalizedStringKey,
        selection: Binding<Value>,
        @ViewBuilder options: () -> Options
    ) -> some View {
        if usesMenuPickers {
            Picker(title, selection: selection, content: options)
                .pickerStyle(.menu)
                .labelsHidden()
        } else {
            Picker(title, selection: selection, content: options)
                .pickerStyle(.segmented)
                .labelsHidden()
        }
    }

    private var readingModeCards: some View {
        let layout = usesMenuPickers
            ? AnyLayout(VStackLayout(spacing: Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Spacing.xs))

        return layout {
            ForEach(ReaderPagingMode.allCases, id: \.self) { mode in
                ReaderReadingModeCard(
                    mode: mode,
                    isSelected: self.layout.pagingMode == mode
                ) {
                    actions.setPagingMode(mode)
                }
            }
        }
    }

    private var rotationRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) {
                rotationTitle
                Spacer(minLength: 0)
                rotationButtons
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                rotationTitle
                rotationButtons
            }
        }
    }

    private var rotationTitle: some View {
        VStack(alignment: .leading, spacing: Spacing.xxxs) {
            HStack(spacing: Spacing.xs) {
                Text("Rotation")
                if layout.rotation != .degrees0 {
                    Text(layout.rotation.title)
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Text("This Reading Only")
                .font(AppFont.footnote())
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var rotationButtons: some View {
        HStack(spacing: 0) {
            rotationButton("rotate.left", title: "Rotate Left", action: actions.rotateCounterClockwise)
            rotationButton("rotate.right", title: "Rotate Right", action: actions.rotateClockwise)
            if layout.rotation != .degrees0 {
                rotationButton("arrow.counterclockwise", title: "Reset Rotation", action: actions.resetRotation)
            }
        }
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private func rotationButton(
        _ systemImage: String,
        title: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AppFont.body(.semibold))
                .foregroundStyle(Color.appAccent)
                .frame(minWidth: 44, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }

    private var spreadModeBinding: Binding<ReaderSpreadMode> {
        Binding(get: { layout.spreadMode }, set: actions.setSpreadMode)
    }

    private var readingDirectionBinding: Binding<ReaderReadingDirection> {
        Binding(get: { layout.readingDirection }, set: actions.setReadingDirection)
    }

    private var coverAsSinglePageBinding: Binding<Bool> {
        Binding(get: { layout.coverAsSinglePage }, set: actions.setCoverAsSinglePage)
    }

    private var fitModeBinding: Binding<ReaderFitMode> {
        Binding(get: { layout.fitMode }, set: actions.setFitMode)
    }

    private var pageSpacingBinding: Binding<Bool> {
        Binding(get: { layout.pageSpacingEnabled }, set: actions.setPageSpacingEnabled)
    }
}

/// Paged or vertical scroll, as a picture card.
private struct ReaderReadingModeCard: View {
    let mode: ReaderPagingMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xxs) {
                Image(systemName: mode == .paged ? "rectangle.split.2x1" : "rectangle.split.1x2")
                    .font(AppFont.title3())
                Text(mode.title)
                    .font(AppFont.footnote(.semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(isSelected ? Color.appAccentOnSoft : Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.xs)
            .background(
                isSelected ? Color.appAccentSoft : Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .strokeBorder(Color.appAccent, lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A sheet that fits its content and leaves the page behind it usable, or a
/// popover sized to its content.
private struct ReaderDisplayPanelSizing: ViewModifier {
    let contentHeight: CGFloat
    let presentsAsPopover: Bool
    let popoverWidth: CGFloat

    func body(content: Content) -> some View {
        // Opaque, so the controls stay legible over any page.
        if presentsAsPopover {
            content
                .frame(width: popoverWidth, height: contentHeight > 0 ? contentHeight : nil)
                .presentationBackground(Color.surfacePrimary)
                .presentationCompactAdaptation(.popover)
        } else {
            content
                .presentationBackground(Color.surfacePrimary)
                .presentationDetents([.height(max(contentHeight, 200))])
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.hidden)
        }
    }
}

private extension ReaderFitMode {
    /// Fits in a four-part segmented control.
    var shortTitle: String {
        switch self {
        case .page:
            return String(localized: "Whole Page")
        case .width:
            return String(localized: "Width")
        case .height:
            return String(localized: "Height")
        case .originalSize:
            return String(localized: "Original")
        }
    }
}
