import SwiftUI

struct ReaderThumbnailBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss

    let document: ComicDocument
    let currentPageIndex: Int
    let onSelectPage: (Int) -> Void

    @State private var focusCurrentRequestID = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surfaceGrouped
                    .ignoresSafeArea()

                ReaderThumbnailBrowserUIKitContainer(
                    document: document,
                    currentPageIndex: currentPageIndex,
                    focusCurrentRequestID: focusCurrentRequestID
                ) { pageIndex in
                    onSelectPage(pageIndex)
                    dismiss()
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
                        focusCurrentRequestID &+= 1
                    }
                }
            }
        }
        .adaptiveSheetWidth(1120)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .modifier(ReaderThumbnailBrowserLegacyNavigationBarModifier())
    }
}

private struct ReaderThumbnailBrowserLegacyNavigationBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
