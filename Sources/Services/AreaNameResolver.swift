import Foundation
import MapKit

/// Derives a suburb/town area name for the Areas visited tally.
///
/// Grain matches the product rule: Daylesford → one place; three Melbourne
/// suburbs → three places. Prefers MapKit `cityName`, then parses the
/// formatted address when MapKit leaves city empty (common for older entries
/// and some AU reverse-geocode results).
enum AreaNameResolver {
    private static let auStates: Set<String> = [
        "NSW", "VIC", "QLD", "SA", "WA", "TAS", "ACT", "NT"
    ]

    /// Normalised key so "Fitzroy" and "fitzroy" count as one area.
    static func normalisedKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func preferredAreaName(from mapItem: MKMapItem) -> String? {
        cleaned(mapItem.addressRepresentations?.cityName)
            ?? fromFormattedAddress(mapItem.address?.fullAddress)
            ?? fromFormattedAddress(
                mapItem.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)
            )
    }

    /// Best-effort suburb/town extraction from a stored address string.
    static func fromFormattedAddress(_ address: String?) -> String? {
        guard let address = cleaned(address), address != "Address unavailable" else { return nil }

        var parts = address
            .split(separator: ",", omittingEmptySubsequences: false)
            .compactMap { cleaned(String($0)) }
        guard !parts.isEmpty else { return nil }

        if parts.count >= 2, looksLikeCountry(parts[parts.count - 1]) {
            parts.removeLast()
        }
        guard let trailing = parts.last else { return nil }

        // US-style: "Cupertino, CA 95014" → city is the previous comma part.
        if parts.count >= 2, isStateOrPostcodeOnly(trailing) {
            return cleaned(parts[parts.count - 2])
        }

        // AU-style: "Fitzroy VIC 3065" or "Daylesford VIC 3460".
        if let suburb = stripTrailingStateAndPostcode(trailing), !isStateOrPostcodeOnly(suburb) {
            return suburb
        }

        // Plain trailing place name with no state/postcode suffix.
        if !isStateOrPostcodeOnly(trailing), !looksLikeStreet(trailing) {
            return trailing
        }

        // Fall back one more comma part when the trailer looked like a street.
        if parts.count >= 2, looksLikeStreet(trailing) {
            let previous = parts[parts.count - 2]
            if let suburb = stripTrailingStateAndPostcode(previous) ?? cleaned(previous),
               !isStateOrPostcodeOnly(suburb),
               !looksLikeStreet(suburb) {
                return suburb
            }
        }

        return nil
    }

    // MARK: - Internals

    private static func stripTrailingStateAndPostcode(_ value: String) -> String? {
        let tokens = value.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }

        var end = tokens.count
        // Drop trailing postcode (AU 4-digit or US 5 / 5+4).
        if end >= 1, isPostcode(tokens[end - 1]) {
            end -= 1
        }
        // Drop trailing state / territory code.
        if end >= 1, isStateCode(tokens[end - 1]) {
            end -= 1
        }
        // Only accept when a state/postcode suffix was actually removed.
        guard end > 0, end < tokens.count else { return nil }
        return cleaned(tokens[..<end].joined(separator: " "))
    }

    private static func isStateOrPostcodeOnly(_ value: String) -> Bool {
        let tokens = value.split(separator: " ").map(String.init)
        guard !tokens.isEmpty, tokens.count <= 2 else { return false }
        if tokens.count == 1 {
            return isStateCode(tokens[0]) || isPostcode(tokens[0])
        }
        return isStateCode(tokens[0]) && isPostcode(tokens[1])
    }

    private static func isStateCode(_ token: String) -> Bool {
        let upper = token.uppercased()
        if auStates.contains(upper) { return true }
        // US / CA style two-letter region codes.
        return upper.count == 2 && upper.unicodeScalars.allSatisfy(CharacterSet.uppercaseLetters.contains)
    }

    private static func isPostcode(_ token: String) -> Bool {
        let digits = token.replacingOccurrences(of: "-", with: "")
        return (digits.count == 4 || digits.count == 5 || digits.count == 9)
            && digits.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
    }

    private static func looksLikeCountry(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower == "australia"
            || lower == "united states"
            || lower == "usa"
            || lower == "new zealand"
            || lower == "united kingdom"
            || lower == "canada"
    }

    private static func looksLikeStreet(_ value: String) -> Bool {
        let lower = value.lowercased()
        let streetMarkers = [
            " st", " street", " rd", " road", " ave", " avenue", " dr", " drive",
            " ct", " court", " pl", " place", " ln", " lane", " hwy", " highway",
            " blvd", " parade", " pde", " crescent", " cres", " way", " track",
            " terrace", " tce"
        ]
        if streetMarkers.contains(where: { lower.hasSuffix($0) || lower.contains($0 + " ") }) {
            return true
        }
        // Leading street number: "123 High St".
        if let first = value.split(separator: " ").first,
           first.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains) {
            return true
        }
        return false
    }
}
