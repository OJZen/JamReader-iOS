import SwiftUI

struct ReaderThumbnailBrowserSheet: View {
    let document: ComicDocument
    let currentPageIndex: Int
    let onSelectPage: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isPageNumberFieldFocused: Bool
    @State private var pageNumberText = ""

    private let thumbnailWidth: CGFloat = 118
    private let thumbnailHeight: CGFloat = 166

    private var pageCount: Int {
        document.pageCount ?? 0
    }

    private var normalizedSelectedPageIndex: Int? {
        guard let pageNumber = Int(pageNumberText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...pageCount).contains(pageNumber)
        else {
            return nil
        }

        return pageNumber - 1
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            pageOverviewCard(proxy: proxy)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: thumbnailWidth, maximum: thumbnailWidth), spacing: 16)],
                                spacing: 18
                            ) {
                                ForEach(0..<pageCount, id: \.self) { pageIndex in
                                    ReaderThumbnailCell(
                                        document: document,
                                        pageIndex: pageIndex,
                                        isCurrentPage: pageIndex == currentPageIndex,
                                        width: thumbnailWidth,
                                        height: thumbnailHeight
                                    ) {
                                        openPage(at: pageIndex)
                                    }
                                    .id(pageIndex)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                    }
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
                            isPageNumberFieldFocused = false
                            scrollToPage(currentPageIndex, using: proxy, animated: true)
                        }
                    }
                }
                .onAppear {
                    if pageNumberText.isEmpty {
                        pageNumberText = "\(currentPageIndex + 1)"
                    }
                }
                .onChange(of: currentPageIndex) { _, newValue in
                    guard !isPageNumberFieldFocused else {
                        return
                    }

                    pageNumberText = "\(newValue + 1)"
                }
                .task(id: scrollRequestID) {
                    guard pageCount > 0 else {
                        return
                    }

                    try? await Task.sleep(nanoseconds: 120_000_000)
                    scrollToPage(currentPageIndex, using: proxy, animated: false)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var scrollRequestID: String {
        "\(document.fileURL.path)#\(currentPageIndex)#\(pageCount)"
    }

    private func pageOverviewCard(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Browse Pages")
                    .font(.title3.weight(.semibold))

                Text("Jump quickly, compare nearby pages, or return to where you left off.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                ReaderThumbnailStatChip(
                    title: "Current",
                    value: "\(currentPageIndex + 1)"
                )

                ReaderThumbnailStatChip(
                    title: "Total",
                    value: "\(pageCount)"
                )
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Open page")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("Page", text: $pageNumberText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($isPageNumberFieldFocused)
                        .submitLabel(.go)
                        .frame(maxWidth: 132)
                        .onSubmit {
                            openSelectedPage()
                        }
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button("Open") {
                        openSelectedPage()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(normalizedSelectedPageIndex == nil)

                    Button("Current") {
                        isPageNumberFieldFocused = false
                        scrollToPage(currentPageIndex, using: proxy, animated: true)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 20)
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

    private func scrollToPage(_ pageIndex: Int, using proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(pageIndex, anchor: .center)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.2), action)
        } else {
            action()
        }
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
            VStack(alignment: .leading, spacing: 8) {
                ReaderPageThumbnailView(
                    document: document,
                    pageIndex: pageIndex,
                    width: width,
                    height: height
                )

                Text("Page \(pageIndex + 1)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(isCurrentPage ? Color.accentColor : Color.primary)
                    .lineLimit(1)

                if isCurrentPage {
                    Text("Current")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            .frame(width: width + 20, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isCurrentPage ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isCurrentPage ? Color.accentColor : Color.black.opacity(0.08),
                        lineWidth: isCurrentPage ? 2 : 1
                    )
            }
            .shadow(
                color: isCurrentPage ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.04),
                radius: 10,
                y: 4
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ReaderThumbnailStatChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.66))
        )
    }
}
