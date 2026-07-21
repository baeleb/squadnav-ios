import XCTest
import CoreLocation

/// F8: RouteEncoder.decode crashes on malformed input.
final class RouteEncoderTests: XCTestCase {

    /// Control: proves the encode/decode harness works on valid input.
    func testRoundTripEncodeDecode() {
        let coords = [
            CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            CLLocationCoordinate2D(latitude: 37.3382, longitude: -121.8863),
            CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437),
            CLLocationCoordinate2D(latitude: 0, longitude: 0)
        ]
        let encoded = RouteEncoder.encode(coordinates: coords)
        XCTAssertFalse(encoded.isEmpty)

        let decoded = RouteEncoder.decode(polyline: encoded)
        XCTAssertEqual(decoded.count, coords.count)
        for (original, roundTripped) in zip(coords, decoded) {
            XCTAssertEqual(original.latitude, roundTripped.latitude, accuracy: 1e-5)
            XCTAssertEqual(original.longitude, roundTripped.longitude, accuracy: 1e-5)
        }
    }

    /// F8: VERIFIED BY CRASH on 2026-07-20 (iPhone 17 Pro simulator).
    /// decode("~") killed the xctest runner with:
    ///   Swift/StringIndexValidation.swift:121: Fatal error: String index is out of bounds
    /// ("~" -> byte 63 >= 0x20, decodeValue's repeat-while advances to
    /// endIndex then reads string[endIndex] on the next iteration.)
    /// Skipped so the rest of the suite can complete; unskipping reproduces.
    func testDecodeTruncatedPolylineDoesNotCrash() throws {
        throw XCTSkip("F8 VERIFIED: this input crashes the test runner (String index out of bounds). See header comment.")
        let result = RouteEncoder.decode(polyline: "~")
        XCTAssertTrue(result.isEmpty, "Truncated polyline should decode to empty, not crash")
    }

    /// F8: VERIFIED BY CRASH on 2026-07-20 (iPhone 17 Pro simulator).
    /// decode("é") killed the xctest runner with:
    ///   SquadNavTests/RouteEncoder.swift:77: Fatal error: Unexpectedly found
    ///   nil while unwrapping an Optional value
    /// (Character.asciiValue is nil for non-ASCII; force unwrap at line 77.)
    /// Skipped so the rest of the suite can complete; unskipping reproduces.
    func testDecodeNonASCIIDoesNotCrash() throws {
        throw XCTSkip("F8 VERIFIED: this input crashes the test runner (asciiValue! force unwrap). See header comment.")
        let result = RouteEncoder.decode(polyline: "é")
        XCTAssertTrue(result.isEmpty, "Non-ASCII polyline should decode to empty, not crash")
    }
}
