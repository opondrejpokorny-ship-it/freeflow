import SwiftUI

struct LocalWhisperModelsSettingsView: View {
    @State private var states: [String: LocalWhisperModelState] = [:]
    @State private var managerError: String?

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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Local Whisper Models", systemImage: "waveform.badge.mic")
                .font(.headline)

            Text("Models are stored only on this Mac. Local transcription remains disabled until the local provider is implemented.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
        .task {
            await refreshStates()
        }
    }

    @ViewBuilder
    private func modelRow(_ model: LocalWhisperCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.subheadline.weight(.semibold))
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
                Label("Download disabled until the upstream file's SHA-256 is independently verified.", systemImage: "lock.shield")
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
            Button("Remove", role: .destructive) {
                remove(model)
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
            states[model.id] = state
        }
    }

    private func remove(_ model: LocalWhisperCatalogEntry) {
        guard let manager, let descriptor = model.descriptor else { return }
        Task {
            do {
                try await manager.remove(descriptor)
                states[model.id] = .notInstalled
            } catch {
                states[model.id] = .failed(error.localizedDescription)
            }
        }
    }
}
