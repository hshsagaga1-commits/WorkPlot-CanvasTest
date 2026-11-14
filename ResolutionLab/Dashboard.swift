import SwiftUI
import UniformTypeIdentifiers

struct Dashboard: View {
    @State private var report = DisplayReport()
    @State private var selectingAfter = false
    @State private var declaredRestart = false
    @State private var isImportPresented = false
    @State private var isReading = false
    @State private var isExportPresented = false
    @State private var exportFile: ReportFile?
    @State private var presentedSheet: PresentedSheet?
    @State private var error: String?
    @State private var didLoad = false
    @State private var feedback: String?

    private let store = ReportStore(
        url: URL.applicationSupportDirectory
            .appendingPathComponent("ResolutionLab", isDirectory: true)
            .appendingPathComponent("display-report.json")
    )

    private enum PresentedSheet: String, Identifiable {
        case comparison
        case logs
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let capture = report.latest ?? report.reference {
                        captureCard(capture)
                    } else {
                        card {
                            Label("Coleta de tela", systemImage: "display")
                                .font(.title2.weight(.semibold))
                            Text("Salve uma referência antes de reiniciar o iPhone.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    captureControls
                    reportControls
                    if let feedback {
                        Text(feedback)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .padding(16)
                .frame(maxWidth: 580)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("ResolutionLab")
            .navigationBarTitleDisplayMode(.inline)
            .task { restore() }
            .sheet(item: $presentedSheet) { sheet in sheetView(sheet) }
            .fileImporter(isPresented: $isImportPresented, allowedContentTypes: [.json]) { result in
                importReference(result)
            }
            .fileExporter(
                isPresented: $isExportPresented,
                document: exportFile,
                contentType: .json,
                defaultFilename: report.latest == nil ? "ResolutionLab-antes" : "ResolutionLab-depois"
            ) { result in
                switch result {
                case .success: feedback = "JSON exportado."
                case .failure(let failure): error = failure.localizedDescription
                }
            }
            .alert("ResolutionLab", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private var captureControls: some View {
        card {
            Picker("Etapa da coleta", selection: $selectingAfter) {
                Text("Antes").tag(false)
                Text("Depois").tag(true)
            }
            .pickerStyle(.segmented)

            if selectingAfter {
                Toggle("Desliguei e liguei o iPhone", isOn: $declaredRestart)
                Text("Use a mesma orientação e o mesmo Zoom da Tela da referência.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if report.reference != nil {
                Text("Uma nova coleta inicial substitui o par salvo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(action: collect) {
                Label("Coletar", systemImage: "viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!didLoad || isReading || (selectingAfter && (report.reference == nil || !declaredRestart)))
        }
    }

    private var reportControls: some View {
        card {
            if let reference = report.reference {
                LabeledContent("Referência", value: reference.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
            }

            Button { presentedSheet = .comparison } label: {
                Label("Comparar", systemImage: "rectangle.on.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            }
            .disabled(report.reference == nil || report.latest == nil)

            Button(action: exportReport) {
                Label("Exportar JSON", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            }
            .disabled(report.reference == nil)

            Button { presentedSheet = .logs } label: {
                Label("Ver logs", systemImage: "doc.text")
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            }
            .disabled(report.reference == nil)

            Button { isImportPresented = true } label: {
                Label(isReading ? "Lendo JSON…" : "Importar referência", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            }
            .disabled(!didLoad || isReading)
        }
        .buttonStyle(.bordered)
    }

    private func captureCard(_ capture: DisplayCapture) -> some View {
        card {
            Text(capture.phase == .historical ? "Referência do WorkPlot" : "Modo de tela reportado pelo UIKit")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(pixels(capture.geometry.currentMode))
                .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityAddTraits(.isHeader)
            LabeledContent("Modelo", value: capture.machine)
            LabeledContent("iOS", value: capture.osVersion ?? "Indisponível")
            LabeledContent("Build", value: capture.build ?? "Indisponível")
            Divider()
            LabeledContent("Pixels nativos", value: pixels(capture.geometry.nativeBounds))
            LabeledContent("Área lógica", value: points(capture.geometry.bounds))
            LabeledContent("Escalas UIKit e nativa", value: scales(capture.geometry))
            Text("Leitura da tela da cena do app")
                .foregroundStyle(.secondary)
                .font(.footnote)
        }
        .font(.subheadline)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func sheetView(_ sheet: PresentedSheet) -> some View {
        NavigationStack {
            List {
                switch sheet {
                case .comparison:
                    if let reference = report.reference, let latest = report.latest {
                        comparisonRows(reference: reference, latest: latest)
                    }
                case .logs:
                    if let reference = report.reference {
                        logRows(capture: reference, title: "Referência")
                    }
                    if let latest = report.latest {
                        logRows(capture: latest, title: "Depois")
                    }
                }
            }
            .navigationTitle(sheet == .comparison ? "Comparar" : "Logs de coleta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { presentedSheet = nil }
                }
            }
        }
    }

    @ViewBuilder
    private func comparisonRows(reference: DisplayCapture, latest: DisplayCapture) -> some View {
        let comparison = DisplayComparison(reference: reference, latest: latest)
        Section {
            Text(comparison.outcome.rawValue).font(.headline)
            LabeledContent("Modo de referência", value: pixels(reference.geometry.currentMode))
            LabeledContent("Modo depois", value: pixels(latest.geometry.currentMode))
        } footer: {
            Text("A comparação se limita à tela reportada ao UIKit. O reboot é informado por você.")
        }

        Section("Métricas comparadas") {
            LabeledContent("Pixels nativos", value: comparison.nativeBounds.rawValue)
            LabeledContent("Área lógica", value: comparison.logicalBounds.rawValue)
            LabeledContent("Lista de modos", value: comparison.availableModes.rawValue)
            LabeledContent("Escala UIKit", value: comparison.scale.rawValue)
            LabeledContent("Escala nativa", value: comparison.nativeScale.rawValue)
            LabeledContent("Orientação", value: comparison.orientation.rawValue)
            LabeledContent("Build", value: comparison.build.rawValue)
        }
    }

    @ViewBuilder
    private func logRows(capture: DisplayCapture, title: String) -> some View {
        let geometry = capture.geometry
        Section(title) {
            LabeledContent("Data", value: capture.capturedAt.formatted(date: .abbreviated, time: .standard))
            LabeledContent("Modelo", value: capture.machine)
            LabeledContent("Build", value: capture.build ?? "Indisponível")
            LabeledContent("Modo", value: pixels(geometry.currentMode))
            LabeledContent("Pixels nativos", value: pixels(geometry.nativeBounds))
            LabeledContent("Área lógica", value: points(geometry.bounds))
            LabeledContent("Área lógica fixa", value: points(geometry.fixedCoordinateSpace))
            LabeledContent("Janela do app", value: points(geometry.sceneBounds))
            LabeledContent("Escalas", value: scales(geometry))
            LabeledContent("Orientação", value: orientationLabel(capture.orientation))
            LabeledContent(
                "Modos disponíveis",
                value: geometry.availableModes.isEmpty ? "Indisponível" : geometry.availableModes.map { pixels($0) }.joined(separator: ", ")
            )
            LabeledContent("Reboot", value: capture.phase == .afterReportedRestart ? "Informado pelo operador" : "Sem registro")
            if let revision = capture.sourceRevision {
                LabeledContent("Revisão", value: String(revision.prefix(12)))
            }
            if let historical = capture.historical {
                if let field = historical.mobileGestalt {
                    LabeledContent("MobileGestalt histórico", value: dimensions(field.dimensions))
                    Text("\(field.type) · \(field.byteCount) bytes · Float64 little-endian")
                    Text(field.hex).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }
                if let preferences = historical.preferenceDimensions {
                    LabeledContent("CFPreferences histórico", value: dimensions(preferences))
                }
                if let written = historical.protectedWriteRecorded {
                    LabeledContent("Escrita no teste histórico", value: written ? "Registrada" : "Sem escrita registrada")
                }
            }
        }
    }

    private func restore() {
        guard !didLoad else { return }
        defer { didLoad = true }
        do {
            report = try store.load()
            selectingAfter = report.reference != nil
        } catch {
            self.error = "Falha ao ler o relatório salvo. \(error.localizedDescription)"
        }
    }

    private func collect() {
        if selectingAfter && (report.reference == nil || !declaredRestart) { return }
        do {
            let capture = try ScreenSampler.capture(phase: selectingAfter ? .afterReportedRestart : .beforeRestart)
            let next = selectingAfter
                ? DisplayReport(reference: report.reference, latest: capture)
                : DisplayReport(reference: capture)
            try save(next)
            if selectingAfter { declaredRestart = false }
            feedback = selectingAfter ? "Coleta posterior salva." : "Referência salva."
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save(_ next: DisplayReport) throws {
        try store.save(next)
        report = next
    }

    private func importReference(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let failure):
            error = failure.localizedDescription
        case .success(let url):
            isReading = true
            Task { @MainActor in
                defer { isReading = false }
                do {
                    let capture = try await Task.detached(priority: .userInitiated) {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        return try ReportCodec.reference(from: ReportCodec.read(from: url))
                    }.value
                    try save(DisplayReport(reference: capture))
                    selectingAfter = true
                    declaredRestart = false
                    feedback = "Referência importada e salva."
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func exportReport() {
        do {
            exportFile = ReportFile(data: try ReportCodec.encode(report))
            isExportPresented = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func dimensions(_ value: DisplaySize) -> String {
        "\(number(value.width)) × \(number(value.height))"
    }

    private func pixels(_ value: DisplaySize?) -> String {
        value.map { "\(dimensions($0)) px" } ?? "Indisponível"
    }

    private func points(_ value: DisplaySize?) -> String {
        value.map { "\(dimensions($0)) pt" } ?? "Indisponível"
    }

    private func scales(_ geometry: ScreenGeometry) -> String {
        "\(number(geometry.scale))× / \(number(geometry.nativeScale))×"
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never))
    }

    private func orientationLabel(_ orientation: DisplayOrientation?) -> String {
        switch orientation {
        case .portrait: return "Retrato"
        case .landscape: return "Paisagem"
        case nil: return "Indisponível"
        }
    }
}

private struct ReportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw ReportError.fileUnavailable }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
