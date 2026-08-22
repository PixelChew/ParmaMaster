import Foundation
import ImageIO
import Observation
import UIKit

/// Sendable disk accessor so photo bytes can be read off the main actor
/// (e.g. from BackupService's detached export task) without touching
/// PhotoStore's MainActor state (audit B-06).
struct PhotoDiskIO: Sendable {
    let directoryURL: URL

    nonisolated func data(for filename: String) -> Data? {
        try? Data(contentsOf: directoryURL.appending(path: filename))
    }

    nonisolated func thumbnailImage(for filename: String, maxPixelSize: CGFloat) -> UIImage? {
        let url = directoryURL.appending(path: filename)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }

    nonisolated func fullImage(for filename: String) -> UIImage? {
        UIImage(contentsOfFile: directoryURL.appending(path: filename).path)
    }
}

@MainActor
@Observable
final class PhotoStore {
    private let fileManager: FileManager
    let directoryURL: URL

    /// Decoded images keyed by filename ("thumb:"-prefixed for thumbnails).
    /// NSCache evicts automatically under memory pressure (audit P-05).
    private let imageCache = NSCache<NSString, UIImage>()

    var diskIO: PhotoDiskIO {
        PhotoDiskIO(directoryURL: directoryURL)
    }

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directoryURL = applicationSupport.appending(path: "ParmaMaster/Photos", directoryHint: .isDirectory)
        }
        try? fileManager.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
    }

    func save(imageData: Data, replacing oldFilename: String? = nil) throws -> String {
        guard let image = UIImage(data: imageData),
              let normalised = image.normalisedAndResized(maxDimension: PhotoTuning.maxStoredDimension) else {
            throw PhotoStoreError.invalidImage
        }
        guard let compressed = normalised.jpegData(compressionQuality: PhotoTuning.jpegCompressionQuality) else {
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

    func cachedImage(for filename: String, thumbnail: Bool) -> UIImage? {
        imageCache.object(forKey: thumbnail ? Self.thumbnailKey(for: filename) : filename as NSString)
    }

    func cacheImage(_ image: UIImage, filename: String, thumbnail: Bool) {
        imageCache.setObject(image, forKey: thumbnail ? Self.thumbnailKey(for: filename) : filename as NSString)
    }

    func image(for filename: String?) -> UIImage? {
        guard let filename else { return nil }
        let key = filename as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let image = UIImage(contentsOfFile: directoryURL.appending(path: filename).path) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    /// Downsampled image for list rows and cards, decoded via ImageIO so the
    /// full-size bitmap never enters memory (audit P-05).
    func thumbnail(for filename: String?) -> UIImage? {
        guard let filename else { return nil }
        let key = Self.thumbnailKey(for: filename)
        if let cached = imageCache.object(forKey: key) { return cached }
        let url = directoryURL.appending(path: filename)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: PhotoTuning.thumbnailPixelSize
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = UIImage(cgImage: thumbnail)
        imageCache.setObject(image, forKey: key)
        return image
    }

    func data(for filename: String) -> Data? {
        try? Data(contentsOf: directoryURL.appending(path: filename))
    }

    func restore(data: Data, filename: String) throws {
        guard UIImage(data: data) != nil else { throw PhotoStoreError.invalidImage }
        try data.write(to: directoryURL.appending(path: filename), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        invalidateCache(for: filename)
    }

    func delete(filename: String) throws {
        invalidateCache(for: filename)
        let url = directoryURL.appending(path: filename)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func removeAll() throws {
        imageCache.removeAllObjects()
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        let contents = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        for url in contents {
            try fileManager.removeItem(at: url)
        }
    }

    private func invalidateCache(for filename: String) {
        imageCache.removeObject(forKey: filename as NSString)
        imageCache.removeObject(forKey: Self.thumbnailKey(for: filename))
    }

    private static func thumbnailKey(for filename: String) -> NSString {
        "thumb:\(filename)" as NSString
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
