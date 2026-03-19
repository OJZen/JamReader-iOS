import SwiftUI

struct BrowseHomeView: View {
    let dependencies: AppDependencies

    var body: some View {
        NavigationStack {
            RemoteServerListView(dependencies: dependencies)
        }
    }
}
