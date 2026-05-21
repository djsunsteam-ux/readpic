import AppKit
import SwiftUI

struct BatchConvertView: View {
    @State private var config = ExportConfiguration()
    @State private var outputFolder: URL?
    @State private var outputFolderLabel = "Not selected"
    @State private var fileStates: [FileState] = []
    @State private var isConverting = false
    @State private var isCancelled = false
    @State private var convertedCount = 0
    @State private var failedCount = 0
    @State private var openFolderAfterExport = true
    @FocusState private var focusedField: Field?
    /// Fixed aspect ratio set on appear — prevents ratio drift when onChange
    /// fires during digit-by-digit typing.
    @State private var lockedAspectRatio: CGFloat = 16.0 / 9.0

    enum Field { case width, height }

    let files: [FileItem]
    let onComplete: () -> Void

    private var totalCount: Int { files.count }

    struct FileState: Identifiable {
        var id: URL { url }
        let url: URL
        let name: String
        var status: Status = .pending

        enum Status {
            case pending
            case processing
            case completed
            case failed(String)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text("Batch Convert / Export")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(totalCount) files")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    formatSection
                    resizeSection
                    outputSection
                    progressSection
                }
                .padding(.horizontal, 20)
            }

            Divider()

            HStack(spacing: 10) {
                Button("Cancel") { onComplete() }
                    .keyboardShortcut(.escape)
                Spacer()

                if isConverting {
                    Button("Cancel Conversion") { isCancelled = true }
                        .keyboardShortcut(.escape)
                }

                Button(action: convert) {
                    HStack(spacing: 6) {
                        if isConverting { ProgressView().controlSize(.mini) }
                        Text(isConverting ? "Converting..." : "Export \(totalCount) Files")
                    }
                    .frame(minWidth: 120)
                }
                .keyboardShortcut(.return)
                .disabled(!isValid || isConverting)
            }
            .padding(20)
        }
        .frame(width: 460)
        .onChange(of: config.lockAspectRatio) { _, newValue in
            if newValue {
                lockedAspectRatio = CGFloat(max(1, config.exportWidth)) / CGFloat(max(1, config.exportHeight))
            }
        }
        .onAppear {
            fileStates = files.map { FileState(url: $0.url, name: $0.name, status: .pending) }
            lockedAspectRatio = CGFloat(max(1, config.exportWidth)) / CGFloat(max(1, config.exportHeight))
        }
    }

    // MARK: - Sections

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Format")
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker(selection: $config.format) {
                ForEach(ImageWriter.SaveFormat.allCases, id: \.self) { fmt in
                    Text(fmt.rawValue).tag(fmt)
                }
            } label: { }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(spacing: 4) {
                if config.format.supportsQuality {
                    HStack {
                        Text("Quality")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(config.quality * 100))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $config.quality, in: 0.1...1.0, step: 0.05)
                }
            }
            .frame(minHeight: 50)
        }
    }

    private var resizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resize")
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                VStack(spacing: 2) {
                    TextField("Width", value: $config.exportWidth, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .frame(width: 90)
                        .focused($focusedField, equals: .width)
                        .onChange(of: config.exportWidth) { _, newValue in
                            guard config.lockAspectRatio, focusedField == .width else { return }
                            config.exportHeight = max(1, Int(CGFloat(max(1, newValue)) / lockedAspectRatio))
                        }
                    Text("Width (px)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Text("×")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, -12)

                VStack(spacing: 2) {
                    TextField("Height", value: $config.exportHeight, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .frame(width: 90)
                        .focused($focusedField, equals: .height)
                        .onChange(of: config.exportHeight) { _, newValue in
                            guard config.lockAspectRatio, focusedField == .height else { return }
                            config.exportWidth = max(1, Int(CGFloat(max(1, newValue)) * lockedAspectRatio))
                        }
                    Text("Height (px)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Toggle(isOn: $config.lockAspectRatio) {
                    Image(systemName: config.lockAspectRatio ? "lock.fill" : "lock.open")
                        .font(.system(size: 13))
                }
                .toggleStyle(.button)
                .help("Lock aspect ratio")
                .padding(.top, -12)
            }

            // Aspect ratio presets (only when unlocked)
            if !config.lockAspectRatio {
                Divider()
                HStack {
                    Text("Ratio")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], spacing: 6) {
                    ForEach(ExportConfiguration.AspectPreset.all) { preset in
                        Button(preset.label) {
                            applyAspectPreset(preset)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                Text(outputFolderLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose...") { selectOutputFolder() }
                    .font(.system(size: 12))
            }

            Toggle("Open folder after export", isOn: $openFolderAfterExport)
                .font(.system(size: 11))
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isConverting || convertedCount > 0 || failedCount > 0 {
                Text("Progress")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                ProgressView(
                    value: Double(convertedCount + failedCount),
                    total: Double(totalCount)
                )

                HStack {
                    Text("\(convertedCount + failedCount) of \(totalCount)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if failedCount > 0 {
                        Text("\(failedCount) failed")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                    if convertedCount > 0 {
                        Text("\(convertedCount) converted")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    }
                }

                // File list with status
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(fileStates) { state in
                            HStack(spacing: 6) {
                                Image(systemName: iconName(for: state.status))
                                    .font(.system(size: 10))
                                    .foregroundStyle(iconColor(for: state.status))
                                Text(state.name)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(textColor(for: state.status))
                                if case .failed(let msg) = state.status {
                                    Text(msg)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.red)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
    }

    // MARK: - Helpers

    private func iconName(for status: FileState.Status) -> String {
        switch status {
        case .pending:    "circle"
        case .processing: "arrow.triangle.2.circlepath"
        case .completed:  "checkmark.circle.fill"
        case .failed:     "exclamationmark.circle.fill"
        }
    }

    private func iconColor(for status: FileState.Status) -> Color {
        switch status {
        case .pending:    .secondary
        case .processing: .accentColor
        case .completed:  .green
        case .failed:     .red
        }
    }

    private func textColor(for status: FileState.Status) -> Color {
        switch status {
        case .failed: .red
        default:      .primary
        }
    }

    private var isValid: Bool {
        outputFolder != nil && !files.isEmpty
    }

    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose export destination folder"
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputFolder = url
        outputFolderLabel = url.path
    }

    private func applyAspectPreset(_ preset: ExportConfiguration.AspectPreset) {
        switch focusedField {
        case .width:
            let h = max(1, Int(CGFloat(config.exportWidth) / preset.ratio))
            config.exportHeight = h
        case .height, .none:
            let w = max(1, Int(CGFloat(config.exportHeight) * preset.ratio))
            config.exportWidth = w
        }
    }

    // MARK: - Convert

    private func convert() {
        guard let folder = outputFolder else { return }
        isConverting = true
        isCancelled = false
        convertedCount = 0
        failedCount = 0

        let fmt = config.format
        let quality = config.quality
        let targetW = config.exportWidth
        let targetH = config.exportHeight
        let ext = config.fileExtension

        Task {
            for i in files.indices {
                guard !isCancelled else { break }

                fileStates[i].status = .processing

                // Heavy work off the main actor
                let result = await Task.detached(priority: .userInitiated) { [files, i, targetW, targetH, ext, fmt, quality, folder] in
                    let file = files[i]
                    let decoder = ImageDecoder()

                    guard let decoded = try? decoder.decode(url: file.url) else {
                        return (index: i, ok: false, error: "can't read")
                    }

                    guard let transformed = ImageWriter.applyTransform(
                        to: decoded.image, rotation: 0, isFlipped: false
                    ) else {
                        return (index: i, ok: false, error: "process error")
                    }

                    let finalImage = ImageWriter.resize(transformed, to: targetW, targetHeight: targetH) ?? transformed

                    let baseName = (file.name as NSString).deletingPathExtension
                    let destURL = folder.appendingPathComponent("\(baseName).\(ext)")
                    let compressionQuality: CGFloat? = fmt.supportsQuality ? quality : nil
                    let ok = ImageWriter.write(finalImage, to: destURL, format: fmt, compressionQuality: compressionQuality)

                    return (index: i, ok: ok, error: ok ? "" : "write error")
                }.value

                if result.ok {
                    fileStates[result.index].status = .completed
                    convertedCount += 1
                } else {
                    fileStates[result.index].status = .failed(result.error.isEmpty ? "error" : result.error)
                    failedCount += 1
                }

                // Let UI update between files
                await Task.yield()
            }

            isConverting = false
            if convertedCount > 0, openFolderAfterExport {
                NSWorkspace.shared.open(folder)
            }
            onComplete()
        }
    }
}
