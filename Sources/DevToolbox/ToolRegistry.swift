import SwiftUI

/// A single tool entry. Adding a new tool to the app is just appending one
/// `ToolItem` to `ToolRegistry.all` and supplying its SwiftUI view.
struct ToolItem: Identifiable {
    let id: String
    let name: String
    let group: ToolGroup
    let systemImage: String
    let makeView: () -> AnyView
}

enum ToolGroup: String, CaseIterable {
    case json = "JSON"
    case diff = "对比"
    case codec = "编解码"
    case hashTime = "哈希/时间/UUID"
}

enum ToolRegistry {
    /// The full catalog. Append here to register a new tool.
    static let all: [ToolItem] = [
        ToolItem(id: "json.format", name: "JSON 格式化/压缩", group: .json,
                 systemImage: "curlybraces", makeView: { AnyView(JSONFormatView()) }),
        ToolItem(id: "json.yaml", name: "JSON ↔ YAML", group: .json,
                 systemImage: "arrow.left.arrow.right", makeView: { AnyView(JSONYAMLView()) }),
        ToolItem(id: "json.escape", name: "JSON 转义/反转义", group: .json,
                 systemImage: "quote.opening", makeView: { AnyView(JSONEscapeView()) }),

        ToolItem(id: "diff.text", name: "文本对比", group: .diff,
                 systemImage: "doc.on.doc", makeView: { AnyView(TextDiffView()) }),

        ToolItem(id: "codec.base64", name: "Base64", group: .codec,
                 systemImage: "b.square", makeView: { AnyView(Base64View()) }),
        ToolItem(id: "codec.url", name: "URL 编解码", group: .codec,
                 systemImage: "link", makeView: { AnyView(URLCodecView()) }),
        ToolItem(id: "codec.hex", name: "Hex 编解码", group: .codec,
                 systemImage: "number", makeView: { AnyView(HexView()) }),
        ToolItem(id: "codec.jwt", name: "JWT 解析", group: .codec,
                 systemImage: "key", makeView: { AnyView(JWTView()) }),

        ToolItem(id: "hash.digest", name: "哈希 (MD5/SHA)", group: .hashTime,
                 systemImage: "lock.shield", makeView: { AnyView(HashView()) }),
        ToolItem(id: "time.timestamp", name: "时间戳互转", group: .hashTime,
                 systemImage: "clock", makeView: { AnyView(TimestampView()) }),
        ToolItem(id: "uuid.gen", name: "UUID 生成", group: .hashTime,
                 systemImage: "wand.and.stars", makeView: { AnyView(UUIDView()) }),
    ]

    static var grouped: [(group: ToolGroup, items: [ToolItem])] {
        ToolGroup.allCases.compactMap { g in
            let items = all.filter { $0.group == g }
            return items.isEmpty ? nil : (g, items)
        }
    }
}
