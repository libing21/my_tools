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

enum SmartDiff {
    enum RowKind { case equal, replace, delete, insert }

    struct Row: Identifiable {
        let id = UUID()
        let kind: RowKind
        let leftNumber: Int?
        let rightNumber: Int?
        let leftText: String
        let rightText: String
    }

    struct Result {
        let rows: [Row]
        let mode: String
        let leftSource: String
        let rightSource: String
        let didFormatJSON: Bool
    }

    static func compare(_ rawLeft: String, _ rawRight: String, autoFormatJSON: Bool) -> Result {
        let normalized = autoFormatJSON
            ? normalizeJSONIfPossible(rawLeft, rawRight)
            : (left: rawLeft, right: rawRight, mode: "文本对比", didFormatJSON: false)
        return Result(rows: rows(left: normalized.left, right: normalized.right),
                      mode: normalized.mode,
                      leftSource: normalized.left,
                      rightSource: normalized.right,
                      didFormatJSON: normalized.didFormatJSON)
    }

    private static func normalizeJSONIfPossible(_ left: String, _ right: String) -> (left: String, right: String, mode: String, didFormatJSON: Bool) {
        if case .success(let l) = JSONUtil.format(left, pretty: true),
           case .success(let r) = JSONUtil.format(right, pretty: true) {
            return (l, r, "JSON 已格式化后对比", true)
        }
        return (left, right, "文本对比", false)
    }

    private static func rows(left: String, right: String) -> [Row] {
        let diff = DiffEngine.diff(left, right)
        var rows: [Row] = []
        var i = 0
        while i < diff.count {
            let line = diff[i]

            if line.kind == .delete || line.kind == .insert {
                var deletes: [DiffEngine.Line] = []
                var inserts: [DiffEngine.Line] = []
                while i < diff.count && diff[i].kind != .equal {
                    if diff[i].kind == .delete {
                        deletes.append(diff[i])
                    } else {
                        inserts.append(diff[i])
                    }
                    i += 1
                }

                let paired = min(deletes.count, inserts.count)
                for idx in 0..<paired {
                    rows.append(Row(kind: .replace,
                                    leftNumber: deletes[idx].leftNumber,
                                    rightNumber: inserts[idx].rightNumber,
                                    leftText: deletes[idx].text,
                                    rightText: inserts[idx].text))
                }
                if deletes.count > paired {
                    for line in deletes[paired...] {
                        rows.append(Row(kind: .delete,
                                        leftNumber: line.leftNumber,
                                        rightNumber: nil,
                                        leftText: line.text,
                                        rightText: ""))
                    }
                }
                if inserts.count > paired {
                    for line in inserts[paired...] {
                        rows.append(Row(kind: .insert,
                                        leftNumber: nil,
                                        rightNumber: line.rightNumber,
                                        leftText: "",
                                        rightText: line.text))
                    }
                }
                continue
            }

            switch line.kind {
            case .equal:
                rows.append(Row(kind: .equal,
                                leftNumber: line.leftNumber,
                                rightNumber: line.rightNumber,
                                leftText: line.text,
                                rightText: line.text))
            case .delete:
                rows.append(Row(kind: .delete,
                                leftNumber: line.leftNumber,
                                rightNumber: nil,
                                leftText: line.text,
                                rightText: ""))
            case .insert:
                rows.append(Row(kind: .insert,
                                leftNumber: nil,
                                rightNumber: line.rightNumber,
                                leftText: "",
                                rightText: line.text))
            }
            i += 1
        }
        return rows
    }
}

struct TextDiffView: View {
    @State private var left = ""
    @State private var right = ""
    @State private var result: SmartDiff.Result?
    @State private var onlyDiff = true
    @State private var autoFormatJSON = true

    private var visibleRows: [SmartDiff.Row] {
        let rows = result?.rows ?? []
        return onlyDiff ? rows.filter { $0.kind != .equal } : rows
    }

    private var changeCount: Int {
        (result?.rows ?? []).filter { $0.kind != .equal }.count
    }

    var body: some View {
        ToolScaffold("文本对比", subtitle: "JSON 自动格式化；差异在左右两侧精确高亮") {
            inputBlock
            HStack(spacing: 12) {
                Button("对比") { compare() }
                    .buttonStyle(.borderedProminent)
                Button("清空") { left = ""; right = ""; result = nil }
                Toggle("JSON 自动格式化", isOn: $autoFormatJSON)
                    .toggleStyle(.switch)
                Toggle("仅显示差异", isOn: $onlyDiff)
                    .toggleStyle(.switch)
                legend
                Spacer()
                if let result {
                    Text(statusText(for: result))
                        .font(.caption)
                        .foregroundColor(changeCount == 0 ? .green : .secondary)
                }
            }
            if result != nil {
                resultBlock
            } else {
                emptyResultHint
            }
        }
    }

