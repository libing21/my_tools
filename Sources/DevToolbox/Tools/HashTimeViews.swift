import SwiftUI
import Foundation
import CryptoKit

struct HashView: View {
    @State private var input = ""
    @State private var md5 = ""
    @State private var sha1 = ""
    @State private var sha256 = ""
    @State private var sha512 = ""

    var body: some View {
        ToolScaffold("哈希 (MD5/SHA)", subtitle: "对 UTF-8 文本计算各类摘要") {
            EditorPane(title: "输入", text: $input)
            HStack {
                Button("计算") { compute() }
                Button("清空") { input = ""; md5 = ""; sha1 = ""; sha256 = ""; sha512 = "" }
            }
            VStack(spacing: 8) {
                hashRow("MD5", $md5)
                hashRow("SHA-1", $sha1)
                hashRow("SHA-256", $sha256)
                hashRow("SHA-512", $sha512)
            }
        }
    }

    private func hashRow(_ label: String, _ value: Binding<String>) -> some View {
        HStack(alignment: .top) {
            Text(label).frame(width: 70, alignment: .leading).foregroundColor(.secondary)
            EditorPane(title: "", text: value, editable: false)
                .frame(height: 44)
        }
    }

    private func compute() {
        let data = Data(input.utf8)
        md5 = Insecure.MD5.hash(data: data).hexString
        sha1 = Insecure.SHA1.hash(data: data).hexString
        sha256 = SHA256.hash(data: data).hexString
        sha512 = SHA512.hash(data: data).hexString
    }
}

private extension Sequence where Element == UInt8 {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

struct TimestampView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var now = ""

    var body: some View {
        ToolScaffold("时间戳互转", subtitle: "Unix 时间戳（秒/毫秒）与日期互转") {
            HStack {
                Button("当前时间戳") {
                    let t = Date().timeIntervalSince1970
                    now = "秒: \(Int(t))   毫秒: \(Int(t * 1000))"
                }
                if !now.isEmpty { Text(now).font(.callout).textSelection(.enabled) }
            }
            HStack(spacing: 12) {
                EditorPane(title: "输入（时间戳或日期）", text: $input)
                VStack {
                    Button("时间戳→日期") { tsToDate() }
                    Button("日期→时间戳") { dateToTs() }
                    Button("清空") { input = ""; output = "" }
                }
                .frame(width: 120)
                EditorPane(title: "输出", text: $output, editable: false)
            }
            Text("日期格式示例：2026-06-29 21:00:00").font(.caption).foregroundColor(.secondary)
        }
    }

    private func tsToDate() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Double(trimmed) else { output = "无效的时间戳"; return }
        // Heuristic: treat >= 1e12 as milliseconds.
        let seconds = raw >= 1_000_000_000_000 ? raw / 1000 : raw
        let date = Date(timeIntervalSince1970: seconds)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.timeZone = TimeZone.current
        let local = fmt.string(from: date)
        fmt.timeZone = TimeZone(identifier: "UTC")
        let utc = fmt.string(from: date)
        output = "本地: \(local)\nUTC:  \(utc)"
    }

    private func dateToTs() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.timeZone = TimeZone.current
        guard let date = fmt.date(from: input.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            output = "无法解析日期，请用 yyyy-MM-dd HH:mm:ss"
            return
        }
        let t = date.timeIntervalSince1970
        output = "秒: \(Int(t))\n毫秒: \(Int(t * 1000))"
    }
}

struct UUIDView: View {
    @State private var output = ""
    @State private var count = 1
    @State private var upper = false

    var body: some View {
        ToolScaffold("UUID 生成", subtitle: "生成 v4 随机 UUID") {
            HStack {
                Stepper("数量: \(count)", value: $count, in: 1...100)
                    .frame(width: 160)
                Toggle("大写", isOn: $upper)
                Button("生成") { generate() }
                Button("清空") { output = "" }
            }
            EditorPane(title: "结果", text: $output, editable: false)
        }
    }

    private func generate() {
        let ids = (0..<count).map { _ -> String in
            let s = UUID().uuidString
            return upper ? s : s.lowercased()
        }
        output = ids.joined(separator: "\n")
    }
}
