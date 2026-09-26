import SwiftUI
import XCTest
@testable import JamReader

final class ReaderVerticalThumbnailRailGeometryTests: XCTestCase {
    func testRailContainsEveryPageInDocumentOrder() {
        let indices = ReaderVerticalThumbnailRailGeometry.pageIndices(pageCount: 100)

        XCTAssertEqual(Array(indices), Array(0..<100))
    }

    func testFocusInfluenceFallsOffAcrossTwoNeighborGroups() {
        let focused = ReaderVerticalThumbnailRailGeometry.focusInfluence(pageDistance: 0)
        let firstNeighbor = ReaderVerticalThumbnailRailGeometry.focusInfluence(pageDistance: 1)
        let secondNeighbor = ReaderVerticalThumbnailRailGeometry.focusInfluence(pageDistance: 2)
        let distantPage = ReaderVerticalThumbnailRailGeometry.focusInfluence(pageDistance: 3)

        XCTAssertGreaterThan(focused, firstNeighbor)
        XCTAssertGreaterThan(firstNeighbor, secondNeighbor)
        XCTAssertGreaterThan(secondNeighbor, distantPage)
        XCTAssertEqual(distantPage, 0)
    }

    func testDenseRailThumbnailStaysSmallerThanItsNaturalStride() {
        let thumbnailHeight = ReaderVerticalThumbnailRailGeometry.compactThumbnailHeight(
            naturalStride: 4.4,
            maximumHeight: 10,
            minimumGap: 0.8
        )

        XCTAssertEqual(thumbnailHeight, 3.6, accuracy: 0.001)
        XCTAssertLessThan(thumbnailHeight, 4.4)
    }

    func testSubpixelRailThumbnailStillFitsInsideItsSlot() {
        let naturalStride: CGFloat = 0.1
        let minimumGap: CGFloat = 0.035
        let thumbnailHeight = ReaderVerticalThumbnailRailGeometry.compactThumbnailHeight(
            naturalStride: naturalStride,
            maximumHeight: 10,
            minimumGap: minimumGap
        )

        XCTAssertLessThanOrEqual(thumbnailHeight + minimumGap, naturalStride + 0.001)
    }

    func testCompactTrackHeightGrowsWithPageCountAndStopsAtItsLimit() {
        let shortDocumentHeight = ReaderVerticalThumbnailRailGeometry.compactTrackHeight(
            pageCount: 5,
            preferredPageStride: 2.8,
            focusInset: 58,
            minimumHeight: 120,
            maximumHeight: 380
        )
        let mediumDocumentHeight = ReaderVerticalThumbnailRailGeometry.compactTrackHeight(
            pageCount: 30,
            preferredPageStride: 2.8,
            focusInset: 58,
            minimumHeight: 120,
            maximumHeight: 380
        )
        let longDocumentHeight = ReaderVerticalThumbnailRailGeometry.compactTrackHeight(
            pageCount: 200,
            preferredPageStride: 2.8,
            focusInset: 58,
            minimumHeight: 120,
            maximumHeight: 380
        )

        XCTAssertEqual(shortDocumentHeight, 127.2, accuracy: 0.001)
        XCTAssertEqual(mediumDocumentHeight, 197.2, accuracy: 0.001)
        XCTAssertEqual(longDocumentHeight, 380, accuracy: 0.001)
        XCTAssertLessThan(shortDocumentHeight, mediumDocumentHeight)
        XCTAssertLessThan(mediumDocumentHeight, longDocumentHeight)
    }

    func testCompactTrackHeightHonorsSmallViewportLimit() {
        let height = ReaderVerticalThumbnailRailGeometry.compactTrackHeight(
            pageCount: 100,
            preferredPageStride: 3.8,
            focusInset: 72,
            minimumHeight: 148,
            maximumHeight: 84
        )

        XCTAssertEqual(height, 84, accuracy: 0.001)
    }

    func testIPadTrackUsesLargerDensityWithoutExceedingItsLimit() {
        let height = ReaderVerticalThumbnailRailGeometry.compactTrackHeight(
            pageCount: 100,
            preferredPageStride: 3.8,
            focusInset: 72,
            minimumHeight: 148,
            maximumHeight: 540
        )

        XCTAssertEqual(height, 520.2, accuracy: 0.001)
        XCTAssertLessThanOrEqual(height, 540)
    }

