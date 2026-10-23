import UIKit

// Draws a DoctorSummary.Document as a US Letter PDF, flowing onto new pages as needed. Always in light
// colors, since it gets printed

enum SummaryPDF {
    static let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    static let margin: CGFloat = 54

    private static let ink = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    private static let gray = UIColor(red: 0.40, green: 0.40, blue: 0.42, alpha: 1)
    private static let rule = UIColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1)
    private static let headerFill = UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)
    private static let drawing: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    private static func font(_ size: CGFloat, _ weight: CGFloat = 400, display: Bool = false) -> UIFont {
        Fonts.make(display ? .display(size, weight) : .body(size, weight), size: size)
    }

    private static func text(_ s: String, _ font: UIFont, _ color: UIColor) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 2
        return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    private static func height(_ s: NSAttributedString, _ width: CGFloat) -> CGFloat {
        ceil(s.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: drawing, context: nil).height)
    }

    static func render(_ doc: DoctorSummary.Document) -> Data {
        let width = page.width - 2 * margin
        // Room at the bottom of each page for the footer
        let bottom = page.height - margin - 20
        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            var y: CGFloat = 0
            var pageNumber = 0

            func newPage() {
                ctx.beginPage()
                pageNumber += 1
                y = margin
                text("\(doc.footer) · Page \(pageNumber)", font(9), gray)
                    .draw(with: CGRect(x: margin, y: page.height - margin + 4, width: width, height: 14), options: drawing, context: nil)
            }

            // Text across the page, on a new page if it doesn't fit on this one
            func paragraph(_ s: NSAttributedString, gap: CGFloat) {
                let h = height(s, width)
                if y + h > bottom { newPage() }
                s.draw(with: CGRect(x: margin, y: y, width: width, height: h), options: drawing, context: nil)
                y += h + gap
            }

            // Rows of cells. The header row repeats at the top of each new page
            func table(_ rows: [[String]]) {
                guard let header = rows.first, !header.isEmpty else { return }
                let pad: CGFloat = 5
                let column = width / CGFloat(header.count)
                func rowHeight(_ cells: [String], _ isHeader: Bool) -> CGFloat {
                    (cells.map { c in height(text(c, font(9.5, isHeader ? 600 : 400), ink), column - 2 * pad) }.max() ?? 0) + 2 * pad
                }
                func row(_ cells: [String], header isHeader: Bool) {
                    let made = cells.map { c in text(c, font(9.5, isHeader ? 600 : 400), ink) }
                    let h = rowHeight(cells, isHeader)
                    if y + h > bottom {
                        newPage()
                        if !isHeader { row(header, header: true) }
                    }
                    if isHeader {
                        headerFill.setFill()
                        UIRectFill(CGRect(x: margin, y: y, width: width, height: h))
                    }
                    for (i, a) in made.enumerated() {
                        a.draw(with: CGRect(x: margin + CGFloat(i) * column + pad, y: y + pad, width: column - 2 * pad, height: h - 2 * pad), options: drawing, context: nil)
                    }
                    rule.setFill()
                    UIRectFill(CGRect(x: margin, y: y + h - 0.5, width: width, height: 0.5))
                    y += h
                }
                // The header and the first row start together, on a new page if they don't both fit here
                let first = rows.count > 1 ? rowHeight(rows[1], false) : 0
                if y + rowHeight(header, true) + first > bottom { newPage() }
                row(header, header: true)
                for cells in rows.dropFirst() { row(cells, header: false) }
                y += 8
            }

            newPage()
            paragraph(text(doc.title, font(24, 600, display: true), ink), gap: 2)
            paragraph(text(doc.made, font(11), gray), gap: 16)
            for section in doc.sections {
                // Don't leave a section title alone at the bottom of a page
                if y + 70 > bottom { newPage() }
                paragraph(text(section.title, font(14, 600, display: true), ink), gap: 6)
                for line in section.lines { paragraph(text(line, font(10.5), ink), gap: 4) }
                if section.table.count > 1 {
                    y += 2
                    table(section.table)
                }
                if let note = section.note { paragraph(text(note, font(9), gray), gap: 4) }
                y += 12
            }
        }
    }
}
