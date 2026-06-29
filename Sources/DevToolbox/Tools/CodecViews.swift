import SwiftUI
import Foundation

struct Base64View: View {
    @State private var input = ""
    @State private var output = ""

    var body: some View {
        ToolScaffold("Base64 编解码", subtitle: "UTF-8 文本与 Base64 互转") {
            HStack(spacing: 12) {
                EditorPane(title: "输入", text: $input)
                VStack {
                    Button("编码") { encode() }
                    Button("解码") { decode() }
                    Button("清空") { input = ""; output = "" }
                }
                .frame(width: 90)
                EditorPane(title: "输出", text: $output, editable: false)
            }
        }
    }

    private func encode() {
        output = Data(input.utf8).base64EncodedString()
    }

    private func decode() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = Data(base64Encoded: trimmed),
           let s = String(data: data, encoding: .utf8) {
            output = s
        } else if let data = Data(base64Encoded: trimmed) {
            output = "[二进制数据，\(data.count) 字节，无法显示为 UTF-8]"
        } else {
            output = "无效的 Base64"
        }
    }
}

struct URLCodecView: View {
    @State private var input = ""
    @State private var output = ""

    var body: some View {
        ToolScaffold("URL 编解码", subtitle: "百分号编码 / 解码") {
            HStack(spacing: 12) {
                EditorPane(title: "输入", text: $input)
                VStack {
                    Button("编码") { encode() }
                    Button("解码") { decode() }
                    Button("清空") { input = ""; output = "" }
                }
                .frame(width: 90)
                EditorPane(title: "输出", text: $output, editable: false)
            }
        }
    }

    private func encode() {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        output = input.addingPercentEncoding(withAllowedCharacters: allowed) ?? "编码失败"
    }

    private func decode() {
        output = input.removingPercentEncoding ?? "无效的 URL 编码"
    }
}

struct HexView: View {
    @State private var input = ""
    @State private var output = ""

    var body: some View {
        ToolScaffold("Hex 编解码", subtitle: "UTF-8 文本与十六进制互转") {
            HStack(spacing: 12) {
                EditorPane(title: "输入", text: $input)
                VStack {
                    Button("编码") { encode() }
                    Button("解码") { decode() }
                    Button("清空") { input = ""; output = "" }
                }
                .frame(width: 90)
                EditorPane(title: "输出", text: $output, editable: false)
            }
        }
    }

    private func encode() {
        output = Data(input.utf8).map { String(format: "%02x", $0) }.joined()
    }

    private func decode() {
        let cleaned = input.filter { !$0.isWhitespace }
        guard cleaned.count % 2 == 0 else { output = "Hex 长度必须为偶数"; return }
        var bytes = [UInt8]()
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let b = UInt8(cleaned[idx..<next], radix: 16) else {
                output = "无效的 Hex 字符"; return
            }
            bytes.append(b)
            idx = next
        }
        output = String(data: Data(bytes), encoding: .utf8) ?? "[无法显示为 UTF-8]"
    }
}
