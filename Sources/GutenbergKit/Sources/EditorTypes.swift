import Foundation

struct EditorBlockType: Decodable, Identifiable {
    var id: String { name }

    let name: String
    let title: String?
    let description: String?
    let category: String?
    let keywords: [String]?
}

struct EditorAssets: Decodable {
    let styles: String
    let scripts: String
}
