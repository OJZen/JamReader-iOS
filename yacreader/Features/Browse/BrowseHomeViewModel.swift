import Foundation

// BrowseHomeView now uses RemoteServerListViewModel directly so the top-level
// Browse tab can stay focused on server entry and creation. This file remains
// in place to preserve the existing project file reference.

struct BrowseHomeAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
