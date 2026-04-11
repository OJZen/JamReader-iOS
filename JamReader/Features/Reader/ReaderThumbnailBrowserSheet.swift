import SwiftUI

struct ReaderThumbnailBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let document: ComicDocument
    let currentPageIndex: Int
    let onSelectPage: (Int) -> Void

    @FocusState private var isPageNumberFieldFocused: Bool
    @State private var pageNumberText = ""
    @State private var sliderPageNumber: Double = 1

    private var pageCount: Int {
        max(document.pageCount ?? 0, 0)
    }

    private var clampedCurrentPageIndex: Int {
        guard pageCount > 0 else {
            return 0
        }

        return min(max(currentPageIndex, 0), pageCount - 1)
    }

    private var currentPageNumber: Int {
        pageCount > 0 ? clampedCurrentPageIndex + 1 : 0
    }

    private var selectedSliderPageNumber: Int {
        guard pageCount > 0 else {
            return 0
        }

        return min(max(Int(sliderPageNumber.rounded()), 1), pageCount)
    }

    private var selectedPreviewPageIndex: Int {
        normalizedSelectedPageIndex ?? max(selectedSliderPageNumber - 1, 0)
    }

    private var normalizedSelectedPageIndex: Int? {
        guard let pageNumber = Int(pageNumberText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...pageCount).contains(pageNumber)
        else {
            return nil
        }

        return pageNumber - 1
    }

    private var progressFraction: Double {
        guard pageCount > 0 else {
            return 0
        }

        return Double(currentPageNumber) / Double(pageCount)
    }

    private var progressPercent: Int {
        Int((progressFraction * 100).rounded())
    }

    private var remainingPageCount: Int {
        max(pageCount - currentPageNumber, 0)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let layout = ReaderThumbnailBrowserLayout(
                    containerWidth: geometry.size.width,
                    horizontalSizeClass: horizontalSizeClass
                )

                ScrollViewReader { proxy in
                    ZStack {
                        ReaderThumbnailBrowserBackground()
                            .ignoresSafeArea()

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: layout.sectionSpacing) {
                                pageOverviewSection(layout: layout, proxy: proxy)
                                pageGridSection(layout: layout)
                            }
                            .frame(width: layout.contentWidth, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, layout.outerHorizontalPadding)
                            .padding(.top, layout.topPadding)
                            .padding(.bottom, layout.bottomPadding)
                        }
                        .scrollDismissesKeyboard(.interactively)
                    }
                    .navigationTitle("Pages")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }

                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Current") {
                                focusCurrentPage(using: proxy, animated: true)
                            }
                        }
                    }
                    .onAppear {
                        syncPageSelection(to: clampedCurrentPageIndex)
                    }
                    .onChange(of: currentPageIndex) { _, newValue in
                        guard !isPageNumberFieldFocused else {
                            return
                        }

                        syncPageSelection(to: newValue)
                    }
                    .onChange(of: pageNumberText) { _, newValue in
                        synchronizeSliderSelection(with: newValue)
                    }
                    .task(id: scrollRequestID) {
                        guard pageCount > 0 else {
                            return
                        }

                        try? await Task.sleep(nanoseconds: 120_000_000)
                        scrollToPage(clampedCurrentPageIndex, using: proxy, animated: false)
                    }
                }
            }
        }
        .adaptiveSheetWidth(1120)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var scrollRequestID: String {
        "\(document.fileURL.path)#\(currentPageIndex)#\(pageCount)"
    }

    @ViewBuilder
    private func pageOverviewSection(
        layout: ReaderThumbnailBrowserLayout,
        proxy: ScrollViewProxy
    ) -> some View {
        Group {
            if layout.usesSplitHeader {
                HStack(alignment: .top, spacing: layout.headerSpacing) {
                    currentProgressCard(layout: layout)
                    quickJumpCard(layout: layout, proxy: proxy)
                }
            } else {
                VStack(alignment: .leading, spacing: layout.headerSpacing) {
                    currentProgressCard(layout: layout)
                    quickJumpCard(layout: layout, proxy: proxy)
                }
            }
        }
    }

    private func currentProgressCard(layout: ReaderThumbnailBrowserLayout) -> some View {
        ReaderThumbnailBrowserCard(accentColor: .accentColor) {
            HStack(alignment: .top, spacing: layout.cardContentSpacing) {
                currentThumbnailHero(layout: layout)
                currentProgressDetails(layout: layout)
            }
        }
    }

    private func currentThumbnailHero(layout: ReaderThumbnailBrowserLayout) -> some View {
        ReaderPageThumbnailView(
            document: document,
            pageIndex: clampedCurrentPageIndex,
            width: layout.heroThumbnailWidth,
            height: layout.heroThumbnailHeight,
            cornerRadius: 18
        )
        .overlay(alignment: .topLeading) {
            ReaderThumbnailPageBadge(title: "P\(currentPageNumber)")
            .padding(Spacing.sm)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }

    private func currentProgressDetails(layout: ReaderThumbnailBrowserLayout) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text("Now Reading")
                    .font(AppFont.footnote(.semibold))
                    .foregroundStyle(.secondary)

                Text("Page \(currentPageNumber)")
                    .font(layout.usesRegularLayout ? AppFont.title3(.bold) : AppFont.headline(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Text("\(progressPercent)% completed across \(pageCount) pages")
                    .font(AppFont.footnote())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progressFraction)
                .tint(.accentColor)

            HStack(spacing: Spacing.xs) {
                ReaderThumbnailCompactStat(title: "Progress", value: "\(progressPercent)%")
                ReaderThumbnailCompactStat(title: "Left", value: "\(remainingPageCount)")
                ReaderThumbnailCompactStat(title: "Total", value: "\(pageCount)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickJumpCard(
        layout: ReaderThumbnailBrowserLayout,
        proxy: ScrollViewProxy
    ) -> some View {
        ReaderThumbnailBrowserCard(accentColor: .orange) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .center, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: Spacing.xxxs) {
                        Text("Quick Jump")
                            .font(AppFont.headline())
                            .foregroundStyle(.primary)

                        Text(selectionSummaryText)
                            .font(AppFont.footnote())
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    if layout.showsJumpPreview && pageCount > 0 {
                        ReaderPageThumbnailView(
                            document: document,
                            pageIndex: selectedPreviewPageIndex,
                            width: layout.jumpPreviewWidth,
                            height: layout.jumpPreviewHeight,
                            cornerRadius: 16
                        )
                    }
                }

                HStack(alignment: .center, spacing: Spacing.xs) {
                    TextField("Page", text: $pageNumberText)
                        .keyboardType(.numberPad)
                        .font(AppFont.headline(.semibold).monospacedDigit())
                        .padding(.horizontal, Spacing.sm)
                        .frame(width: layout.jumpFieldWidth, height: layout.inputHeight)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                                .fill(Color(.systemBackground).opacity(0.82))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                                .stroke(
                                    isPageNumberFieldFocused ? Color.accentColor.opacity(0.55) : Color.black.opacity(0.08),
                                    lineWidth: isPageNumberFieldFocused ? 1.5 : 1
                                )
                        )
                        .focused($isPageNumberFieldFocused)

                    Text("/ \(pageCount)")
                        .font(AppFont.body(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    
                    Button("Go To") {
                        openSelectedPage()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(normalizedSelectedPageIndex == nil)

                    Button {
                        scrollToSelectedPage(using: proxy)
                    } label: {
                        Label("Locate", systemImage: "viewfinder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(normalizedSelectedPageIndex == nil)
                }

                Slider(
                    value: $sliderPageNumber,
                    in: 1...Double(max(pageCount, 1)),
                    step: 1
                ) { editing in
                    if editing {
                        isPageNumberFieldFocused = false
                    }
                }
                .tint(.accentColor)
                .disabled(pageCount == 0)
                .onChange(of: sliderPageNumber) { _, newValue in
                    guard pageCount > 0 else {
                        return
                    }

                    let pageNumber = min(max(Int(newValue.rounded()), 1), pageCount)
                    let updatedText = "\(pageNumber)"
                    guard pageNumberText != updatedText else {
                        return
                    }

                    pageNumberText = updatedText
                }
            }
        }
    }

    private func pageGridSection(layout: ReaderThumbnailBrowserLayout) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text("All Pages")
                        .font(layout.usesRegularLayout ? AppFont.title3(.bold) : AppFont.headline(.semibold))
                        .foregroundStyle(.primary)

                    Text("Tap any thumbnail to jump instantly.")
                        .font(AppFont.callout())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text("\(pageCount)")
                    .font(AppFont.footnote(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
            }
            LazyVGrid(
                columns: layout.gridColumns,
                alignment: .leading,
                spacing: layout.gridSpacing
            ) {
                ForEach(0..<pageCount, id: \.self) { pageIndex in
                    ReaderThumbnailCell(
                        document: document,
                        pageIndex: pageIndex,
                        isCurrentPage: pageIndex == clampedCurrentPageIndex,
                        width: layout.gridThumbnailWidth,
                        height: layout.gridThumbnailHeight
                    ) {
                        openPage(at: pageIndex)
                    }
                    .id(pageIndex)
                }
            }
        }
    }

    private var selectionSummaryText: String {
        guard pageCount > 0 else {
            return "No Pages"
        }

        return "Page \(selectedSliderPageNumber) / \(pageCount)"
    }

    private func openSelectedPage() {
        guard let pageIndex = normalizedSelectedPageIndex else {
            return
        }

        openPage(at: pageIndex)
    }

    private func openPage(at pageIndex: Int) {
        onSelectPage(pageIndex)
        dismiss()
    }

    private func focusCurrentPage(using proxy: ScrollViewProxy, animated: Bool) {
        guard pageCount > 0 else {
            return
        }

        isPageNumberFieldFocused = false
        syncPageSelection(to: clampedCurrentPageIndex)
        scrollToPage(clampedCurrentPageIndex, using: proxy, animated: animated)
    }

    private func scrollToSelectedPage(using proxy: ScrollViewProxy) {
        guard let pageIndex = normalizedSelectedPageIndex else {
            return
        }

        isPageNumberFieldFocused = false
        scrollToPage(pageIndex, using: proxy, animated: true)
    }

    private func scrollToPage(_ pageIndex: Int, using proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(pageIndex, anchor: .center)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.24), action)
        } else {
            action()
        }
    }

    private func syncPageSelection(to pageIndex: Int) {
        guard pageCount > 0 else {
            pageNumberText = ""
            sliderPageNumber = 1
            return
        }

        let clampedIndex = min(max(pageIndex, 0), pageCount - 1)
        let pageNumber = clampedIndex + 1
        pageNumberText = "\(pageNumber)"
        sliderPageNumber = Double(pageNumber)
    }

    private func synchronizeSliderSelection(with text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageNumber = Int(trimmedText), (1...pageCount).contains(pageNumber) else {
            return
        }

        let targetValue = Double(pageNumber)
        guard sliderPageNumber != targetValue else {
            return
        }

        sliderPageNumber = targetValue
    }
}

