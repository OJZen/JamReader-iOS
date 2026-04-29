//
//  JamReaderApp.swift
//  JamReader
//
//  Created by 欧君子 on 2026/3/17.
//

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private var dependencies: AppDependencies?
    private var libraryListViewModel: LibraryListViewModel?
    private var memoryPressureCoordinator: AppMemoryPressureCoordinator?
    private var appRootCoordinator: AppRootCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let dependencies = AppDependencies.makeDefault()
        let libraryListViewModel = LibraryListViewModel(
            store: dependencies.libraryDescriptorStore,
            storageManager: dependencies.libraryStorageManager,
            inspector: dependencies.databaseInspector,
            databaseBootstrapper: dependencies.libraryDatabaseBootstrapper,
            libraryScanner: dependencies.libraryScanner,
            maintenanceStatusStore: dependencies.libraryMaintenanceStatusStore,
            importedComicsImportService: dependencies.importedComicsImportService
        )
        let memoryPressureCoordinator = AppMemoryPressureCoordinator()
        let appRootCoordinator = AppRootCoordinator(
            dependencies: dependencies,
            libraryListViewModel: libraryListViewModel
        )

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = appRootCoordinator.rootViewController
        window.makeKeyAndVisible()

        self.window = window
        self.dependencies = dependencies
        self.libraryListViewModel = libraryListViewModel
        self.memoryPressureCoordinator = memoryPressureCoordinator
        self.appRootCoordinator = appRootCoordinator
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        memoryPressureCoordinator?.purgeVolatileCaches()
    }
}