    func testMagnificationPushesTheRemainingRailAwayFromFocus() {
        let upperBaseCenter = ReaderVerticalThumbnailRailGeometry.thumbCenterY(
            pageIndex: 46,
            pageCount: 100,
            trackHeight: compactTrackHeight,
            trackInset: compactTrackInset
        )
        let lowerBaseCenter = ReaderVerticalThumbnailRailGeometry.thumbCenterY(
            pageIndex: 52,
            pageCount: 100,
            trackHeight: compactTrackHeight,
            trackInset: compactTrackInset
        )
        let upperMagnifiedCenter = magnifiedCenter(pageIndex: 46, focusedPagePosition: 49)
        let lowerMagnifiedCenter = magnifiedCenter(pageIndex: 52, focusedPagePosition: 49)

        XCTAssertLessThan(upperMagnifiedCenter, upperBaseCenter)
        XCTAssertGreaterThan(lowerMagnifiedCenter, lowerBaseCenter)
    }

    func testMagnifiedPagesStaySeparateAndInsideCompactTrackDuringAnimation() {
        assertMagnifiedPagesStaySeparateAndInsideTrack(
            trackHeight: compactTrackHeight,
            trackInset: compactTrackInset,
            thumbnailHeight: compactThumbnailHeight,
            maximumThumbnailHeight: 44,
            minimumGap: compactMinimumGap
        )
    }

    func testLargerIPadMagnificationStaysInsideCompactTrack() {
        let trackHeight: CGFloat = 520.2
        let trackInset: CGFloat = 72
        let naturalStride = ReaderVerticalThumbnailRailGeometry.naturalPageStride(
            pageCount: 100,
            trackHeight: trackHeight,
            trackInset: trackInset
        )
        let minimumGap = min(
            max(naturalStride * 0.18, 0.08),
            naturalStride * 0.35
        )
        let thumbnailHeight = ReaderVerticalThumbnailRailGeometry.compactThumbnailHeight(
            naturalStride: naturalStride,
            maximumHeight: 12,
            minimumGap: minimumGap
        )
        let maximumThumbnailHeight = 56 * (trackHeight / 540)

        assertMagnifiedPagesStaySeparateAndInsideTrack(
            trackHeight: trackHeight,
            trackInset: trackInset,
            thumbnailHeight: thumbnailHeight,
            maximumThumbnailHeight: maximumThumbnailHeight,
            minimumGap: minimumGap
        )
    }

    func testAdaptivePresetsPackItemsWithinPhoneAndPadTracks() {
        let configurations: [(UIUserInterfaceIdiom, CGSize, EdgeInsets)] = [
            (
                .phone,
                CGSize(width: 390, height: 844),
                EdgeInsets(top: 47, leading: 0, bottom: 34, trailing: 0)
            ),
            (
                .pad,
                CGSize(width: 834, height: 1_194),
                EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
            )
        ]

        for (idiom, viewportSize, safeAreaInsets) in configurations {
            for pageCount in [2, 5, 10, 19, 20, 30, 60, 100, 500, 1_000] {
                let layout = ReaderVerticalThumbnailRailLayout.adaptive(
                    viewportSize: viewportSize,
                    safeAreaInsets: safeAreaInsets,
                    pageCount: pageCount,
                    userInterfaceIdiom: idiom
                )
                XCTAssertLessThanOrEqual(layout.trackHeight, viewportSize.height * 2 / 3)
                let widths: [CGFloat] = idiom == .pad ? [6, 10, 16, 24] : [4, 8, 12, 18]
                XCTAssertTrue(widths.contains(layout.railThumbnailWidth))
                let naturalStride = ReaderVerticalThumbnailRailGeometry.naturalPageStride(
                    pageCount: pageCount,
                    trackHeight: layout.trackHeight,
                    trackInset: layout.trackInset
                )
                XCTAssertEqual(
                    naturalStride - layout.railThumbnailHeight,
                    layout.minimumThumbnailGap,
                    accuracy: 0.001
                )
                XCTAssertLessThanOrEqual(layout.minimumThumbnailGap, 1)
                let finalPagePosition = CGFloat(pageCount - 1)
                let leadingFocusPositions = Array(
                    stride(from: CGFloat.zero, through: min(finalPagePosition, 4), by: 0.25)
                )
                let focusPositions = leadingFocusPositions
                    + [finalPagePosition / 2]
                    + leadingFocusPositions.map { finalPagePosition - $0 }

                assertMagnifiedPagesStaySeparateAndInsideTrack(
                    trackHeight: layout.trackHeight,
                    trackInset: layout.trackInset,
                    thumbnailHeight: layout.railThumbnailHeight,
                    maximumThumbnailHeight: layout.maximumFocusedThumbnailHeight,
                    minimumGap: layout.minimumThumbnailGap,
                    pageCount: pageCount,
                    focusPositions: focusPositions
                )
            }
        }
    }

