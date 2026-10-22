import Application
import Foundation
import SharedKernel

/// An in-memory volume for tests. Thread-safe; records every directory read.
public final class FakeVolumeReader: VolumeReader, @unchecked Sendable {
    private let lock = NSLock()
    private var directories: [CanonicalPath: Result<[DirectoryEntry], DirectoryReadError>] = [:]
    private var entryTypes: [CanonicalPath: Result<EntryType, DirectoryReadError>] = [:]
    private var devices: [CanonicalPath: Int32] = [:]
    private var capacities: [CanonicalPath: Result<CapacityReading, DirectoryReadError>] = [:]
    private var log: [CanonicalPath] = []
    private var _reverseEntryOrder = false
    private var _onRead: (@Sendable (CanonicalPath, _ readsSoFar: Int) -> Void)?

    /// Device id returned for paths without an explicit one.
    public let defaultDeviceID: Int32

    public init(defaultDeviceID: Int32 = 1) { self.defaultDeviceID = defaultDeviceID }

    /// Every `readDirectory` call, in order.
    public var readLog: [CanonicalPath] { lock.withLock { log } }

    /// Serve entries in reverse order, for determinism tests.
    public var reverseEntryOrder: Bool {
        get { lock.withLock { _reverseEntryOrder } }
        set { lock.withLock { _reverseEntryOrder = newValue } }
    }

    /// Called before each read with the number of reads so far, including this one.
    public var onRead: (@Sendable (CanonicalPath, _ readsSoFar: Int) -> Void)? {
        get { lock.withLock { _onRead } }
        set { lock.withLock { _onRead = newValue } }
    }

    // MARK: builders

    public func directory(_ path: String, _ entries: [DirectoryEntry]) {
        let p = Self.path(path)
        lock.withLock {
            directories[p] = .success(entries)
            if entryTypes[p] == nil { entryTypes[p] = .success(.directory) }
        }
    }

    public func failing(_ path: String, _ error: DirectoryReadError) {
        let p = Self.path(path)
        lock.withLock {
            directories[p] = .failure(error)
            if entryTypes[p] == nil { entryTypes[p] = .success(.directory) }
        }
    }

    public func entryType(_ path: String, _ type: EntryType) {
        lock.withLock { entryTypes[Self.path(path)] = .success(type) }
    }

    public func failingEntryType(_ path: String, _ error: DirectoryReadError) {
        lock.withLock { entryTypes[Self.path(path)] = .failure(error) }
    }

    public func device(_ path: String, _ id: Int32) {
        lock.withLock { devices[Self.path(path)] = id }
    }

    public func capacity(_ mountPath: String, _ reading: CapacityReading) {
        lock.withLock { capacities[Self.path(mountPath)] = .success(reading) }
    }

    public func failingCapacity(_ mountPath: String, _ error: DirectoryReadError) {
        lock.withLock { capacities[Self.path(mountPath)] = .failure(error) }
    }

    // MARK: VolumeReader

    public func readDirectory(at path: CanonicalPath) throws(DirectoryReadError) -> [DirectoryEntry] {
        let (count, hook) = lock.withLock { () -> (Int, (@Sendable (CanonicalPath, Int) -> Void)?) in
            log.append(path)
            return (log.count, _onRead)
        }
        hook?(path, count)
        let (result, reverse) = lock.withLock { (directories[path], _reverseEntryOrder) }
        switch result {
        case .success(let entries)?: return reverse ? entries.reversed() : entries
        case .failure(let error)?: throw error
        case nil: throw .notFound
        }
    }

    public func entryType(at path: CanonicalPath) throws(DirectoryReadError) -> EntryType {
        switch lock.withLock({ entryTypes[path] }) {
        case .success(let type)?: return type
        case .failure(let error)?: throw error
        case nil: throw .notFound
        }
    }

    public func deviceID(of path: CanonicalPath) throws(DirectoryReadError) -> Int32 {
        lock.withLock {
            var current: CanonicalPath? = path
            while let p = current {
                if let id = devices[p] { return id }
                current = p.parent
            }
            return defaultDeviceID
        }
    }

    public func capacity(ofVolumeAt mountPath: CanonicalPath) throws(DirectoryReadError) -> CapacityReading {
        switch lock.withLock({ capacities[mountPath] }) {
        case .success(let reading)?: return reading
        case .failure(let error)?: throw error
        case nil: throw .notFound
        }
    }

    private static func path(_ raw: String) -> CanonicalPath {
        guard let p = CanonicalPath(raw) else { preconditionFailure("not a canonical path: \(raw)") }
        return p
    }
}
