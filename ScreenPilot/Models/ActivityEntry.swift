import Foundation

struct ActivityEntry: Codable {
    let timestamp: Date
    let app: String
    let bundleId: String?
    let windowTitle: String?
    let summary: String
}
