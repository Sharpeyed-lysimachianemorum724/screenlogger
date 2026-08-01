import XCTest

final class AppInstallLocationTests: XCTestCase {
    func testInstallerVolumeRequiresInstallationBeforePermissionSetup() {
        XCTAssertTrue(
            AppInstallLocation.requiresInstallationBeforePermissionSetup(
                bundleURL: URL(fileURLWithPath: "/Volumes/Screenlogger 0.1.0/Screenlogger.app")
            )
        )
    }

    func testApplicationsAndDevelopmentBuildsCanContinue() {
        XCTAssertFalse(
            AppInstallLocation.requiresInstallationBeforePermissionSetup(
                bundleURL: URL(fileURLWithPath: "/Applications/Screenlogger.app")
            )
        )
        XCTAssertFalse(
            AppInstallLocation.requiresInstallationBeforePermissionSetup(
                bundleURL: URL(
                    fileURLWithPath:
                        "/Users/test/project/build/DerivedData/Build/Products/Debug/Screenlogger.app"
                )
            )
        )
    }
}
