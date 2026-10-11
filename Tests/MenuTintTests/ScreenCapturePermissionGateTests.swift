import Foundation
import XCTest
@testable import MenuTint

final class ScreenCapturePermissionGateTests: XCTestCase {
    func testDisabledLaunchDoesNotCheckOrRequestPermission() {
        let permission = FakePermission()
        permission.gate.requestIfNeeded(tintingEnabled: false)

        XCTAssertEqual(permission.preflightCount, 0)
        XCTAssertEqual(permission.requestCount, 0)
    }

    func testEnabledLaunchWithoutGrantRequestsOnce() {
        let permission = FakePermission()
        permission.gate.requestIfNeeded(tintingEnabled: true)

        XCTAssertEqual(permission.preflightCount, 1)
        XCTAssertEqual(permission.requestCount, 1)
    }

    func testTurningOffNeverChecksOrRequestsPermission() {
        let permission = FakePermission()
        let gate = permission.gate
        gate.requestIfNeeded(tintingEnabled: true)
        let previousPreflights = permission.preflightCount
        let previousRequests = permission.requestCount

        gate.requestIfNeeded(tintingEnabled: false)

        XCTAssertEqual(permission.preflightCount, previousPreflights)
        XCTAssertEqual(permission.requestCount, previousRequests)
        XCTAssertFalse(permission.granted)
    }

    func testTurningOnWithoutGrantRequestsOnce() {
        let permission = FakePermission()
        let gate = permission.gate
        gate.requestIfNeeded(tintingEnabled: false)
        gate.requestIfNeeded(tintingEnabled: true)

        XCTAssertEqual(permission.preflightCount, 1)
        XCTAssertEqual(permission.requestCount, 1)
    }

    func testAlreadyGrantedPermissionDoesNotRequestAtLaunchOrOnToggle() {
        let permission = FakePermission(granted: true)
        let gate = permission.gate
        gate.requestIfNeeded(tintingEnabled: true)
        gate.requestIfNeeded(tintingEnabled: false)
        gate.requestIfNeeded(tintingEnabled: true)

        XCTAssertEqual(permission.preflightCount, 2)
        XCTAssertEqual(permission.requestCount, 0)
        XCTAssertTrue(permission.granted)
    }

    func testRequestResultDoesNotReplacePreflight() {
        for result in [false, true] {
            let permission = FakePermission(requestResult: result)
            let gate = permission.gate
            gate.requestIfNeeded(tintingEnabled: true)
            gate.requestIfNeeded(tintingEnabled: false)
            gate.requestIfNeeded(tintingEnabled: true)

            XCTAssertEqual(permission.preflightCount, 2)
            XCTAssertEqual(permission.requestCount, 2)
            XCTAssertFalse(permission.granted)
        }
    }

    func testInfoPlistContainsExactApprovedPurposeString() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repository.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        XCTAssertEqual(
            plist["NSScreenCaptureUsageDescription"] as? String,
            "MenuTint needs Screen Recording access to tint the menu bar. Captured frames are processed locally and aren’t saved or shared."
        )
    }
}

private final class FakePermission {
    var granted: Bool
    let requestResult: Bool
    var preflightCount = 0
    var requestCount = 0

    init(granted: Bool = false, requestResult: Bool = false) {
        self.granted = granted
        self.requestResult = requestResult
    }

    var gate: ScreenCapturePermissionGate {
        ScreenCapturePermissionGate(
            preflight: {
                self.preflightCount += 1
                return self.granted
            },
            request: {
                self.requestCount += 1
                return self.requestResult
            }
        )
    }
}
