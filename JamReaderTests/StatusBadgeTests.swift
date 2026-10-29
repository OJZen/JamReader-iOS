import SwiftUI
import UIKit
import XCTest
@testable import JamReader

final class StatusBadgeTests: XCTestCase {
    private let allStatuses: [StatusBadge.Status] = [
        .notDownloaded,
        .downloading(fraction: 0.62),
        .downloading(fraction: nil),
        .offline,
        .staleCopy,
        .failed,
        .read,
        .readOnly,
        .needsReauthorization
    ]

    func testEveryStatusHasTextAndAnIcon() throws {
        for status in allStatuses {
            XCTAssertFalse(status.title.isEmpty, "\(status)")

            if case .downloading = status {
                XCTAssertNil(status.systemImage, "Downloading draws a progress ring")
            } else {
                let systemImage = try XCTUnwrap(status.systemImage, "\(status)")
                XCTAssertNotNil(UIImage(systemName: systemImage), systemImage)
            }
        }
    }

    func testDownloadingTitleShowsClampedPercent() {
        XCTAssertEqual(StatusBadge.Status.downloading(fraction: 0.624).title, "Downloading 62%")
        XCTAssertEqual(StatusBadge.Status.downloading(fraction: 1.4).title, "Downloading 100%")
        XCTAssertEqual(StatusBadge.Status.downloading(fraction: -0.2).title, "Downloading 0%")
        XCTAssertEqual(StatusBadge.Status.downloading(fraction: nil).title, "Downloading")
    }

    /// Writes a badge sheet for visual acceptance when `JR_ACCEPTANCE_RENDER_DIR` is set
    /// (pass it as `TEST_RUNNER_JR_ACCEPTANCE_RENDER_DIR` to xcodebuild).
    @MainActor
    func testRenderBadgeSheetForAcceptance() throws {
        guard let directory = ProcessInfo.processInfo.environment["JR_ACCEPTANCE_RENDER_DIR"] else {
            throw XCTSkip("Set JR_ACCEPTANCE_RENDER_DIR to render the badge sheet.")
        }

        // The narrow AX5 variant shows titles wrapping between words and whole
        // badges moving to the next row.
        let variants: [(String, ColorScheme, DynamicTypeSize, CGFloat?)] = [
            ("light", .light, .large, nil),
            ("dark", .dark, .large, nil),
            ("light-ax5", .light, .accessibility5, nil),
            ("light-ax5-narrow", .light, .accessibility5, 240)
        ]
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for (name, scheme, typeSize, width) in variants {
            let sheet = Group {
                if let width {
                    WrappingHStack(horizontalSpacing: Spacing.xs, verticalSpacing: Spacing.xs) {
                        ForEach(allStatuses, id: \.self) { status in
                            StatusBadge(status: status)
                        }
                    }
                    .frame(width: width, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(allStatuses, id: \.self) { status in
                            StatusBadge(status: status)
                        }
                    }
                }
            }
            .padding(Spacing.md)
            .background(Color(.systemGroupedBackground))
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, typeSize)

            let renderer = ImageRenderer(content: sheet)
            renderer.scale = 3
            let data = try XCTUnwrap(renderer.uiImage?.pngData())
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("status-badges-\(name).png"))
        }
    }

    func testRemoteCopyStatesMapToTheSharedBadge() {
        XCTAssertNil(RemoteComicCachedAvailability.unavailable.statusBadgeStatus)
        XCTAssertEqual(RemoteComicCachedAvailability.unavailable.detailStatusBadgeStatus, .notDownloaded)
        XCTAssertEqual(RemoteComicCachedAvailability(kind: .current).detailStatusBadgeStatus, .offline)
        XCTAssertEqual(RemoteComicCachedAvailability(kind: .stale).detailStatusBadgeStatus, .staleCopy)
    }
}

/// Asset colors must keep the values from docs/design-system/tokens.json.
final class DesignTokenColorTests: XCTestCase {
    private struct Expectation {
        let asset: String
        let light: UInt32
        let dark: UInt32
        var alpha: (light: CGFloat, dark: CGFloat) = (1, 1)
    }

