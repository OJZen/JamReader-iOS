import SwiftUI

/// "Library › … › Current" under a subfolder's large title. Every level but
/// the current one is a button, replacing the old Up / Library buttons.
struct LibraryBreadcrumb: View {
    let libraryName: String
    let ancestors: [LibraryFolder]
    let current: LibraryFolder
    let onSelectFolder: (Int64) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Large text wraps between levels instead of scrolling out of view.
                WrappingHStack(horizontalSpacing: Spacing.xxs, verticalSpacing: Spacing.xxs) {
                    items
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xxs) {
                        items
                    }
                    .lineLimit(1)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
        .font(AppFont.subheadline())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Location"))
    }

    @ViewBuilder
    private var items: some View {
        ForEach(levels, id: \.id) { level in
            HStack(spacing: Spacing.xxs) {
                Button(level.title) {
                    onSelectFolder(level.id)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.appAccent)

                Image(systemName: "chevron.forward")
                    .font(AppFont.caption2(.semibold))
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
            }
        }

        Text(current.displayName)
            .foregroundStyle(Color.textSecondary)
            .accessibilityAddTraits(.isStaticText)
    }

    /// The root folder is named after the library; other ancestors keep their names.
    private var levels: [(id: Int64, title: String)] {
        let rootLevel = (id: Int64(1), title: libraryName)
        let deeper = ancestors
            .filter { !$0.isRoot }
            .map { (id: $0.id, title: $0.displayName) }
        return [rootLevel] + deeper
    }
}
