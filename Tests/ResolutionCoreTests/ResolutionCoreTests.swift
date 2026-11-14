import Foundation
import XCTest
@testable import ResolutionCore

final class ResolutionCoreTests: XCTestCase {
    private let native = DisplaySize(width: 828, height: 1792)
    private let alternate = DisplaySize(width: 1125, height: 2436)
    private let logical = DisplaySize(width: 414, height: 896)

    func testLegacyReferenceKeepsReportedModeAndHistoricalPreferenceDistinct() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "workplot-v2", withExtension: "json"))
        let capture = try ReportCodec.reference(from: Data(contentsOf: url))
        XCTAssertEqual(capture.phase, .historical)
        XCTAssertEqual(capture.geometry.currentMode, native)
        XCTAssertEqual(capture.historical?.mobileGestalt?.dimensions, alternate)
        XCTAssertEqual(capture.historical?.mobileGestalt?.byteCount, 16)
        XCTAssertEqual(capture.historical?.preferenceDimensions, native)
        XCTAssertEqual(capture.historical?.protectedWriteRecorded, false)

        let data = try ReportCodec.encode(DisplayReport(reference: capture))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("privateFieldForTest"))
    }

    func testMissingCurrentModeIsNotInferredFromNativeBounds() {
        let comparison = DisplayComparison(reference: makeCapture(mode: native), latest: makeCapture(mode: nil))
        XCTAssertEqual(comparison.outcome, .currentModeUnavailable)
        XCTAssertEqual(comparison.nativeBounds, .unchanged)
        XCTAssertEqual(comparison.currentMode, .unavailable)
    }

    func testRotationDoesNotReportModeChange() {
        let comparison = DisplayComparison(
            reference: makeCapture(mode: native),
            latest: makeCapture(
                mode: DisplaySize(width: 1792, height: 828),
                logical: DisplaySize(width: 896, height: 414),
                orientation: .landscape
            )
        )
        XCTAssertEqual(comparison.outcome, .unchanged)
        XCTAssertEqual(comparison.logicalBounds, .unchanged)
        XCTAssertEqual(comparison.orientation, .changed)
    }

    func testLayoutChangeIsReportedWithSameMode() {
        let comparison = DisplayComparison(
            reference: makeCapture(mode: native),
            latest: makeCapture(mode: native, logical: DisplaySize(width: 375, height: 812), scale: 2.2)
        )
        XCTAssertEqual(comparison.outcome, .otherGeometryChanged)
        XCTAssertEqual(comparison.currentMode, .unchanged)
        XCTAssertEqual(comparison.logicalBounds, .changed)
        XCTAssertEqual(comparison.scale, .changed)
    }

    func testReportedModeChangeWithIdenticalNativeBounds() {
        let comparison = DisplayComparison(reference: makeCapture(mode: native), latest: makeCapture(mode: alternate))
        XCTAssertEqual(comparison.outcome, .reportedModeChanged)
        XCTAssertEqual(comparison.nativeBounds, .unchanged)
    }

    func testDifferentOSBuildRemainsDistinct() {
        let comparison = DisplayComparison(
            reference: makeCapture(mode: native),
            latest: makeCapture(mode: alternate, build: "Fixture-B")
        )
        XCTAssertEqual(comparison.outcome, .differentEnvironment)
    }

    func testRoundTripRetainsBothColetasAndManualRestartStatus() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("relatorio.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ReportStore(url: url)
        XCTAssertEqual(try store.load(), DisplayReport())
        let reference = makeCapture(mode: native, phase: .beforeRestart)
        let latest = makeCapture(mode: native, phase: .afterReportedRestart)
        let report = DisplayReport(reference: reference, latest: latest)
        try store.save(report)
        XCTAssertEqual(try store.load(), report)
        XCTAssertEqual(try ReportCodec.reference(from: Data(contentsOf: url)).phase, .afterReportedRestart)
    }

    func testRejectsUnsupportedAndOversizedReports() {
        XCTAssertThrowsError(try ReportCodec.reference(from: Data("{\"schema\":99}".utf8)))
        XCTAssertThrowsError(try ReportCodec.reference(from: Data(count: ReportCodec.byteLimit + 1)))
    }

    private func makeCapture(
        mode: DisplaySize?,
        logical: DisplaySize? = nil,
        orientation: DisplayOrientation = .portrait,
        scale: Double = 2,
        build: String = "Fixture-A",
        phase: CapturePhase = .beforeRestart
    ) -> DisplayCapture {
        DisplayCapture(
            phase: phase,
            capturedAt: Date(timeIntervalSince1970: 1_767_268_800),
            machine: "iPhone12,1",
            osVersion: "27.0",
            build: build,
            orientation: orientation,
            appVersion: "0.1.0",
            sourceRevision: "synthetic",
            geometry: ScreenGeometry(
                bounds: logical ?? self.logical,
                nativeBounds: native,
                currentMode: mode,
                availableModes: [native],
                scale: scale,
                nativeScale: 2,
                fixedCoordinateSpace: self.logical,
                sceneBounds: nil
            ),
            historical: nil
        )
    }
}
