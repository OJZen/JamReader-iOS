import Foundation

struct LibraryScanCompletionState: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}
