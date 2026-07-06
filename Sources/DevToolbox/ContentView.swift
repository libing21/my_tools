import SwiftUI

struct ContentView: View {
    @State private var selection: String? = ToolRegistry.all.first?.id
    @State private var query: String = ""

    private var filteredGroups: [(group: ToolGroup, items: [ToolItem])] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return ToolRegistry.grouped
        }
        let q = query.lowercased()
        return ToolGroup.allCases.compactMap { g in
            let items = ToolRegistry.all.filter { $0.group == g && $0.name.lowercased().contains(q) }
            return items.isEmpty ? nil : (g, items)
        }
    }

    private var selectedTool: ToolItem? {
        ToolRegistry.all.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("搜索工具", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                .padding(.horizontal, 8)
                .padding(.top, 8)

                List(selection: $selection) {
                    ForEach(filteredGroups, id: \.group) { section in
                        Section(section.group.rawValue) {
                            ForEach(section.items) { item in
                                Label(item.name, systemImage: item.systemImage)
                                    .tag(item.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 240)
        } detail: {
            if let tool = selectedTool {
                tool.makeView()
                    .id(tool.id)
            } else {
                Text("选择一个工具").foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
    }
}
