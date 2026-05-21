import AppKit
import SwiftUI

// MARK: - Transition type

enum SlideshowTransition: String, CaseIterable, Sendable {
    case dissolve = "Dissolve"
    case instant  = "Instant"

    var animation: Animation? {
        switch self {
        case .dissolve: .easeInOut(duration: 0.4)
        case .instant:  nil
        }
    }
}

// MARK: - View

struct SlideshowView: View {
    @Bindable var model: ViewerModel

    @State private var controlsVisible = true
    @State private var showSettings = false
    @State private var hoveringControls = false
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var keyMonitor: Any?

    private let controlsHideDelay: TimeInterval = 2.5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Image — observe model.decodedImage reactively
                if let img = model.decodedImage?.image {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .id(model.currentFile?.url)
                        .transition(.opacity.animation(model.slideshowTransition.animation))
                } else {
                    ProgressView()
                        .controlSize(.large)
                }

                // Controls overlay
                if controlsVisible {
                    VStack {
                        Spacer()
                        controlsBar
                            .padding(.horizontal, 24)
                            .padding(.bottom, 32)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleControls() }
            .background(ScrollWheelHandler(onPrevious: { slideshowPrevious() }, onNext: { slideshowNext() }))
        }
        .focusEffectDisabled()
        .onAppear {
            scheduleHideControls()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 49:  togglePlayPause(); return nil  // Space
                case 123: slideshowPrevious(); return nil  // Left arrow
                case 124: slideshowNext(); return nil      // Right arrow
                default: break
                }
                return event
            }
        }
        .onDisappear {
            hideControlsTask?.cancel()
            if let m = keyMonitor as? NSObjectProtocol { NSEvent.removeMonitor(m) }
        }
        .onChange(of: showSettings) { _, _ in
            if showSettings {
                hideControlsTask?.cancel()
            } else {
                scheduleHideControls()
            }
        }
    }

    // MARK: - Controls

    private var controlsBar: some View {
        HStack(spacing: 16) {
            Button { model.stopSlideshow() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("Exit slideshow (Esc)")

            Divider().frame(height: 20)

            Button { slideshowPrevious() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("Previous")

            Button { togglePlayPause() } label: {
                Image(systemName: model.isAnimationPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(.white.opacity(0.15), in: Circle())

            Button { slideshowNext() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("Next")

            if let url = model.currentFile?.url,
               let idx = model.navigableFiles.firstIndex(where: { $0.url == url }) {
                Text("\(idx + 1) / \(model.navigableFiles.count)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 4)
            }

            Spacer()

            Button { showSettings.toggle() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .popover(isPresented: $showSettings) { settingsPanel }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onHover { over in
            hoveringControls = over
            if over {
                hideControlsTask?.cancel()
            } else if !showSettings {
                scheduleHideControls()
            }
        }
    }

    // MARK: - Settings

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Slideshow Settings")
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Speed")
                        .font(.system(size: 12))
                    Spacer()
                    Text(speedLabel)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.slideshowInterval, in: 1...10, step: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Transition")
                    .font(.system(size: 12))
                Picker(selection: $model.slideshowTransition) {
                    ForEach(SlideshowTransition.allCases, id: \.rawValue) { t in
                        Text(t.rawValue).tag(t)
                    }
                } label: { }
                .pickerStyle(.segmented)
            }
        }
        .padding(16)
        .frame(width: 220)
    }

    private var speedLabel: String {
        switch model.slideshowInterval {
        case ..<2: "Fast"
        case ..<4: "Normal"
        case ..<7: "Slow"
        default:   "Very Slow"
        }
    }

    // MARK: - Navigation

    private func togglePlayPause() {
        model.isAnimationPaused.toggle()
    }

    private func slideshowPrevious() {
        navigateSlideshow(direction: -1)
    }

    private func slideshowNext() {
        navigateSlideshow(direction: 1)
    }

    private func navigateSlideshow(direction: Int) {
        let nav = model.navigableFiles
        guard nav.count > 1, let url = model.currentFile?.url,
              var idx = nav.firstIndex(where: { $0.url == url })
        else { return }
        let startIdx = idx
        repeat {
            idx = (idx + direction + nav.count) % nav.count
            let ext = nav[idx].url.pathExtension.lowercased()
            if ext != "gif" { break }
        } while idx != startIdx
        guard idx != startIdx, let targetIdx = model.files.firstIndex(where: { $0.url == nav[idx].url }) else { return }
        model.currentIndex = targetIdx
        model.resetRotation()
        model.loadCurrentImage()
        resetAutoAdvance()
    }

    // MARK: - Controls visibility

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }
        if controlsVisible { scheduleHideControls() }
    }

    private func scheduleHideControls() {
        guard !hoveringControls, !showSettings else { return }
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(controlsHideDelay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    controlsVisible = false
                }
            }
        }
    }

    private func resetAutoAdvance() {
        if !hoveringControls, !showSettings { scheduleHideControls() }
    }
}

// MARK: - Scroll wheel handler for slideshow navigation

private struct ScrollWheelHandler: NSViewRepresentable {
    let onPrevious: () -> Void
    let onNext: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollWheelCaptureView()
        view.onPrevious = onPrevious
        view.onNext = onNext
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ScrollWheelCaptureView else { return }
        view.onPrevious = onPrevious
        view.onNext = onNext
    }
}

private class ScrollWheelCaptureView: NSView {
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    private var horizontalAccumulator: CGFloat = 0

    override var acceptsFirstResponder: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        // Horizontal scroll only
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            horizontalAccumulator += event.scrollingDeltaX
            let threshold: CGFloat = 45
            if abs(horizontalAccumulator) >= threshold {
                if horizontalAccumulator > 0 { onPrevious?() } else { onNext?() }
                horizontalAccumulator = 0
            }
        }
    }
}
