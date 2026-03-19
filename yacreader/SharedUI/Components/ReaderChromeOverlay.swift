import SwiftUI

struct ReaderSurface<Content: View, TopBar: View, BottomBar: View, StatusOverlay: View, ModalOverlay: View>: View {
    let isInteractionLocked: Bool
    let isChromeHidden: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let topBar: () -> TopBar
    @ViewBuilder let bottomBar: () -> BottomBar
    @ViewBuilder let statusOverlay: () -> StatusOverlay
    @ViewBuilder let modalOverlay: () -> ModalOverlay

    var body: some View {
        ZStack {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(!isInteractionLocked)

            ReaderChromeOverlay(isHidden: isChromeHidden) {
                topBar()
            } bottomBar: {
                bottomBar()
            }
            .allowsHitTesting(!isInteractionLocked)

            ReaderTopStatusStack(isChromeHidden: isChromeHidden) {
                statusOverlay()
            }
            .allowsHitTesting(!isInteractionLocked)

            modalOverlay()
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
    }
}

struct ReaderChromeOverlay<TopBar: View, BottomBar: View>: View {
    let isHidden: Bool
    @ViewBuilder let topBar: () -> TopBar
    @ViewBuilder let bottomBar: () -> BottomBar

    var body: some View {
        VStack(spacing: 0) {
            if !isHidden {
                topBar()
                    .padding(.top, 12)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 0)

            if !isHidden {
                bottomBar()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: isHidden)
    }
}

struct ReaderTopBar<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let onBack: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ReaderChromeBar {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward")
                        .font(.headline.weight(.semibold))
                }

                VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                trailing()
            }
        }
    }
}

struct ReaderTopStatusStack<Content: View>: View {
    let isChromeHidden: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 8) {
            if !isChromeHidden {
                content()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 88)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: isChromeHidden)
    }
}

struct ReaderChromeBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}

struct ReaderStatusBadge<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

struct ReaderChromePill<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}
