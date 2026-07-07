import Combine
import SwiftUI
import UIKit
import os

@MainActor
final class AppMemoryPressureCoordinator: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private var memoryWarningObserver: NSObjectProtocol?
    private let logger = AppLog.app

    init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.purgeVolatileCaches(reason: "memoryWarning")
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

        purgeBackgroundCaches()
    }

    func purgeVolatileCaches() {
        purgeVolatileCaches(reason: "manual")
    }

    private func purgeVolatileCaches(reason: String) {
        logger.notice(
            "App volatile cache purge requested reason=\(reason, privacy: .public)"
        )
        LocalCoverTransitionCache.shared.clear()
        purgeReaderDisplayCaches()
        RemoteComicThumbnailPipeline.shared.clearMemoryCache()
        purgeAsyncImageCaches(reason: reason)
    }

    func purgeBackgroundCaches() {
        logger.info("App background cache purge requested")
        purgeReaderDisplayCaches()
        RemoteComicThumbnailPipeline.shared.clearDisplayMemoryCache()
        purgeAsyncImageCaches(reason: "background")
    }

    private func purgeReaderDisplayCaches() {
        ReaderPagePreviewStore.shared.clear()
    }

    private func purgeAsyncImageCaches(reason: String) {
        let logger = self.logger
        Task {
            await ReaderPageCache.shared.clearMemoryCache()
            await LocalCoverImagePipeline.shared.clearMemoryCache()
            await ReaderImageSequenceThumbnailPipeline.shared.clearMemoryCache()
            logger.info(
                "App async image cache purge completed reason=\(reason, privacy: .public)"
            )
        }
    }
}
