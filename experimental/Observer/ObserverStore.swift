import Combine
import Foundation

@MainActor
final class ObserverStore: ObservableObject {
    @Published private(set) var hasAttempted = false
    @Published private(set) var isCollecting = false
    @Published private(set) var message = "Colete o inventário de leitura do Core Animation."
    @Published private(set) var jsonText = ""
    @Published private(set) var reportData = Data()

    private var envelope: [String: Any] = [:]
    private var requestID: UUID?

    func collect() {
        guard !hasAttempted else { return }
        do {
            let sample = try ScreenSampler.capture(phase: .beforeRestart)
            let baseline = try ReportCodec.encode(DisplayReport(reference: sample))
            envelope = [
                "format": "resolutionlab.core-animation-observer",
                "schema": 1,
                "status": "READ_ONLY",
                "scope": "CADisplay getters from observer process; global consumer unverified",
                "uiKitReport": try JSONSerialization.jsonObject(with: baseline),
                "coreAnimationInventory": ["status": "pending"],
                "restartEvidence": "not_collected"
            ]
            hasAttempted = true
            isCollecting = true
            let identifier = UUID()
            requestID = identifier
            publish()
            message = "Lendo os getters disponíveis…"

            DispatchQueue.global(qos: .utility).async {
                let inventory = RLReadCADisplayInventory()
                let encoded = try? JSONSerialization.data(withJSONObject: inventory, options: [.sortedKeys])
                DispatchQueue.main.async {
                    self.finish(identifier: identifier, data: encoded)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                guard self.requestID == identifier else { return }
                self.requestID = nil
                self.isCollecting = false
                self.envelope["coreAnimationInventory"] = ["status": "observer_wait_timed_out"]
                self.message = "A espera terminou. O JSON parcial está disponível."
                self.publish()
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func finish(identifier: UUID, data: Data?) {
        guard requestID == identifier else { return }
        requestID = nil
        isCollecting = false
        if let data, let inventory = try? JSONSerialization.jsonObject(with: data) {
            envelope["coreAnimationInventory"] = inventory
            let state = (inventory as? [String: Any])?["status"] as? String ?? "unknown"
            message = "Estado do inventário — \(state)"
        } else {
            envelope["coreAnimationInventory"] = ["status": "serialization_failed"]
            message = "A coleta retornou sem um inventário serializável."
        }
        publish()
    }

    private func publish() {
        do {
            let data = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
            reportData = data
            jsonText = String(decoding: data, as: UTF8.self)
        } catch {
            message = "Falha ao serializar o relatório."
        }
    }
}
