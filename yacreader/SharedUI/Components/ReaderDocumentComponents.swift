import SwiftUI

struct ReaderFallbackStateView: View {
    let title: String
    let systemImage: String?
    let message: String?
    var showsProgress = false

    var body: some View {
        VStack(spacing: Spacing.md) {
            if showsProgress {
                ProgressView()
                    .tint(.white)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
            }

            Text(title)
                .font(AppFont.headline(.semibold))
                .foregroundStyle(.white)

            if let message, !message.isEmpty {
                Text(message)
                    .font(AppFont.callout())
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}

struct ReaderDocumentContentView<UnsupportedContent: View>: View {
    let document: ComicDocument
    let pageIndex: Int
    let layout: ReaderDisplayLayout
    let isHorizontalScrollingDisabled: Bool
    let onPageChanged: (Int) -> Void
    let onReaderTap: (ReaderTapRegion) -> Void
    let onZoomStateChanged: ((Bool) -> Void)?
    @ViewBuilder let unsupportedContent: (UnsupportedComicDocument) -> UnsupportedContent

    var body: some View {
        switch document {
        case .pdf(let pdf):
            ReaderRotatedContentHost(rotation: layout.rotation) {
                PDFReaderContainerView(
                    document: pdf.pdfDocument,
                    requestedPageIndex: pageIndex,
                    rotation: layout.rotation,
                    onPageChanged: onPageChanged,
                    onReaderTap: onReaderTap
                )
            }
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
        case .imageSequence(let imageSequence):
            readerImageSequenceContent(for: imageSequence)
        case .unsupported(let unsupportedDocument):
            unsupportedContent(unsupportedDocument)
        }
    }

    @ViewBuilder
    private func readerImageSequenceContent(for document: ImageSequenceComicDocument) -> some View {
        if layout.pagingMode == .verticalContinuous {
            VerticalImageSequenceReaderContainerView(
                document: document,
                initialPageIndex: pageIndex,
                layout: layout,
                onPageChanged: onPageChanged,
                onReaderTap: onReaderTap
            )
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
        } else {
            ImageSequenceReaderContainerView(
                document: document,
                initialPageIndex: pageIndex,
                layout: layout,
                isHorizontalScrollingDisabled: isHorizontalScrollingDisabled,
                onPageChanged: onPageChanged,
                onReaderTap: onReaderTap,
                onZoomStateChanged: onZoomStateChanged
            )
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
        }
    }
}

struct ReaderPageJumpBar: View {
    let pageIndicatorText: String
    let onTap: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            Button(action: onTap) {
                ReaderPageIndicatorChip(text: pageIndicatorText)
            }
            .buttonStyle(.plain)
        }
    }
}
