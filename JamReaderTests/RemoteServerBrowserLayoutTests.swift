import SwiftUI
import UIKit
import XCTest
@testable import JamReader

@MainActor
final class RemoteServerBrowserLayoutTests: XCTestCase {
    func testIPadPortraitGridUsesFourColumns() {
        let context = RemoteServerBrowserLayoutContext(
            containerWidth: 834,
            horizontalSizeClass: .regular
        )

        let metrics = context.gridItemMetrics()

        XCTAssertEqual(metrics.columns, 4)
        XCTAssertEqual(metrics.itemWidth, 192, accuracy: 0.001)
    }

    func testIPadLandscapeGridUsesFiveColumns() {
        let context = RemoteServerBrowserLayoutContext(
            containerWidth: 1_194,
            horizontalSizeClass: .regular
        )

        let metrics = context.gridItemMetrics()

        XCTAssertEqual(metrics.columns, 5)
        XCTAssertEqual(metrics.itemWidth, 218, accuracy: 0.001)
    }

    func testIPadSplitViewGridKeepsFourColumnsWhenSpaceAllows() {
        let context = RemoteServerBrowserLayoutContext(
            containerWidth: 744,
            horizontalSizeClass: .regular
        )

        let metrics = context.gridItemMetrics()

        XCTAssertEqual(metrics.columns, 4)
        XCTAssertEqual(metrics.itemWidth, 170, accuracy: 0.001)
    }

    func testIPhoneGridUsesTwoColumns() {
        let context = RemoteServerBrowserLayoutContext(
            containerWidth: 393,
            horizontalSizeClass: .compact
        )

        let metrics = context.gridItemMetrics()

        XCTAssertEqual(metrics.columns, 2)
        XCTAssertEqual(metrics.itemWidth, 181, accuracy: 0.001)
    }

    func testCompositionalGroupUsesCalculatedAbsoluteItemWidth() throws {
        let group = RemoteBrowserGridLayoutFactory.makeHorizontalGroup(
            itemWidth: 192,
            itemHeight: 360,
            columns: 4,
            interItemSpacing: 12
        )

        let item = try XCTUnwrap(group.subitems.first)
        let widthDimension = item.layoutSize.widthDimension

        XCTAssertTrue(widthDimension.isAbsolute)
        XCTAssertFalse(widthDimension.isFractionalWidth)
        XCTAssertEqual(widthDimension.dimension, 192, accuracy: 0.001)
        XCTAssertEqual(group.layoutSize.heightDimension.dimension, 360, accuracy: 0.001)
        let interItemSpacing = try XCTUnwrap(group.interItemSpacing)
        XCTAssertEqual(interItemSpacing.spacing, 12, accuracy: 0.001)
    }
}