    private let expectations: [Expectation] = [
        Expectation(asset: "AccentColor", light: 0x9B1E56, dark: 0xE886B2),
        Expectation(asset: "Jam", light: 0x9B1E56, dark: 0xC23A76),
        Expectation(asset: "OnJam", light: 0xFFFFFF, dark: 0xFFFFFF),
        Expectation(asset: "JamDeep", light: 0x5C1233, dark: 0x5C1233),
        Expectation(asset: "ReaderAccent", light: 0xE886B2, dark: 0xE886B2),
        Expectation(asset: "AccentSoft", light: 0xFBE9F0, dark: 0x3E1528),
        Expectation(asset: "AccentOnSoft", light: 0x8A1D4E, dark: 0xF2A5C6),
        Expectation(asset: "StatusSuccess", light: 0x1E7B34, dark: 0x30D158),
        Expectation(asset: "StatusOffline", light: 0x0066CC, dark: 0x409CFF),
        Expectation(asset: "StatusWarning", light: 0xA05A00, dark: 0xFFB340),
        Expectation(asset: "StatusDanger", light: 0xD70015, dark: 0xFF6961),
        Expectation(asset: "StatusFavorite", light: 0xB97F00, dark: 0xFFD60A),
        Expectation(asset: "StatusSuccessSoft", light: 0x34C759, dark: 0x30D158, alpha: (0.14, 0.2)),
        Expectation(asset: "StatusOfflineSoft", light: 0x007AFF, dark: 0x0A84FF, alpha: (0.12, 0.22)),
        Expectation(asset: "StatusWarningSoft", light: 0xFF9500, dark: 0xFF9F0A, alpha: (0.14, 0.2)),
        Expectation(asset: "StatusDangerSoft", light: 0xFF3B30, dark: 0xFF453A, alpha: (0.12, 0.2)),
        Expectation(asset: "ChartDownloads", light: 0x4F6BB3, dark: 0x8FA6E8),
        Expectation(asset: "ChartTemp", light: 0x8E8E93, dark: 0xAEAEB2),
        Expectation(asset: "ChartThumbs", light: 0x48484A, dark: 0x757579)
    ]

    func testAssetColorsMatchTokens() throws {
        let bundle = Bundle(for: SceneDelegate.self)
        for expectation in expectations {
            let color = try XCTUnwrap(
                UIColor(named: expectation.asset, in: bundle, compatibleWith: nil),
                expectation.asset
            )
            assert(color, style: .light, equals: expectation.light, alpha: expectation.alpha.light, expectation.asset)
            assert(color, style: .dark, equals: expectation.dark, alpha: expectation.alpha.dark, expectation.asset)
        }
    }

    func testCoverRadiusAndGridTokens() {
        XCTAssertEqual(CornerRadius.thumbnail, 6)
        XCTAssertEqual(AppLayout.gridItemMinWidthCompact, 100)
        XCTAssertEqual(AppLayout.shelfCoverWidthCompact, 112)
        XCTAssertEqual(AppLayout.shelfCoverWidthRegular, 140)
    }

    func testRemoteTabUsesRemoteTitleAndServerSymbol() {
        XCTAssertEqual(AppRootTab.browse.title, "Remote")
        XCTAssertEqual(AppRootTab.browse.systemImage, "server.rack")
        XCTAssertEqual(AppRootTab.browse.selectedSystemImage, "server.rack")
    }

    private func assert(
        _ color: UIColor,
        style: UIUserInterfaceStyle,
        equals rgb: UInt32,
        alpha expectedAlpha: CGFloat,
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha), name, file: file, line: line)
        let actual = (UInt32((red * 255).rounded()) << 16)
            | (UInt32((green * 255).rounded()) << 8)
            | UInt32((blue * 255).rounded())
        XCTAssertEqual(
            String(format: "%06X", actual),
            String(format: "%06X", rgb),
            "\(name) \(style == .dark ? "dark" : "light")",
            file: file,
            line: line
        )
        XCTAssertEqual(alpha, expectedAlpha, accuracy: 0.002, "\(name) alpha", file: file, line: line)
    }
}
