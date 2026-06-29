import SwiftUI

/// Line-based diff using the classic LCS dynamic-programming algorithm.
enum DiffEngine {
    enum Kind { case equal, insert, delete }
    struct Line: Identifiable {
        let id = UUID()
        let kind: Kind
        let leftNumber: Int?
        let rightNumber: Int?
        let text: String
    }

    static func diff(_ a: String, _ b: String) -> [Line] {
        let left = a.components(separatedBy: "\n")
        let right = b.components(separatedBy: "\n")
        let n = left.count, m = right.count

        // LCS length table.
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    if left[i] == right[j] {
                        dp[i][j] = dp[i + 1][j + 1] + 1
                    } else {
                        dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                    }
                }
            }
        }

        var result: [Line] = []
        var i = 0, j = 0
        var ln = 1, rn = 1
        while i < n && j < m {
            if left[i] == right[j] {
                result.append(Line(kind: .equal, leftNumber: ln, rightNumber: rn, text: left[i]))
                i += 1; j += 1; ln += 1; rn += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                result.append(Line(kind: .delete, leftNumber: ln, rightNumber: nil, text: left[i]))
                i += 1; ln += 1
            } else {
                result.append(Line(kind: .insert, leftNumber: nil, rightNumber: rn, text: right[j]))
                j += 1; rn += 1
            }
        }
        while i < n {
            result.append(Line(kind: .delete, leftNumber: ln, rightNumber: nil, text: left[i]))
            i += 1; ln += 1
        }
        while j < m {
            result.append(Line(kind: .insert, leftNumber: nil, rightNumber: rn, text: right[j]))
            j += 1; rn += 1
        }
        return result
    }
}

struct TextDiffView: View {
    @State private var left = ""
    @State private var right = ""
    @State private var lines: [DiffEngine.Line] = []

    var body: some View {
        ToolScaffold("文本对比", subtitle: "逐行 diff，绿色为新增、红色为删除") {
            HStack(spacing: 12) {
                EditorPane(title: "原文 (左)", text: $left)
                EditorPane(title: "对照 (右)", text: $right)
            }
            HStack {
                Button("对比") { lines = DiffEngine.diff(left, right) }
                Button("清空") { left = ""; right = ""; lines = [] }
                if !lines.isEmpty {
                    let adds = lines.filter { $0.kind == .insert }.count
                    let dels = lines.filter { $0.kind == .delete }.count
                    Text("+\(adds)  -\(dels)").font(.caption).foregroundColor(.secondary)
                }
            }
            if !lines.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            DiffRow(line: line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            }
        }
    }
}

private struct DiffRow: View {
    let line: DiffEngine.Line

    private var bg: Color {
        switch line.kind {
        case .equal: return .clear
        case .insert: return Color.green.opacity(0.18)
        case .delete: return Color.red.opacity(0.18)
        }
    }

    private var marker: String {
        switch line.kind {
        case .equal: return " "
        case .insert: return "+"
        case .delete: return "-"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(line.leftNumber.map(String.init) ?? "")
                .frame(width: 36, alignment: .trailing)
                .foregroundColor(.secondary)
            Text(line.rightNumber.map(String.init) ?? "")
                .frame(width: 36, alignment: .trailing)
                .foregroundColor(.secondary)
            Text(marker).frame(width: 12)
            Text(line.text.isEmpty ? " " : line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.system(.body, design: .monospaced))
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(bg)
    }
}
