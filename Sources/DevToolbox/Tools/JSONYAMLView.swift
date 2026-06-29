import SwiftUI
import Foundation

/// Minimal JSON<->YAML conversion. JSON->YAML is complete (driven by the parsed
/// JSON object). YAML->JSON supports the common subset: nested maps, block
/// sequences, and scalar values (string/number/bool/null). Flow style and
/// anchors are not supported.
enum YAMLUtil {

    // MARK: JSON -> YAML

    static func jsonToYAML(_ json: String) -> Result<String, String> {
        let data = Data(json.utf8)
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return .success(emit(obj, indent: 0))
        } catch {
            return .failure("无效的 JSON: \(error.localizedDescription)")
        }
    }

    private static func emit(_ value: Any, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch value {
        case let dict as [String: Any]:
            if dict.isEmpty { return "{}" }
            var lines: [String] = []
            for key in dict.keys.sorted() {
                let v = dict[key]!
                lines.append(emitEntry(key: key, value: v, indent: indent))
            }
            return lines.joined(separator: "\n")
        case let arr as [Any]:
            if arr.isEmpty { return "[]" }
            var lines: [String] = []
            for v in arr {
                if isScalar(v) {
                    lines.append("\(pad)- \(scalar(v))")
                } else {
                    let nested = emit(v, indent: indent + 1)
                    // Place "- " then nested block starting on next line, but
                    // pull the first nested line up onto the dash line.
                    let nestedLines = nested.split(separator: "\n", omittingEmptySubsequences: false)
                    if let first = nestedLines.first {
                        let firstTrimmed = first.drop(while: { $0 == " " })
                        lines.append("\(pad)- \(firstTrimmed)")
                        for extra in nestedLines.dropFirst() {
                            lines.append(String(extra))
                        }
                    }
                }
            }
            return lines.joined(separator: "\n")
        default:
            return "\(pad)\(scalar(value))"
        }
    }

    private static func emitEntry(key: String, value: Any, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        let k = quoteKeyIfNeeded(key)
        if isScalar(value) {
            return "\(pad)\(k): \(scalar(value))"
        }
        if let dict = value as? [String: Any], dict.isEmpty {
            return "\(pad)\(k): {}"
        }
        if let arr = value as? [Any], arr.isEmpty {
            return "\(pad)\(k): []"
        }
        // Arrays render at the same indent level; maps render one level deeper.
        if value is [Any] {
            return "\(pad)\(k):\n\(emit(value, indent: indent))"
        }
        return "\(pad)\(k):\n\(emit(value, indent: indent + 1))"
    }

    private static func isScalar(_ v: Any) -> Bool {
        !(v is [String: Any]) && !(v is [Any])
    }

    private static func scalar(_ v: Any) -> String {
        if v is NSNull { return "null" }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return n.boolValue ? "true" : "false"
            }
            return n.stringValue
        }
        if let s = v as? String { return quoteScalarIfNeeded(s) }
        return "\(v)"
    }

    private static func quoteScalarIfNeeded(_ s: String) -> String {
        if s.isEmpty { return "\"\"" }
        let needsQuote = s.contains(":") || s.contains("#") || s.contains("\n")
            || s.hasPrefix(" ") || s.hasSuffix(" ")
            || ["true", "false", "null", "yes", "no"].contains(s.lowercased())
            || Double(s) != nil
        if needsQuote {
            let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                           .replacingOccurrences(of: "\"", with: "\\\"")
                           .replacingOccurrences(of: "\n", with: "\\n")
            return "\"\(escaped)\""
        }
        return s
    }

    private static func quoteKeyIfNeeded(_ s: String) -> String {
        if s.contains(":") || s.contains(" ") || s.isEmpty {
            return "\"\(s)\""
        }
        return s
    }

    // MARK: YAML -> JSON (common subset)

    static func yamlToJSON(_ yaml: String) -> Result<String, String> {
        let lines = yaml.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var idx = 0
        let filtered = lines.map { stripComment($0) }
        do {
            let value = try parseBlock(filtered, &idx, indent: 0)
            let data = try JSONSerialization.data(withJSONObject: value,
                                                  options: [.prettyPrinted, .fragmentsAllowed, .sortedKeys])
            guard let str = String(data: data, encoding: .utf8) else {
                return .failure("无法编码输出")
            }
            return .success(str.replacingOccurrences(of: "\\/", with: "/"))
        } catch let e as ParseError {
            return .failure(e.message)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private struct ParseError: Error { let message: String }

    private static func stripComment(_ line: String) -> String {
        // Remove trailing comments not inside quotes (best effort).
        var inSingle = false, inDouble = false
        var result = ""
        for ch in line {
            if ch == "'" && !inDouble { inSingle.toggle() }
            if ch == "\"" && !inSingle { inDouble.toggle() }
            if ch == "#" && !inSingle && !inDouble {
                break
            }
            result.append(ch)
        }
        return result
    }

    private static func indentOf(_ line: String) -> Int {
        var count = 0
        for ch in line { if ch == " " { count += 1 } else { break } }
        return count
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func parseBlock(_ lines: [String], _ idx: inout Int, indent: Int) throws -> Any {
        // Skip blanks
        while idx < lines.count && isBlank(lines[idx]) { idx += 1 }
        guard idx < lines.count else { return NSNull() }

        let curIndent = indentOf(lines[idx])
        let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("- ") || trimmed == "-" {
            return try parseSequence(lines, &idx, indent: curIndent)
        } else {
            return try parseMapping(lines, &idx, indent: curIndent)
        }
    }

    private static func parseSequence(_ lines: [String], _ idx: inout Int, indent: Int) throws -> [Any] {
        var result: [Any] = []
        while idx < lines.count {
            if isBlank(lines[idx]) { idx += 1; continue }
            let ind = indentOf(lines[idx])
            if ind < indent { break }
            if ind > indent { break }
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") || trimmed == "-" else { break }

            let rest = trimmed == "-" ? "" : String(trimmed.dropFirst(2))
            if rest.isEmpty {
                idx += 1
                let nested = try parseBlock(lines, &idx, indent: indent + 1)
                result.append(nested)
            } else if let colon = topLevelColon(rest) {
                // Inline map start: "- key: value" -> treat as a map whose first
                // key sits at this dash position.
                let pseudoIndent = indent + 2
                var synthetic = lines
                synthetic[idx] = String(repeating: " ", count: pseudoIndent) + rest
                _ = colon
                let map = try parseMapping(synthetic, &idx, indent: pseudoIndent)
                result.append(map)
            } else {
                result.append(parseScalar(rest))
                idx += 1
            }
        }
        return result
    }

    private static func parseMapping(_ lines: [String], _ idx: inout Int, indent: Int) throws -> [String: Any] {
        var result: [String: Any] = [:]
        while idx < lines.count {
            if isBlank(lines[idx]) { idx += 1; continue }
            let ind = indentOf(lines[idx])
            if ind != indent { break }
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed == "-" { break }
            guard let colon = topLevelColon(trimmed) else {
                throw ParseError(message: "无法解析行: \(lines[idx])")
            }
            let key = unquote(String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces))
            let after = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if after.isEmpty {
                idx += 1
                // nested block at deeper indent, or null
                if idx < lines.count && !isBlank(lines[idx]) && indentOf(lines[idx]) > indent {
                    result[key] = try parseBlock(lines, &idx, indent: indentOf(lines[idx]))
                } else if idx < lines.count && !isBlank(lines[idx])
                            && indentOf(lines[idx]) == indent
                            && lines[idx].trimmingCharacters(in: .whitespaces).hasPrefix("-") {
                    // sequence at same indent as key
                    result[key] = try parseSequence(lines, &idx, indent: indent)
                } else {
                    result[key] = NSNull()
                }
            } else {
                result[key] = parseScalar(after)
                idx += 1
            }
        }
        return result
    }

    private static func topLevelColon(_ s: String) -> String.Index? {
        var inSingle = false, inDouble = false
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "'" && !inDouble { inSingle.toggle() }
            if ch == "\"" && !inSingle { inDouble.toggle() }
            if ch == ":" && !inSingle && !inDouble {
                let next = s.index(after: i)
                if next == s.endIndex || s[next] == " " {
                    return i
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    private static func parseScalar(_ s: String) -> Any {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 {
            return unquote(t)
        }
        if t.hasPrefix("'") && t.hasSuffix("'") && t.count >= 2 {
            return String(t.dropFirst().dropLast())
        }
        switch t.lowercased() {
        case "null", "~", "": return NSNull()
        case "true", "yes": return true
        case "false", "no": return false
        default: break
        }
        if let i = Int(t) { return i }
        if let d = Double(t) { return d }
        return t
    }

    private static func unquote(_ s: String) -> String {
        var t = s
        if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 {
            t = String(t.dropFirst().dropLast())
            t = t.replacingOccurrences(of: "\\\"", with: "\"")
                 .replacingOccurrences(of: "\\n", with: "\n")
                 .replacingOccurrences(of: "\\\\", with: "\\")
        } else if t.hasPrefix("'") && t.hasSuffix("'") && t.count >= 2 {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }
}

struct JSONYAMLView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var error: String?

    var body: some View {
        ToolScaffold("JSON ↔ YAML", subtitle: "支持常见 YAML 子集（嵌套 map/序列/标量）") {
            HStack(spacing: 12) {
                EditorPane(title: "输入", text: $input)
                VStack {
                    Button("JSON → YAML") { toYAML() }
                    Button("YAML → JSON") { toJSON() }
                    Button("清空") { input = ""; output = ""; error = nil }
                }
                .frame(width: 110)
                EditorPane(title: "输出", text: $output, editable: false)
            }
            if let error = error {
                Text(error).foregroundColor(.red).font(.caption)
            }
        }
    }

    private func toYAML() {
        switch YAMLUtil.jsonToYAML(input) {
        case .success(let s): output = s; error = nil
        case .failure(let e): output = ""; error = e
        }
    }

    private func toJSON() {
        switch YAMLUtil.yamlToJSON(input) {
        case .success(let s): output = s; error = nil
        case .failure(let e): output = ""; error = e
        }
    }
}
