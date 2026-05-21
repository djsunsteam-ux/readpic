import SwiftUI

struct BatchRenameView: View {
    enum RenameMode: String, CaseIterable {
        case sequential = "Sequential"
        case findReplace = "Find & Replace"
    }

    @State private var mode: RenameMode = .sequential
    @State private var baseName: String = ""
    @State private var startNumber: Int = 1
    private let presets = ["IMG", "DSC", "Photo", "Screenshot", "PANO", "Export", "Backup"]
    /// Presets currently active in `baseName` (determined by splitting on `_`).
    private var activePresets: Set<String> {
        Set(baseName.split(separator: "_").map(String.init).filter(presets.contains))
    }

    @State private var findText: String = ""
    @State private var replaceText: String = ""
    @State private var previewItems: [PreviewItem] = []
    @State private var isApplying = false
    @State private var errorMessage: String?

    let files: [FileItem]
    let onComplete: () -> Void

    struct PreviewItem: Identifiable {
        let id: Int
        let originalURL: URL
        let originalName: String
        var newName: String
        var isConflict: Bool
        var status: Status = .pending

        enum Status { case pending, renamed, skipped, failed(String) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text("Batch Rename")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(files.count) files")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 16) {
                    modeSection
                    if mode == .sequential { sequentialSection }
                    else { findReplaceSection }
                    previewSection
                    if let error = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.system(size: 12))
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Divider()

            HStack(spacing: 10) {
                Button("Cancel") { onComplete() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button(action: apply) {
                    HStack(spacing: 6) {
                        if isApplying { ProgressView().controlSize(.mini) }
                        Text(isApplying ? String(localized: "Renaming...") : String(format: String(localized: "Rename %d Files"), files.count))
                    }
                    .frame(minWidth: 100)
                }
                .keyboardShortcut(.return)
                .disabled(!isValid || isApplying)
            }
            .padding(20)
        }
        .frame(width: 500, height: 520)
        .onAppear {
            baseName = commonPrefix(from: files.map(\.name))
            regeneratePreview()
        }
        .onChange(of: mode) { _, _ in regeneratePreview() }
        .onChange(of: baseName) { _, _ in regeneratePreview() }
        .onChange(of: startNumber) { _, _ in regeneratePreview() }

        .onChange(of: findText) { _, _ in regeneratePreview() }
        .onChange(of: replaceText) { _, _ in regeneratePreview() }
    }

