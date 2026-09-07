import SwiftUI
import UIKit
import Foundation
import CryptoKit
import Darwin

// Diagnostic addition only. The original access implementation is not edited.
// No protected-file writes, preference synchronization, respring or reboot calls.
private enum CanvasReadProbe {
    static let sourceCommit = "9756071f3cfa7a8902dbf1a4ee81beebc1210d0a"
    static let originalIPA = "8bf8401a184a0d329cbd7b9d06683619cd64b5832d47d3395420e53fc7718b41"
    static let names = ["com.apple.iokit.IOMobileGraphicsFamily.plist", "com.apple.iomobilegraphicsfamily.plist"]
    static let fixedDirectories = ["/var/Managed Preferences/mobile", "/var/mobile/Library/Preferences", "/var/preferences"]
    static let canvasKey = "ybGkijAwLTwevankfVzsDQ"

    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CanvasDiagnostics", isDirectory: true)
    }

    static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func systemString(_ name: String) -> String {
        var n = 0
        guard sysctlbyname(name, nil, &n, nil, 0) == 0, n > 0 else { return "unavailable" }
        var bytes = [CChar](repeating: 0, count: n)
        guard sysctlbyname(name, &bytes, &n, nil, 0) == 0 else { return "unavailable" }
        return String(cString: bytes)
    }

    static func geometry() -> [String: Any] {
        precondition(Thread.isMainThread)
        let s = UIScreen.main
        func size(_ v: CGSize) -> [String: Double] { ["width": Double(v.width), "height": Double(v.height)] }
        var t = timeval(); var n = MemoryLayout<timeval>.size
        let bootOK = sysctlbyname("kern.boottime", &t, &n, nil, 0) == 0
        var out: [String: Any] = ["timestamp": ISO8601DateFormatter().string(from: Date()),
            "build": systemString("kern.osversion"), "machine": systemString("hw.machine"),
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "missing", "bounds": size(s.bounds.size),
            "fixedCoordinateSpace": size(s.fixedCoordinateSpace.bounds.size), "nativeBounds": size(s.nativeBounds.size),
            "scale": Double(s.scale), "nativeScale": Double(s.nativeScale),
            "availableModes": s.availableModes.map { size($0.size) },
            "systemUptime": ProcessInfo.processInfo.systemUptime,
            "measurementScope": "UIKit in this process; not proof of the global compositor configuration"]
        if let mode = s.currentMode { out["currentMode"] = size(mode.size) }
        if bootOK { out["bootSeconds"] = Int64(t.tv_sec); out["bootMicroseconds"] = Int32(t.tv_usec) }
        return out
    }

    static func typed(_ value: Any?) -> [String: Any] {
        guard let value = value else { return ["present": false] }
        if let data = value as? Data {
            var result: [String: Any] = ["present": true, "type": "data", "bytes": data.count,
                "hexPrefix": data.prefix(256).map { String(format: "%02x", $0) }.joined()]
            if data.count >= 16 && data.count % 16 == 0 {
                let bytes = Array(data.prefix(256)); var values: [String] = []
                for offset in stride(from: 0, through: bytes.count - 8, by: 8) {
                    var bits: UInt64 = 0
                    for i in 0..<8 { bits |= UInt64(bytes[offset + i]) << (8 * i) }
                    values.append(String(Double(bitPattern: bits)))
                }
                result["littleEndianDoubleInterpretation"] = values
            }
            return result
        }
        if let n = value as? NSNumber {
            return ["present": true, "type": "NSNumber", "objCType": String(cString: n.objCType), "value": n.stringValue]
        }
        if let list = value as? [Any] { return ["present": true, "type": "array", "values": list.prefix(32).map { typed($0) }] }
        return ["present": true, "type": String(describing: type(of: value)), "value": String(describing: value).prefix(512).description]
    }

    static func error(_ code: Int32) -> [String: Any] { ["errno": code, "message": String(cString: strerror(code))] }

    static func inspect(_ path: String, backupRoot: URL) -> [String: Any] {
        var out: [String: Any] = ["path": path]
        var st = stat()
        if lstat(path, &st) == 0 {
            out["lstat"] = ["exists": true, "mode": String(st.st_mode, radix: 8), "uid": st.st_uid,
                            "gid": st.st_gid, "bytes": st.st_size, "inode": st.st_ino]
        } else { out["lstat"] = error(errno) }
        // O_RDWR checks opening permission only. It performs no write or truncate.
        let writable = open(path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        if writable >= 0 { close(writable); out["openReadWrite"] = ["success": true, "actualWritePerformed": false] }
        else { var e = error(errno); e["success"] = false; e["actualWritePerformed"] = false; out["openReadWrite"] = e }
        let fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { out["read"] = error(errno); return out }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0 else { out["read"] = error(errno); return out }
        guard (opened.st_mode & S_IFMT) == S_IFREG, opened.st_size <= 4 * 1024 * 1024 else {
            out["read"] = ["skipped": "not a regular file or exceeds 4 MiB"]; return out
        }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 65536)
        while data.count <= 4 * 1024 * 1024 {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                out["read"] = error(errno); return out
            }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count <= 4 * 1024 * 1024 else { out["read"] = ["skipped": "grew beyond size limit"]; return out }
        out["read"] = ["success": true, "bytes": data.count, "sha256": sha(data)]
        do {
            var format = PropertyListSerialization.PropertyListFormat.binary
            let decoded = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
            guard let plist = decoded as? [String: Any] else { out["plist"] = ["error": "not dictionary"]; return out }
            out["plist"] = ["format": format == .binary ? "binary" : "xml/other",
                "canvas_width": typed(plist["canvas_width"]), "canvas_height": typed(plist["canvas_height"]),
                "topLevelKeys": Array(plist.keys).sorted()]
            // Snapshot only the graphics plist, not MobileGestalt or unrelated private data.
            try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
            let name = sha(Data(path.utf8)) + ".plist"
            let destination = backupRoot.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try data.write(to: destination, options: .atomic)
            }
            out["localSnapshot"] = ["filename": name, "sha256": sha(try Data(contentsOf: destination)),
                                    "meaning": "observed state, not asserted factory stock"]
        } catch { out["plistOrSnapshotError"] = error.localizedDescription }
        return out
    }

    static func target(_ path: String, backupRoot: URL) -> [String: Any] {
        let aliases = [path, "/private" + path]
        var out: [String: Any] = ["leasePath": path, "beforeLease": aliases.map { inspect($0, backupRoot: backupRoot) }]
        do {
            out["withOriginalLease"] = try BadQueryLeaseScope.withLease(forPath: path) {
                aliases.map { inspect($0, backupRoot: backupRoot) }
            }
            out["leaseAcquired"] = true
        } catch { out["leaseAcquired"] = false; out["leaseError"] = error.localizedDescription }
        return out
    }

    static func directories() -> ([String], [String: Any]) {
        let path = "/var/containers/Data/System"
        var cPath = path.utf8CString
        let raw = cPath.withUnsafeMutableBufferPointer { bad_query_list($0.baseAddress, 2_000_000) }
        guard let raw = raw else { return ([], ["path": path, "result": "nil: absence and denial not distinguished by original listing API"]) }
        defer { free(raw) }
        let all = String(cString: raw).split(whereSeparator: \.isNewline).map(String.init)
        let accepted = all.filter { item in
            guard item.hasPrefix(path + "/") else { return false }
            return UUID(uuidString: (item as NSString).lastPathComponent) != nil
        }
        return (Array(accepted.prefix(64)), ["path": path, "returnedCount": all.count,
            "acceptedUUIDCount": accepted.count, "limit": 64, "truncated": accepted.count > 64])
    }

    static func preferenceObservations() -> [[String: Any]] {
        ["com.apple.iokit.IOMobileGraphicsFamily", "com.apple.iomobilegraphicsfamily"].map { domain in
            ["domain": domain, "scope": "CFPreferences current user / any host as visible to this process; no synchronize",
             "canvas_width": typed(CFPreferencesCopyValue("canvas_width" as CFString, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)),
             "canvas_height": typed(CFPreferencesCopyValue("canvas_height" as CFString, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost))]
        }
    }

    static func collect(geometry: [String: Any], access: [String: Any], extended: Bool, progress: @escaping (String, URL) -> Void) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let session = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: session, withIntermediateDirectories: true)
        let log = session.appendingPathComponent("canvas-report.json")
        let baselineURL = root.appendingPathComponent("baseline.json")
        var report: [String: Any] = ["schema": 2, "diagnosticVersion": "2", "sourceCommit": sourceCommit,
            "referenceIPA_SHA256": originalIPA, "geometry": geometry, "originalAccessState": access,
            "target": ["width": 1125, "height": 2436], "protectedWritesPerformed": false,
            "actualGraphicsConsumer": "NOT_YET_PROVEN", "status": "running",
            "writeAttempt": ["performed": false, "valuesWritten": "not attempted",
                "postWriteReadback": "not applicable: read-only diagnostic",
                "restore": "not exposed: no resolution change in this diagnostic"]]
        func persist() throws {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: log, options: .atomic)
        }
        try persist()
        func stage(_ message: String) throws {
            report["activeProbe"] = message
            try persist()
            progress(message, log)
        }
        try stage("Lendo MobileGestalt pelo acesso original…")
        do {
            let maybeData: Data? = try GestaltAccess.shared().readGestaltData()
            guard let data = maybeData else {
                throw NSError(domain: "CanvasDiagnostic", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "MobileGestalt retornou nil"])
            }
            guard let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                throw NSError(domain: "CanvasDiagnostic", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "MobileGestalt não contém um dicionário plist"])
            }
            let extra = object["CacheExtra"] as? [String: Any]
            report["mobileGestalt"] = ["readSuccess": true, "fullFileBytes": data.count, "fullFileSHA256": sha(data),
                "MainScreenCanvasSizes": typed(extra?[canvasKey]),
                "exportScope": "canvas key only; full MobileGestalt bytes are not exported"]
        } catch { report["mobileGestalt"] = ["readSuccess": false, "error": error.localizedDescription] }
        report["preferenceObservations"] = preferenceObservations()
        try persist()
        var findings: [[String: Any]] = []
        for dir in fixedDirectories {
            for name in names {
                let path = dir + "/" + name
                try stage("Verificando \(path)")
                findings.append(target(path, backupRoot: session.appendingPathComponent("snapshots")))
                report["graphicsCandidates"] = findings; try persist()
            }
        }
        if extended {
        try stage("Listando containers do sistema (varredura ampliada)…")
        let (containers, listing) = directories()
        report["systemContainerDiscovery"] = listing; try persist()
        for (index, container) in containers.enumerated() {
            try stage("Verificando container \(index + 1) de \(containers.count)…")
            for name in names {
                findings.append(target(container + "/Library/Preferences/" + name,
                    backupRoot: session.appendingPathComponent("snapshots")))
            }
            report["graphicsCandidates"] = findings; try persist()
        }
        } else { report["systemContainerDiscovery"] = ["skipped": "extended scan not selected"] }
        if fm.fileExists(atPath: baselineURL.path) {
            do {
                let baseline = try JSONSerialization.jsonObject(with: Data(contentsOf: baselineURL)) as? [String: Any]
                report["baseline"] = baseline
                let old = baseline?["geometry"] as? [String: Any]
                let comparable = ["machine", "build", "bundleIdentifier"].allSatisfy {
                    (old?[$0] as? String) == (geometry[$0] as? String)
                }
                report["baselineComparable"] = comparable
                if comparable, let before = old?["bootSeconds"] as? NSNumber, let after = geometry["bootSeconds"] as? NSNumber {
                    let sameBoot = before == after && (old?["bootMicroseconds"] as? NSNumber) == (geometry["bootMicroseconds"] as? NSNumber)
                    report["bootComparison"] = sameBoot ? "same marker; no full reboot established" : "boot marker changed; verify full reboot procedure"
                } else { report["bootComparison"] = "boot marker unavailable" }
                if comparable, let oldNative = old?["nativeBounds"] as? NSDictionary, let newNative = geometry["nativeBounds"] as? NSDictionary {
                    report["nativeBoundsChanged"] = !oldNative.isEqual(newNative)
                }
            } catch { report["baselineError"] = error.localizedDescription }
        } else {
            // Store only one initial completed read-only collection as reference.
            let baseline: [String: Any] = ["geometry": geometry, "graphicsCandidates": findings,
                "mobileGestalt": report["mobileGestalt"] ?? [:], "note": "observed current state, not factory stock"]
            try JSONSerialization.data(withJSONObject: baseline, options: [.prettyPrinted, .sortedKeys]).write(to: baselineURL, options: .atomic)
            report["baselineCreated"] = true
        }
        report["status"] = "completed"
        report["activeProbe"] = "none"
        report["finishedAt"] = ISO8601DateFormatter().string(from: Date())
        try persist()
        return log
    }
}

