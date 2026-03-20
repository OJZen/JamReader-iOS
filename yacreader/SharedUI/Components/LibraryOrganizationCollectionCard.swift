import SwiftUI

struct LibraryOrganizationCollectionCard: View {
    let collection: LibraryOrganizationCollection

    var body: some View {
        InsetCard(cornerRadius: 18, contentPadding: 18, strokeOpacity: 0.06) {
            HStack(alignment: .top, spacing: 12) {
                iconView

                VStack(alignment: .leading, spacing: 6) {
                    Text(collection.displayTitle)
                        .font(.headline)
                        .lineLimit(2)

                    Text(collection.countText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                StatusBadge(title: collection.sectionKind.title, tint: .blue)

                if let labelColor = collection.labelColor {
                    StatusBadge(title: labelColor.displayName, tint: labelColor.swiftUIColor)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
    }

    @ViewBuilder
    private var iconView: some View {
        switch collection.type {
        case .label:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill((collection.labelColor ?? .blue).swiftUIColor.opacity(0.18))
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: collection.systemImageName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle((collection.labelColor ?? .blue).swiftUIColor)
                }
        case .readingList:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.blue.opacity(0.12))
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: collection.systemImageName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.blue)
                }
        }
    }
}
