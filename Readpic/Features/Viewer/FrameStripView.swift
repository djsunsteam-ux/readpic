import CoreGraphics
import SwiftUI

/// Horizontal scrub-able strip of GIF/APNG animation frames, shown between
/// the image canvas and the file thumbnail strip.
struct FrameStripView: View {
    let frames: [CoreGraphics.CGImage]
    let totalFrameCount: Int
    let currentIndex: Int
    let isPlaying: Bool
    let onSelect: (Int) -> Void
    let onTogglePlay: () -> Void
    var onScrollStart: (() -> Void)?
    var onScrollEnd: (() -> Void)?

    private let cellSize: CGFloat = 48

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Text("Frame \(currentIndex + 1) of \(totalFrameCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onTogglePlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            // Frame thumbnails in native horizontal scroll view
            ScrollViewReader { proxy in
                NativeHScroll {
                    LazyHStack(spacing: 3) {
                        ForEach(frames.indices, id: \.self) { index in
                            frameCell(index: index)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onScrollStart { onScrollStart?() }
                .onScrollEnd { onScrollEnd?() }
                .frame(height: cellSize + 4)
                .onAppear { proxy.scrollTo(currentIndex, anchor: .center) }
                .onChange(of: currentIndex) { _, newIndex in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func frameCell(index: Int) -> some View {
        let isSelected = index == currentIndex
        let image = frames[index]

        Button {
            onSelect(index)
        } label: {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: cellSize, height: cellSize)
        }
        .buttonStyle(.plain)
        .frame(width: cellSize, height: cellSize)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }
}