    // MARK: - Sections

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker(selection: $mode) {
                ForEach(RenameMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            } label: { }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var sequentialSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Naming")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Base name", text: $baseName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 200)
                    Text("Base name")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Stepper(value: $startNumber, in: 1...9999) {
                            TextField("Start", value: $startNumber, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, design: .monospaced))
                                .frame(width: 60)
                                .multilineTextAlignment(.center)
                        }
                    }
                    Text("Start number")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Preview row
            VStack(alignment: .leading, spacing: 2) {
                Text(sampleName)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                Text("Preview")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            // Preset chips
            Text("Presets")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { preset in
                    Button(preset) { togglePreset(preset) }
                        .font(.system(size: 11, design: .monospaced))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .background(activePresets.contains(preset) ? Color.accentColor.opacity(0.25) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    private var findReplaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Find & Replace")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Find", text: $findText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 200)
                    Text("Find")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    TextField("Replace with", text: $replaceText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 200)
                    Text("Replace with")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Preview")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(previewItems.filter { !$0.isConflict }.count) OK · \(previewItems.filter(\.isConflict).count) conflicts")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(previewItems) { item in
                        HStack(spacing: 6) {
                            Image(systemName: iconName(for: item))
                                .font(.system(size: 10))
                                .foregroundStyle(iconColor(for: item))
                            HStack(spacing: 0) {
                                Text(item.originalName)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .strikethrough(item.originalName != item.newName)
                                if item.originalName != item.newName {
                                    Text("  →  ")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                    Text(item.newName)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(item.isConflict ? .red : .primary)
                                }
                            }
                            .lineLimit(1)
                            .truncationMode(.middle)

                            Spacer()

                            if item.isConflict {
                                Text("Conflict")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(item.isConflict ? Color.red.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .frame(maxHeight: 180)
            .padding(8)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Helpers

    private var sampleName: String {
        guard !previewItems.isEmpty else { return "—" }
        let padded = String(format: "%0\(String(files.count).count)d", startNumber)
        return "\(baseName)_\(padded).\(previewItems[0].originalURL.pathExtension)"
    }

    private var isValid: Bool {
        if mode == .sequential { return !baseName.trimmingCharacters(in: .whitespaces).isEmpty }
        return !findText.isEmpty
    }

    private func iconName(for item: PreviewItem) -> String {
        switch item.status {
        case .pending:    item.originalName != item.newName && !item.isConflict ? "arrow.right" : "minus"
        case .renamed:    "checkmark.circle.fill"
        case .skipped:    "minus.circle"
        case .failed:     "exclamationmark.circle.fill"
        }
    }

    private func iconColor(for item: PreviewItem) -> Color {
        switch item.status {
        case .pending:    item.isConflict ? .red : .secondary
        case .renamed:    .green
        case .skipped:    .secondary
        case .failed:     .red
        }
    }

    private func regeneratePreview() {
        switch mode {
        case .sequential:
            generateSequentialPreview()
        case .findReplace:
            generateFindReplacePreview()
        }
    }

    private func generateSequentialPreview() {
        let digits = String(files.count).count
        let allNames = Set(files.map(\.name))
        previewItems = files.enumerated().map { i, file in
            let num = startNumber + i
            let padded = String(format: "%0\(digits)d", num)
            let ext = file.url.pathExtension
            let newName = "\(baseName)_\(padded).\(ext)"
            let isConflict = newName != file.name && allNames.contains(newName)
            return PreviewItem(id: i, originalURL: file.url, originalName: file.name, newName: newName, isConflict: isConflict)
        }
    }

    private func generateFindReplacePreview() {
        guard !findText.isEmpty else {
            previewItems = files.enumerated().map { i, file in
                PreviewItem(id: i, originalURL: file.url, originalName: file.name, newName: file.name, isConflict: false)
            }
            return
        }
        let allNames = Set(files.map(\.name))
        previewItems = files.enumerated().map { i, file in
            let newName = file.name.replacingOccurrences(of: findText, with: replaceText)
            let isConflict = newName != file.name && allNames.contains(newName)
            return PreviewItem(id: i, originalURL: file.url, originalName: file.name, newName: newName, isConflict: isConflict)
        }
    }

    private func togglePreset(_ preset: String) {
        let parts = baseName.split(separator: "_").map(String.init)
        if parts.contains(preset) {
            baseName = parts.filter { $0 != preset }.joined(separator: "_")
        } else {
            baseName = baseName.isEmpty ? preset : "\(baseName)_\(preset)"
        }
    }

    /// Extract common prefix from a list of filenames (up to the first differing character).
    private func commonPrefix(from names: [String]) -> String {
        guard let first = names.first, names.count > 1 else {
            return names.first.map { name in
                let ext = (name as NSString).pathExtension
                let base = (name as NSString).deletingPathExtension
                return ext.isEmpty ? base : base
            } ?? "IMG"
        }
        let common = first.commonPrefix(with: names[1])
        // Strip trailing digits/separators
        let stripped = common.trimmingCharacters(in: CharacterSet(charactersIn: " _-0123456789"))
        return stripped.isEmpty ? "IMG" : stripped
    }

    // MARK: - Apply

    private func apply() {
        let toRename = previewItems.filter { !$0.isConflict && $0.originalName != $0.newName }
        guard !toRename.isEmpty else {
            errorMessage = "No files to rename"
            return
        }

        isApplying = true
        errorMessage = nil

        Task.detached(priority: .userInitiated) { [previewItems] in
            let fileManager = FileManager.default
            // Build rename plan: sort by original name to avoid folder reordering surprises
            let plan = previewItems
                .filter { !$0.isConflict && $0.originalName != $0.newName }
                .sorted { $0.originalName < $1.originalName }

            var results: [Int] = []

            for item in plan {
                let destURL = item.originalURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(item.newName)

                guard !fileManager.fileExists(atPath: destURL.path) else {
                    continue
                }

                do {
                    try fileManager.moveItem(at: item.originalURL, to: destURL)
                    results.append(item.id)
                } catch {
                    // Skip — file may be in use
                }
            }

            await MainActor.run {
                isApplying = false
                if results.count == toRename.count {
                    onComplete()
                } else {
                    errorMessage = String(format: String(localized: "Renamed %d of %d files"), results.count, toRename.count)
                }
            }
        }
    }
}
