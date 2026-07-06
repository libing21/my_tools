import SwiftUI
import Foundation

enum JSONUtil {
    /// Pretty-print JSON with sorted keys and 2-space indentation.
    static func format(_ input: String, pretty: Bool) -> Result<String, String> {
        let data = Data(input.utf8)
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            var options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .sortedKeys]
            if pretty { options.insert(.prettyPrinted) }
            let out = try JSONSerialization.data(withJSONObject: obj, options: options)
            guard var str = String(data: out, encoding: .utf8) else {
                return .failure("无法编码输出")
            }
            // Foundation escapes forward slashes; undo for readability.
            str = str.replacingOccurrences(of: "\\/", with: "/")
            return .success(str)
        } catch {
            return .failure("无效的 JSON: \(error.localizedDescription)")
        }
    }
}

/// Syntax highlighter for pretty-printed JSON. Works line by line: in
/// pretty-printed output every string value stays on a single line (real
/// newlines are escaped), so a line carries enough context to tell a key
/// (followed by `:`) from a string value.
enum JSONHighlighter {
    static let keyColor = Color(nsColor: .systemPurple)
    static let stringColor = Color(nsColor: .systemGreen)
    static let numberColor = Color(nsColor: .systemBlue)
    static let literalColor = Color(nsColor: .systemOrange)
    static let punctColor = Color.secondary

    static func highlight(line: String) -> AttributedString {
        var result = AttributedString()
        let chars = Array(line)
        let n = chars.count
        var i = 0

        func append(_ s: String, _ color: Color) {
            var piece = AttributedString(s)
            piece.foregroundColor = color
            result += piece
        }

        while i < n {
            let c = chars[i]
            if c == "\"" {
                // Consume a JSON string, honoring backslash escapes.
                var j = i + 1
                var str = "\""
                while j < n {
                    let cj = chars[j]
                    str.append(cj)
                    if cj == "\\" && j + 1 < n {
                        str.append(chars[j + 1]); j += 2; continue
                    }
                    if cj == "\"" { j += 1; break }
                    j += 1
                }
                // Key if the next non-space char is a colon.
                var k = j
                while k < n && (chars[k] == " " || chars[k] == "\t") { k += 1 }
                let isKey = k < n && chars[k] == ":"
                append(str, isKey ? keyColor : stringColor)
                i = j
            } else if c == "-" || c.isNumber {
                var j = i
                var num = ""
                while j < n {
                    let cj = chars[j]
                    if cj.isNumber || cj == "-" || cj == "+" || cj == "." || cj == "e" || cj == "E" {
                        num.append(cj); j += 1
                    } else { break }
                }
                append(num, numberColor)
                i = j
            } else if matches(chars, i, "true") {
                append("true", literalColor); i += 4
            } else if matches(chars, i, "false") {
                append("false", literalColor); i += 5
            } else if matches(chars, i, "null") {
                append("null", literalColor); i += 4
            } else if "{}[]:,".contains(c) {
                append(String(c), punctColor); i += 1
            } else {
                append(String(c), .primary); i += 1
            }
        }
        return result
    }

    private static func matches(_ chars: [Character], _ start: Int, _ word: String) -> Bool {
        let w = Array(word)
        guard start + w.count <= chars.count else { return false }
        for (offset, ch) in w.enumerated() where chars[start + offset] != ch { return false }
        return true
    }
}

enum JSONFoldEngine {
    struct Range: Equatable {
        let start: Int
        let end: Int
        let close: Character
        let hasTrailingComma: Bool

        var hiddenLineCount: Int { max(0, end - start - 1) }
    }

    struct VisibleLine: Identifiable {
        let id: Int
        let originalIndex: Int
        let text: String
        let foldRange: Range?
        let isCollapsed: Bool
    }

    static func ranges(for lines: [String]) -> [Int: Range] {
        var result: [Int: Range] = [:]
        var stack: [(index: Int, open: Character, close: Character)] = []

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let first = trimmed.first, first == "}" || first == "]" {
                if let last = stack.last, last.close == first {
                    stack.removeLast()
                    if idx > last.index + 1 {
                        result[last.index] = Range(start: last.index,
                                                   end: idx,
                                                   close: first,
                                                   hasTrailingComma: trimmed.hasSuffix(","))
                    }
                }
            }

            if let open = trailingContainerOpen(in: line) {
                stack.append((idx, open, open == "{" ? "}" : "]"))
            }
        }

