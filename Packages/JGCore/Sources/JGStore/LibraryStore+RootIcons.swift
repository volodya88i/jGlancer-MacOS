import Foundation
import GRDB
import JGModel

public extension LibraryStore {
    /// The icons of the library folders that have one, by root id (D-129).
    func rootIcons() async throws -> [Int64: FolderIcon] {
        try await writer.read(Self.fetchRootIcons)
    }

    /// The icons, again on every change.
    func observeRootIcons() -> AsyncThrowingStream<[Int64: FolderIcon], Error> {
        observeValues(Self.fetchRootIcons)
    }

    /// Gives a library folder its own icon, or the default one back (`nil`).
    func setRootIcon(_ icon: FolderIcon?, for rootID: Int64) async throws {
        try await writer.write { db in
            guard let icon else {
                try db.execute(sql: "DELETE FROM root_icon WHERE root_id = ?", arguments: [rootID])
                return
            }
            let (kind, value): (String, String) = switch icon {
            case let .symbol(name): ("symbol", name)
            case let .emoji(text): ("emoji", text)
            case .picture: ("picture", "")
            }
            let picture: Data? = if case let .picture(data) = icon {
                data
            } else {
                nil
            }
            try db.execute(
                sql: "INSERT OR REPLACE INTO root_icon (root_id, kind, value, picture) VALUES (?, ?, ?, ?)",
                arguments: [rootID, kind, value, picture]
            )
        }
    }

    private static func fetchRootIcons(_ db: Database) throws -> [Int64: FolderIcon] {
        var icons: [Int64: FolderIcon] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT root_id, kind, value, picture FROM root_icon") {
            let id: Int64 = row["root_id"]
            let value: String = row["value"]
            switch row["kind"] as String {
            case "symbol": icons[id] = .symbol(value)
            case "emoji": icons[id] = .emoji(value)
            case "picture":
                if let data: Data = row["picture"] {
                    icons[id] = .picture(data)
                }
            default: break
            }
        }
        return icons
    }
}
