import Catalog
import SharedKernel
import Testing
@testable import Infrastructure

// Recorded from Xcode 26 on macOS 26.5 (`xcrun simctl runtime list --json`, `xcrun simctl list devices --json`), trimmed.
private let runtimes = #"""
{
  "81934247-D744-4C6A-A50C-BC001F2FDDE6" : {
    "build" : "23D8133",
    "deletable" : true,
    "identifier" : "81934247-D744-4C6A-A50C-BC001F2FDDE6",
    "kind" : "Patchable Cryptex Disk Image",
    "lastUsedAt" : "2026-11-01T17:10:38Z",
    "mountPath" : "\/Library\/Developer\/CoreSimulator\/Volumes\/iOS_23D8133",
    "parentMountPath" : "\/System\/Library\/AssetsV2\/com_apple_MobileAsset_iOSSimulatorRuntime\/c6f07ed8ec1586ca140801a2c7c60f478e947602.asset\/AssetData",
    "path" : "\/System\/Library\/AssetsV2\/com_apple_MobileAsset_iOSSimulatorRuntime\/c6f07ed8ec1586ca140801a2c7c60f478e947602.asset\/AssetData\/Restore\/094-26194-058.dmg",
    "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-26-3",
    "sizeBytes" : 8393503393,
    "state" : "Ready",
    "version" : "26.3.1"
  },
  "22222222-0000-0000-0000-000000000002" : {
    "deletable" : false,
    "identifier" : "22222222-0000-0000-0000-000000000002",
    "path" : "\/Library\/Developer\/CoreSimulator\/Images\/visionOS.dmg",
    "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.xrOS-2-0",
    "state" : "Ready",
    "version" : "2.0"
  }
}
"""#

private let devices = #"""
{
  "devices" : {
    "com.apple.CoreSimulator.SimRuntime.iOS-26-3" : [
      {
        "lastBootedAt" : "2026-09-18T03:37:15Z",
        "dataPath" : "\/Users\/u\/Library\/Developer\/CoreSimulator\/Devices\/C981716A-A88E-4C62-8A3D-A39FA9BC7008\/data",
        "dataPathSize" : 6029025280,
        "udid" : "C981716A-A88E-4C62-8A3D-A39FA9BC7008",
        "isAvailable" : true,
        "deviceTypeIdentifier" : "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
        "state" : "Shutdown",
        "name" : "iPhone 17"
      }
    ],
    "com.apple.CoreSimulator.SimRuntime.iOS-17-5" : [
      {
        "udid" : "DEAD0001-0000-0000-0000-000000000000",
        "isAvailable" : false,
        "availabilityError" : "runtime profile not found",
        "state" : "Shutdown",
        "name" : "iPhone 15"
      }
    ]
  }
}
"""#

@Test func runtimesCarryTheirAssetFolderSizeAndLastUse() throws {
    let parsed = try #require(SimctlOutput.runtimes(runtimes))
    #expect(parsed.map(\.identifier) == ["22222222-0000-0000-0000-000000000002", "81934247-D744-4C6A-A50C-BC001F2FDDE6"])   // sorted
    let ios = try #require(parsed.last)
    #expect(ios.runtimeIdentifier == "com.apple.CoreSimulator.SimRuntime.iOS-26-3")
    #expect(ios.version == "26.3.1")
    #expect(ios.size == ByteCount(8_393_503_393))
    #expect(ios.isDeletable)
    #expect(ios.lastUsedAt == Instant(nanosecondsSince1970: 1_793_553_038 * 1_000_000_000))   // 2026-11-01T17:10:38Z
    #expect(ios.assetFolder == CanonicalPath("/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime/c6f07ed8ec1586ca140801a2c7c60f478e947602.asset"))
    let vision = try #require(parsed.first)
    #expect(vision.assetFolder == nil && vision.lastUsedAt == nil && vision.size == nil && !vision.isDeletable)
    #expect(SimctlOutput.runtimes("[]") == nil)
    #expect(SimctlOutput.runtimes("not json") == nil)
}

@Test func devicesCarryAvailabilityRuntimeAndDataSize() throws {
    let parsed = try #require(SimctlOutput.devices(devices))
    #expect(parsed.map(\.name).sorted() == ["iPhone 15", "iPhone 17"])
    let gone = try #require(parsed.first { $0.name == "iPhone 15" })
    #expect(gone.isAvailable == false)
    #expect(gone.runtimeIdentifier == "com.apple.CoreSimulator.SimRuntime.iOS-17-5")
    #expect(gone.dataSize == nil)
    #expect(parsed.first { $0.name == "iPhone 17" }?.dataSize == ByteCount(6_029_025_280))
    #expect(SimctlOutput.devices("{\"devices\": 3}") == nil)
}

@Test func virtualDeviceConfigNamesItsSystemImage() {
    let config = """
    AvdId=Pixel_9
    image.sysdir.1=system-images/android-37.0/google_apis/arm64-v8a/
    hw.lcd.density=420
    """
    #expect(AndroidOutput.imageFolder(fromConfig: config, sdkRoot: CanonicalPath("/Users/u/Library/Android/sdk")!)
            == CanonicalPath("/Users/u/Library/Android/sdk/system-images/android-37.0/google_apis/arm64-v8a"))
    #expect(AndroidOutput.imageFolder(fromConfig: "hw.lcd.density=420", sdkRoot: CanonicalPath("/sdk")!) == nil)
    #expect(AndroidOutput.package(forImageFolder: CanonicalPath("/sdk/system-images/android-35/google_apis_playstore/arm64-v8a")!,
                                  sdkRoot: CanonicalPath("/sdk")!) == "system-images;android-35;google_apis_playstore;arm64-v8a")
}
