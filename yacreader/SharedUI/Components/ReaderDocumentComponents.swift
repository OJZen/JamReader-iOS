import SwiftUI

struct ReaderDocumentContentView<UnsupportedContent: View>: View {
    let document: ComicDocument
    let pageIndex: Int
    let layout: ReaderDisplayLayout
    let onPageChanged: (Int) -> Void
    let onReaderTap: (ReaderTapRegion) -> Void
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
                onPageChanged: onPageChanged,
                onReaderTap: onReaderTap
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
