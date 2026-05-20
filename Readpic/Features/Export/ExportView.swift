import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Configuration

struct ExportConfiguration {
    var format: ExportFormat = .jpeg
    var quality: Double = 0.9
    var exportWidth: Int = 1920
    var exportHeight: Int = 1080
    var lockAspectRatio = true
    var outputFolder: URL?
    var fileName: String = ""

    var fileExtension: String { format.fileExtension }

    enum ExportFormat: String, CaseIterable, Sendable {
        case jpeg = "JPEG"
        case png  = "PNG"
        case tiff = "TIFF"
        case bmp  = "BMP"
        case heic = "HEIC"

        var fileExtension: String {
            switch self {
            case .jpeg: "jpg"
            case .png:  "png"
            case .tiff: "tiff"
            case .bmp:  "bmp"
            case .heic: "heic"
            }
        }

        var supportsQuality: Bool {
            switch self {
            case .jpeg, .heic: true
            case .png, .tiff, .bmp: false
            }
        }
    }

    struct AspectPreset: Identifiable, Sendable {
        let id: String
        let label: String
        let ratio: CGFloat // width / height

        static let all: [AspectPreset] = [
            .init(id: "1:1",  label: "1:1",  ratio: 1),
            .init(id: "3:2",  label: "3:2",  ratio: 3/2),
            .init(id: "2:3",  label: "2:3",  ratio: 2/3),
            .init(id: "4:3",  label: "4:3",  ratio: 4/3),
            .init(id: "3:4",  label: "3:4",  ratio: 3/4),
            .init(id: "16:9", label: "16:9", ratio: 16/9),
            .init(id: "9:16", label: "9:16", ratio: 9/16),
            .init(id: "21:9", label: "21:9", ratio: 21/9),
        ]
    }
}

// MARK: - View

struct ExportView: View {
    @State private var config = ExportConfiguration()
    @State private var outputFolderLabel = "Not selected"
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var openFolderAfterExport = true
    @State private var lockedAspectRatio: CGFloat = 1
    /// Tracks which dimension the user is editing for aspect-ratio auto-update.
    @FocusState private var focusedField: Field?

    enum Field { case width, height }

    let fileURL: URL
    let sourceWidth: Int
    let sourceHeight: Int
    let rotation: Int
    let isFlipped: Bool
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text("Export / Convert")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 16) {
                    formatSection
                    resizeSection
                    outputSection
                }
                .padding(.horizontal, 20)
            }

            Divider()

            // Error
            if let error = exportError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }

            // Buttons
            HStack(spacing: 10) {
                Button("Cancel") { onComplete() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button(action: export) {
                    HStack(spacing: 6) {
                        if isExporting { ProgressView().controlSize(.mini) }
                        Text("Export")
                    }
                    .frame(minWidth: 80)
                }
                .keyboardShortcut(.return)
                .disabled(!isValid || isExporting)
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
            let base = (fileURL.lastPathComponent as NSString).deletingPathExtension
            config.fileName = "\(base)_exported"
            // Use source dimensions from metadata; fall back to reading from file
            let w: Int
            let h: Int
            if sourceWidth > 0, sourceHeight > 0 {
                w = sourceWidth
                h = sourceHeight
            } else if let dim = Self.readDimensions(from: fileURL) {
                w = dim.0
                h = dim.1
            } else {
                w = 1920
                h = 1080
            }
            config.exportWidth = w
            config.exportHeight = h
            lockedAspectRatio = CGFloat(max(1, w)) / CGFloat(max(1, h))
        }
    }

    // MARK: - Sections

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Format")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker(selection: $config.format) {
                ForEach(ExportConfiguration.ExportFormat.allCases, id: \.self) { fmt in
                    Text(fmt.rawValue).tag(fmt)
                }
            } label: { }
            .pickerStyle(.segmented)
            .labelsHidden()

            if config.format.supportsQuality {
                VStack(spacing: 4) {
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
        }
    }

    private var resizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resize")
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

                    // Original size reference
                    HStack {
                        Text("Original: \(sourceWidth) × \(sourceHeight)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Spacer()
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

            VStack(spacing: 8) {
                HStack {
                    TextField("File name", text: $config.fileName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                    Text(".\(config.fileExtension)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

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
            }
            .padding(8)
        }
    }

    // MARK: - Preset

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

    // MARK: - Validation

    private var isValid: Bool {
        !config.fileName.trimmingCharacters(in: .whitespaces).isEmpty
        && config.outputFolder != nil
        && config.exportWidth > 0
        && config.exportHeight > 0
    }

    // MARK: - Folder Picker

    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose export destination folder"
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        config.outputFolder = url
        outputFolderLabel = url.path
    }

    // MARK: - Export

    private func export() {
        guard let folder = config.outputFolder else { return }
        let fileName = config.fileName.trimmingCharacters(in: .whitespaces)
        guard !fileName.isEmpty else { return }

        let fmt = config.format
        let quality = config.quality
        let targetW = config.exportWidth
        let targetH = config.exportHeight
        let ext = config.fileExtension
        let url = fileURL
        let rot = rotation
        let flip = isFlipped

        isExporting = true
        exportError = nil

        Task.detached(priority: .userInitiated) {
            // Decode fresh from file (works in both grid and viewer mode)
            let decoder = ImageDecoder()
            guard let decoded = try? decoder.decode(url: url) else {
                await MainActor.run {
                    exportError = "Failed to read image"
                    isExporting = false
                }
                return
            }

            guard let transformed = ImageWriter.applyTransform(
                to: decoded.image, rotation: rot, isFlipped: flip
            ) else {
                await MainActor.run {
                    exportError = "Failed to process image"
                    isExporting = false
                }
                return
            }

            let finalImage = ImageWriter.resize(transformed, to: targetW, targetHeight: targetH) ?? transformed

            let destURL = folder.appendingPathComponent("\(fileName).\(ext)")
            let compressionQuality: CGFloat? = fmt.supportsQuality ? quality : nil
            let saveFormat = ImageWriter.SaveFormat.from(extension: ext) ?? .jpeg

            guard ImageWriter.write(finalImage, to: destURL, format: saveFormat, compressionQuality: compressionQuality) else {
                await MainActor.run {
                    exportError = "Failed to write file"
                    isExporting = false
                }
                return
            }

            await MainActor.run {
                isExporting = false
                if openFolderAfterExport {
                    NSWorkspace.shared.open(folder)
                }
                onComplete()
            }
        }
    }
    /// Read pixel dimensions directly from an image file (synchronous helper).
    private static func readDimensions(from url: URL) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
              w > 0, h > 0 else { return nil }
        return (Int(w), Int(h))
    }
}

// MARK: - Resize helper

extension ImageWriter {
    static func resize(_ image: CGImage, to targetWidth: Int, targetHeight: Int) -> CGImage? {
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return ctx.makeImage()
    }
}
