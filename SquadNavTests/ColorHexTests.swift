import XCTest
import SwiftUI
import UIKit

/// F15: Color(hex:) 8-digit parsing — AARRGGBB vs the conventional RRGGBBAA.
final class ColorHexTests: XCTestCase {

    /// "FF000080" under the widespread RRGGBBAA convention = semi-transparent
    /// red (r=FF, a=80). Extensions.swift:16 parses 8 digits as AARRGGBB
    /// (a=FF, r=00, b=80 -> opaque dark blue). Assert the conventional
    /// expectation; failure proves the actual byte order is AARRGGBB.
    func testEightDigitHexParsedAsRRGGBBAA() {
        let uiColor = UIColor(Color(hex: "FF000080"))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(uiColor.getRed(&r, green: &g, blue: &b, alpha: &a))

        XCTAssertEqual(r, 1.0, accuracy: 0.01,
                       "F15: RRGGBBAA expectation — red channel should be FF (actual parse is AARRGGBB -> r=00)")
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01,
                       "F15: RRGGBBAA expectation — blue channel should be 00 (actual parse is AARRGGBB -> b=80)")
        XCTAssertEqual(a, 128.0 / 255.0, accuracy: 0.01,
                       "F15: RRGGBBAA expectation — alpha should be 0x80 (actual parse is AARRGGBB -> a=FF)")
    }

    /// Control: 6-digit parsing is unambiguous and must be solid red.
    func testSixDigitHexControl() {
        let uiColor = UIColor(Color(hex: "FF0000"))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(uiColor.getRed(&r, green: &g, blue: &b, alpha: &a))

        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
        XCTAssertEqual(a, 1.0, accuracy: 0.01)
    }
}
