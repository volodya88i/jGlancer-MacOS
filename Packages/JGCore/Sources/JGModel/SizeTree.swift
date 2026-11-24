import Foundation

/// One file of the size map (D-127): what the library knows of it.
public struct SizeEntry: Hashable, Sendable {
    public let id: Int64
    public let folderID: Int64
    public let size: Int64
    public let kind: MediaKind
    /// The lowercased extension, for the color's shade.
    public let fileExtension: String
    public let name: String

    public init(id: Int64, folderID: Int64, size: Int64, kind: MediaKind, name: String) {
        self.id = id
        self.folderID = folderID
        self.size = size
        self.kind = kind
        self.name = name
        fileExtension = (name as NSString).pathExtension.lowercased()
    }
}

/// The folder shown and everything below it as a tree of sizes (D-127, like WizTree): folders hold their subfolders and
/// files, each folder's size is the sum of what it holds, children come largest first. Folders without files of the
/// query are left out. Stored flat (`nodes`, the root at 0) so a layout can index it.
public struct SizeTree: Equatable, Sendable {
    public enum Item: Hashable, Sendable {
        case folder(Int64)
        case file(Int64)
    }

    public struct Node: Equatable, Sendable {
        public let item: Item
        public let name: String
        public let size: Int64
        /// Nil for folders.
        public let kind: MediaKind?
        public let fileExtension: String
        /// Indices into `nodes`, largest first.
        public let children: [Int]
    }

    public let nodes: [Node]

    public init() {
        nodes = []
    }

    /// The tree of `folder` (the sidebar's node, with its subfolders) over the query's `files`.
    public init(folder: FolderNode, files: [SizeEntry]) {
        let byFolder = Dictionary(grouping: files, by: \.folderID)
        var nodes: [Node] = []
        // Builds `node`'s subtree into `nodes` (children first) and returns its index, or nil when it holds nothing.
        func build(_ node: FolderNode) -> Int? {
            var children: [(index: Int, size: Int64)] = []
            for child in node.children ?? [] {
                if let index = build(child) {
                    children.append((index, nodes[index].size))
                }
            }
            for file in byFolder[node.id] ?? [] where file.size > 0 {
                nodes.append(Node(
                    item: .file(file.id), name: file.name, size: file.size, kind: file.kind,
                    fileExtension: file.fileExtension, children: []
                ))
                children.append((nodes.count - 1, file.size))
            }
            let size = children.reduce(Int64(0)) { $0 + $1.size }
            guard size > 0 else { return nil }
            children.sort { $0.size == $1.size ? $0.index < $1.index : $0.size > $1.size }
            nodes.append(Node(
                item: .folder(node.id), name: node.folder.name, size: size, kind: nil, fileExtension: "",
                children: children.map(\.index)
            ))
            return nodes.count - 1
        }
        guard let root = build(folder) else {
            self.nodes = []
            return
        }
        // The root goes first: indices are remapped so that `nodes[0]` is the folder shown.
        var order = Array(nodes.indices)
        order.swapAt(0, root)
        var position = [Int](repeating: 0, count: nodes.count)
        for (new, old) in order.enumerated() {
            position[old] = new
        }
        self.nodes = order.map { old in
            let node = nodes[old]
            return Node(
                item: node.item, name: node.name, size: node.size, kind: node.kind, fileExtension: node.fileExtension,
                children: node.children.map { position[$0] }
            )
        }
    }

    public var isEmpty: Bool {
        nodes.isEmpty
    }

    /// The folder shown.
    public var root: Node? {
        nodes.first
    }
}
