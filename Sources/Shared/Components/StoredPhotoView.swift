import SwiftUI
import UIKit

struct StoredPhotoView: View {
    let filename: String?
    /// Renders a downsampled image for list rows and cards (audit P-05).
    var useThumbnail = false
    @Environment(PhotoStore.self) private var photoStore
    @State private var image: UIImage?

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                if let image {
                    AspectFillImage(image: image)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: filename == nil ? "fork.knife" : "photo.badge.exclamationmark")
                            .font(.title)
                        Text(filename == nil ? "No photo" : "Photo unavailable")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .clipped()
            .clipShape(.rect(cornerRadius: BrandStyle.cardRadius))
            .accessibilityLabel(filename == nil ? "No Parma photo" : "Parma photo")
            .task(id: "\(filename ?? "")-\(useThumbnail)") {
                await loadImage()
            }
    }

    @MainActor
    private func loadImage() async {
        guard let filename else {
            image = nil
            return
        }
        if let cached = photoStore.cachedImage(for: filename, thumbnail: useThumbnail) {
            image = cached
            return
        }
        let disk = photoStore.diskIO
        let loadThumbnail = useThumbnail
        let loaded = await Task.detached(priority: .utility) {
            if loadThumbnail {
                return disk.thumbnailImage(for: filename, maxPixelSize: PhotoTuning.thumbnailPixelSize)
            }
            return disk.fullImage(for: filename)
        }.value
        guard let loaded else { return }
        photoStore.cacheImage(loaded, filename: filename, thumbnail: useThumbnail)
        image = loaded
    }
}
