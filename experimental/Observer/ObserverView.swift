import SwiftUI
import UniformTypeIdentifiers

struct ObserverView: View {
    @StateObject private var store = ObserverStore()
    @State private var exporting = false
    @State private var exportMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Inventário do Core Animation")
                        .font(.title2.weight(.semibold))
                    Text("Leitura de CADisplay no processo observador")
                        .foregroundStyle(.secondary)
                    Text(store.message)
                    if store.isCollecting { ProgressView() }
                    Button("Coletar inventário") { store.collect() }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.hasAttempted)
                    Button("Exportar JSON") { exporting = true }
                        .buttonStyle(.bordered)
                        .disabled(store.reportData.isEmpty)
                    if let exportMessage { Text(exportMessage).foregroundStyle(.secondary) }
                    if !store.jsonText.isEmpty {
                        Text(store.jsonText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding(20)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("ResolutionLab Observer")
            .navigationBarTitleDisplayMode(.inline)
            .fileExporter(isPresented: $exporting,
                          document: ObserverDocument(data: store.reportData),
                          contentType: .json,
                          defaultFilename: "ResolutionLab-Observer") { result in
                switch result {
                case .success: exportMessage = "JSON exportado."
                case .failure(let error): exportMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct ObserverDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