private struct ReaderThumbnailBrowserLayout {
    let containerWidth: CGFloat
    let usesRegularLayout: Bool
    let usesSplitHeader: Bool
    let showsJumpPreview: Bool
    let outerHorizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let contentMaxWidth: CGFloat
    let contentWidth: CGFloat
    let sectionSpacing: CGFloat
    let headerSpacing: CGFloat
    let cardContentSpacing: CGFloat
    let heroThumbnailWidth: CGFloat
    let heroThumbnailHeight: CGFloat
    let jumpPreviewWidth: CGFloat
    let jumpPreviewHeight: CGFloat
    let jumpFieldWidth: CGFloat
    let inputHeight: CGFloat
    let gridThumbnailWidth: CGFloat
    let gridThumbnailHeight: CGFloat
    let gridSpacing: CGFloat
    let gridCardMinWidth: CGFloat
    let gridCardMaxWidth: CGFloat

    init(containerWidth: CGFloat, horizontalSizeClass: UserInterfaceSizeClass?) {
        let regularLayout = horizontalSizeClass == .regular && containerWidth >= 700
        usesRegularLayout = regularLayout
        usesSplitHeader = regularLayout && containerWidth >= 820
        showsJumpPreview = regularLayout && containerWidth >= 1080
        outerHorizontalPadding = regularLayout ? 28 : 16
        topPadding = regularLayout ? 14 : 8
        bottomPadding = regularLayout ? 34 : 28
        let availableContentWidth = max(containerWidth - (outerHorizontalPadding * 2), 0)
        contentMaxWidth = regularLayout ? 860 : availableContentWidth
        let centeredRegularWidth = max(availableContentWidth - 72, 0)
        contentWidth = regularLayout
            ? min(contentMaxWidth, centeredRegularWidth)
            : availableContentWidth
        sectionSpacing = regularLayout ? 18 : 14
        headerSpacing = regularLayout ? 12 : 10
        cardContentSpacing = regularLayout ? 12 : 10
        heroThumbnailWidth = regularLayout ? 144 : 108
        heroThumbnailHeight = regularLayout ? 204 : 154
        jumpPreviewWidth = regularLayout ? 60 : 0
        jumpPreviewHeight = regularLayout ? 84 : 0
        jumpFieldWidth = regularLayout ? 88 : 76
        inputHeight = regularLayout ? 42 : 40
        gridThumbnailWidth = regularLayout ? 150 : 116
        gridThumbnailHeight = regularLayout ? 214 : 168
        gridSpacing = regularLayout ? 20 : 14
        gridCardMinWidth = regularLayout ? 182 : 138
        gridCardMaxWidth = regularLayout ? 212 : 156
        self.containerWidth = containerWidth
    }

