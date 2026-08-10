import MapKit
import SwiftUI

struct LocationPickerView: View {
    let onSelect: (VenueCandidate) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var completer = MapSearchCompleter()
    @State private var isResolving = false
    @State private var errorMessage: String?
    private let searchService = MapSearchService()

    var body: some View {
        NavigationStack {
            Group {
                if completer.query.isEmpty {
                    ContentUnavailableView(
                        "Search Apple Maps",
                        systemImage: "map",
                        description: Text("Enter a pub or venue name. The selected Maps place becomes the canonical venue identity.")
                    )
                } else if let message = completer.errorMessage {
                    ContentUnavailableView(
                        "Search unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(message)
                    )
                } else if completer.results.isEmpty {
                    ProgressView("Searching nearby places…")
                } else {
                    List(completer.results, id: \.self) { completion in
                        Button {
                            resolve(completion)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(completion.title).foregroundStyle(.primary)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(isResolving)
                    }
                }
            }
            .navigationTitle("Choose Venue")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $completer.query, prompt: "Pub or venue")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
            .overlay {
                if isResolving {
                    ProgressView()
                        .controlSize(.large)
                        .padding()
                        .background(.regularMaterial, in: .circle)
                }
            }
            .alert("Couldn’t Select Venue", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private func resolve(_ completion: MKLocalSearchCompletion) {
        isResolving = true
        Task {
            defer { isResolving = false }
            do {
                let venue = try await searchService.resolve(completion)
                onSelect(venue)
                dismiss()
            } catch {
                errorMessage = "The selected place could not be loaded. Check your connection and try again."
            }
        }
    }
}
