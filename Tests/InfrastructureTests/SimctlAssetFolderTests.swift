import Catalog
import SharedKernel
import Testing
@testable import Infrastructure

/// A runtime whose disk image sits outside the download still names its download through `parentMountPath`.
@Test func aRuntimeNamesItsDownloadThroughItsParentMountWhenItsImageLivesElsewhere() throws {
    let json = #"""
    {
      "33333333-0000-0000-0000-000000000003" : {
        "deletable" : true,
        "identifier" : "33333333-0000-0000-0000-000000000003",
        "parentMountPath" : "\/System\/Library\/AssetsV2\/com_apple_MobileAsset_iOSSimulatorRuntime\/ab12.asset\/AssetData",
        "path" : "\/Library\/Developer\/CoreSimulator\/Images\/ios.dmg",
        "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-18-0",
        "state" : "Ready",
        "version" : "18.0"
      }
    }
    """#
    let runtimes = try #require(SimctlOutput.runtimes(json))
    #expect(runtimes.first?.assetFolder == CanonicalPath("/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime/ab12.asset"))
}
