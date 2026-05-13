import Foundation
import UniformTypeIdentifiers
import SwiftUI

struct ExplorationData: Codable {
    let version: Int
    let exportedAt: Date
    let tileCount: Int
    let tiles: [TileCoord]

    init(tiles: Set<TileCoord>) {
        self.version = 1
        self.exportedAt = Date()
        self.tileCount = tiles.count
        self.tiles = Array(tiles)
    }
}

struct ExplorationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: ExplorationData

    init(tiles: Set<TileCoord>) {
        self.data = ExplorationData(tiles: tiles)
    }

    init(configuration: ReadConfiguration) throws {
        guard let fileData = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.data = try decoder.decode(ExplorationData.self, from: fileData)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(data)
        return FileWrapper(regularFileWithContents: jsonData)
    }
}