struct CanvasInvestigationView: View {
    @ObservedObject private var manager = ExploitManager.shared
    @State private var busy = false
    @State private var status = "Aguarde o acesso automático e toque em Coletar diagnóstico."
    @State private var report: URL?
    @State private var showShare = false
    @State private var dimensions = ""
    @State private var extended = false
    @State private var logPreview = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("WorkPlot(3) • diagnóstico 2")) {
                    Text("Acesso: \(manager.sandboxGranted ? "Unlocked" : "Locked")")
                    Text("Método: \(manager.exploitMethod)")
                    Text("Build: \(manager.osBuild)")
                    Text(dimensions)
                    Text("Fonte original confirmado pelo IPA idêntico. Este diagnóstico não grava configurações de resolução.").font(.footnote)
                }
                Section(header: Text("Coleta")) {
                    Toggle("Incluir varredura ampliada de containers", isOn: $extended).disabled(busy)
                    Button(busy ? "Coletando…" : "Coletar diagnóstico") { start() }.disabled(busy)
                    Text(status).font(.footnote)
                    Button("Exportar JSON") { showShare = true }.disabled(report == nil)
                    Text("Faça uma coleta agora e outra após desligar e ligar o iPhone. Envie os dois JSONs e as capturas originais da tela.").font(.footnote)
                }
                Section(header: Text("Log visível / coleta parcial")) {
                    Text(logPreview.isEmpty ? "Nenhuma coleta." : logPreview)
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                Section(header: Text("Resultado")) {
                    Text("Abrir um arquivo com permissão de escrita não comprova uma gravação nem identifica o consumidor gráfico. O JSON distingue essas etapas.").font(.footnote)
                    Text("Não há botão Apply nesta rodada. O objetivo é localizar e observar o destino sem repetir alterações que não funcionaram.").font(.footnote)
                }
            }
            .navigationTitle("Canvas diagnóstico")
            .onAppear {
                let s = UIScreen.main
                dimensions = "Native bounds: \(Int(s.nativeBounds.width)) × \(Int(s.nativeBounds.height))"
                if let enumerator = FileManager.default.enumerator(at: CanvasReadProbe.root, includingPropertiesForKeys: [.contentModificationDateKey]) {
                    let logs = enumerator.compactMap { $0 as? URL }.filter { $0.lastPathComponent == "canvas-report.json" }
                    report = logs.sorted {
                        let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        return a > b
                    }.first
                    refreshLog()
                }
            }
            .sheet(isPresented: $showShare) { if let report = report { CanvasReportShare(url: report) } }
        }
    }

    private func refreshLog() {
        if let report = report, let text = try? String(contentsOf: report, encoding: .utf8) {
            logPreview = String(text.prefix(180_000))
        }
    }

    private func start() {
        guard !busy else { return }
        busy = true
        let geometry = CanvasReadProbe.geometry()
        let access: [String: Any] = ["unlocked": manager.sandboxGranted, "method": manager.exploitMethod,
                                     "statusText": manager.statusText]
        let includeContainers = extended
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try CanvasReadProbe.collect(geometry: geometry, access: access, extended: includeContainers) { text, partialURL in
                    DispatchQueue.main.async { status = text; report = partialURL; refreshLog() }
                }
                DispatchQueue.main.async { report = url; refreshLog(); busy = false; status = "Coleta concluída. Exporte o JSON." }
            } catch { DispatchQueue.main.async { busy = false; refreshLog(); status = "Falha: \(error.localizedDescription)" } }
        }
    }
}

private struct CanvasReportShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
