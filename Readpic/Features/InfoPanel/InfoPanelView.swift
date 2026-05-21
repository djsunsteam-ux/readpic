import SwiftUI

struct InfoPanelView: View {
    let model: ViewerModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: topContentPadding)

                if let metadata = model.metadata {
                    GroupSection(title: "File") {
                        InfoRow(label: "Name", value: metadata.name)
                        InfoRow(label: "Path", value: metadata.path, monospaced: true, lineLimit: 2)
                        InfoRow(label: "Size", value: metadata.formattedFileSize)
                        InfoRow(label: "Created", value: metadata.createdAt?.formatted() ?? "—")
                        InfoRow(label: "Modified", value: metadata.modifiedAt?.formatted() ?? "—")
                    }

                    GroupSection(title: "Image") {
                        InfoRow(label: "Dimensions", value: metadata.dimensionsText)
                        InfoRow(label: "Format", value: metadata.format)
                        InfoRow(label: "Color Space", value: metadata.colorSpace)
                        if let bitDepth = metadata.bitDepth {
                            InfoRow(label: "Bit Depth", value: "\(bitDepth)-bit")
                        }
                    }

                    if metadata.dateTaken != nil || metadata.camera != nil || metadata.lens != nil || metadata.iso != nil || metadata.aperture != nil || metadata.shutterSpeed != nil {
                        GroupSection(title: "Camera") {
                            if let dateTaken = metadata.dateTakenText {
                                InfoRow(label: "Date Taken", value: dateTaken)
                            }
                            if let camera = metadata.camera {
                                InfoRow(label: "Camera", value: camera)
                            }
                            if let lens = metadata.lens {
                                InfoRow(label: "Lens", value: lens)
                            }
                            if let iso = metadata.iso {
                                InfoRow(label: "ISO", value: String(iso))
                            }
                            if let aperture = metadata.apertureText {
                                InfoRow(label: "Aperture", value: aperture)
                            }
                            if let shutter = metadata.shutterText {
                                InfoRow(label: "Shutter", value: shutter)
                            }
                        }
                    }

                    if metadata.locationText != nil {
                        GroupSection(title: "GPS") {
                            if let loc = metadata.locationText {
                                InfoRow(label: "Location", value: loc, monospaced: true, lineLimit: 3)
                            }
                        }
                    }

                    // MARK: - Favorites
                    GroupSection(title: "Favorites") {
                        Button(action: { model.toggleFavorite() }) {
                            Image(systemName: model.isCurrentFileFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 20))
                                .foregroundStyle(model.isCurrentFileFavorite ? .red : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(model.isCurrentFileFavorite ? "Remove from Favorites" : "Add to Favorites")
                        .padding(.vertical, 2)
                    }

                    // MARK: - Rating
                    GroupSection(title: "Rating") {
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { star in
                                Button(action: {
                                    let newRating = star == model.currentFileRating ? 0 : star
                                    model.rateCurrentFile(newRating)
                                }) {
                                    Image(systemName: star <= model.currentFileRating ? "star.fill" : "star")
                                        .font(.system(size: 18))
                                        .foregroundStyle(star <= model.currentFileRating ? Color.yellow : Color.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Rate \(star) star\(star == 1 ? "" : "s")")
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Divider()
                        .padding(.vertical, 12)

                    Button(action: { model.exportMetadata() }) {
                        Label("Export Info", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 13))
                }

                Color.clear.frame(height: bottomContentPadding)
            }
            .padding(16)
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
    }

    /// Extra top padding so content starts below the overlaid toolbar.
    private var topContentPadding: CGFloat {
        let barsHidden = model.isFullScreen && !model.cursorNearTop && !model.cursorNearBottom
        return barsHidden ? 0 : 40
    }

    /// Extra bottom padding so content ends above the overlaid bottom bars.
    private var bottomContentPadding: CGFloat {
        model.bottomBarsTotalHeight + 24  // 24pt breathing room
    }
}

private struct GroupSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)

        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(.bottom, 16)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false
    var lineLimit: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, design: monospaced ? .monospaced : .default))
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
