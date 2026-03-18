import SwiftUI

struct LibraryComicFilterBar: View {
    let selection: LibraryComicQuickFilter
    let action: (LibraryComicQuickFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LibraryComicQuickFilter.allCases) { filter in
                    Button {
                        action(filter)
                    } label: {
                        Label(filter.title, systemImage: filter.systemImageName)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .foregroundStyle(selection == filter ? Color.white : Color.primary)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selection == filter ? Color.accentColor : Color(.secondarySystemBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Comic Filters")
    }
}
