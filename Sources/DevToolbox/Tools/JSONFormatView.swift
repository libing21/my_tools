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

struct JSONFormatView: View {
    @State private var input = ""
    @State private var outputLines: [String] = []
    @State private var plainOutput = ""
    @State private var error: String?

    var body: some View {
        ToolScaffold("JSON 格式化 / 压缩", subtitle: "校验并美化或压缩 JSON") {
            HStack(spacing: 12) {
                EditorPane(title: "输入", text: $input)
                VStack(spacing: 8) {
                    Button("格式化") { run(pretty: true) }
                        .buttonStyle(.borderedProminent)
                    Button("压缩") { run(pretty: false) }
                    Button("清空") { input = ""; outputLines = []; plainOutput = ""; error = nil }
                }
                .frame(width: 90)
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
                        ForEach(Array(outputLines.enumerated()), id: \.offset) { idx, _ in
                            Text("\(idx + 1)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                    .padding(.trailing, 8)
                    .padding(.leading, 6)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(outputLines.enumerated()), id: \.offset) { _, line in
                            Text(JSONHighlighter.highlight(line: line))
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: true, vertical: false)
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
            error = nil
        case .failure(let e):
            plainOutput = ""; outputLines = []; error = e
        }
    }
}
