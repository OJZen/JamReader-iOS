import SwiftUI

struct LibraryOrganizationCollectionCard: View {
    let collection: LibraryOrganizationCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
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
