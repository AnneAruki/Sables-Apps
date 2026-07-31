//
//  SableEagerAdaptiveGrid.swift
//  Sable's Library
//

import SwiftUI

struct SableEagerAdaptiveGrid: Layout {
    var minimumItemWidth: CGFloat
    var maximumItemWidth: CGFloat?
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    init(
        minimumItemWidth: CGFloat,
        maximumItemWidth: CGFloat? = nil,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat
    ) {
        self.minimumItemWidth = minimumItemWidth
        self.maximumItemWidth = maximumItemWidth
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else {
            return CGSize(width: proposal.width ?? 0, height: 0)
        }

        let metrics = metrics(
            availableWidth: proposal.width ?? minimumItemWidth,
            subviews: subviews
        )
        return CGSize(
            width: proposal.width ?? metrics.contentWidth,
            height: metrics.contentHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }

        let metrics = metrics(
            availableWidth: bounds.width,
            subviews: subviews
        )
        var rowOriginY = bounds.minY

        for row in metrics.rowHeights.indices {
            let start = row * metrics.columnCount
            let end = min(start + metrics.columnCount, subviews.count)

            for index in start..<end {
                let column = index - start
                subviews[index].place(
                    at: CGPoint(
                        x:
                            bounds.minX
                            + CGFloat(column)
                                * (
                                    metrics.itemWidth
                                        + horizontalSpacing
                                ),
                        y: rowOriginY
                    ),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(
                        width: metrics.itemWidth,
                        height: nil
                    )
                )
            }

            rowOriginY += metrics.rowHeights[row]
            if row < metrics.rowHeights.count - 1 {
                rowOriginY += verticalSpacing
            }
        }
    }

    private func metrics(
        availableWidth rawWidth: CGFloat,
        subviews: Subviews
    ) -> Metrics {
        let availableWidth =
            rawWidth.isFinite
            ? max(0, rawWidth)
            : minimumItemWidth
        let columnCount = max(
            1,
            Int(
                (availableWidth + horizontalSpacing)
                    / (minimumItemWidth + horizontalSpacing)
            )
        )
        let uncappedItemWidth = max(
            0,
            (
                availableWidth
                    - CGFloat(columnCount - 1) * horizontalSpacing
            ) / CGFloat(columnCount)
        )
        let itemWidth = min(
            maximumItemWidth ?? uncappedItemWidth,
            uncappedItemWidth
        )
        let rowCount = Int(
            ceil(Double(subviews.count) / Double(columnCount))
        )
        var rowHeights = Array(repeating: CGFloat.zero, count: rowCount)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(
                ProposedViewSize(width: itemWidth, height: nil)
            )
            let row = index / columnCount
            rowHeights[row] = max(rowHeights[row], size.height)
        }

        return Metrics(
            columnCount: columnCount,
            itemWidth: itemWidth,
            rowHeights: rowHeights,
            contentWidth:
                CGFloat(columnCount) * itemWidth
                + CGFloat(columnCount - 1) * horizontalSpacing,
            contentHeight:
                rowHeights.reduce(0, +)
                + CGFloat(max(0, rowCount - 1)) * verticalSpacing
        )
    }

    private struct Metrics {
        var columnCount: Int
        var itemWidth: CGFloat
        var rowHeights: [CGFloat]
        var contentWidth: CGFloat
        var contentHeight: CGFloat
    }
}
