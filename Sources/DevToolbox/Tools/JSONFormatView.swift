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

struct JSONFormatView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var error: String?

    var body: some View {
        ToolScaffold("JSON 格式化 / 压缩", subtitle: "校验并美化或压缩 JSON") {
            HStack(spacing: 12) {
                EditorPane(title: "输入", text: $input)
                VStack {
                    Button("格式化") { run(pretty: true) }
                    Button("压缩") { run(pretty: false) }
                    Button("清空") { input = ""; output = ""; error = nil }
                }
                .frame(width: 90)
                EditorPane(title: "输出", text: $output, editable: false)
            }
            if let error = error {
                Text(error).foregroundColor(.red).font(.caption)
            }
        }
    }

    private func run(pretty: Bool) {
        switch JSONUtil.format(input, pretty: pretty) {
        case .success(let s): output = s; error = nil
        case .failure(let e): output = ""; error = e
        }
    }
}
