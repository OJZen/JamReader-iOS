import SwiftUI
import UIKit

/// Icon + text capsule on a soft background. Color only supports the text;
/// VoiceOver reads the title. See docs/design-system/components/StatusBadge.
struct StatusBadge: View {
    enum Status: Hashable {
        // Remote copy: the one set of five states used across the app.
        case notDownloaded
        case downloading(fraction: Double?)
        case offline
        case staleCopy
        case failed
        // Reading and library access.
        case read
        case readOnly
        case needsReauthorization

        var title: String {
            switch self {
            case .notDownloaded:
                return String(localized: "Not Downloaded")
            case .downloading(let fraction):
                guard let fraction else {
                    return String(localized: "Downloading")
                }
                let percent = Int((min(max(fraction, 0), 1) * 100).rounded())
                return String(localized: "Downloading \(percent)%")
            case .offline:
                return String(localized: "Available Offline")
            case .staleCopy:
                return String(localized: "Older Copy")
            case .failed:
                return String(localized: "Download Failed")
            case .read:
                return String(localized: "Read")
            case .readOnly:
                return String(localized: "Read Only")
            case .needsReauthorization:
                return String(localized: "Needs Reauthorization")
            }
        }

        /// `nil` for `.downloading`, which draws a progress ring instead.
        var systemImage: String? {
            switch self {
            case .notDownloaded:
                return "arrow.down.circle"
            case .downloading:
                return nil
            case .offline:
                return "arrow.down.circle.fill"
            case .staleCopy:
                return "clock.badge.exclamationmark"
            case .failed:
                return "exclamationmark.triangle"
            case .read:
                return "checkmark.circle"
            case .readOnly:
                return "lock"
            case .needsReauthorization:
                return "lock.trianglebadge.exclamationmark"
            }
        }

        var foregroundColor: Color {
            switch self {
            case .notDownloaded:
                return .textSecondary
            case .downloading:
                return .appAccentOnSoft
            case .offline:
                return .appOffline
            case .staleCopy, .readOnly:
                return .appWarning
            case .failed, .needsReauthorization:
                return .appDanger
            case .read:
                return .appSuccess
            }
        }

        var backgroundColor: Color {
            switch self {
            case .notDownloaded:
                return Color(.tertiarySystemFill)
            case .downloading:
                return .appAccentSoft
            case .offline:
                return .appOfflineSoft
            case .staleCopy, .readOnly:
                return .appWarningSoft
            case .failed, .needsReauthorization:
                return .appDangerSoft
            case .read:
                return .appSuccessSoft
            }
        }

        /// Foreground for UIKit cells that show the status as an icon.
        var foregroundUIColor: UIColor {
            switch self {
            case .notDownloaded:
                return .secondaryLabel
            case .downloading:
                return UIColor(resource: .accentOnSoft)
            case .offline:
                return UIColor(resource: .statusOffline)
            case .staleCopy, .readOnly:
                return UIColor(resource: .statusWarning)
            case .failed, .needsReauthorization:
                return UIColor(resource: .statusDanger)
            case .read:
                return UIColor(resource: .statusSuccess)
            }
        }
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var wordSpacing: CGFloat = 3.5

    let status: Status

    var body: some View {
        let wraps = dynamicTypeSize.isAccessibilitySize
        content(wraps: wraps)
            .font(AppFont.caption(.semibold).monospacedDigit())
            .foregroundStyle(status.foregroundColor)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxxs)
            .frame(minHeight: 22)
            .background(
                status.backgroundColor,
                in: wraps
                    ? AnyShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
                    : AnyShape(Capsule())
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.title)
    }

    /// At accessibility sizes each word is laid out whole, so a long title
    /// wraps between words and never splits one.
    @ViewBuilder
    private func content(wraps: Bool) -> some View {
        if wraps {
            WrappingHStack(horizontalSpacing: wordSpacing, verticalSpacing: 0) {
                icon
                ForEach(Array(Self.words(in: status.title).enumerated()), id: \.offset) { _, word in
                    if Self.breaksWithinWords(word) {
                        Text(word)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(word)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
            }
        } else {
            HStack(spacing: Spacing.xxs) {
                icon
                Text(status.title)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if case .downloading(let fraction) = status {
            StatusBadgeProgressRing(fraction: fraction)
        } else if let systemImage = status.systemImage {
            Image(systemName: systemImage)
                .imageScale(.small)
        }
    }

    private static func words(in title: String) -> [String] {
        title.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Chinese and Japanese text has no spaces and may break between characters.
    private static func breaksWithinWords(_ word: String) -> Bool {
        word.unicodeScalars.contains { scalar in
            scalar.properties.isIdeographic || (0x3040...0x30FF).contains(scalar.value)
        }
    }
}

/// Lays out views in rows, starting a new row when the next view does not fit,
/// so status badges (and the words inside a wrapped badge) move whole.
struct WrappingHStack: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(maxWidth: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrangement(maxWidth: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrangement(maxWidth: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames = [CGRect]()
        var rowStart = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        func finishRow() {
            // Center items vertically within their row.
            for index in rowStart..<frames.count {
                frames[index].origin.y = y + (rowHeight - frames[index].height) / 2
            }
            y += rowHeight
        }

        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }

            if x > 0, x + size.width > maxWidth {
                finishRow()
                y += verticalSpacing
                rowStart = frames.count
                x = 0
                rowHeight = 0
            }

            frames.append(CGRect(origin: CGPoint(x: x, y: 0), size: size))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }

        if !frames.isEmpty {
            finishRow()
        }

        return (frames, CGSize(width: usedWidth, height: y))
    }
}

private struct StatusBadgeProgressRing: View {
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 11

    let fraction: Double?

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 2)
                .opacity(0.25)

            Circle()
                .trim(from: 0, to: min(max(fraction ?? 0.25, 0), 1))
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

extension RemoteComicCachedAvailability {
    /// Badge for a local copy, or `nil` when nothing is stored on this device.
    var statusBadgeStatus: StatusBadge.Status? {
        switch kind {
        case .unavailable:
            return nil
        case .current:
            return .offline
        case .stale:
            return .staleCopy
        }
    }

    /// Status for detail pages, which also name the remote-only state.
    var detailStatusBadgeStatus: StatusBadge.Status {
        statusBadgeStatus ?? .notDownloaded
    }
}
