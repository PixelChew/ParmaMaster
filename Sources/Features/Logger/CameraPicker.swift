import AVFoundation
import SwiftUI
import UIKit

struct CameraPicker: View {
    let onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var authorization = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            switch authorization {
            case .authorized:
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    CameraController { data in
                        onImage(data)
                        dismiss()
                    }
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "Camera unavailable",
                        systemImage: "camera.fill",
                        description: Text("Use Choose from Photos or Choose File instead.")
                    )
                }
            case .denied, .restricted:
                ContentUnavailableView {
                    Label("Camera access is off", systemImage: "camera.badge.ellipsis")
                } description: {
                    Text("Enable Camera for Parma Master in iOS Settings, or choose an existing photo.")
                } actions: {
                    Button("Open Settings") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            default:
                ProgressView("Requesting camera access…")
                    .task {
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        authorization = AVCaptureDevice.authorizationStatus(for: .video)
                    }
            }
        }
    }
}

// UIImagePickerController is a legacy API. It remains functional and is kept
// deliberately: replacing camera capture with a custom AVCaptureSession flow
// needs on-device verification before it can ship.
private struct CameraController: UIViewControllerRepresentable {
    let onImage: (Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (Data) -> Void

        init(onImage: @escaping (Data) -> Void) {
            self.onImage = onImage
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                onImage(data)
            }
        }
    }
}
