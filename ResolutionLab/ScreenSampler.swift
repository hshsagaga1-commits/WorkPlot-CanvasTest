import Darwin
import UIKit

enum SampleError: LocalizedError {
    case sceneUnavailable
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .sceneUnavailable: return "Abra o ResolutionLab em primeiro plano para coletar a tela."
        case .modelUnavailable: return "O iOS não informou o identificador do modelo."
        }
    }
}

@MainActor
enum ScreenSampler {
    static func capture(phase: CapturePhase) throws -> DisplayCapture {
        let front = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        guard let scene = front.first(where: { $0.windows.contains(where: \.isKeyWindow) }) ?? front.first else {
            throw SampleError.sceneUnavailable
        }
        guard let machine = machineIdentifier() else { throw SampleError.modelUnavailable }

        let screen = scene.screen
        let orientation: UIInterfaceOrientation
        if #available(iOS 26.0, *) {
            orientation = scene.effectiveGeometry.interfaceOrientation
        } else {
            orientation = scene.interfaceOrientation
        }
        let capture = DisplayCapture(
            phase: phase,
            capturedAt: Date(),
            machine: machine,
            osVersion: UIDevice.current.systemVersion,
            build: osBuild(),
            orientation: orientation.isPortrait ? .portrait : (orientation.isLandscape ? .landscape : nil),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            sourceRevision: Bundle.main.object(forInfoDictionaryKey: "RLSourceCommit") as? String,
            geometry: ScreenGeometry(
                bounds: size(screen.bounds.size),
                nativeBounds: size(screen.nativeBounds.size),
                currentMode: screen.currentMode.map { size($0.size) },
                availableModes: screen.availableModes.map { size($0.size) },
                scale: Double(screen.scale),
                nativeScale: Double(screen.nativeScale),
                fixedCoordinateSpace: size(screen.fixedCoordinateSpace.bounds.size),
                sceneBounds: scene.windows.first(where: \.isKeyWindow).map { size($0.bounds.size) }
            ),
            historical: nil
        )
        guard capture.isValid else { throw ReportError.invalidGeometry }
        return capture
    }

    private static func size(_ value: CGSize) -> DisplaySize {
        DisplaySize(width: Double(value.width), height: Double(value.height))
    }

    private static func machineIdentifier() -> String? {
        var info = utsname()
        guard uname(&info) == 0 else { return nil }
        return withUnsafeBytes(of: &info.machine) {
            let value = String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
            return value.isEmpty ? nil : value
        }
    }

    private static func osBuild() -> String? {
        var count = 0
        guard sysctlbyname("kern.osversion", nil, &count, nil, 0) == 0, (2...128).contains(count) else {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: count)
        let result = bytes.withUnsafeMutableBytes {
            sysctlbyname("kern.osversion", $0.baseAddress, &count, nil, 0)
        }
        guard result == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
