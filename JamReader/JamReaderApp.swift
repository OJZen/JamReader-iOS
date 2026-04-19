//
//  JamReaderApp.swift
//  JamReader
//
//  Created by 欧君子 on 2026/3/17.
//

import SwiftUI

@main
struct JamReaderApp: App {
    private let dependencies: AppDependencies
    @StateObject private var libraryListViewModel: LibraryListViewModel

    init() {
        let dependencies = AppDependencies.makeDefault()
        self.dependencies = dependencies
        _libraryListViewModel = StateObject(
            wrappedValue: LibraryListViewModel(
                store: dependencies.libraryDescriptorStore,
                storageManager: dependencies.libraryStorageManager,
                inspector: dependencies.databaseInspector,
                databaseBootstrapper: dependencies.libraryDatabaseBootstrapper,
                libraryScanner: dependencies.libraryScanner,
                maintenanceStatusStore: dependencies.libraryMaintenanceStatusStore,
                importedComicsImportService: dependencies.importedComicsImportService
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(viewModel: libraryListViewModel, dependencies: dependencies)
        }
    }
}
