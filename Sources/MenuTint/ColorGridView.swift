import AppKit

/// A clickable grid of colour swatches that lives inside an NSMenu.
/// Picking a colour keeps the menu open so colours can be compared quickly.
final class ColorGridView: NSView {
    var onSelect: ((String) -> Void)?

    /// Hex of the currently used colour (highlighted with a ring), nil if none.
    var selectedHex: String? {
        didSet { needsDisplay = true }
    }

    private let rows: [[String]]
    private let columns: Int

    private static let cellSize: CGFloat = 16
    private static let spacing: CGFloat = 4
    private static let horizontalInset: CGFloat = 20
    private static let verticalInset: CGFloat = 4

    /// - Parameter rows: hex colour strings, one array per row (rows may be shorter than others).
    init(rows: [[String]]) {
        self.rows = rows.filter { !$0.isEmpty }
        columns = max(1, rows.map(\.count).max() ?? 1)
        let width = Self.horizontalInset * 2 + CGFloat(columns) * Self.cellSize + CGFloat(columns - 1) * Self.spacing
        let rowCount = CGFloat(self.rows.count)
        let height = Self.verticalInset * 2 + rowCount * Self.cellSize + max(0, rowCount - 1) * Self.spacing
        super.init(frame: NSRect(x: 0, y: 0, width: max(width, 250), height: height))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, hex) in row.enumerated() {
                guard let color = NSColor(hex: hex) else { continue }
                let rect = cellRect(row: rowIndex, column: columnIndex)
                let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                color.setFill()
                path.fill()
                NSColor.black.withAlphaComponent(0.2).setStroke()
                path.lineWidth = 0.5
                path.stroke()

                if let selectedHex, hex.caseInsensitiveCompare(selectedHex) == .orderedSame {
                    let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: 5.5, yRadius: 5.5)
                    NSColor.labelColor.setStroke()
                    ring.lineWidth = 1.5
                    ring.stroke()
                }
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, hex) in row.enumerated()
            where cellRect(row: rowIndex, column: columnIndex).insetBy(dx: -2, dy: -2).contains(point) {
                selectedHex = hex
                onSelect?(hex)
                return
            }
        }
    }

    private func cellRect(row: Int, column: Int) -> NSRect {
        NSRect(
            x: Self.horizontalInset + CGFloat(column) * (Self.cellSize + Self.spacing),
            y: Self.verticalInset + CGFloat(row) * (Self.cellSize + Self.spacing),
            width: Self.cellSize,
            height: Self.cellSize
        )
    }

    // MARK: Palette

    /// 12 hues × 6 shades, plus a row of neutrals.
    static let palette: [[String]] = {
        let hues = (0..<12).map { CGFloat($0) / 12 }
        let shades: [(saturation: CGFloat, brightness: CGFloat)] = [
            (0.25, 1.0),
            (0.45, 1.0),
            (0.70, 1.0),
            (0.90, 1.0),
            (1.00, 0.80),
            (1.00, 0.60),
        ]
        var rows = shades.map { shade in
            hues.map { hue in
                NSColor(hue: hue, saturation: shade.saturation, brightness: shade.brightness, alpha: 1).hexString
            }
        }
        rows.append((0..<12).map { i in
            NSColor(white: 1 - CGFloat(i) / 11 * 0.85, alpha: 1).hexString
        })
        return rows
    }()
}