        return result
    }

    static func visibleLines(lines: [String], collapsed: Set<Int>, ranges: [Int: Range]) -> [VisibleLine] {
        var visible: [VisibleLine] = []
        var idx = 0
        while idx < lines.count {
            if let range = ranges[idx], collapsed.contains(idx) {
                visible.append(VisibleLine(id: idx,
                                           originalIndex: idx,
                                           text: collapsedText(opening: lines[idx], range: range),
                                           foldRange: range,
                                           isCollapsed: true))
                idx = range.end + 1
            } else {
                visible.append(VisibleLine(id: idx,
                                           originalIndex: idx,
                                           text: lines[idx],
                                           foldRange: ranges[idx],
                                           isCollapsed: false))
                idx += 1
            }
        }
        return visible
    }

    private static func collapsedText(opening: String, range: Range) -> String {
        let comma = range.hasTrailingComma ? "," : ""
        return "\(opening) … \(range.close)\(comma)  // folded \(range.hiddenLineCount) lines"
    }

    private static func trailingContainerOpen(in line: String) -> Character? {
        var inString = false
        var escaped = false
        var lastSignificant: Character?

        for ch in line {
            if escaped {
                escaped = false
                continue
            }
            if ch == "\\" && inString {
                escaped = true
                continue
            }
            if ch == "\"" {
                inString.toggle()
                lastSignificant = ch
                continue
            }
            if !inString && !ch.isWhitespace {
                lastSignificant = ch
            }
        }

        if lastSignificant == "{" { return "{" }
        if lastSignificant == "[" { return "[" }
        return nil
    }
}

struct JSONFormatView: View {
    @State private var input = ""
    @State private var outputLines: [String] = []
    @State private var plainOutput = ""
    @State private var error: String?
    @State private var collapsedLines: Set<Int> = []

    private var foldRanges: [Int: JSONFoldEngine.Range] {
        JSONFoldEngine.ranges(for: outputLines)
    }

    private var visibleOutputLines: [JSONFoldEngine.VisibleLine] {
        JSONFoldEngine.visibleLines(lines: outputLines, collapsed: collapsedLines, ranges: foldRanges)
    }

    var body: some View {
        ToolScaffold("JSON 格式化 / 压缩", subtitle: "校验并美化或压缩 JSON") {
            HStack(spacing: 12) {
                EditorPane(title: "输入", text: $input)
                VStack(spacing: 8) {
                    Button("格式化") { run(pretty: true) }
                        .buttonStyle(.borderedProminent)
                    Button("压缩") { run(pretty: false) }
                    Button("全部折叠") { collapsedLines = Set(foldRanges.keys) }
                        .disabled(foldRanges.isEmpty)
                    Button("全部展开") { collapsedLines = [] }
                        .disabled(collapsedLines.isEmpty)
                    Button("清空") { input = ""; outputLines = []; plainOutput = ""; error = nil; collapsedLines = [] }
                }
                .frame(width: 100)
                jsonOutput
            }
            if let error = error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red).font(.caption)
            }
        }
    }

    private var jsonOutput: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("输出").font(.caption).foregroundColor(.secondary)
                if !foldRanges.isEmpty {
                    Text("可折叠 \(foldRanges.count) 个节点")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !plainOutput.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(plainOutput, forType: .string)
                    } label: { Image(systemName: "doc.on.clipboard") }
                    .buttonStyle(.borderless)
                    .help("复制")
                }
            }
            ScrollView([.vertical, .horizontal]) {
                HStack(alignment: .top, spacing: 0) {
                    // Line-number gutter.
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(visibleOutputLines) { line in
                            Text("\(line.originalIndex + 1)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                    .padding(.trailing, 8)
                    .padding(.leading, 6)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleOutputLines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                if let range = line.foldRange {
                                    Button {
                                        toggleFold(line.originalIndex)
                                    } label: {
                                        Image(systemName: line.isCollapsed ? "chevron.right" : "chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.secondary)
                                            .frame(width: 14)
                                    }
                                    .buttonStyle(.plain)
                                    .help(line.isCollapsed ? "展开 \(range.hiddenLineCount) 行" : "折叠 \(range.hiddenLineCount) 行")
                                } else {
                                    Spacer().frame(width: 18)
                                }
                                Text(JSONHighlighter.highlight(line: line.text))
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
        }
    }

    private func run(pretty: Bool) {
        switch JSONUtil.format(input, pretty: pretty) {
        case .success(let s):
            plainOutput = s
            outputLines = s.components(separatedBy: "\n")
            collapsedLines = []
            error = nil
        case .failure(let e):
            plainOutput = ""; outputLines = []; collapsedLines = []; error = e
        }
    }

    private func toggleFold(_ line: Int) {
        if collapsedLines.contains(line) {
            collapsedLines.remove(line)
        } else {
            collapsedLines.insert(line)
        }
    }
}
