import SwiftUI

/// RGB + luminance histogram with interactive channel toggle.
struct HistogramChartView: View {
    let histogram: Histogram
    let imageURL: URL

    @State private var soloChannel: SoloChannel? = nil

    enum SoloChannel: String, CaseIterable {
        case red, green, blue, luminance
    }

    private let binCount = Histogram.binCount

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chartBody
            channelToggles
        }
        .id(imageURL)
    }

    // MARK: - Chart

    private var chartBody: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Dark background panel
            Rectangle()
                .fill(Color.primary.opacity(0.12))

            // Pre-computed smoothed channel curves (single pass at compute time)
            let layers: [(values: [CGFloat], color: Color, key: SoloChannel)] = [
                (histogram.smoothLuminance, .white,      .luminance),
                (histogram.smoothBlue,      .blue,       .blue),
                (histogram.smoothGreen,     .green,      .green),
                (histogram.smoothRed,       .red,        .red),
            ]

            ForEach(layers, id: \.key) { ch in
                if soloChannel == nil || soloChannel == ch.key {
                    channelCurve(values: ch.values, color: ch.color, width: w, height: h)
                }
            }
        }
        .frame(height: 120)
    }

    // MARK: - Channel toggles

    private var channelToggles: some View {
        HStack(spacing: 8) {
            ForEach(Array(SoloChannel.allCases), id: \.self) { ch in
                let isSelected = soloChannel == ch
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        soloChannel = isSelected ? nil : ch
                    }
                }) {
                    Text(ch.label)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.15), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Drawing

    private func channelCurve(values: [CGFloat], color: Color, width: CGFloat, height: CGFloat) -> some View {
        let safe = max(values.max() ?? 0, 1)
        let step = width / CGFloat(binCount)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: height))

        // Draw area fill
        for i in 0..<binCount {
            let x = (CGFloat(i) + 0.5) * step
            let y = height - (values[i] / safe * height)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: width, y: height))
        path.closeSubpath()
        let fill = path.fill(color.opacity(0.2))

        // Draw top curve with smooth quadratic beziers
        var curve = Path()
        curve.move(to: CGPoint(x: (0.5) * step, y: height - (values[0] / safe * height)))

        for i in 1..<binCount {
            let x0 = (CGFloat(i - 1) + 0.5) * step
            let y0 = height - (values[i - 1] / safe * height)
            let x1 = (CGFloat(i) + 0.5) * step
            let y1 = height - (values[i] / safe * height)
            // Quadratic bezier: control point at midpoint between bins
            let mx = (x0 + x1) / 2
            curve.addQuadCurve(to: CGPoint(x: x1, y: y1), control: CGPoint(x: mx, y: y0))
        }
        let stroke = curve.stroke(color.opacity(0.7), lineWidth: 1)

        return ZStack { fill; stroke }
    }

}

// MARK: - Channel helpers

private extension HistogramChartView.SoloChannel {
    var label: String {
        switch self {
        case .red:       return "Red".localized
        case .green:     return "Green".localized
        case .blue:      return "Blue".localized
        case .luminance: return "Luminance".localized
        }
    }
}
