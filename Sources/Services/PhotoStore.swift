import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class PhotoStore {
    private let fileManager: FileManager
    let directoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = applicationSupport.appending(path: "ParmaMaster/Photos", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func save(imageData: Data, replacing oldFilename: String? = nil) throws -> String {
        guard let image = UIImage(data: imageData), let normalised = image.normalisedAndResized(maxDimension: 1_920) else {
            throw PhotoStoreError.invalidImage
        }
        guard let compressed = normalised.jpegData(compressionQuality: 0.78) else {
            throw PhotoStoreError.couldNotCompress
        }

        let filename = "\(UUID().uuidString).jpg"
        let destination = directoryURL.appending(path: filename)
        try compressed.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if let oldFilename, oldFilename != filename {
            try? delete(filename: oldFilename)
        }
        return filename
    }

    func image(for filename: String?) -> UIImage? {
        guard let filename else { return nil }
        return UIImage(contentsOfFile: directoryURL.appending(path: filename).path)
    }

    func data(for filename: String) -> Data? {
        try? Data(contentsOf: directoryURL.appending(path: filename))
    }

    func restore(data: Data, filename: String) throws {
        guard UIImage(data: data) != nil else { throw PhotoStoreError.invalidImage }
        try data.write(to: directoryURL.appending(path: filename), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func delete(filename: String) throws {
        let url = directoryURL.appending(path: filename)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func removeAll() throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        let contents = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        for url in contents {
            try fileManager.removeItem(at: url)
        }
    }
}

enum PhotoStoreError: LocalizedError {
    case invalidImage
    case couldNotCompress

    var errorDescription: String? {
        switch self {
        case .invalidImage: "That file is not a supported image."
        case .couldNotCompress: "The photo could not be prepared for storage."
        }
    }
}

private extension UIImage {
    func normalisedAndResized(maxDimension: CGFloat) -> UIImage? {
        let longest = max(size.width, size.height)
        let scale = min(1, maxDimension / max(longest, 1))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
