import SwiftUI

// MARK: - MarkdownContentView
// Full-featured Markdown renderer for SwiftUI.
// Handles: H1/H2/H3, **bold**, *italic*, bullet lists, numbered lists,
//          horizontal rules, markdown tables, and paragraph blocks.

struct MarkdownContentView: View {
    let text: String
    var bodyFont: Font = .subheadline
    var textColor: Color = .white.opacity(0.88)
    var accentColor: Color = .white

    private var blocks: [MDBlock] { MDParser.parse(text.emojiStripped) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks.indices, id: \.self) { i in
                blockView(blocks[i])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Block Renderer
    @ViewBuilder
    private func blockView(_ block: MDBlock) -> some View {
        switch block {

        case .h1(let t):
            inlineText(t)
                .font(.title2).fontWeight(.bold)
                .foregroundStyle(accentColor)
                .padding(.top, 4)

        case .h2(let t):
            inlineText(t)
                .font(.headline).fontWeight(.semibold)
                .foregroundStyle(accentColor)
                .padding(.top, 2)

        case .h3(let t):
            inlineText(t)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(accentColor.opacity(0.85))

        case .paragraph(let t):
            inlineText(t)
                .font(bodyFont)
                .foregroundStyle(textColor)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(bodyFont).fontWeight(.bold)
                            .foregroundStyle(accentColor)
                        inlineText(items[i])
                            .font(bodyFont)
                            .foregroundStyle(textColor)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .numbered(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(i + 1).")
                            .font(bodyFont).fontWeight(.semibold)
                            .foregroundStyle(accentColor)
                            .frame(minWidth: 20, alignment: .trailing)
                        inlineText(items[i])
                            .font(bodyFont)
                            .foregroundStyle(textColor)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .horizontalRule:
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
                .padding(.vertical, 2)

        case .table(let headers, let rows):
            mdTable(headers: headers, rows: rows)
        }
    }

    // MARK: - Inline text with AttributedString (bold/italic)
    @ViewBuilder
    private func inlineText(_ s: String) -> some View {
        if let attr = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attr)
        } else {
            Text(s)
        }
    }

    // MARK: - Table renderer
    @ViewBuilder
    private func mdTable(headers: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(headers.indices, id: \.self) { i in
                    Text(headers[i].trimmingCharacters(in: .whitespaces))
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }
            }
            .background(Color.white.opacity(0.06))

            Divider().background(Color.white.opacity(0.15))

            // Data rows
            ForEach(rows.indices, id: \.self) { ri in
                HStack(spacing: 0) {
                    let cols = rows[ri]
                    ForEach(0..<max(cols.count, headers.count), id: \.self) { ci in
                        let cell = ci < cols.count ? cols[ci].trimmingCharacters(in: .whitespaces) : ""
                        Text(cell)
                            .font(.caption)
                            .foregroundStyle(textColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                    }
                }
                .background(ri % 2 == 0 ? Color.clear : Color.white.opacity(0.02))

                if ri < rows.count - 1 {
                    Divider().background(Color.white.opacity(0.06))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - Markdown Parser

private enum MDBlock {
    case h1(String)
    case h2(String)
    case h3(String)
    case paragraph(String)
    case bullets([String])
    case numbered([String])
    case horizontalRule
    case table(headers: [String], rows: [[String]])
}

private enum MDParser {
    static func parse(_ raw: String) -> [MDBlock] {
        let lines = raw.components(separatedBy: "\n")
        var blocks: [MDBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines (already acted as separators)
            if trimmed.isEmpty { i += 1; continue }

            // Headings
            if trimmed.hasPrefix("### ") {
                blocks.append(.h3(String(trimmed.dropFirst(4))))
                i += 1; continue
            }
            if trimmed.hasPrefix("## ") {
                blocks.append(.h2(String(trimmed.dropFirst(3))))
                i += 1; continue
            }
            if trimmed.hasPrefix("# ") {
                blocks.append(.h1(String(trimmed.dropFirst(2))))
                i += 1; continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.horizontalRule)
                i += 1; continue
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("- ") { items.append(String(l.dropFirst(2))); i += 1 }
                    else if l.hasPrefix("* ") { items.append(String(l.dropFirst(2))); i += 1 }
                    else if l.isEmpty { i += 1; break }
                    else { break }
                }
                if !items.isEmpty { blocks.append(.bullets(items)) }
                continue
            }

            // Numbered list
            if let _ = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if let r = l.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                        items.append(String(l[r.upperBound...]))
                        i += 1
                    } else if l.isEmpty { i += 1; break }
                    else { break }
                }
                if !items.isEmpty { blocks.append(.numbered(items)) }
                continue
            }

            // Markdown table (line contains |)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                var tableLines: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("|") { tableLines.append(l); i += 1 }
                    else { break }
                }
                if let table = parseTable(tableLines) {
                    blocks.append(table)
                }
                continue
            }

            // Paragraph: collect consecutive non-special lines
            var paraLines: [String] = []
            while i < lines.count {
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                if l.isEmpty || l.hasPrefix("#") || l.hasPrefix("- ") || l.hasPrefix("* ") ||
                   l.hasPrefix("|") || l == "---" || l == "***" { break }
                if let _ = l.range(of: #"^\d+\.\s"#, options: .regularExpression) { break }
                paraLines.append(lines[i])
                i += 1
            }
            let joined = paraLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
        }

        return blocks
    }

    private static func parseTable(_ lines: [String]) -> MDBlock? {
        guard lines.count >= 2 else { return nil }

        let splitRow: (String) -> [String] = { row in
            row.components(separatedBy: "|")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }

        let headers = splitRow(lines[0])
        // lines[1] is the separator row (| :--- | :--- |)
        let dataLines = lines.dropFirst(2)
        let rows = dataLines.map { splitRow($0) }

        guard !headers.isEmpty else { return nil }
        return .table(headers: headers, rows: Array(rows))
    }
}

// MARK: - Emoji Stripping Extension

extension String {
    var emojiStripped: String {
        unicodeScalars.filter { s in
            // Remove emoji blocks and variation selectors
            !(0x1F300...0x1FAFF ~= s.value) &&  // Misc symbols, emoji
            !(0x2600...0x27BF ~= s.value) &&     // Misc symbols
            !(0xFE00...0xFE0F ~= s.value) &&     // Variation selectors
            !(0x1F000...0x1F02F ~= s.value) &&   // Mahjong
            !(0x1F0A0...0x1F0FF ~= s.value) &&   // Playing cards
            !(0x1F900...0x1F9FF ~= s.value) &&   // Supplemental symbols
            !(0x1FA00...0x1FA6F ~= s.value)      // Chess symbols
        }.reduce("") { $0 + String($1) }
    }
}
