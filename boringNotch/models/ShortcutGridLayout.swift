//
//  ShortcutGridLayout.swift
//  boringNotch
//
//  Works out how to fill the shortcuts panel with tiles and no dead space.
//

import CoreGraphics
import Foundation

/// A solved arrangement: how many columns, and the exact tile size that fills
/// the available area.
struct ShortcutGridSolution: Equatable {
    var columns: Int
    var rows: Int
    var tileWidth: CGFloat
    var tileHeight: CGFloat
    /// True when the tiles cannot be shrunk enough to fit the available height,
    /// so the caller must make the panel scrollable rather than let them spill.
    var scrolls: Bool = false

    func totalHeight(spacing: CGFloat) -> CGFloat {
        tileHeight * CGFloat(rows) + spacing * CGFloat(max(0, rows - 1))
    }

    func totalWidth(spacing: CGFloat) -> CGFloat {
        tileWidth * CGFloat(columns) + spacing * CGFloat(max(0, columns - 1))
    }
}

enum ShortcutGridLayout {
    static let minTileWidth: CGFloat = 44
    static let minTileHeight: CGFloat = 34
    /// Tiles are allowed to grow past the preferred size, but only so far —
    /// otherwise two shortcuts in a tall notch become absurd slabs.
    static let maxGrowthFactor: CGFloat = 1.6
    /// Width ÷ height that tiles look best at, matching the cards in Shortcuts.app.
    static let targetAspect: CGFloat = 1.25

    /// Chooses a column count and tile size that fills `size` for `count` tiles.
    ///
    /// Pure so it can be tested without a view. `preferredTile` comes from the
    /// user's size setting and acts as a density hint: it steers the column
    /// count, then tiles are stretched to consume the leftover space exactly,
    /// which is what removes the dead space.
    static func solve(
        count: Int,
        size: CGSize,
        spacing: CGFloat,
        preferredTile: CGFloat
    ) -> ShortcutGridSolution? {
        guard count > 0, size.width > 0, size.height > 0 else { return nil }

        var best: ShortcutGridSolution?
        var bestScore = -Double.greatestFiniteMagnitude

        for columns in 1...count {
            let rows = Int(ceil(Double(count) / Double(columns)))

            let width = (size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let height = (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            guard width >= minTileWidth, height >= minTileHeight else { continue }

            // Don't let tiles balloon when there are only a few of them.
            let cappedHeight = min(height, preferredTile * maxGrowthFactor)
            let cappedWidth = min(width, preferredTile * maxGrowthFactor * targetAspect)

            // Prefer arrangements whose tiles land near the requested size and
            // near the target proportions, and that waste little of the area.
            let aspect = cappedWidth / cappedHeight
            let aspectPenalty = abs(log(Double(aspect / targetAspect)))
            let sizePenalty = abs(log(Double(cappedHeight / preferredTile)))
            let used = Double(cappedWidth * cappedHeight) * Double(count)
            let coverage = used / Double(size.width * size.height)

            let score = coverage - 0.55 * aspectPenalty - 0.35 * sizePenalty
            if score > bestScore {
                bestScore = score
                best = ShortcutGridSolution(
                    columns: columns,
                    rows: rows,
                    tileWidth: cappedWidth,
                    tileHeight: cappedHeight
                )
            }
        }

        // Nothing satisfied the minimums — the panel is too small to show every
        // tile at a usable size. Lay them out at the minimum and tell the caller
        // to scroll, rather than shrinking them into illegibility or letting the
        // grid overflow its bounds.
        if best == nil {
            let columns = max(1, Int((size.width + spacing) / (minTileWidth + spacing)))
            let rows = Int(ceil(Double(count) / Double(columns)))
            let width = max(minTileWidth, (size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            best = ShortcutGridSolution(
                columns: columns,
                rows: rows,
                tileWidth: max(1, width),
                tileHeight: minTileHeight,
                scrolls: true
            )
        }

        // A solution can still exceed the height if the growth cap left the rows
        // taller than the space; mark it so the caller scrolls.
        if var solution = best {
            if solution.totalHeight(spacing: spacing) > size.height + 0.5 {
                solution.scrolls = true
            }
            return solution
        }
        return nil
    }
}
