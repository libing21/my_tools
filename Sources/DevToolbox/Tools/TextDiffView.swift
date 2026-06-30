import SwiftUI
import AppKit

/// Line-based diff using the classic LCS dynamic-programming algorithm.
/// Kept for callers/tests that need line granularity.
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

/// Character-level diff. Produces a unified sequence of segments so the UI can
/// highlight exactly which characters were deleted/inserted, even within one
/// very long line. Common prefix/suffix are trimmed first so near-identical
/// long texts only run LCS over the small differing middle.
enum CharDiff {
    enum Kind { case equal, insert, delete }
    struct Segment: Identifiable {
        let id = UUID()
        let kind: Kind
        let text: String
    }

    static func diff(_ a: String, _ b: String) -> [Segment] {
        let aArr = Array(a), bArr = Array(b)

        var p = 0
        while p < aArr.count && p < bArr.count && aArr[p] == bArr[p] { p += 1 }
        var sa = aArr.count, sb = bArr.count
        while sa > p && sb > p && aArr[sa - 1] == bArr[sb - 1] { sa -= 1; sb -= 1 }

        var segs: [Segment] = []
        if p > 0 { segs.append(Segment(kind: .equal, text: String(aArr[0..<p]))) }
        segs.append(contentsOf: lcs(Array(aArr[p..<sa]), Array(bArr[p..<sb])))
        if sa < aArr.count { segs.append(Segment(kind: .equal, text: String(aArr[sa...]))) }
        return merge(segs)
    }

    private static func lcs(_ left: [Character], _ right: [Character]) -> [Segment] {
        let n = left.count, m = right.count
        if n == 0 && m == 0 { return [] }
        if n == 0 { return [Segment(kind: .insert, text: String(right))] }
        if m == 0 { return [Segment(kind: .delete, text: String(left))] }
        // Memory guard: if the middle is still huge, treat as full replace.
        if n * m > 6_000_000 {
            return [Segment(kind: .delete, text: String(left)),
                    Segment(kind: .insert, text: String(right))]
        }

        var dp = Array(repeating: Array(repeating: Int32(0), count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = left[i] == right[j] ? dp[i + 1][j + 1] + 1
                                               : max(dp[i + 1][j], dp[i][j + 1])
            }
        }

        var segs: [Segment] = []
        var buf = ""
        var bufKind: Kind = .equal
        func flush() { if !buf.isEmpty { segs.append(Segment(kind: bufKind, text: buf)); buf = "" } }
        func push(_ c: Character, _ k: Kind) { if k != bufKind { flush(); bufKind = k }; buf.append(c) }

        var i = 0, j = 0
        while i < n && j < m {
            if left[i] == right[j] { push(left[i], .equal); i += 1; j += 1 }
            else if dp[i + 1][j] >= dp[i][j + 1] { push(left[i], .delete); i += 1 }
            else { push(right[j], .insert); j += 1 }
        }
        while i < n { push(left[i], .delete); i += 1 }
        while j < m { push(right[j], .insert); j += 1 }
        flush()
        return segs
    }

    private static func merge(_ segs: [Segment]) -> [Segment] {
        var out: [Segment] = []
        for s in segs {
            if let last = out.last, last.kind == s.kind {
                out[out.count - 1] = Segment(kind: s.kind, text: last.text + s.text)
            } else {
                out.append(s)
            }
        }
        return out
    }
}

struct TextDiffView: View {
    @State private var left = ""
    @State private var right = ""
    @State private var segments: [CharDiff.Segment] = []
    @State private var compared = false

    private var changeCount: Int {
        segments.filter { $0.kind != .equal }.count
    }

    var body: some View {
        ToolScaffold("文本对比", subtitle: "字符级对比：红色为删除，绿色为新增") {
            HStack(spacing: 12) {
                EditorPane(title: "原文 (左)", text: $left)
                EditorPane(title: "对照 (右)", text: $right)
            }
            HStack(spacing: 12) {
                Button("对比") { segments = CharDiff.diff(left, right); compared = true }
                    .buttonStyle(.borderedProminent)
                Button("清空") { left = ""; right = ""; segments = []; compared = false }
                legend
                Spacer()
                if compared {
                    Text(changeCount == 0 ? "完全一致" : "\(changeCount) 处不同")
                        .font(.caption)
                        .foregroundColor(changeCount == 0 ? .green : .secondary)
                }
            }
            if compared {
                resultBlock
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(Color.red.opacity(0.28)).frame(width: 14, height: 14)
                Text("删除").font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.28)).frame(width: 14, height: 14)
                Text("新增").font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("差异（合并视图）").font(.caption).foregroundColor(.secondary)
            ScrollView {
                Text(attributed)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
        }
    }

    /// Build a single attributed string: deletions red + strikethrough on a red
    /// wash, insertions green on a green wash, equal text normal.
    private var attributed: AttributedString {
        if changeCount == 0 && !segments.isEmpty {
            var s = AttributedString(left.isEmpty ? "（无内容）" : left)
            s.foregroundColor = .secondary
            return s
        }
        var result = AttributedString()
        for seg in segments {
            var piece = AttributedString(seg.text)
            switch seg.kind {
            case .equal:
                piece.foregroundColor = .primary
            case .delete:
                piece.foregroundColor = Color(nsColor: .systemRed)
                piece.backgroundColor = Color.red.opacity(0.22)
                piece.strikethroughStyle = .single
            case .insert:
                piece.foregroundColor = Color(nsColor: .systemGreen)
                piece.backgroundColor = Color.green.opacity(0.22)
            }
            result += piece
        }
        return result
    }
}
