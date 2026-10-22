import Inventory
import SharedKernel
import Testing

@Test func footprintRejectsFreesAboveTakesUp() {
    #expect(throws: InventoryError.freesExceedsTakesUp(.root)) { try Footprint(takesUp: ByteCount(1), freesAtLeast: ByteCount(2)) }
}

@Test func volumeCapacityRejectsImpossibleNumbers() {
    #expect(throws: InventoryError.availableExceedsTotal) {
        try VolumeCapacity(total: ByteCount(10), available: ByteCount(11), availableIncludingPurgeable: ByteCount(11), usedByVolume: ByteCount(1))
    }
    #expect(throws: InventoryError.usedExceedsTotal) {
        try VolumeCapacity(total: ByteCount(10), available: ByteCount(1), availableIncludingPurgeable: ByteCount(1), usedByVolume: ByteCount(11))
    }
}

@Test func volumeCapacityDerivedFigures() throws {
    let c = try VolumeCapacity(total: ByteCount(1000), available: ByteCount(200), availableIncludingPurgeable: ByteCount(250), usedByVolume: ByteCount(700))
    #expect(c.purgeable == ByteCount(50))
    #expect(c.containerUsed == ByteCount(800))
    let noPurge = try VolumeCapacity(total: ByteCount(1000), available: ByteCount(200), availableIncludingPurgeable: ByteCount(150), usedByVolume: ByteCount(700))
    #expect(noPurge.purgeable == .zero)   // Apple doesn't promise important >= available
}

@Test func otherVolumesUsedWithAndWithoutSwap() throws {
    let c = try VolumeCapacity(total: ByteCount(1000), available: ByteCount(200), availableIncludingPurgeable: ByteCount(200), usedByVolume: ByteCount(700))
    #expect(DiskLayout(data: c, swapUsed: ByteCount(50)).otherVolumesUsed == ByteCount(50))
    #expect(DiskLayout(data: c, swapUsed: nil).otherVolumesUsed == ByteCount(100))
    #expect(DiskLayout(data: c, swapUsed: ByteCount(500)).otherVolumesUsed == .zero)   // clamped
}
