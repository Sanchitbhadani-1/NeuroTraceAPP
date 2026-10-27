// SUMMARYPDF.SWIFT DRAWS THE DOCTOR SUMMARY AS A US LETTER PDF IN LIGHT COLORS
// IT ADDS NEW PAGES AS THE TEXT AND TABLES FILL THEM, WITH A FOOTER ON EACH PAGE

import UIKit

// Turns a doctor summary into PDF data
enum SummaryPDF {

    // The page size in points, and the space around the edges
    static let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    static let margin: CGFloat = 54

    // The colors for text, gray text, table lines and the table header
    private static let ink = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    private static let gray = UIColor(red: 0.40, green: 0.40, blue: 0.42, alpha: 1)
    private static let rule = UIColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1)
    private static let headerFill = UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)

    // The options used to measure and draw text that wraps onto many lines
    private static let drawing: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    // Make a body font, or a display font, at a size and weight
    private static func font(_ size: CGFloat, _ weight: CGFloat = 400, display: Bool = false) -> UIFont {
        Fonts.make(display ? .display(size, weight) : .body(size, weight), size: size)
    }

    // Make styled text with a font and color that wraps at words
    private static func text(_ s: String, _ font: UIFont, _ color: UIColor) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 2
        return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    // How tall the text is when it wraps at this width, rounded up
    private static func height(_ s: NSAttributedString, _ width: CGFloat) -> CGFloat {
        ceil(s.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: drawing, context: nil).height)
    }

    // Draw the whole summary and give back the PDF data
    static func render(_ doc: DoctorSummary.Document) -> Data {

        // The width of the text, and where the text has to stop above the footer
        let width = page.width - 2 * margin
        let bottom = page.height - margin - 20
        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in

            // Where the next thing is drawn on the page, and the page number
            var y: CGFloat = 0
            var pageNumber = 0

            // Start a new page, move to the top, and draw the footer with the page number
            func newPage() {
                ctx.beginPage()
                pageNumber += 1
                y = margin
                text("\(doc.footer) · Page \(pageNumber)", font(9), gray)
                    .draw(with: CGRect(x: margin, y: page.height - margin + 4, width: width, height: 14), options: drawing, context: nil)
            }

            // Draw text across the page, on a new page if it doesn't fit on this one, then move down
            func paragraph(_ s: NSAttributedString, gap: CGFloat) {
                let h = height(s, width)
                if y + h > bottom { newPage() }
                s.draw(with: CGRect(x: margin, y: y, width: width, height: h), options: drawing, context: nil)
                y += h + gap
            }

            // Draw rows of cells, with the first row as the header
            func table(_ rows: [[String]]) {

                // Stop if there is no header, then split the width into equal columns
                guard let header = rows.first, !header.isEmpty else { return }
                let pad: CGFloat = 5
                let column = width / CGFloat(header.count)

                // How tall a row is, from its tallest cell plus padding
                func rowHeight(_ cells: [String], _ isHeader: Bool) -> CGFloat {
                    (cells.map { c in height(text(c, font(9.5, isHeader ? 600 : 400), ink), column - 2 * pad) }.max() ?? 0) + 2 * pad
                }

                // Draw one row of cells
                func row(_ cells: [String], header isHeader: Bool) {

                    // Make the cell text, bold for the header, and find the row height
                    let made = cells.map { c in text(c, font(9.5, isHeader ? 600 : 400), ink) }
                    let h = rowHeight(cells, isHeader)

                    // If the row doesn't fit, start a new page and draw the header again first
                    if y + h > bottom {
                        newPage()
                        if !isHeader { row(header, header: true) }
                    }

                    // Fill the header row with a light gray
                    if isHeader {
                        headerFill.setFill()
                        UIRectFill(CGRect(x: margin, y: y, width: width, height: h))
                    }

                    // Draw each cell in its column
                    for (i, a) in made.enumerated() {
                        a.draw(with: CGRect(x: margin + CGFloat(i) * column + pad, y: y + pad, width: column - 2 * pad, height: h - 2 * pad), options: drawing, context: nil)
                    }

                    // Draw a thin line under the row and move down
                    rule.setFill()
                    UIRectFill(CGRect(x: margin, y: y + h - 0.5, width: width, height: 0.5))
                    y += h
                }

                // Start a new page if the header and the first row don't both fit here
                let first = rows.count > 1 ? rowHeight(rows[1], false) : 0
                if y + rowHeight(header, true) + first > bottom { newPage() }

                // Draw the header, then every other row, then leave a small gap
                row(header, header: true)
                for cells in rows.dropFirst() { row(cells, header: false) }
                y += 8
            }

            // The first page with the title and the date it was made
            newPage()
            paragraph(text(doc.title, font(24, 600, display: true), ink), gap: 2)
            paragraph(text(doc.made, font(11), gray), gap: 16)

            // Each section of the summary
            for section in doc.sections {

                // Start a new page if less than 70 points are left
                if y + 70 > bottom { newPage() }

                // The section title and its lines of text
                paragraph(text(section.title, font(14, 600, display: true), ink), gap: 6)
                for line in section.lines { paragraph(text(line, font(10.5), ink), gap: 4) }

                // The table, when it has more than a header row
                if section.table.count > 1 {
                    y += 2
                    table(section.table)
                }

                // The note in gray, when there is one, then a gap before the next section
                if let note = section.note { paragraph(text(note, font(9), gray), gap: 4) }
                y += 12
            }
        }
    }
}
