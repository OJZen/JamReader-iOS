import Combine
import SwiftUI
import UIKit

@MainActor
final class AppMemoryPressureCoordinator: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private var memoryWarningObserver: NSObjectProtocol?

    init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.purgeVolatileCaches()
            }
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        guard scenePhase == .background else {
            return
        }

        purgeVolatileCaches()
    }

    func purgeVolatileCaches() {
        LocalCoverTransitionCache.shared.clear()
        ReaderPagePreviewStore.shared.clear()
        PDFThumbnailStore.shared.clear()
        RemoteComicThumbnailPipeline.shared.clearMemoryCache()

        Task {
            await ReaderPageCache.shared.clearMemoryCache()
            await LocalCoverImagePipeline.shared.clearMemoryCache()
            await ReaderImageSequenceThumbnailPipeline.shared.clearMemoryCache()
        }
    }
}
