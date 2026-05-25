import Foundation
import CoreLocation

/// Encodes and decodes polyline coordinates using Google's Encoded Polyline Algorithm.
/// This allows storing an MKRoute's path as a compact string in Firestore.
enum RouteEncoder {

    /// Encodes an array of coordinates into a polyline string.
    static func encode(coordinates: [CLLocationCoordinate2D]) -> String {
        var encoded = ""
        var previousLat: Int = 0
        var previousLng: Int = 0

        for coordinate in coordinates {
            let lat = Int(round(coordinate.latitude * 1e5))
            let lng = Int(round(coordinate.longitude * 1e5))

            encoded += encodeValue(lat - previousLat)
            encoded += encodeValue(lng - previousLng)

            previousLat = lat
            previousLng = lng
        }

        return encoded
    }

    /// Decodes a polyline string into an array of coordinates.
    static func decode(polyline: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        var index = polyline.startIndex
        var lat: Int = 0
        var lng: Int = 0

        while index < polyline.endIndex {
            let (latDiff, newIndex1) = decodeValue(from: polyline, startingAt: index)
            lat += latDiff
            index = newIndex1

            let (lngDiff, newIndex2) = decodeValue(from: polyline, startingAt: index)
            lng += lngDiff
            index = newIndex2

            let coordinate = CLLocationCoordinate2D(
                latitude: Double(lat) / 1e5,
                longitude: Double(lng) / 1e5
            )
            coordinates.append(coordinate)
        }

        return coordinates
    }

    // MARK: - Private Helpers

    private static func encodeValue(_ value: Int) -> String {
        var v = value < 0 ? ~(value << 1) : (value << 1)
        var encoded = ""

        while v >= 0x20 {
            let charValue = (v & 0x1F) | 0x20
            encoded += String(UnicodeScalar(charValue + 63)!)
            v >>= 5
        }
        encoded += String(UnicodeScalar(v + 63)!)

        return encoded
    }

    private static func decodeValue(from string: String, startingAt index: String.Index) -> (Int, String.Index) {
        var result = 0
        var shift = 0
        var currentIndex = index
        var byte: Int

        repeat {
            byte = Int(string[currentIndex].asciiValue! - 63)
            currentIndex = string.index(after: currentIndex)
            result |= (byte & 0x1F) << shift
            shift += 5
        } while byte >= 0x20

        let value = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        return (value, currentIndex)
    }
}
