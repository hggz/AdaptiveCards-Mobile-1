//
//  WindowsCardHostTests.swift
//  AdaptiveCardsCrossUITests — windows-port scaffold
//
//  Smoke tests for the empty Windows host placeholder. Future commits expand
//  this into a per-element rendering test suite (TextBlock, Image, FactSet,
//  Container, ActionSet, ...) that asserts the swift-cross-ui widget tree
//  shape for each Adaptive Card element.
//

import XCTest
@testable import AdaptiveCardsCrossUI

final class WindowsCardHostTests: XCTestCase {

    func testInitializerWithDefaultHostConfigCompiles() {
        let host = WindowsCardHost()
        XCTAssertEqual(host.hostConfigJSON, "{}")
    }

    func testInitializerWithCustomHostConfigStoresPayloadVerbatim() {
        let json = #"{"fontFamily":"Segoe UI"}"#
        let host = WindowsCardHost(hostConfigJSON: json)
        XCTAssertEqual(host.hostConfigJSON, json)
    }

    func testBackendIdentifierMatchesCurrentPlatform() {
        let id = WindowsCardHost.backendIdentifier
        #if os(Windows)
        XCTAssertEqual(id, "winui")
        #elseif os(Linux)
        XCTAssertEqual(id, "gtk")
        #elseif os(macOS)
        XCTAssertEqual(id, "appkit")
        #elseif os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)
        XCTAssertEqual(id, "uikit")
        #else
        XCTAssertEqual(id, "unknown")
        #endif
    }
}
