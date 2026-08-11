import XCTest
@testable import ParmaMaster

final class AreaNameResolverTests: XCTestCase {
    func testParsesAustralianSuburbBeforeStateAndPostcode() {
        XCTAssertEqual(
            AreaNameResolver.fromFormattedAddress("123 Smith St, Fitzroy VIC 3065, Australia"),
            "Fitzroy"
        )
        XCTAssertEqual(
            AreaNameResolver.fromFormattedAddress("Daylesford VIC 3460, Australia"),
            "Daylesford"
        )
        XCTAssertEqual(
            AreaNameResolver.fromFormattedAddress("45 Burke Rd, Camberwell VIC 3124, Australia"),
            "Camberwell"
        )
    }

    func testParsesUSCityBeforeStateAndPostcode() {
        XCTAssertEqual(
            AreaNameResolver.fromFormattedAddress("1 Apple Park Way, Cupertino, CA 95014, United States"),
            "Cupertino"
        )
    }

    func testIgnoresUnavailableAndEmptyAddresses() {
        XCTAssertNil(AreaNameResolver.fromFormattedAddress("Address unavailable"))
        XCTAssertNil(AreaNameResolver.fromFormattedAddress("   "))
        XCTAssertNil(AreaNameResolver.fromFormattedAddress(nil))
    }

    func testNormalisedKeysCollapseCaseAndDiacritics() {
        XCTAssertEqual(
            AreaNameResolver.normalisedKey("Fitzroy"),
            AreaNameResolver.normalisedKey("fitzroy")
        )
        XCTAssertEqual(
            AreaNameResolver.normalisedKey("Montreal"),
            AreaNameResolver.normalisedKey("Montréal")
        )
    }

    func testThreeMelbourneSuburbsAreThreePlaces() {
        let addresses = [
            "10 Brunswick St, Fitzroy VIC 3065, Australia",
            "200 Sydney Rd, Brunswick VIC 3056, Australia",
            "100 Burke Rd, Camberwell VIC 3124, Australia"
        ]
        let keys = Set(addresses.compactMap {
            AreaNameResolver.fromFormattedAddress($0).map(AreaNameResolver.normalisedKey)
        })
        XCTAssertEqual(keys.count, 3)
    }
}
