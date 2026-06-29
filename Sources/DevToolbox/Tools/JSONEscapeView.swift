import SwiftUI
import Foundation

struct JSONEscapeView: View {
    @State private var input = ""
    @State private var output = ""

    var body: some View {
        ToolScaffold("JSON 转义 / 反转义", subtitle: "将字符串转义为可嵌入 JSON 的形式，或反向解析") {
            HStack(spacing: 12) {
                EditorPane(title: "输入", text: $input)
                VStack {
                    Button("转义") { escape() }
                    Button("反转义") { unescape() }
                    Button("清空") { input = ""; output = "" }
                }
                .frame(width: 90)
                EditorPane(title: "输出", text: $output, editable: false)
            }
        }
    }

    private func escape() {
        // Encode the raw string as a JSON string literal, then strip outer quotes.
        if let data = try? JSONSerialization.data(withJSONObject: [input], options: [.fragmentsAllowed]),
           let arr = String(data: data, encoding: .utf8) {
            // arr looks like ["..."]; extract inner.
            var s = arr
            if s.hasPrefix("[") { s.removeFirst() }
            if s.hasSuffix("]") { s.removeLast() }
            s = s.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("\"") { s.removeFirst() }
            if s.hasSuffix("\"") { s.removeLast() }
            output = s
        } else {
            output = ""
        }
    }

    private func unescape() {
        let wrapped = "\"\(input)\""
        if let data = wrapped.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let s = obj as? String {
            output = s
        } else {
            output = "无法反转义：输入不是合法的转义字符串"
        }
    }
}
