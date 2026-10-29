#if DEBUG
import UIKit

/// Debug-only hooks for UI acceptance runs:
/// - `-JRAcceptanceImportDirectory <path>` imports the CBZ files in that
///   directory into Imported Comics through the normal import service.
/// - `-JRAcceptanceWebDAVPort <port>` adds a guest profile for a local WebDAV server.
/// - `-JRAcceptanceOpenComic <file name prefix>` opens that comic from
///   Imported Comics in the reader, so protected reader UI can be captured
///   without navigating the library UI.
@MainActor
enum AcceptanceLaunchSupport {
    private static var presenter: UIKitPresentationCoordinator?

    static func run(
        dependencies: AppDependencies,
        libraryListViewModel: LibraryListViewModel,
        rootViewController: UIViewController
    ) {
        importFixturesIfRequested(into: libraryListViewModel)
        addWebDAVServerIfRequested(dependencies: dependencies)
        openComicIfRequested(dependencies: dependencies, rootViewController: rootViewController)
    }

    /// `-JRAcceptanceWebDAVPort <port>` adds a guest WebDAV profile for a local
    /// test server at http://127.0.0.1 once.
    private static func addWebDAVServerIfRequested(dependencies: AppDependencies) {
        let port = UserDefaults.standard.integer(forKey: "JRAcceptanceWebDAVPort")
        let name = "Acceptance WebDAV"
        guard port > 0,
              var profiles = try? dependencies.remoteServerProfileStore.load(),
              !profiles.contains(where: { $0.name == name }) else {
            return
        }

        profiles.append(
            RemoteServerProfile(
                name: name,
                providerKind: .webdav,
                host: "http://127.0.0.1",
                port: port,
                shareName: "",
                authenticationMode: .guest
            )
        )
        try? dependencies.remoteServerProfileStore.save(profiles)
    }

    private static func importFixturesIfRequested(into viewModel: LibraryListViewModel) {
        guard let path = UserDefaults.standard.string(forKey: "JRAcceptanceImportDirectory") else {
            return
        }

        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? [])
            .filter { $0.pathExtension.lowercased() == "cbz" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else {
            return
        }

        viewModel.importComicFiles(from: urls, destinationSelection: .importedComics)
    }

    private static func openComicIfRequested(
        dependencies: AppDependencies,
        rootViewController: UIViewController
    ) {
        guard let prefix = UserDefaults.standard.string(forKey: "JRAcceptanceOpenComic"),
              let descriptor = try? dependencies.libraryDescriptorStore.load()
                .first(where: { $0.kind == .importedComics }) else {
            return
        }

        let databaseURL = dependencies.libraryStorageManager.databaseURL(for: descriptor)
        guard let storedComic = try? dependencies.libraryDatabaseReader.loadAllComics(databaseURL: databaseURL)
            .first(where: { $0.fileName.hasPrefix(prefix) }) else {
            return
        }

        // Always start on page 1 so every capture run sees the same reader state.
        let progress = ComicReadingProgress(
            currentPage: 1,
            pageCount: storedComic.pageCount,
            hasBeenOpened: storedComic.hasBeenOpened,
            read: false,
            lastTimeOpened: storedComic.lastOpenedAt ?? Date(timeIntervalSince1970: 0)
        )
        try? dependencies.libraryDatabaseWriter.updateReadingProgress(
            for: storedComic.id,
            progress: progress,
            in: databaseURL
        )
        let comic = storedComic.updatingReadingProgress(progress)

        let presenter = UIKitPresentationCoordinator(
            dependencies: dependencies,
            rootViewController: rootViewController
        )
        self.presenter = presenter
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            presenter.presentReader(
                .local(
                    LocalReaderPresentation(
                        descriptor: descriptor,
                        comic: comic,
                        navigationContext: nil,
                        sourceFrame: .zero,
                        previewImage: nil,
                        onComicUpdated: nil,
                        onDismiss: nil
                    )
                )
            )
        }
    }
}
#endif
