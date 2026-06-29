import SwiftUI
import Foundation

struct JWTView: View {
    @State private var input = ""
    @State private var header = ""
    @State private var payload = ""
    @State private var note = ""

    var body: some View {
        ToolScaffold("JWT 解析", subtitle: "解码 header 与 payload（不验证签名）") {
            EditorPane(title: "JWT", text: $input)
            HStack {
                Button("解析") { decode() }
                Button("清空") { input = ""; header = ""; payload = ""; note = "" }
                if !note.isEmpty {
                    Text(note).font(.caption).foregroundColor(.red)
                }
            }
            HStack(spacing: 12) {
                EditorPane(title: "Header", text: $header, editable: false)
                EditorPane(title: "Payload", text: $payload, editable: false)
            }
        }
    }

    private func decode() {
        note = ""
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = token.components(separatedBy: ".")
        guard parts.count >= 2 else {
            note = "不是有效的 JWT（应为 header.payload.signature）"
            header = ""; payload = ""
            return
        }
        header = decodeSegment(parts[0]) ?? "无法解码 header"
        payload = decodeSegment(parts[1]) ?? "无法解码 payload"
    }

    /// Decode a base64url segment and pretty-print as JSON.
    private func decodeSegment(_ segment: String) -> String? {
        var base64 = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Pad to a multiple of 4.
        let rem = base64.count % 4
        if rem > 0 { base64 += String(repeating: "=", count: 4 - rem) }

        guard let data = Data(base64Encoded: base64) else { return nil }
        if let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: pretty, encoding: .utf8) {
            return str.replacingOccurrences(of: "\\/", with: "/")
        }
        return String(data: data, encoding: .utf8)
    }
}
