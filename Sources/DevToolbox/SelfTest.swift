import Foundation
import CryptoKit

/// Headless verification of the pure-logic parts of each tool. Run with
/// `DevToolbox --selftest`. Prints PASS/FAIL per case and exits non-zero on
/// any failure so it can gate a build.
enum SelfTest {
    static func run() {
        var failures = 0
        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("PASS  \(name)")
            } else {
                failures += 1
                print("FAIL  \(name)  \(detail)")
            }
        }

        // JSON format
        if case .success(let s) = JSONUtil.format("{\"b\":1,\"a\":2}", pretty: true) {
            check("json.format.pretty", s.contains("\"a\"") && s.contains("\n"), s)
        } else { check("json.format.pretty", false, "returned failure") }

        if case .success(let s) = JSONUtil.format("{ \"a\" : 1 }", pretty: false) {
            check("json.format.minify", s == "{\"a\":1}", s)
        } else { check("json.format.minify", false) }

        if case .failure = JSONUtil.format("{not json}", pretty: true) {
            check("json.format.invalid", true)
        } else { check("json.format.invalid", false, "should have failed") }

        // JSON -> YAML
        if case .success(let y) = YAMLUtil.jsonToYAML("{\"name\":\"x\",\"list\":[1,2],\"nested\":{\"k\":true}}") {
            check("yaml.fromJSON.keys", y.contains("name: x"), y)
            check("yaml.fromJSON.list", y.contains("- 1") && y.contains("- 2"), y)
            check("yaml.fromJSON.bool", y.contains("k: true"), y)
        } else { check("yaml.fromJSON", false) }

        // YAML -> JSON round trip on a nested structure
        let yamlInput = """
        name: demo
        count: 3
        enabled: true
        tags:
          - a
          - b
        meta:
          owner: bob
          score: 9.5
        """
        if case .success(let j) = YAMLUtil.yamlToJSON(yamlInput),
           let data = j.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            check("yaml.toJSON.scalar", (obj["name"] as? String) == "demo", j)
            check("yaml.toJSON.int", (obj["count"] as? Int) == 3, j)
            check("yaml.toJSON.bool", (obj["enabled"] as? Bool) == true, j)
            check("yaml.toJSON.list", (obj["tags"] as? [Any])?.count == 2, j)
            let meta = obj["meta"] as? [String: Any]
            check("yaml.toJSON.nested", (meta?["owner"] as? String) == "bob", j)
        } else { check("yaml.toJSON", false, "parse failed") }

        // Diff
        let d = DiffEngine.diff("a\nb\nc", "a\nx\nc")
        let inserts = d.filter { $0.kind == .insert }.count
        let deletes = d.filter { $0.kind == .delete }.count
        let equals = d.filter { $0.kind == .equal }.count
        check("diff.counts", inserts == 1 && deletes == 1 && equals == 2,
              "ins=\(inserts) del=\(deletes) eq=\(equals)")

        // Char-level diff: reconstruct left from equal+delete, right from equal+insert.
        let cd = CharDiff.diff("the quick brown fox", "the slow brown cat")
        let reLeft = cd.filter { $0.kind != .insert }.map { $0.text }.joined()
        let reRight = cd.filter { $0.kind != .delete }.map { $0.text }.joined()
        check("chardiff.reconstruct", reLeft == "the quick brown fox" && reRight == "the slow brown cat",
              "L=\(reLeft) R=\(reRight)")
        check("chardiff.haschange", cd.contains { $0.kind != .equal })
        let same = CharDiff.diff("identical", "identical")
        check("chardiff.identical", same.allSatisfy { $0.kind == .equal })

        // Hash (known vectors for empty string)
        let empty = Data("".utf8)
        let md5 = Insecure.MD5.hash(data: empty).map { String(format: "%02x", $0) }.joined()
        check("hash.md5.empty", md5 == "d41d8cd98f00b204e9800998ecf8427e", md5)
        let sha256 = SHA256.hash(data: empty).map { String(format: "%02x", $0) }.joined()
        check("hash.sha256.empty",
              sha256 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", sha256)

        // Base64 round trip
        let b64 = Data("héllo".utf8).base64EncodedString()
        let back = Data(base64Encoded: b64).flatMap { String(data: $0, encoding: .utf8) }
        check("base64.roundtrip", back == "héllo", back ?? "nil")

        print("\n\(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")")
        exit(failures == 0 ? 0 : 1)
    }
}