    func testWidestPresetCapsShortDocumentSize() {
        let viewportSize = CGSize(width: 834, height: 1_194)
        let insets = EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
        for idiom in [UIUserInterfaceIdiom.phone, .pad] {
            for pageCount in [2, 5, 10] {
                let layout = ReaderVerticalThumbnailRailLayout.adaptive(
                    viewportSize: viewportSize,
                    safeAreaInsets: insets,
                    pageCount: pageCount,
                    userInterfaceIdiom: idiom
                )

                XCTAssertEqual(layout.railThumbnailWidth, idiom == .pad ? 24 : 18)
                XCTAssertEqual(layout.railThumbnailHeight, layout.railThumbnailWidth * 1.5, accuracy: 0.001)
                XCTAssertLessThan(layout.trackHeight, viewportSize.height * 2 / 3)
            }
        }
    }

    func testIPadChoosesNarrowerPresetsForMorePages() {
        let configurations: [(Int, CGFloat)] = [(10, 24), (25, 16), (40, 10), (60, 6), (1_000, 6)]
        for (pageCount, expectedWidth) in configurations {
            let layout = ReaderVerticalThumbnailRailLayout.adaptive(
                viewportSize: CGSize(width: 834, height: 1_194),
                safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0),
                pageCount: pageCount,
                userInterfaceIdiom: .pad
            )

            XCTAssertEqual(layout.railThumbnailWidth, expectedWidth)
            if pageCount == 1_000 {
                XCTAssertEqual(layout.trackHeight, 796, accuracy: 0.001)
                XCTAssertLessThan(layout.railThumbnailHeight, expectedWidth * 1.5)
            }
        }
    }

    func testAdaptiveTrackHonorsLandscapeAndSmallWindowClearance() {
        for viewportSize in [CGSize(width: 844, height: 390), CGSize(width: 600, height: 200)] {
            let insets = EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
            let layout = ReaderVerticalThumbnailRailLayout.adaptive(
                viewportSize: viewportSize,
                safeAreaInsets: insets,
                pageCount: 1_000,
                userInterfaceIdiom: .pad
            )

            XCTAssertEqual(
                layout.trackHeight,
                min(viewportSize.height * 2 / 3, viewportSize.height - 24 - 20 - 112),
                accuracy: 0.001
            )
        }
    }

    private func assertMagnifiedPagesStaySeparateAndInsideTrack(
        trackHeight: CGFloat,
        trackInset: CGFloat,
        thumbnailHeight: CGFloat,
        maximumThumbnailHeight: CGFloat,
        minimumGap: CGFloat,
        pageCount: Int = 100,
        focusPositions: [CGFloat]? = nil
    ) {
        let pageIndices = Array(0..<pageCount)
        let resolvedFocusPositions = focusPositions ?? Array(
            stride(
                from: CGFloat.zero,
                through: CGFloat(pageIndices.count - 1),
                by: 0.5
            )
        )

        for focusPosition in resolvedFocusPositions {
            let centers = pageIndices.map {
                ReaderVerticalThumbnailRailGeometry.magnifiedThumbCenterY(
                    pageIndex: $0,
                    focusedPagePosition: focusPosition,
                    pageCount: pageIndices.count,
                    trackHeight: trackHeight,
                    trackInset: trackInset,
                    baseThumbnailHeight: thumbnailHeight,
                    maximumThumbnailHeight: maximumThumbnailHeight,
                    minimumGap: minimumGap
                )
            }
            let heights = pageIndices.map { pageIndex in
                ReaderVerticalThumbnailRailGeometry.magnifiedDimension(
                    base: thumbnailHeight,
                    maximum: maximumThumbnailHeight,
                    influence: ReaderVerticalThumbnailRailGeometry.focusInfluence(
                        pageDistance: CGFloat(pageIndex) - focusPosition
                    )
                )
            }

            for index in 0..<(pageIndices.count - 1) {
                let actualGap = centers[index + 1] - centers[index]
                let requiredGap = (heights[index] + heights[index + 1]) / 2
                    + minimumGap
                XCTAssertGreaterThanOrEqual(
                    actualGap + 0.001,
                    requiredGap,
                    "Overlap at focus position \(focusPosition), page \(index)"
                )
            }

            XCTAssertGreaterThanOrEqual(
                centers[0] - heights[0] / 2,
                0,
                "Top overflow at focus position \(focusPosition)"
            )
            XCTAssertLessThanOrEqual(
                centers[pageCount - 1] + heights[pageCount - 1] / 2,
                trackHeight,
                "Bottom overflow at focus position \(focusPosition)"
            )
        }
    }

    func testThumbPositionMapsFirstAndLastPagesToTravelEnds() {
        let firstCenter = ReaderVerticalThumbnailRailGeometry.thumbCenterY(
            pageIndex: 0,
            pageCount: 10,
            trackHeight: 400,
            trackInset: 31
        )
        let lastCenter = ReaderVerticalThumbnailRailGeometry.thumbCenterY(
            pageIndex: 9,
            pageCount: 10,
            trackHeight: 400,
            trackInset: 31
        )

        XCTAssertEqual(firstCenter, 31, accuracy: 0.001)
        XCTAssertEqual(lastCenter, 369, accuracy: 0.001)
    }

    func testDragLocationMapsToNearestPageAndClampsAtEdges() {
        XCTAssertEqual(
            ReaderVerticalThumbnailRailGeometry.pageIndex(
                at: -100,
                pageCount: 10,
                trackHeight: 400,
                trackInset: 31
            ),
            0
        )
        XCTAssertEqual(
            ReaderVerticalThumbnailRailGeometry.pageIndex(
                at: 200,
                pageCount: 10,
                trackHeight: 400,
                trackInset: 31
            ),
            5
        )
        XCTAssertEqual(
            ReaderVerticalThumbnailRailGeometry.pageIndex(
                at: 500,
                pageCount: 10,
                trackHeight: 400,
                trackInset: 31
            ),
            9
        )
    }

    private let compactTrackHeight: CGFloat = 380
    private let compactTrackInset: CGFloat = 58

    private var compactNaturalStride: CGFloat {
        ReaderVerticalThumbnailRailGeometry.naturalPageStride(
            pageCount: 100,
            trackHeight: compactTrackHeight,
            trackInset: compactTrackInset
        )
    }

    private var compactMinimumGap: CGFloat {
        min(
            max(compactNaturalStride * 0.18, 0.08),
            compactNaturalStride * 0.35
        )
    }

    private var compactThumbnailHeight: CGFloat {
        ReaderVerticalThumbnailRailGeometry.compactThumbnailHeight(
            naturalStride: compactNaturalStride,
            maximumHeight: 10,
            minimumGap: compactMinimumGap
        )
    }

    private func magnifiedCenter(
        pageIndex: Int,
        focusedPagePosition: CGFloat
    ) -> CGFloat {
        ReaderVerticalThumbnailRailGeometry.magnifiedThumbCenterY(
            pageIndex: pageIndex,
            focusedPagePosition: focusedPagePosition,
            pageCount: 100,
            trackHeight: compactTrackHeight,
            trackInset: compactTrackInset,
            baseThumbnailHeight: compactThumbnailHeight,
            maximumThumbnailHeight: 44,
            minimumGap: compactMinimumGap
        )
    }
}