    var gridColumns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: gridCardMinWidth,
                    maximum: gridCardMaxWidth
                ),
                spacing: gridSpacing,
                alignment: .top
            )
        ]
    }
}

private struct ReaderThumbnailBrowserBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground),
                    Color(.secondarySystemGroupedBackground),
                    Color(.systemBackground).opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 36)
                .offset(x: 130, y: -180)

            Circle()
                .fill(Color.orange.opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 48)
                .offset(x: -140, y: 220)
        }
    }
}

private struct ReaderThumbnailBrowserCard<Content: View>: View {
    let accentColor: Color
    let content: Content

    init(
        accentColor: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.accentColor = accentColor
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground).opacity(0.92))

                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(0.10),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 18, y: 10)
    }
}

private struct ReaderThumbnailCompactStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppFont.caption(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(AppFont.subheadline(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct ReaderThumbnailPageBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppFont.caption(.semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.92))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct ReaderThumbnailStatusBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(AppFont.caption(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.92))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
    }
}

private struct ReaderThumbnailCell: View {
    let document: ComicDocument
    let pageIndex: Int
    let isCurrentPage: Bool
    let width: CGFloat
    let height: CGFloat
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ReaderPageThumbnailView(
                    document: document,
                    pageIndex: pageIndex,
                    width: width,
                    height: height
                )
                .overlay(alignment: .topLeading) {
                    Text("\(pageIndex + 1)")
                        .font(AppFont.caption(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(.systemBackground).opacity(0.92))
                        )
                        .padding(Spacing.sm)
                }
                .overlay(alignment: .topTrailing) {
                    if isCurrentPage {
                        ReaderThumbnailStatusBadge(
                            title: "Now",
                            tint: .accentColor
                        )
                        .padding(Spacing.sm)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text("Page \(pageIndex + 1)")
                        .font(AppFont.subheadline(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)

                    Text(isCurrentPage ? "Reading now" : "Tap to open")
                        .font(AppFont.caption())
                        .foregroundStyle(isCurrentPage ? Color.accentColor : .secondary)
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        isCurrentPage
                        ? Color.accentColor.opacity(0.14)
                        : Color(.secondarySystemGroupedBackground).opacity(0.94)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        isCurrentPage ? Color.accentColor.opacity(0.75) : Color.black.opacity(0.07),
                        lineWidth: isCurrentPage ? 1.8 : 1
                    )
            }
            .shadow(
                color: .black.opacity(isCurrentPage ? 0.12 : 0.05),
                radius: isCurrentPage ? 14 : 8,
                y: isCurrentPage ? 8 : 4
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerHoverEffect()
    }
}
