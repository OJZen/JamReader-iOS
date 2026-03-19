import SwiftUI

struct AppRootView: View {
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @SceneStorage("appRoot.selectedTab") private var selectedTabRawValue = AppRootTab.library.rawValue

    private var selectedTab: Binding<AppRootTab> {
        Binding(
            get: { AppRootTab(rawValue: selectedTabRawValue) ?? .library },
            set: { selectedTabRawValue = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: selectedTab) {
            LibraryHomeView(viewModel: viewModel, dependencies: dependencies)
                .tabItem {
                    Label("Library", systemImage: AppRootTab.library.systemImage)
                }
                .tag(AppRootTab.library)

            BrowseHomeView(dependencies: dependencies)
                .tabItem {
                    Label("Browse", systemImage: AppRootTab.browse.systemImage)
                }
                .tag(AppRootTab.browse)

            SettingsHomeView(viewModel: viewModel, dependencies: dependencies)
                .tabItem {
                    Label("Settings", systemImage: AppRootTab.settings.systemImage)
                }
                .tag(AppRootTab.settings)
        }
    }
}

private enum AppRootTab: String, Hashable {
    case library
    case browse
    case settings

    var systemImage: String {
        switch self {
        case .library:
            return "books.vertical.fill"
        case .browse:
            return "globe.asia.australia.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}
