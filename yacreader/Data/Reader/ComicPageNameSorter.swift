import Foundation

enum ComicPageNameSorter {
    nonisolated static let supportedImageExtensions: Set<String> = [
        "jpg",
        "jpeg",
        "png",
        "gif",
        "tiff",
        "tif",
        "bmp",
        "webp"
    ]

    nonisolated static func isSupportedImagePath(_ path: String) -> Bool {
        let sanitizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedPath.isEmpty else {
            return false
        }

        if sanitizedPath.split(separator: "/").contains(where: { $0 == "__MACOSX" }) {
            return false
        }

        let pathExtension = URL(fileURLWithPath: sanitizedPath).pathExtension.lowercased()
        return supportedImageExtensions.contains(pathExtension)
    }

    nonisolated static func sortedPageNames(_ pageNames: [String]) -> [String] {
        let naturallySorted = pageNames.sorted(by: naturalLessThan)
        guard naturallySorted.count < 1_000 else {
            return naturallySorted
        }

        let partition = partitionDoublePages(in: naturallySorted)
        return merge(singlePages: partition.singlePages, doublePages: partition.doublePages)
    }

    nonisolated private static func naturalLessThan(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    nonisolated private static func partitionDoublePages(in pageNames: [String]) -> (singlePages: [String], doublePages: [String]) {
        let maxExpectedLength = String(pageNames.count).count * 2
        let commonPrefix = mostCommonPrefix(in: pageNames)

        var singlePages: [String] = []
        var doublePages: [String] = []

        for pageName in pageNames {
            let fileName = lastPathComponent(of: pageName)
            if isDoublePage(
                fileName,
                commonPrefix: commonPrefix,
                maxExpectedDoublePageNumberLength: maxExpectedLength
            ) {
                doublePages.append(pageName)
            } else {
                singlePages.append(pageName)
            }
        }

        return (singlePages, doublePages)
    }

    nonisolated private static func merge(singlePages: [String], doublePages: [String]) -> [String] {
        var merged: [String] = []
        merged.reserveCapacity(singlePages.count + doublePages.count)

        var singleIndex = 0
        var doubleIndex = 0

        while singleIndex < singlePages.count, doubleIndex < doublePages.count {
            if naturalLessThan(singlePages[singleIndex], doublePages[doubleIndex]) {
                merged.append(singlePages[singleIndex])
                singleIndex += 1
            } else {
                merged.append(doublePages[doubleIndex])
                doubleIndex += 1
            }
        }

        if singleIndex < singlePages.count {
            merged.append(contentsOf: singlePages[singleIndex...])
        }

        if doubleIndex < doublePages.count {
            merged.append(contentsOf: doublePages[doubleIndex...])
        }

        return merged
    }

    nonisolated private static func mostCommonPrefix(in pageNames: [String]) -> String {
        guard let firstPage = pageNames.first else {
            return ""
        }

        if pageNames.count == 1 {
            let candidate = stripTrailingDigits(from: lastPathComponent(of: firstPage))
            return candidate.allSatisfy(\.isNumber) ? "" : candidate
        }

        var frequency: [String: Int] = [:]
        var currentPrefixLength = lastPathComponent(of: firstPage).count
        var currentPrefixCount = 1
        var previous = lastPathComponent(of: firstPage)

        for index in 1..<pageNames.count {
            let current = lastPathComponent(of: pageNames[index])
            let sharedPrefixLength = sharedPrefixCount(lhs: previous, rhs: current)

            if sharedPrefixLength < currentPrefixLength, sharedPrefixLength > 0 {
                let key = String(previous.prefix(currentPrefixLength))
                frequency[key] = currentPrefixCount
                currentPrefixLength = sharedPrefixLength
                currentPrefixCount += 1
            } else if sharedPrefixLength == 0 {
                let key = String(previous.prefix(currentPrefixLength))
                frequency[key] = currentPrefixCount
                currentPrefixLength = current.count
                currentPrefixCount = 1
            } else {
                currentPrefixCount += 1
            }

            previous = current
        }

        let finalKey = String(previous.prefix(currentPrefixLength))
        frequency[finalKey] = currentPrefixCount

        let bestMatch = frequency.max { lhs, rhs in
            lhs.value < rhs.value
        }

        guard let prefix = bestMatch?.key, let frequencyCount = bestMatch?.value else {
            return ""
        }

        if prefix.allSatisfy(\.isNumber) {
            return ""
        }

        if Double(frequencyCount) < Double(pageNames.count) * 0.60 {
            return ""
        }

        return prefix
    }

    nonisolated private static func isDoublePage(
        _ pageName: String,
        commonPrefix: String,
        maxExpectedDoublePageNumberLength: Int
    ) -> Bool {
        guard pageName.hasPrefix(commonPrefix) else {
            return false
        }

        let suffix = pageName.dropFirst(commonPrefix.count)
        let pageNumberSubstring = String(suffix.prefix(while: \.isNumber))

        guard pageNumberSubstring.count >= 3,
              pageNumberSubstring.count <= maxExpectedDoublePageNumberLength,
              pageNumberSubstring.count.isMultiple(of: 2)
        else {
            return false
        }

        let halfLength = pageNumberSubstring.count / 2
        let leftValue = Int(pageNumberSubstring.prefix(halfLength)) ?? 0
        let rightValue = Int(pageNumberSubstring.suffix(halfLength)) ?? 0

        guard leftValue > 0, rightValue > 0 else {
            return false
        }

        return (rightValue - leftValue) == 1
    }

    nonisolated private static func sharedPrefixCount(lhs: String, rhs: String) -> Int {
        var count = 0
        for (leftCharacter, rightCharacter) in zip(lhs, rhs) {
            guard leftCharacter == rightCharacter else {
                break
            }

            count += 1
        }

        return count
    }

    nonisolated private static func stripTrailingDigits(from value: String) -> String {
        String(value.dropLast(value.reversed().prefix(while: \.isNumber).count))
    }

    nonisolated private static func lastPathComponent(of path: String) -> String {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = normalizedPath.split(separator: "/", omittingEmptySubsequences: true)
        return components.last.map(String.init) ?? normalizedPath
    }
}
