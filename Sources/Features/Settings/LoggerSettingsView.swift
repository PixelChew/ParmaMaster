import SwiftUI

struct LoggerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var draft = RatingConfiguration.default
    @State private var maximumInputs: [RatingCategory: String] = [:]
    @State private var photoEnabled = true
    @State private var errorMessage: String?
    @State private var isConfigured = false

    var body: some View {
        Form {
            Section("Overall score") {
                Picker("Display style", selection: overallDisplayModeBinding) {
                    ForEach(RatingDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Text("The overall maximum is always the sum of enabled category maximums: \(derivedMaximum.displayString).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(RatingCategory.allCases) { category in
                CategorySettingsSection(
                    category: category,
                    configuration: componentBinding(category),
                    maximumText: maximumBinding(category),
                    canDisable: draft.enabledComponents.count > 1,
                    overallUsesStars: draft.overallDisplayMode == .stars,
                    onInvalidStarMode: {
                        errorMessage = "Stars need a whole-number maximum from 1 to 10. Enter one before switching \(category.rawValue) to Stars."
                    }
                )
            }

            Section("Photo") {
                Toggle("Offer photo controls", isOn: $photoEnabled)
                Text("Photos are always optional. Turning this off hides the logger controls but never removes existing photos.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .brandedNavigationTitle("Parma Logging")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") { save() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draftIsValid)
            }
        }
        .onAppear { configureIfNeeded() }
        .alert("Check Rating Settings", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please correct the rating settings.")
        }
    }

    private var derivedMaximum: Decimal {
        draft.enabledComponents.map(\.maximum).reduce(0, +)
    }

    private var overallDisplayModeBinding: Binding<RatingDisplayMode> {
        Binding(
            get: { draft.overallDisplayMode },
            set: { mode in
                if !draft.applyOverallDisplayMode(mode) {
                    errorMessage = "Every enabled category needs a whole-number maximum from 1 to 10 before using Stars."
                }
            }
        )
    }

    private var draftIsValid: Bool {
        var checked = draft
        for index in checked.components.indices {
            guard let value = Decimal.parseUserInput(maximumInputs[checked.components[index].category] ?? "") else { return false }
            checked.components[index].maximum = value
        }
        return checked.isValid
    }

    private func componentBinding(_ category: RatingCategory) -> Binding<ComponentConfiguration> {
        Binding(
            get: { draft.components.first(where: { $0.category == category })! },
            set: { updated in draft.update(category) { $0 = updated } }
        )
    }

    private func maximumBinding(_ category: RatingCategory) -> Binding<String> {
        Binding(
            get: { maximumInputs[category] ?? "" },
            set: { value in
                maximumInputs[category] = value
                if let maximum = Decimal.parseUserInput(value) {
                    draft.update(category) { $0.maximum = maximum }
                }
            }
        )
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        draft = settings.ratingConfiguration
        maximumInputs = Dictionary(uniqueKeysWithValues: draft.components.map { ($0.category, $0.maximum.displayString) })
        photoEnabled = settings.photoFeatureEnabled
    }

    private func save() {
        guard draftIsValid else {
            errorMessage = "Each enabled category needs a positive maximum, and star maximums must be whole numbers from 1 to 10."
            return
        }
        settings.ratingConfiguration = draft
        settings.photoFeatureEnabled = photoEnabled
        dismiss()
    }
}

private struct CategorySettingsSection: View {
    let category: RatingCategory
    @Binding var configuration: ComponentConfiguration
    @Binding var maximumText: String
    let canDisable: Bool
    let overallUsesStars: Bool
    let onInvalidStarMode: () -> Void

    var body: some View {
        Section {
            Toggle("Enabled", isOn: Binding(
                get: { configuration.isEnabled },
                set: { enabled in
                    if enabled || canDisable { configuration.isEnabled = enabled }
                }
            ))

            if configuration.isEnabled {
                Picker("Scale style", selection: Binding(
                    get: { configuration.displayMode },
                    set: { mode in
                        if mode == .stars,
                           (!configuration.maximum.isFinite || configuration.maximum <= 0 || configuration.maximum > 10 || configuration.maximum.rounded(scale: 0) != configuration.maximum) {
                            onInvalidStarMode()
                        } else {
                            configuration.displayMode = mode
                        }
                    }
                )) {
                    ForEach(RatingDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .disabled(overallUsesStars)

                HStack {
                    Text(configuration.displayMode == .stars ? "Star count" : "Maximum")
                    Spacer()
                    TextField("Maximum", text: $maximumText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
            }
        } header: {
            Text(category.rawValue)
        } footer: {
            if overallUsesStars && configuration.isEnabled {
                Text("The overall Stars style applies to every enabled category.")
            } else if !canDisable && configuration.isEnabled {
                Text("At least one rating category must remain enabled.")
            }
        }
    }
}
