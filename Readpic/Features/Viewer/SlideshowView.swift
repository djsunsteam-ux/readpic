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
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var currentImage: CGImage?
    @State private var imageOpacity: Double = 1

    private let controlsHideDelay: TimeInterval = 2.5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Image
                if let img = currentImage {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .opacity(imageOpacity)
                        .animation(model.slideshowTransition.animation, value: imageOpacity)
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
        }
        .onAppear {
            loadCurrentSlideImage()
            scheduleHideControls()
        }
        .onDisappear {
            hideControlsTask?.cancel()
        }
    }

    // MARK: - Controls

    private var controlsBar: some View {
        HStack(spacing: 16) {
            // Exit
            Button { model.stopSlideshow() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("Exit slideshow (Esc)")

            Divider()
                .frame(height: 20)

            // Previous
            Button { slideshowPrevious() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("Previous")

            // Play / Pause
            Button { togglePlayPause() } label: {
                Image(systemName: model.isAnimationPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(.white.opacity(0.15), in: Circle())
            .help(model.isAnimationPaused ? "Resume" : "Pause")

            // Next
            Button { slideshowNext() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("Next")

            // Current position
            if let url = model.currentFile?.url,
               let idx = model.navigableFiles.firstIndex(where: { $0.url == url }) {
                Text("\(idx + 1) / \(model.navigableFiles.count)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 4)
            }

            Spacer()

            // Settings
            Button { showSettings.toggle() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .popover(isPresented: $showSettings) {
                settingsPanel
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Settings panel

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
                Slider(value: speedBinding, in: 1...10, step: 1)
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
        let interval = model.slideshowInterval
        if interval < 2 { return "Fast" }
        if interval < 4 { return "Normal" }
        if interval < 7 { return "Slow" }
        return "Very Slow"
    }

    /// Map slider value (1-10) to interval (1s-10s).
    private var speedBinding: Binding<Double> {
        Binding(
            get: { model.slideshowInterval },
            set: { model.slideshowInterval = $0 }
        )
    }

    // MARK: - Actions

    private func togglePlayPause() {
        model.isAnimationPaused.toggle()
        if !model.isAnimationPaused {
            // Resuming — schedule next advance
        }
    }

    private func slideshowPrevious() {
        let nav = model.navigableFiles
        guard nav.count > 1, let url = model.currentFile?.url,
              var idx = nav.firstIndex(where: { $0.url == url })
        else { return }
        let startIdx = idx
        repeat {
            idx = (idx - 1 + nav.count) % nav.count
            let ext = nav[idx].url.pathExtension.lowercased()
            if ext != "gif" { break }
        } while idx != startIdx
        guard idx != startIdx, let targetIdx = model.files.firstIndex(where: { $0.url == nav[idx].url }) else { return }
        model.currentIndex = targetIdx
        model.resetRotation()
        model.loadCurrentImage()
        loadCurrentSlideImage()
        resetAutoAdvance()
    }

    private func slideshowNext() {
        let nav = model.navigableFiles
        guard nav.count > 1, let url = model.currentFile?.url,
              var idx = nav.firstIndex(where: { $0.url == url })
        else { return }
        let startIdx = idx
        repeat {
            idx = (idx + 1) % nav.count
            let ext = nav[idx].url.pathExtension.lowercased()
            if ext != "gif" { break }
        } while idx != startIdx
        guard idx != startIdx, let targetIdx = model.files.firstIndex(where: { $0.url == nav[idx].url }) else { return }
        model.currentIndex = targetIdx
        model.resetRotation()
        model.loadCurrentImage()
        loadCurrentSlideImage()
        resetAutoAdvance()
    }

    private func loadCurrentSlideImage() {
        // Use the decoded image from the viewer model
        if let img = model.decodedImage?.image {
            currentImage = img
        }
    }

    // MARK: - Controls visibility

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            scheduleHideControls()
        }
    }

    private func scheduleHideControls() {
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
        // Re-schedule the auto-advance from the model's slideshow task
        // The model handles this via slideshowTask
        scheduleHideControls()
    }
}
