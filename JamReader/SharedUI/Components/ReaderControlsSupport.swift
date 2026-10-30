import SwiftUI

// Reader display controls shared with Settings → Reading Defaults.

// MARK: - Double-Page Pairing

struct ReaderDoublePagePairingPicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var keepsFirstPageSingle: Bool

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Forms default to a menu; Settings moves it to the next page.
            pairingPicker
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Page Pairing")
                    .font(AppFont.subheadline())

                pairingPicker
                    .labelsHidden()
                    .pickerStyle(.segmented)
            }
        }
    }

    private var pairingPicker: some View {
        Picker("Page Pairing", selection: $keepsFirstPageSingle) {
            Text("Odd Page Ordering")
                .accessibilityHint("Pair pages 1 and 2, then 3 and 4")
                .tag(false)
            Text("Even Page Ordering")
                .accessibilityHint("Show page 1 alone, then pair pages 2 and 3, 4 and 5")
                .tag(true)
        }
    }
}

struct ReaderPageSpacingToggle: View {
    @Binding var isEnabled: Bool

    var body: some View {
        Toggle("Page Spacing", isOn: $isEnabled)
    }
}

struct ReaderRotatedContentHost<Content: View>: View {
    let rotation: ReaderRotationAngle
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let outerSize = proxy.size
            let innerSize = rotation.isQuarterTurn
                ? CGSize(width: outerSize.height, height: outerSize.width)
                : outerSize

            content()
                .frame(width: innerSize.width, height: innerSize.height)
                .rotationEffect(.degrees(Double(rotation.rawValue)))
                .position(x: outerSize.width * 0.5, y: outerSize.height * 0.5)
        }
        .clipped()
    }
}
