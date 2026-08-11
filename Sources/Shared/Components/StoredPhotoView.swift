import SwiftUI
import UIKit

struct StoredPhotoView: View {
    let filename: String?
    /// Renders a downsampled image for list rows and cards.
    var useThumbnail = false
    @Environment(PhotoStore.self) private var photoStore

    private var loadedImage: UIImage? {
        useThumbnail ? photoStore.thumbnail(for: filename) : photoStore.image(for: filename)
    }

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                if let image = loadedImage {
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
    }
}
