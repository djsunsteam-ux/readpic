import SwiftUI

struct GridView: View {
    let files: [FileItem]
    let filteredIndices: [Int]
    let currentIndex: Int
    let selectedIndices: Set<Int>
    let rootFolderName: String
    let handleClick: (Int, _ isCommand: Bool, _ isShift: Bool) -> Void
    let open: (Int) -> Void
    let topInset: CGFloat
    let bottomInset: CGFloat
    var trailingInset: CGFloat = 0
    let needsGridScroll: UInt
    let gridScrollTarget: Int?
    let onScrollTargetConsumed: () -> Void

    @State private var thumbnails: [URL: CGImage] = [:]
    @State private var failedURLs: Set<URL> = []

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
    ]

    /// Whether the file list contains files from subfolders (any non-empty relativeFolder).
    private var hasSubfolderFiles: Bool {
        files.contains(where: { !$0.relativeFolder.isEmpty })
    }

    /// Group filteredIndices by adjacent `relativeFolder` values.
    /// When subfolder mode is active, root-level files use `rootFolderName` as header.
    /// When no subfolder files exist, returns a single section with no header.
    private var sections: [(header: String, indices: [Int])] {
        guard hasSubfolderFiles else {
            return [("", filteredIndices)]
        }
        var result: [(String, [Int])] = []
        var currentFolder = "\0"  // sentinel that won't match any real folder
        var currentIndices: [Int] = []

        for idx in filteredIndices {
            let folder = files[idx].relativeFolder
            if folder != currentFolder {
                if !currentIndices.isEmpty {
                    result.append((currentFolder, currentIndices))
                }
                currentFolder = folder
                currentIndices = [idx]
            } else {
                currentIndices.append(idx)
            }
        }
        if !currentIndices.isEmpty {
            result.append((currentFolder, currentIndices))
        }
        // Replace empty header (root-level files) with rootFolderName
        return result.map { header, indices in
            (header.isEmpty ? rootFolderName : header, indices)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12, pinnedViews: [.sectionHeaders]) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        Section {
                            ForEach(section.indices, id: \.self) { fileIndex in
                                gridCell(for: fileIndex)
                                    .id(fileIndex)
                                    .padding(.horizontal, 16)
                            }
                        } header: {
                            folderHeader(section.header, count: section.indices.count)
                        }
                    }
                }
                .padding(.bottom, 16)
                .overlay {
                    if filteredIndices.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 28))
                                .foregroundStyle(.tertiary)
                            Text.loc("No matching files")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .offset(y: -20)
                    }
                }
            }
            .contentMargins(.top, topInset, for: .scrollContent)
            .contentMargins(.bottom, bottomInset, for: .scrollContent)
            .contentMargins(.trailing, trailingInset, for: .scrollContent)

            .onAppear {
                scrollToCurrent(proxy: proxy)
            }
            .onChange(of: selectedIndices) { _, _ in
                scrollToCurrent(proxy: proxy)
            }
            .onChange(of: currentIndex) { _, _ in
                scrollToCurrent(proxy: proxy)
            }
            .onChange(of: needsGridScroll) { _, _ in
                scrollToCurrent(proxy: proxy)
            }
            .onChange(of: trailingInset) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    scrollToCurrent(proxy: proxy)
                }
            }
            .onChange(of: gridScrollTarget) { _, newValue in
                guard let target = newValue else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(target, anchor: .top)
                }
                onScrollTargetConsumed()
            }
        }
        .task(id: files.map(\.url)) {
            thumbnails = [:]
            failedURLs = []
        }
    }

    private func scrollToCurrent(proxy: ScrollViewProxy) {
        let target = selectedIndices.sorted().first ?? currentIndex
        guard files.indices.contains(target), filteredIndices.contains(target) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    @ViewBuilder
    private func gridCell(for index: Int) -> some View {
        let file = files[index]
        let isSelected = selectedIndices.contains(index)
            || (selectedIndices.isEmpty && index == currentIndex)

        VStack(spacing: 6) {
            thumbnailView(for: file)
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(Color.clear)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )

            Text(file.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            handleClick(index, flags.contains(.command), flags.contains(.shift))
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                open(index)
            }
        )
        .task {
            await loadThumbnail(for: file.url)
        }
    }

    @ViewBuilder
    private func thumbnailView(for file: FileItem) -> some View {
        ZStack(alignment: .topTrailing) {
            if let cgImage = thumbnails[file.url] {
                Image(cgImage, scale: 1, label: Text(file.name))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 120)
            } else if failedURLs.contains(file.url) {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text.loc("Failed to load")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxHeight: 120)
            }

            if FavoritesManager.shared.isFavorite(file.url) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .padding(4)
            }
        }
    }

    @ViewBuilder
    private func folderHeader(_ folderPath: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(folderPath)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("(\(count))")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    private func loadThumbnail(for url: URL) async {
        guard thumbnails[url] == nil, !failedURLs.contains(url) else { return }
        guard let image = await ThumbnailLoader.load(url: url) else {
            failedURLs.insert(url)
            return
        }
        thumbnails[url] = image
    }
}
