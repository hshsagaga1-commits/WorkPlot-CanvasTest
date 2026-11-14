import Foundation

struct DisplaySize: Codable, Hashable, Sendable {
    let width: Double
    let height: Double

    var isValid: Bool {
        width.isFinite && height.isFinite && (0.01...65_536).contains(width) && (0.01...65_536).contains(height)
    }

    var normalized: Self {
        Self(width: min(width, height), height: max(width, height))
    }
}

enum DisplayOrientation: String, Codable, Sendable {
    case portrait
    case landscape
}

enum CapturePhase: String, Codable, Sendable {
    case beforeRestart
    case afterReportedRestart
    case historical
}

struct ScreenGeometry: Codable, Equatable, Sendable {
    let bounds: DisplaySize
    let nativeBounds: DisplaySize
    let currentMode: DisplaySize?
    let availableModes: [DisplaySize]
    let scale: Double
    let nativeScale: Double
    let fixedCoordinateSpace: DisplaySize?
    let sceneBounds: DisplaySize?

    var isValid: Bool {
        bounds.isValid && nativeBounds.isValid && currentMode?.isValid != false
            && fixedCoordinateSpace?.isValid != false && sceneBounds?.isValid != false
            && availableModes.count <= 64 && availableModes.allSatisfy(\.isValid)
            && (0.05...16).contains(scale) && (0.05...16).contains(nativeScale)
    }
}

struct HistoricalCanvas: Codable, Equatable, Sendable {
    let dimensions: DisplaySize
    let byteCount: Int
    let hex: String
    let type: String
}

struct WorkPlotHistory: Codable, Equatable, Sendable {
    let mobileGestalt: HistoricalCanvas?
    let preferenceDimensions: DisplaySize?
    let protectedWriteRecorded: Bool?
}

struct DisplayCapture: Codable, Equatable, Sendable {
    let phase: CapturePhase
    let capturedAt: Date
    let machine: String
    let osVersion: String?
    let build: String?
    let orientation: DisplayOrientation?
    let appVersion: String?
    let sourceRevision: String?
    let geometry: ScreenGeometry
    let historical: WorkPlotHistory?

    var isValid: Bool {
        !machine.isEmpty && machine.utf8.count <= 64 && geometry.isValid
    }
}

struct DisplayReport: Codable, Equatable, Sendable {
    static let currentFormat = "resolutionlab.display-report"
    static let currentSchema = 1
    static let scope = "UIKit da cena do processo"

    let format: String
    let schema: Int
    let status: String
    let measurementScope: String
    var reference: DisplayCapture?
    var latest: DisplayCapture?

    init(reference: DisplayCapture? = nil, latest: DisplayCapture? = nil) {
        format = Self.currentFormat
        schema = Self.currentSchema
        status = "READ_ONLY"
        measurementScope = Self.scope
        self.reference = reference
        self.latest = latest
    }

    var isValid: Bool {
        format == Self.currentFormat && schema == Self.currentSchema
            && status == "READ_ONLY" && measurementScope == Self.scope
            && reference?.isValid != false && latest?.isValid != false
    }
}

struct DisplayComparison: Sendable {
    enum Change: String, Sendable {
        case unchanged = "Igual"
        case changed = "Diferente"
        case unavailable = "Indisponível"
    }

    enum Outcome: String, Sendable {
        case unchanged = "Mesma geometria medida no UIKit"
        case reportedModeChanged = "O modo reportado pelo UIKit mudou"
        case otherGeometryChanged = "O modo ficou igual e outra métrica mudou"
        case currentModeUnavailable = "O modo ficou indisponível em uma das coletas"
        case differentEnvironment = "Modelo ou build diferente"
    }

    let outcome: Outcome
    let nativeBounds: Change
    let currentMode: Change
    let availableModes: Change
    let logicalBounds: Change
    let scale: Change
    let nativeScale: Change
    let orientation: Change
    let build: Change

    init(reference: DisplayCapture, latest: DisplayCapture) {
        let before = reference.geometry
        let after = latest.geometry
        nativeBounds = Self.compare(before.nativeBounds.normalized, after.nativeBounds.normalized)
        currentMode = Self.compare(before.currentMode?.normalized, after.currentMode?.normalized)
        availableModes = Self.compare(
            before.availableModes.isEmpty ? nil : Set(before.availableModes.map(\.normalized)),
            after.availableModes.isEmpty ? nil : Set(after.availableModes.map(\.normalized))
        )
        logicalBounds = Self.compare(before.bounds.normalized, after.bounds.normalized)
        scale = Self.compare(before.scale, after.scale)
        nativeScale = Self.compare(before.nativeScale, after.nativeScale)
        orientation = Self.compare(reference.orientation, latest.orientation)
        build = Self.compare(reference.build, latest.build)

        if reference.machine != latest.machine || build == .changed {
            outcome = .differentEnvironment
        } else if currentMode == .unavailable {
            outcome = .currentModeUnavailable
        } else if currentMode == .changed {
            outcome = .reportedModeChanged
        } else if [nativeBounds, availableModes, logicalBounds, scale, nativeScale].contains(.changed) {
            outcome = .otherGeometryChanged
        } else {
            outcome = .unchanged
        }
    }

    private static func compare<Value: Equatable>(_ reference: Value?, _ latest: Value?) -> Change {
        guard let reference, let latest else { return .unavailable }
        return reference == latest ? .unchanged : .changed
    }
}
