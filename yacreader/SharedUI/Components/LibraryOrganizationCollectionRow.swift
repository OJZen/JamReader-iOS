import SwiftUI

struct LibraryOrganizationCollectionRow: View {
    let collection: LibraryOrganizationCollection
    var showsAssignmentIndicator = false
    var trailingLabel: String?
    var trailingTint: Color = .accentColor
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            iconView

            VStack(alignment: .leading, spacing: 4) {
                Text(collection.displayTitle)
                    .font(.headline)

                Text(collection.countText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if showsAssignmentIndicator {
                Image(systemName: collection.isAssigned ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(collection.isAssigned ? Color.green : Color.secondary)
            } else if let trailingLabel {
                Text(trailingLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(trailingTint)
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, trailingAccessoryReservedWidth)
    }

    @ViewBuilder
    private var iconView: some View {
        switch collection.type {
        case .label:
            ZStack {
                Circle()
                    .fill((collection.labelColor ?? .blue).swiftUIColor)
                    .frame(width: 14, height: 14)

                Circle()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    .frame(width: 14, height: 14)
            }
            .frame(width: 28, height: 28)
        case .readingList:
            Image(systemName: collection.systemImageName)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)
        }
    }
}
