import SwiftUI

struct LockMark: Shape {
    static let pattern = [".XXX.", "X...X", "XXXXX", "XX.XX", "XXXXX"]
    static let size = pattern.count
    static let gap: CGFloat = 0
    static let cells: [(column: Int, row: Int)] = pattern.enumerated().flatMap { row, line in
        line.enumerated().compactMap { column, character in
            character == "X" ? (column: column, row: row) : nil
        }
    }

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let cell = side / CGFloat(Self.size)
        let inset = cell * Self.gap / 2
        let left = rect.midX - side / 2
        let top = rect.midY - side / 2
        var path = Path()
        for item in Self.cells {
            path.addRect(CGRect(
                x: left + CGFloat(item.column) * cell + inset,
                y: top + CGFloat(item.row) * cell + inset,
                width: cell - inset * 2,
                height: cell - inset * 2
            ))
        }
        return path
    }
}
