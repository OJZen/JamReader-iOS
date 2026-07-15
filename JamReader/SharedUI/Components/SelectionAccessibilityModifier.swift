import SwiftUI

extension View {
    @ViewBuilder
    func accessibilitySelectionState(
        isPresented: Bool,
        isSelected: Bool
    ) -> some View {
        if isPresented {
            self
                .accessibilityValue(isSelected ? Text("Selected") : Text("Not Selected"))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            self
        }
    }
}
