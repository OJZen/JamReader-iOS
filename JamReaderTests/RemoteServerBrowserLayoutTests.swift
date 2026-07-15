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

    func testAccessibilityTextExpandsRemoteBrowserCards() {
        let standardListHeight = RemoteBrowserDynamicTypeLayoutMetrics.listCardHeight(for: .large)
        let accessibilityListHeight = RemoteBrowserDynamicTypeLayoutMetrics.listCardHeight(
            for: .accessibilityExtraExtraExtraLarge
        )
        let standardGridLabelHeight = RemoteBrowserDynamicTypeLayoutMetrics.gridLabelHeight(for: .large)
        let accessibilityGridLabelHeight = RemoteBrowserDynamicTypeLayoutMetrics.gridLabelHeight(
            for: .accessibilityExtraExtraExtraLarge
        )

        XCTAssertGreaterThan(accessibilityListHeight, standardListHeight)
        XCTAssertGreaterThan(accessibilityGridLabelHeight, standardGridLabelHeight)
        XCTAssertGreaterThan(accessibilityListHeight, 156)
        XCTAssertGreaterThan(accessibilityGridLabelHeight, 124)
    }

    func testAccessibilitySectionHeaderFitsTitleAndMetadata() {
        let standardHeight = RemoteBrowserDynamicTypeLayoutMetrics.sectionHeaderHeight(
            title: "Folders",
            metadata: "3 folders",
            availableWidth: 361,
            contentSizeCategory: .large
        )
        let accessibilityHeight = RemoteBrowserDynamicTypeLayoutMetrics.sectionHeaderHeight(
            title: "Folders",
            metadata: "3 folders",
            availableWidth: 361,
            contentSizeCategory: .accessibilityExtraExtraExtraLarge
        )

        XCTAssertGreaterThan(accessibilityHeight, standardHeight)
        XCTAssertGreaterThan(accessibilityHeight, 84)
    }

    func testGridAccessibilityDescribesFolderAsActionableItem() {
        let item = RemoteDirectoryItem(
            serverID: UUID(),
            providerKind: .smb,
            shareName: "Comics",
            cacheScopeKey: "scope",
            path: "/Manga",
            name: "Manga",
            kind: .directory,
            fileSize: nil,
            modifiedAt: nil,
            pageCountHint: nil,
            coverPath: nil,
            previewItems: []
        )
        let row = RemoteBrowserListRowModel(
            item: item,
            readingSession: nil,
            cacheAvailability: .unavailable
        )

        XCTAssertTrue(RemoteBrowserGridAccessibility.value(for: row).contains("Folder"))
        XCTAssertEqual(RemoteBrowserGridAccessibility.hint(for: item), "Opens folder")
    }

    func testGridAccessibilityIncludesOfflineStateForComic() {
        let serverID = UUID()
        let item = RemoteDirectoryItem(
            serverID: serverID,
            providerKind: .smb,
            shareName: "Comics",
            cacheScopeKey: "scope",
            path: "/Manga/Book.cbz",
            name: "Book.cbz",
            kind: .comicFile,
            fileSize: 1_024,
            modifiedAt: nil,
            pageCountHint: nil,
            coverPath: nil,
            previewItems: []
        )
        let row = RemoteBrowserListRowModel(
            item: item,
            readingSession: nil,
            cacheAvailability: RemoteComicCachedAvailability(kind: .current)
        )

        XCTAssertTrue(RemoteBrowserGridAccessibility.value(for: row).contains("Offline Ready"))
        XCTAssertEqual(RemoteBrowserGridAccessibility.hint(for: item), "Opens comic")
    }

    func testGridAccessibilityKeepsOfflineStateAlongsideReadingProgress() {
        let serverID = UUID()
        let item = RemoteDirectoryItem(
            serverID: serverID,
            providerKind: .smb,
            shareName: "Comics",
            cacheScopeKey: "scope",
            path: "/Manga/Book.cbz",
            name: "Book.cbz",
            kind: .comicFile,
            fileSize: 1_024,
            modifiedAt: nil,
            pageCountHint: nil,
            coverPath: nil,
            previewItems: []
        )
        let readingSession = RemoteComicReadingSession(
            serverID: serverID,
            providerKind: .smb,
            serverName: "Server",
            shareName: "Comics",
            cacheScopeKey: "scope",
            path: item.path,
            fileName: item.name,
            pageCount: 20,
            currentPage: 4,
            hasBeenOpened: true,
            read: false,
            lastTimeOpened: Date(),
            fileSize: item.fileSize,
            modifiedAt: item.modifiedAt
        )
        let row = RemoteBrowserListRowModel(
            item: item,
            readingSession: readingSession,
            cacheAvailability: RemoteComicCachedAvailability(kind: .current)
        )

        let accessibilityValue = RemoteBrowserGridAccessibility.value(for: row)
        XCTAssertTrue(accessibilityValue.contains("Page 4 / 20"))
        XCTAssertTrue(accessibilityValue.contains("Offline Ready"))
    }
}
