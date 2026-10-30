import CoreGraphics

/// Columns for a full-width grid that a vertical fold crosses (iPhone Duo):
/// an even count, equal widths, and the middle gutter centred on the fold.
/// The narrower side keeps its outer inset; the other side's spare width goes
/// to its outer edge. Inactive folds count too, so opening or closing the
/// device only moves the gutter instead of reflowing the grid.
/// See docs/design-system/06-iphone-duo.md, "横跨竖向折叠区的网格".
struct FoldSplitGridMetrics: Equatable {
    let itemWidth: CGFloat
    /// Leading x of each column, in the container's coordinates.
    let columnOrigins: [CGFloat]

    var columns: Int {
        columnOrigins.count
    }

    /// The space between the two middle columns.
    var centerGutter: CGFloat {
        let half = columns / 2
        guard half > 0 else {
            return 0
        }
        return columnOrigins[half] - (columnOrigins[half - 1] + itemWidth)
    }

    /// `nil` when the fold does not cross the content, or a side has no room
    /// for one column.
    static func make(
        containerWidth: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        foldMinX: CGFloat,
        foldMaxX: CGFloat,
        minimumItemWidth: CGFloat,
        maximumItemWidth: CGFloat? = nil,
        spacing: CGFloat
    ) -> FoldSplitGridMetrics? {
        let contentMinX = leadingInset
        let contentMaxX = containerWidth - trailingInset
        guard foldMinX <= foldMaxX,
              foldMaxX > contentMinX,
              foldMinX < contentMaxX,
              minimumItemWidth > 0 else {
            return nil
        }

        let center = (foldMinX + foldMaxX) / 2
        let gutter = max(spacing, foldMaxX - foldMinX + spacing)
        let leftSpace = center - gutter / 2 - contentMinX
        let rightSpace = contentMaxX - (center + gutter / 2)
        let sideSpace = min(leftSpace, rightSpace)
        guard sideSpace >= minimumItemWidth else {
            return nil
        }

        let perSide = max(1, Int((sideSpace + spacing) / (minimumItemWidth + spacing)))
        var itemWidth = floor((sideSpace - CGFloat(perSide - 1) * spacing) / CGFloat(perSide))
        if let maximumItemWidth {
            itemWidth = min(itemWidth, maximumItemWidth)
        }
        let sideWidth = CGFloat(perSide) * itemWidth + CGFloat(perSide - 1) * spacing
        let leftStart = center - gutter / 2 - sideWidth
        let rightStart = center + gutter / 2
        let origins = (0..<perSide).map { leftStart + CGFloat($0) * (itemWidth + spacing) }
            + (0..<perSide).map { rightStart + CGFloat($0) * (itemWidth + spacing) }
        return FoldSplitGridMetrics(itemWidth: itemWidth, columnOrigins: origins)
    }
}
