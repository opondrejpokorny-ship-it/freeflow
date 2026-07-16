import SwiftUI

enum LanguagePickerMode: Sendable {
    case transcription
    case output

    func options(locale: Locale = .current) -> [(code: String, name: String)] {
        switch self {
        case .transcription:
            return LanguageService.inputOptions(locale: locale)
        case .output:
            return LanguageService.outputOptions(locale: locale)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .transcription:
            return "Transcription Language"
        case .output:
            return "Output Language"
        }
    }
}

/// Searchable language field designed for the full Whisper language catalog.
///
/// A normal SwiftUI `Picker` becomes difficult to use with 100 languages. This
/// control keeps the compact settings-row appearance while presenting a
/// searchable popover when opened.
struct LanguagePickerView: View {
    let mode: LanguagePickerMode
    @Binding var selection: String

    @State private var isPresented = false
    @State private var searchText = ""
    @Environment(\.locale) private var locale

    private var options: [(code: String, name: String)] {
        mode.options(locale: locale)
    }

    private var selectedName: String {
        options.first(where: { $0.code == selection })?.name
            ?? options.first?.name
            ?? selection
    }

    private var filteredOptions: [(code: String, name: String)] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }

        return options.filter { option in
            option.name.localizedCaseInsensitiveContains(query)
                || option.code.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Button {
            searchText = ""
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(selectedName)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(mode.accessibilityLabel)
        .accessibilityValue(selectedName)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            languagePopover
        }
    }

    private var languagePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search languages", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredOptions, id: \.code) { option in
                            Button {
                                selection = option.code
                                isPresented = false
                            } label: {
                                HStack(spacing: 10) {
                                    Group {
                                        if selection == option.code {
                                            Image(systemName: "checkmark")
                                        } else {
                                            Color.clear
                                        }
                                    }
                                    .frame(width: 12, height: 12)

                                    Text(option.name)
                                    Spacer(minLength: 8)
                                    if !option.code.isEmpty {
                                        Text(option.code)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(option.code)
                        }
                    }
                }
                .onAppear {
                    proxy.scrollTo(selection, anchor: .center)
                }
            }

            if filteredOptions.isEmpty {
                Text("No matching language")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .padding(12)
        .frame(width: 320, height: 390)
    }
}
