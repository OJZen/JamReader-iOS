import CoreGraphics
import Foundation

enum ReaderSpreadMode: String, CaseIterable, Hashable {
    case singlePage
    case doublePage

    var title: String {
        switch self {
        case .singlePage:
            return "Single Page"
        case .doublePage:
            return "Double Page"
        }
    }
}

enum ReaderReadingDirection: String, CaseIterable, Hashable {
    case leftToRight
    case rightToLeft

    var title: String {
        switch self {
        case .leftToRight:
            return "Left to Right"
        case .rightToLeft:
            return "Right to Left"
        }
    }
}

enum ReaderFitMode: String, CaseIterable, Hashable {
    case page
    case width
    case height
    case originalSize

    var title: String {
        switch self {
        case .page:
            return "Fit Page"
        case .width:
            return "Fit Width"
        case .height:
            return "Fit Height"
        case .originalSize:
            return "Original Size"
        }
    }
}

enum ReaderRotationAngle: Int, CaseIterable, Hashable {
    case degrees0 = 0
    case degrees90 = 90
    case degrees180 = 180
    case degrees270 = 270

    var title: String {
        "\(rawValue)°"
    }

    var radians: CGFloat {
        CGFloat(rawValue) * .pi / 180
    }

    var isQuarterTurn: Bool {
        self == .degrees90 || self == .degrees270
    }

    func rotatedClockwise() -> ReaderRotationAngle {
        switch self {
        case .degrees0:
            return .degrees90
        case .degrees90:
            return .degrees180
        case .degrees180:
            return .degrees270
        case .degrees270:
            return .degrees0
        }
    }

    func rotatedCounterClockwise() -> ReaderRotationAngle {
        switch self {
        case .degrees0:
            return .degrees270
        case .degrees90:
            return .degrees0
        case .degrees180:
            return .degrees90
        case .degrees270:
            return .degrees180
        }
    }

    func rotatedSize(for size: CGSize) -> CGSize {
        guard isQuarterTurn else {
            return size
        }

        return CGSize(width: size.height, height: size.width)
    }
}

struct ReaderDisplayLayout: Equatable {
    var spreadMode: ReaderSpreadMode
    var readingDirection: ReaderReadingDirection
    var coverAsSinglePage: Bool
    var fitMode: ReaderFitMode
    var rotation: ReaderRotationAngle

    init(
        spreadMode: ReaderSpreadMode = .singlePage,
        readingDirection: ReaderReadingDirection = .leftToRight,
        coverAsSinglePage: Bool = true,
        fitMode: ReaderFitMode = .page,
        rotation: ReaderRotationAngle = .degrees0
    ) {
        self.spreadMode = spreadMode
        self.readingDirection = readingDirection
        self.coverAsSinglePage = coverAsSinglePage
        self.fitMode = fitMode
        self.rotation = rotation
    }

    init(defaultsFor type: LibraryFileType) {
        switch type {
        case .manga, .yonkoma:
            self.init(spreadMode: .singlePage, readingDirection: .rightToLeft, coverAsSinglePage: true, fitMode: .page)
        case .westernManga, .comic, .webComic:
            self.init(spreadMode: .singlePage, readingDirection: .leftToRight, coverAsSinglePage: true, fitMode: .page)
        }
    }

    func normalized(allowingDoublePageSpread: Bool) -> ReaderDisplayLayout {
        guard !allowingDoublePageSpread, spreadMode == .doublePage else {
            return self
        }

        var adjustedLayout = self
        adjustedLayout.spreadMode = .singlePage
        return adjustedLayout
    }
}

struct ReaderSpreadDescriptor: Equatable {
    let pageIndices: [Int]

    var primaryPageIndex: Int {
        pageIndices.min() ?? 0
    }

    func displayPageIndices(for direction: ReaderReadingDirection) -> [Int] {
        guard direction == .rightToLeft, pageIndices.count > 1 else {
            return pageIndices
        }

        return pageIndices.reversed()
    }

    static func makeSpreads(pageCount: Int, layout: ReaderDisplayLayout) -> [ReaderSpreadDescriptor] {
        guard pageCount > 0 else {
            return []
        }

        switch layout.spreadMode {
        case .singlePage:
            return (0..<pageCount).map { ReaderSpreadDescriptor(pageIndices: [$0]) }
        case .doublePage:
            var spreads: [ReaderSpreadDescriptor] = []
            var currentIndex = 0

            if layout.coverAsSinglePage {
                spreads.append(ReaderSpreadDescriptor(pageIndices: [0]))
                currentIndex = 1
            }

            while currentIndex < pageCount {
                let nextIndex = currentIndex + 1
                if nextIndex < pageCount {
                    spreads.append(ReaderSpreadDescriptor(pageIndices: [currentIndex, nextIndex]))
                    currentIndex += 2
                } else {
                    spreads.append(ReaderSpreadDescriptor(pageIndices: [currentIndex]))
                    currentIndex += 1
                }
            }

            return spreads
        }
    }

    static func spreadIndex(containing pageIndex: Int, in spreads: [ReaderSpreadDescriptor]) -> Int? {
        spreads.firstIndex { $0.pageIndices.contains(pageIndex) }
    }
}
