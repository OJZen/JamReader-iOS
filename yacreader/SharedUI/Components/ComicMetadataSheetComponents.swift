import SwiftUI

struct ComicMetadataOverviewContent: View {
    let title: String
    let fileName: String
    var badges: [StatusBadgeItem] = []

    private var overviewItems: [FormOverviewItem] {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedFileName.isEmpty,
              normalizedFileName.localizedStandardCompare(normalizedTitle) != .orderedSame else {
            return []
        }

        return [FormOverviewItem(title: "File", value: fileName)]
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .lineLimit(2)

        AdaptiveStatusBadgeGroup(badges: badges)

        if !overviewItems.isEmpty {
            FormOverviewContent(items: overviewItems)
        }
    }
}
