//
//  CoverageSweep2Tests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI
import Testing
@testable import Thaw

/// Coverage sweep, part 2: the small presentation-facing value types whose
/// existing suites stopped at raw values and `Codable`.
///
/// Covers:
///
/// - `IceBarLayout` — `id`, `localized`, and the string parser's rejection
///   path. The parser accepts both case names and stringified raw values
///   because it backs the `thaw://` settings URI, so an accepted alias set
///   is part of that public surface.
/// - `IceBarLocation.localized` (`IceBarLocationTests` covers everything
///   else about the type).
/// - `ControlItemImageSet.id`, which is `hashValue` rather than the name —
///   worth pinning because a `List` selection keyed on it must survive two
///   equal sets colliding.
/// - `NavigationIdentifier`'s *default* `localized`. No shipping conformer
///   reaches it — the one that overrode it went with the settings sidebar —
///   so it is exercised through a test-local conformer.
///
/// Deliberate gaps: `IceBarLocation.iceIcon`'s label interpolates
/// `Constants.displayName`, so it is asserted to be distinct from its
/// siblings rather than compared against a rebuilt literal — reconstructing
/// the interpolation in the test would only restate the implementation.
@MainActor
@Suite("Coverage sweep 2: bar, divider and navigation display values")
struct CoverageSweep2Tests {
    // MARK: - IceBarLayout

    @MainActor
    @Suite("IceBarLayout")
    struct BarLayoutTests {
        @Test("Every layout's identifier is its raw value")
        func idMatchesRawValue() {
            for layout in IceBarLayout.allCases {
                #expect(layout.id == layout.rawValue)
            }
        }

        @Test("Every layout has its own label")
        func localizedLabels() {
            #expect(IceBarLayout.horizontal.localized == "水平")
            #expect(IceBarLayout.vertical.localized == "垂直")
            #expect(IceBarLayout.grid.localized == "グリッド")
        }

        @Test("No two layouts share a label")
        func localizedLabelsAreDistinct() {
            let labels = IceBarLayout.allCases.map(\.localized)
            #expect(Set(labels).count == labels.count)
        }

        /// `fromString` backs `thaw://set?key=iceBarLayout&value=…`, so both
        /// spellings are an external contract.
        @Test(
            "Both the case name and the raw value parse to the same layout",
            arguments: zip(["horizontal", "vertical", "grid"], [IceBarLayout.horizontal, .vertical, .grid])
        )
        func fromStringAcceptsNameAndRawValue(_ name: String, _ expected: IceBarLayout) {
            #expect(IceBarLayout.fromString(name) == expected)
            #expect(IceBarLayout.fromString(String(expected.rawValue)) == expected)
        }

        @Test(
            "An unknown spelling is rejected rather than defaulted",
            arguments: ["", "Horizontal", "HORIZONTAL", "3", "-1", "column", " grid"]
        )
        func fromStringRejectsUnknownSpellings(_ candidate: String) {
            #expect(IceBarLayout.fromString(candidate) == nil)
        }
    }

    // MARK: - IceBarLocation

    @MainActor
    @Suite("IceBarLocation labels")
    struct BarLocationTests {
        @Test("The fixed labels are the documented ones")
        func localizedLabels() {
            #expect(IceBarLocation.dynamic.localized == "ダイナミック")
            #expect(IceBarLocation.mousePointer.localized == "マウスポインター")
            #expect(IceBarLocation.leftAligned.localized == "左揃え")
            #expect(IceBarLocation.rightAligned.localized == "右揃え")
        }

        @Test("No two locations share a label")
        func localizedLabelsAreDistinct() {
            let labels = IceBarLocation.allCases.map(\.localized)
            #expect(Set(labels).count == labels.count)
        }
    }

    // MARK: - ControlItemImageSet

    @MainActor
    @Suite("ControlItemImageSet identity")
    struct ImageSetTests {
        @Test("The identifier is the hash of the whole set, not just its name")
        func idIsTheHashValue() {
            let set = ControlItemImageSet.defaultIceIcon
            #expect(set.id == set.hashValue)
        }

        @Test("Two sets that differ only in their images get different identifiers")
        func differingImagesGetDifferentIdentifiers() {
            let first = ControlItemImageSet(name: .dot, image: .catalog("DotFill"))
            let second = ControlItemImageSet(name: .dot, image: .catalog("DotStroke"))
            #expect(first.id != second.id)
        }

        @Test("Two identical sets share an identifier")
        func identicalSetsShareAnIdentifier() {
            let first = ControlItemImageSet(name: .dot, image: .catalog("DotFill"))
            let second = ControlItemImageSet(name: .dot, hidden: .catalog("DotFill"), visible: .catalog("DotFill"))
            #expect(first == second)
            #expect(first.id == second.id)
        }
    }

    // MARK: - NavigationIdentifier

    @MainActor
    @Suite("NavigationIdentifier default label")
    struct NavigationIdentifierTests {
        /// The protocol's `RawValue == String` default has no shipping
        /// caller left, so it is only reachable through a conformer declared
        /// here. This exists to prove it keeps working for the next one.
        @Test("A String-raw conformer labels itself with its raw value")
        func defaultLocalizedUsesTheRawValue() {
            #expect(SweepNavigationIdentifier.first.localized == "First Destination")
            #expect(SweepNavigationIdentifier.second.localized == "Second Destination")
        }
    }
}

// MARK: - Test-local NavigationIdentifier conformer

/// A conformer that deliberately does **not** override `localized`, so the
/// protocol extension's `RawValue == String` default is what runs.
private enum SweepNavigationIdentifier: String, NavigationIdentifier {
    typealias ID = Int

    case first = "First Destination"
    case second = "Second Destination"

    var iconResource: IconResource {
        .systemSymbol("gearshape")
    }
}
