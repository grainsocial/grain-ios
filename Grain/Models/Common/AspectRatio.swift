import Foundation

struct AspectRatio: Codable, Sendable {
    let width: Int
    let height: Int

    var ratio: Double {
        Double(width) / Double(height)
    }
}
