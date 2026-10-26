import Inventory
import SharedKernel

/// The locked folders the Full Disk Access notice names: the person's own first (Trash, Mail, iPhone backups),
/// then system folders, each group in path order.
public enum LockedFolders {
    public static func examples(in scan: Scan, home: CanonicalPath, limit: Int = 5) -> [CanonicalPath] {
        let locked = scan.unreadable.filter { $0.reason == .notPermitted }.map(\.path)
        let own = locked.filter { $0.isSameOrDescendant(of: home) }
        let system = locked.filter { !$0.isSameOrDescendant(of: home) }
        return Array((own + system).prefix(limit))
    }
}
