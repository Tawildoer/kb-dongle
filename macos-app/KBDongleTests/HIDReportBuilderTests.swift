import XCTest
@testable import KBDongle

final class HIDReportBuilderTests: XCTestCase {
    var builder: HIDReportBuilder!

    override func setUp() { builder = HIDReportBuilder() }

    func testKeyDownProducesCorrectHIDReport() {
        let report = builder.keyDown(cgKeyCode: 0x00, flags: [])
        XCTAssertEqual(report[0], 0x00)
        XCTAssertEqual(report[1], 0x00)
        XCTAssertEqual(report[2], 0x04)
    }

    func testKeyUpRemovesKeycode() {
        _ = builder.keyDown(cgKeyCode: 0x00, flags: [])
        let report = builder.keyUp(cgKeyCode: 0x00, flags: [])
        XCTAssertEqual(report[2], 0x00)
    }

    func testShiftModifierSetsBit() {
        let report = builder.keyDown(cgKeyCode: 0x38, flags: [])
        XCTAssertEqual(report[0], 0x02)
        XCTAssertEqual(report[2], 0x00)
    }

    func testMouseReport() {
        let report = HIDReportBuilder.mouseReport(buttons: 0x01, dx: 10, dy: -5, scroll: 0)
        XCTAssertEqual(report[0], 0x01)
        XCTAssertEqual(report[1], 10)
        XCTAssertEqual(report[2], UInt8(bitPattern: -5))
        XCTAssertEqual(report[3], 0x00)
    }
}
