import QuickLook
import SwiftUI
import UIKit

struct QuickLookDocumentReaderView: UIViewControllerRepresentable {
    let fileURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.view.backgroundColor = .black
        controller.reloadData()
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        guard context.coordinator.fileURL != fileURL else {
            return
        }

        context.coordinator.fileURL = fileURL
        controller.dataSource = context.coordinator
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> any QLPreviewItem {
            fileURL as NSURL
        }
    }
}
