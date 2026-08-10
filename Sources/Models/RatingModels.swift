import Foundation

enum RatingCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case parma = "Parma"
    case chips = "Chips"
    case salad = "Salad"

    var id: String { rawValue }
}

enum RatingDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case numeric = "Out of"
    case stars = "Stars"

    var id: String { rawValue }
}

struct ComponentConfiguration: Codable, Hashable, Identifiable, Sendable {
    var category: RatingCategory
    var isEnabled: Bool
    var displayMode: RatingDisplayMode
    var maximum: Decimal

    var id: RatingCategory { category }

    var isValid: Bool {
        guard maximum.isFinite, maximum > 0 else { return false }
        if displayMode == .stars {
            return maximum.rounded(scale: 0) == maximum && maximum <= 10
        }
        return true
    }
}

struct RatingConfiguration: Codable, Hashable, Sendable {
    var components: [ComponentConfiguration]
    var overallDisplayMode: RatingDisplayMode

    static let `default` = RatingConfiguration(
        components: [
            ComponentConfiguration(category: .parma, isEnabled: true, displayMode: .numeric, maximum: 5),
            ComponentConfiguration(category: .chips, isEnabled: true, displayMode: .numeric, maximum: 3),
            ComponentConfiguration(category: .salad, isEnabled: true, displayMode: .numeric, maximum: 2)
        ],
        overallDisplayMode: .numeric
    )

    var enabledComponents: [ComponentConfiguration] {
        components.filter(\.isEnabled)
    }

    var isValid: Bool {
        !enabledComponents.isEmpty && components.allSatisfy { !$0.isEnabled || $0.isValid }
    }

    mutating func update(_ category: RatingCategory, _ change: (inout ComponentConfiguration) -> Void) {
        guard let index = components.firstIndex(where: { $0.category == category }) else { return }
        change(&components[index])
    }

    @discardableResult
    mutating func applyOverallDisplayMode(_ mode: RatingDisplayMode) -> Bool {
        if mode == .stars {
            let starCompatible = enabledComponents.allSatisfy {
                $0.maximum.isFinite && $0.maximum > 0 && $0.maximum <= 10
                    && $0.maximum.rounded(scale: 0) == $0.maximum
            }
            guard starCompatible else { return false }
        }

        overallDisplayMode = mode
        for index in components.indices where components[index].isEnabled {
            components[index].displayMode = mode
        }
        return true
    }
}

struct ComponentRatingSnapshot: Codable, Hashable, Identifiable, Sendable {
    var category: RatingCategory
    var isEnabled: Bool
    var displayMode: RatingDisplayMode
    var maximum: Decimal
    var score: Decimal?

    var id: RatingCategory { category }
}

struct RatingSnapshot: Codable, Hashable, Sendable {
    var components: [ComponentRatingSnapshot]
    var overallDisplayMode: RatingDisplayMode

    var enabledComponents: [ComponentRatingSnapshot] {
        components.filter(\.isEnabled)
    }

    var total: Decimal {
        enabledComponents.compactMap(\.score).reduce(0, +)
    }

    var maximum: Decimal {
        enabledComponents.map(\.maximum).reduce(0, +)
    }

    var normalisedScore: Decimal {
        guard maximum > 0 else { return 0 }
        return total / maximum
    }

    var hasValidScores: Bool {
        !enabledComponents.isEmpty && enabledComponents.allSatisfy { component in
            guard let score = component.score else { return false }
            return component.maximum > 0 && score.isFinite && score >= 0 && score <= component.maximum
        }
    }

    func numericallyMatches(_ other: RatingSnapshot) -> Bool {
        let lhs = Dictionary(uniqueKeysWithValues: enabledComponents.map { ($0.category, $0.score) })
        let rhs = Dictionary(uniqueKeysWithValues: other.enabledComponents.map { ($0.category, $0.score) })
        return lhs == rhs
    }

    static func blank(configuration: RatingConfiguration) -> RatingSnapshot {
        RatingSnapshot(
            components: configuration.components.map {
                ComponentRatingSnapshot(
                    category: $0.category,
                    isEnabled: $0.isEnabled,
                    displayMode: $0.displayMode,
                    maximum: $0.maximum,
                    score: nil
                )
            },
            overallDisplayMode: configuration.overallDisplayMode
        )
    }
}

extension Decimal {
    var isFinite: Bool {
        !isNaN
    }

    func rounded(scale: Int) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }

    var displayString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: self)) ?? description
    }

    static func parseUserInput(_ text: String, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        if let number = formatter.number(from: trimmed) as? NSDecimalNumber,
           number != .notANumber {
            return number.decimalValue
        }

        let normalised = trimmed.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
        return Decimal(string: normalised, locale: Locale(identifier: "en_US_POSIX"))
    }
}
