import XCTest
@testable import ZCodeAccountSwitcherCore

final class ZCodeProcessServiceTests: XCTestCase {
    func testZCodeProcessMatcherDoesNotMatchSwitcherBundleId() {
        XCTAssertFalse(ZCodeProcessService.isZCodeApplication(
            localizedName: "ZCode Account Switcher",
            bundleURL: URL(fileURLWithPath: "/tmp/ZCodeAccountSwitcher.app"),
            bundleIdentifier: "com.zcode.account-switcher.mac"
        ))

        XCTAssertTrue(ZCodeProcessService.isZCodeApplication(
            localizedName: "ZCode",
            bundleURL: URL(fileURLWithPath: "/Applications/ZCode.app"),
            bundleIdentifier: "dev.zcode.app"
        ))
    }

    func testZCodeCommandMatcherCatchesHelperProcessesWithoutFalsePositives() {
        XCTAssertTrue(ZCodeProcessService.isZCodeProcessCommand("ZCode"))
        XCTAssertTrue(ZCodeProcessService.isZCodeProcessCommand(
            "/Applications/ZCode.app/Contents/Frameworks/ZCode Helper.app/Contents/MacOS/ZCode Helper --type=gpu-process"
        ))
        XCTAssertTrue(ZCodeProcessService.isZCodeProcessCommand("zcode-host-local-1"))
        XCTAssertTrue(ZCodeProcessService.isZCodeProcessCommand(
            "/Applications/ZCode.app/Contents/Frameworks/Electron Framework.framework/Helpers/chrome_crashpad_handler --annotation=_productName=ZCode"
        ))

        XCTAssertFalse(ZCodeProcessService.isZCodeProcessCommand(
            "/tmp/ZCodeAccountSwitcher.app/Contents/MacOS/ZCodeAccountSwitcher"
        ))
        XCTAssertFalse(ZCodeProcessService.isZCodeProcessCommand(
            "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled"
        ))
    }
}
