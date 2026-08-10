import SwiftUI

struct StoredPhotoView: View {
    let filename: String?
    @Environment(PhotoStore.self) private var photoStore

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                if let image = photoStore.image(for: filename) {
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
