import Foundation

enum ReportError: LocalizedError {
    case unsupportedFormat
    case invalidGeometry
    case reportTooLarge
    case noMeasurement
    case fileUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Formato de relatório incompatível."
        case .invalidGeometry: return "O relatório contém dimensões ou valores inválidos."
        case .reportTooLarge: return "O relatório ultrapassa 128 KiB."
        case .noMeasurement: return "O arquivo não tem uma coleta para importar."
        case .fileUnavailable: return "Escolha um arquivo JSON disponível em Arquivos."
        }
    }
}

enum ReportCodec {
    static let byteLimit = 128 * 1024

    static func read(from url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ReportError.fileUnavailable }
        if let length = values.fileSize, length > byteLimit {
            throw ReportError.reportTooLarge
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while let chunk = try file.read(upToCount: byteLimit + 1 - data.count), !chunk.isEmpty {
            data.append(chunk)
            if data.count > byteLimit { throw ReportError.reportTooLarge }
        }
        return data
    }

    static func encode(_ report: DisplayReport) throws -> Data {
        guard report.isValid else { throw ReportError.invalidGeometry }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        let data = try encoder.encode(report)
        guard data.count <= byteLimit else { throw ReportError.reportTooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> DisplayReport {
        let decoder = try makeDecoder(for: data)
        let report = try decoder.decode(DisplayReport.self, from: data)
        guard report.isValid else { throw ReportError.invalidGeometry }
        return report
    }

    static func reference(from data: Data) throws -> DisplayCapture {
        let decoder = try makeDecoder(for: data)
        let header = try decoder.decode(Header.self, from: data)
        let capture: DisplayCapture
        switch (header.format, header.schema) {
        case (DisplayReport.currentFormat, DisplayReport.currentSchema):
            let report = try decoder.decode(DisplayReport.self, from: data)
            guard report.isValid else { throw ReportError.invalidGeometry }
            guard let saved = report.latest ?? report.reference else { throw ReportError.noMeasurement }
            capture = saved
        case (nil, 2):
            capture = try decoder.decode(WorkPlotV2.self, from: data).capture
        default:
            throw ReportError.unsupportedFormat
        }
        guard capture.isValid else { throw ReportError.invalidGeometry }
        return capture
    }

    private static func makeDecoder(for data: Data) throws -> JSONDecoder {
        guard data.count <= byteLimit else { throw ReportError.reportTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Data ISO 8601 inválida.")
        }
        return decoder
    }

    private struct Header: Decodable {
        let format: String?
        let schema: Int
    }
}

struct ReportStore: Sendable {
    let url: URL

    func load() throws -> DisplayReport {
        guard FileManager.default.fileExists(atPath: url.path) else { return DisplayReport() }
        return try ReportCodec.decode(ReportCodec.read(from: url))
    }

    func save(_ report: DisplayReport) throws {
        let data = try ReportCodec.encode(report)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

private struct WorkPlotV2: Decodable {
    let sourceCommit: String?
    let geometry: Geometry
    let mobileGestalt: Gestalt?
    let preferenceObservations: [Preferences]?
    let protectedWritesPerformed: Bool?
    let writeAttempt: WriteAttempt?

    var capture: DisplayCapture {
        let preferences = preferenceObservations?.first { $0.domain == "com.apple.iokit.IOMobileGraphicsFamily" }
        let writeRecorded: Bool?
        if let protectedWritesPerformed, let writeAttempt {
            writeRecorded = protectedWritesPerformed || writeAttempt.performed
        } else if protectedWritesPerformed == true || writeAttempt?.performed == true {
            writeRecorded = true
        } else {
            writeRecorded = nil
        }
        return DisplayCapture(
            phase: .historical,
            capturedAt: geometry.timestamp,
            machine: geometry.machine,
            osVersion: nil,
            build: geometry.build,
            orientation: nil,
            appVersion: nil,
            sourceRevision: sourceCommit,
            geometry: ScreenGeometry(
                bounds: geometry.bounds,
                nativeBounds: geometry.nativeBounds,
                currentMode: geometry.currentMode,
                availableModes: geometry.availableModes ?? [],
                scale: geometry.scale,
                nativeScale: geometry.nativeScale,
                fixedCoordinateSpace: geometry.fixedCoordinateSpace,
                sceneBounds: nil
            ),
            historical: WorkPlotHistory(
                mobileGestalt: mobileGestalt?.canvas?.historicalField,
                preferenceDimensions: preferences?.dimensions,
                protectedWriteRecorded: writeRecorded
            )
        )
    }

    struct Geometry: Decodable {
        let timestamp: Date
        let machine: String
        let build: String?
        let bounds: DisplaySize
        let nativeBounds: DisplaySize
        let currentMode: DisplaySize?
        let availableModes: [DisplaySize]?
        let fixedCoordinateSpace: DisplaySize?
        let scale: Double
        let nativeScale: Double
    }

    struct Gestalt: Decodable {
        let canvas: Canvas?

        enum CodingKeys: String, CodingKey {
            case canvas = "MainScreenCanvasSizes"
        }
    }

    struct Canvas: Decodable {
        let present: Bool?
        let type: String?
        let bytes: Int?
        let hexPrefix: String?

        var historicalField: HistoricalCanvas? {
            guard present == true, type == "data", bytes == 16, let hex = hexPrefix, hex.utf8.count == 32 else {
                return nil
            }
            var octets: [UInt8] = []
            var index = hex.startIndex
            while index < hex.endIndex {
                guard let end = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex),
                      let value = UInt8(hex[index..<end], radix: 16) else { return nil }
                octets.append(value)
                index = end
            }
            guard octets.count == 16 else { return nil }
            let dimensions = DisplaySize(
                width: Self.littleEndianDouble(octets.prefix(8)),
                height: Self.littleEndianDouble(octets.suffix(8))
            )
            guard dimensions.isValid else { return nil }
            return HistoricalCanvas(dimensions: dimensions, byteCount: octets.count, hex: hex, type: "data")
        }

        private static func littleEndianDouble(_ octets: ArraySlice<UInt8>) -> Double {
            var bits: UInt64 = 0
            for (index, octet) in octets.enumerated() {
                bits |= UInt64(octet) << (index * 8)
            }
            return Double(bitPattern: bits)
        }
    }

    struct Preferences: Decodable {
        let domain: String
        let canvas_width: Preference?
        let canvas_height: Preference?

        var dimensions: DisplaySize? {
            guard let width = canvas_width?.number, let height = canvas_height?.number else { return nil }
            let size = DisplaySize(width: width, height: height)
            return size.isValid ? size : nil
        }
    }

    struct Preference: Decodable {
        let present: Bool?
        let value: String?

        var number: Double? {
            guard present == true, let value else { return nil }
            return Double(value)
        }
    }

    struct WriteAttempt: Decodable {
        let performed: Bool
    }
}
