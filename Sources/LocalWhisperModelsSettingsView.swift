import SwiftUI

struct LocalWhisperModelsSettingsView: View {
    @AppStorage(AppState.speechExecutionModeStorageKey)
    private var executionModeRawValue = SpeechExecutionMode.cloud.rawValue
    @AppStorage(AppState.localWhisperModelIDStorageKey)
    private var selectedModelID = "base"
    @AppStorage(AppState.localWhisperExecutablePathStorageKey)
    private var customExecutablePath = ""

    @State private var states: [String: LocalWhisperModelState] = [:]
    @State private var managerError: String?
    @State private var runtimeStatus = LocalWhisperRuntimeDetector().detect()

    private let manager: LocalWhisperModelManager?
    private let models = LocalWhisperModelCatalog.recommended

    init() {
        do {
            manager = try LocalWhisperModelManager()
        } catch {
            manager = nil
            _managerError = State(initialValue: error.localizedDescription)
        }
    }

    private var executionMode: SpeechExecutionMode {
        SpeechExecutionMode(rawValue: executionModeRawValue) ?? .cloud
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Transcription mode", selection: $executionModeRawValue) {
                Text("Cloud").tag(SpeechExecutionMode.cloud.rawValue)
                Text("Local (offline)").tag(SpeechExecutionMode.local.rawValue)
            }
            .pickerStyle(.segmented)

            Text(executionMode == .local
                 ? "Audio is transcribed on this Mac. FreeFlow does not silently fall back to Cloud."
                 : "Audio is sent to the configured OpenAI-compatible transcription provider.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if executionMode == .local {
                runtimeSection
                Divider()
                modelSection
            }
        }
        .task {
            if LocalWhisperModelCatalog.entry(id: selectedModelID)?.isInstallable != true {
                selectedModelID = "base"
            }
            refreshRuntime()
            await refreshStates()
        }
        .onChange(of: customExecutablePath) { _ in
            refreshRuntime()
        }
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("whisper.cpp runtime")
                        .font(.subheadline.weight(.semibold))
                    Text(runtimeDescription)
                        .font(.caption)
                        .foregroundStyle(runtimeStatus.isReady ? Color.secondary : Color.orange)
                }
                Spacer()
                Button("Detect") {
                    refreshRuntime()
                }
            }

            TextField("Optional path to whisper-cli", text: $customExecutablePath)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))

            Text("FreeFlow checks this path first, then the app bundle, /opt/homebrew/bin, and /usr/local/bin. Realtime cloud streaming is ignored in Local mode.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Active local model", selection: $selectedModelID) {
                ForEach(models.filter(\.isInstallable)) { model in
                    Text(model.displayName).tag(model.id)
                }
            }

            if let managerError {
                Label(managerError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ForEach(models) { model in
                modelRow(model)
                if model.id != models.last?.id {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ model: LocalWhisperCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.subheadline.weight(.semibold))
                        if selectedModelID == model.id {
                            Text("Selected")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        }
                    }
                    Text("\(ByteCountFormatter.string(fromByteCount: model.approximateSizeBytes, countStyle: .file)) · \(model.qualityDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                stateControls(for: model)
            }

            if case let .downloading(progress) = states[model.id] {
                if let progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                }
            }

            if !model.isInstallable {
                Label("Download locked until this pinned file's SHA-256 is verified.", systemImage: "lock.shield")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func stateControls(for model: LocalWhisperCatalogEntry) -> some View {
        switch states[model.id] ?? .notInstalled {
        case .notInstalled:
            Button("Download") {
                install(model)
            }
            .disabled(!model.isInstallable || manager == nil)

        case .downloading:
            Button("Downloading…") {}
                .disabled(true)

        case .ready:
            HStack(spacing: 8) {
                if selectedModelID != model.id {
                    Button("Use") {
                        selectedModelID = model.id
                    }
                }
                Button("Remove", role: .destructive) {
                    remove(model)
                }
            }

        case .invalidChecksum:
            Button("Remove invalid file", role: .destructive) {
                remove(model)
            }

        case .failed:
            Button("Retry") {
                install(model)
            }
            .disabled(!model.isInstallable || manager == nil)
        }
    }

    private var runtimeDescription: String {
        guard runtimeStatus.isReady, let executableURL = runtimeStatus.executableURL else {
            return "Not found. Install whisper.cpp or provide an executable path."
        }
        let acceleration = runtimeStatus.metalIsExpected ? "Metal expected" : "CPU"
        return "Ready at \(executableURL.path) · \(acceleration)"
    }

    private func refreshRuntime() {
        let trimmed = customExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let customURL: URL?
        if trimmed.isEmpty {
            customURL = nil
        } else {
            customURL = URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
        }
        runtimeStatus = LocalWhisperRuntimeDetector(customExecutableURL: customURL).detect()
    }

    private func refreshStates() async {
        guard let manager else { return }
        for model in models {
            guard let descriptor = model.descriptor else {
                states[model.id] = .notInstalled
                continue
            }
            states[model.id] = await manager.state(for: descriptor)
        }
    }

    private func install(_ model: LocalWhisperCatalogEntry) {
        guard let manager, let descriptor = model.descriptor else { return }
        states[model.id] = .downloading(progress: 0)
        Task {
            let state = await manager.install(descriptor) { progress in
                Task { @MainActor in
                    states[model.id] = .downloading(progress: progress)
                }
            }
            await MainActor.run {
                states[model.id] = state
                if case .ready = state {
                    selectedModelID = model.id
                }
            }
        }
    }

    private func remove(_ model: LocalWhisperCatalogEntry) {
        guard let manager, let descriptor = model.descriptor else { return }
        Task {
            do {
                try await manager.remove(descriptor)
                await MainActor.run {
                    states[model.id] = .notInstalled
                }
            } catch {
                await MainActor.run {
                    states[model.id] = .failed(error.localizedDescription)
                }
            }
        }
    }
}
