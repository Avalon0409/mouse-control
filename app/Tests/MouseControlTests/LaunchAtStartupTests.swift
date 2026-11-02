import XCTest
@testable import MouseControlTestHost

/// Exercises launch at startup behavior.
final class LaunchAtStartupTests: XCTestCase {
    func testLaunchAgentPropertyListTargetsServiceModeAtNextLogin() {
        let plist = BackgroundServiceCoordinator.launchAgentPropertyList(executablePath: "/Applications/OpenSnek.app/Contents/MacOS/OpenSnek", workingDirectoryPath: "/Applications/OpenSnek.app/Contents/MacOS")

        XCTAssertEqual(plist["Label"] as? String, "local.mousecontrol.MouseControl.service")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/Applications/OpenSnek.app/Contents/MacOS/OpenSnek", "--service-mode", "--login-start"])
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["KeepAlive"] as? Bool, false)
        XCTAssertEqual(plist["WorkingDirectory"] as? String, "/Applications/OpenSnek.app/Contents/MacOS")
    }
}
