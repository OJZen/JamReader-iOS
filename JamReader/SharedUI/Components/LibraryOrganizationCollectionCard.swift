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

                    if let metadataText = collection.metadataText {
                        Text(metadataText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
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

private extension LibraryOrganizationCollection {
    var metadataText: String? {
        var parts = [typeTitle]

        if let labelColor {
            parts.append(labelColor.displayName)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var typeTitle: String {
        switch type {
        case .label:
            return "Tag"
        case .readingList:
            return "Reading List"
        }
    }
}