    private var inputBlock: some View {
        HStack(spacing: 12) {
            EditorPane(title: "原文 (左)", text: $left)
            EditorPane(title: "对照 (右)", text: $right)
        }
        .frame(height: 220)
    }

    private var emptyResultHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.left.and.right.text.vertical")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("粘贴两段文本或 JSON,点击对比")
                .font(.headline)
            Text("JSON 会先格式化、排序 key,再按行和字符高亮差异。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor).opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
    }

    private func compare() {
        let next = SmartDiff.compare(left, right, autoFormatJSON: autoFormatJSON)
        result = next
        if next.didFormatJSON {
            left = next.leftSource
            right = next.rightSource
        }
    }

    private func statusText(for result: SmartDiff.Result) -> String {
        if changeCount == 0 { return "完全一致 · \(result.mode)" }
        let replace = result.rows.filter { $0.kind == .replace }.count
        let delete = result.rows.filter { $0.kind == .delete }.count
        let insert = result.rows.filter { $0.kind == .insert }.count
        return "\(changeCount) 行不同 · 修改 \(replace) · 删除 \(delete) · 新增 \(insert) · \(result.mode)"
    }

    private var legend: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(Color.red.opacity(0.28)).frame(width: 14, height: 14)
                Text("左侧删除").font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.28)).frame(width: 14, height: 14)
                Text("右侧新增").font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                resultHeader("左侧", color: .red)
                resultHeader("右侧", color: .green)
            }
            .padding(.horizontal, 1)
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleRows) { row in
                        SmartDiffRow(row: row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
        }
    }

    private func resultHeader(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color.opacity(0.7)).frame(width: 7, height: 7)
            Text(title).font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct SmartDiffRow: View {
    let row: SmartDiff.Row

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            cell(number: row.leftNumber, text: leftAttributed)
                .background(leftBackground)
            Divider()
            cell(number: row.rightNumber, text: rightAttributed)
                .background(rightBackground)
        }
        .font(.system(.body, design: .monospaced))
    }

    private func cell(number: Int?, text: AttributedString) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number.map(String.init) ?? "")
                .frame(width: 42, alignment: .trailing)
                .foregroundColor(.secondary.opacity(0.6))
            Text(text)
                .textSelection(.enabled)
                .frame(minWidth: 360, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var leftBackground: Color {
        switch row.kind {
        case .delete: return Color.red.opacity(0.12)
        default: return .clear
        }
    }

    private var rightBackground: Color {
        switch row.kind {
        case .insert: return Color.green.opacity(0.12)
        default: return .clear
        }
    }

    private var leftAttributed: AttributedString {
        switch row.kind {
        case .equal:
            return plain(row.leftText)
        case .delete:
            return styled(row.leftText, .delete)
        case .insert:
            return plain(" ")
        case .replace:
            return attributedSide(from: row.leftText, to: row.rightText, side: .left)
        }
    }

    private var rightAttributed: AttributedString {
        switch row.kind {
        case .equal:
            return plain(row.rightText)
        case .delete:
            return plain(" ")
        case .insert:
            return styled(row.rightText, .insert)
        case .replace:
            return attributedSide(from: row.leftText, to: row.rightText, side: .right)
        }
    }

    private enum Side { case left, right }

    private func attributedSide(from left: String, to right: String, side: Side) -> AttributedString {
        let segments = CharDiff.diff(left, right)
        var result = AttributedString()
        for seg in segments {
            switch (side, seg.kind) {
            case (.left, .insert), (.right, .delete):
                continue
            case (.left, .delete):
                result += styled(seg.text, .delete)
            case (.right, .insert):
                result += styled(seg.text, .insert)
            case (_, .equal):
                result += plain(seg.text)
            }
        }
        return result
    }

    private func plain(_ text: String) -> AttributedString {
        var s = AttributedString(text.isEmpty ? " " : text)
        s.foregroundColor = .primary
        return s
    }

    private func styled(_ text: String, _ kind: CharDiff.Kind) -> AttributedString {
        var s = AttributedString(text.isEmpty ? " " : text)
        switch kind {
        case .delete:
            s.foregroundColor = Color(nsColor: .systemRed)
            s.backgroundColor = Color.red.opacity(0.24)
            s.strikethroughStyle = .single
        case .insert:
            s.foregroundColor = Color(nsColor: .systemGreen)
            s.backgroundColor = Color.green.opacity(0.24)
        case .equal:
            s.foregroundColor = .primary
        }
        return s
    }
}
