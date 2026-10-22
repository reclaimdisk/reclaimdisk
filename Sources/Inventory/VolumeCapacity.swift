import SharedKernel

/// Capacity of one APFS volume. On APFS, `total` and `available` are the container's; `usedByVolume` is this volume's.
public struct VolumeCapacity: Hashable, Sendable {
    public let total: ByteCount
    public let available: ByteCount
    public let availableIncludingPurgeable: ByteCount
    public let usedByVolume: ByteCount

    public init(total: ByteCount, available: ByteCount, availableIncludingPurgeable: ByteCount, usedByVolume: ByteCount) throws(InventoryError) {
        guard available <= total else { throw .availableExceedsTotal }
        guard usedByVolume <= total else { throw .usedExceedsTotal }
        self.total = total
        self.available = available
        self.availableIncludingPurgeable = availableIncludingPurgeable
        self.usedByVolume = usedByVolume
    }

    /// Space macOS could purge on its own. Shown separately, never counted as reclaimed.
    public var purgeable: ByteCount { availableIncludingPurgeable.subtractingClamped(available) }

    /// Everything allocated in the APFS container, across all its volumes.
    public var containerUsed: ByteCount { total.subtractingClamped(available) }
}

/// The disk as the Overview shows it: the Data volume, swap, and the rest of the container.
public struct DiskLayout: Hashable, Sendable {
    public let data: VolumeCapacity
    /// nil when the VM volume can't be read.
    public let swapUsed: ByteCount?

    public init(data: VolumeCapacity, swapUsed: ByteCount?) {
        self.data = data
        self.swapUsed = swapUsed
    }

    /// System, Preboot, Recovery and the rest: container used minus Data minus swap.
    public var otherVolumesUsed: ByteCount {
        data.containerUsed.subtractingClamped(data.usedByVolume).subtractingClamped(swapUsed ?? .zero)
    }
}
