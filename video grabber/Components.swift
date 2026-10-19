//
//  Components.swift
//  My Videos
//

import SwiftUI
import AppKit

// MARK: - Brand

enum Brand {
    static let indigo = Color(red: 0.38, green: 0.40, blue: 0.95)
}

/// The app's mark, drawn in SwiftUI so it matches the app icon at any size.
struct AppGlyph: View {
    var size: CGFloat

    private var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
    }

    var body: some View {
        ZStack {
            tile.fill(
                LinearGradient(colors: [Color(red: 0.20, green: 0.21, blue: 0.27),
                                        Color(red: 0.07, green: 0.07, blue: 0.10)],
                               startPoint: .top, endPoint: .bottom)
            )
            // A whisper of indigo glowing up from behind the play mark.
            tile.fill(
                RadialGradient(colors: [Brand.indigo.opacity(0.38), .clear],
                               center: .center, startRadius: 0, endRadius: size * 0.51)
            )
            tile.fill(
                LinearGradient(colors: [.white.opacity(0.10), .clear],
                               startPoint: .top, endPoint: .center)
            )
            tile.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: max(0.5, size * 0.005)
            )
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.40, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [.white, Color(red: 0.84, green: 0.86, blue: 0.93)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .offset(x: size * 0.032)
                .shadow(color: Color(red: 0.35, green: 0.38, blue: 1.0).opacity(0.45), radius: size * 0.05)
                .shadow(color: .black.opacity(0.35), radius: size * 0.022, y: size * 0.012)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: size * 0.12, y: size * 0.06)
        .accessibilityHidden(true)
    }
}

/// A faint indigo glow at the top of the window, echoing the app icon.
struct WindowBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RadialGradient(colors: [Brand.indigo.opacity(scheme == .dark ? 0.14 : 0.07), .clear],
                       center: .top, startRadius: 0, endRadius: 560)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

// MARK: - Grouped cards (System Settings style)

/// A titled, rounded group of rows separated by inset hairlines.
struct FormCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.element.id) { index, subview in
                        if index > 0 {
                            Divider().padding(.leading, 46)
                        }
                        subview
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
            if let footer {
                Text(footer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// One row inside a FormCard: colored icon tile + label on the left, control on the right.
struct FormRow<Trailing: View>: View {
    let title: String
    let systemImage: String
    let color: Color
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }
}

/// White SF Symbol on a small gradient rounded square, as in System Settings.
struct IconTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(color.gradient)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Notice banner

struct NoticeBanner<Actions: View>: View {
    let systemImage: String
    let tint: Color
    let title: String
    var message: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(tint.opacity(0.08)), in: .rect(cornerRadius: 16, style: .continuous))
        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
    }
}

// MARK: - Thumbnails

/// A 16:9 remote thumbnail with a graceful placeholder.
struct Thumbnail: View {
    let url: URL?
    var isAudio = false
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            Image(systemName: isAudio ? "music.note" : "play.rectangle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.tertiary)
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .accessibilityHidden(true)
    }
}

// MARK: - Range slider (clip)

/// A QuickTime-trim–style range slider with two draggable handles.
struct RangeSlider: View {
    @Binding var lower: Double
    @Binding var upper: Double
    let bounds: ClosedRange<Double>
    var minimumSpan: Double = 1

    private let handle: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let track = max(geo.size.width - handle, 1)
            let span = max(bounds.upperBound - bounds.lowerBound, 0.001)
            let x = { (v: Double) -> CGFloat in CGFloat((v - bounds.lowerBound) / span) * track }
            let value = { (px: CGFloat) -> Double in
                bounds.lowerBound + Double(min(max(px - handle / 2, 0), track) / track) * span
            }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 6)
                    .padding(.horizontal, handle / 2)
                Capsule()
                    .fill(Color.accentColor.gradient)
                    .frame(width: max(x(upper) - x(lower), 0), height: 6)
                    .offset(x: x(lower) + handle / 2)
                knob
                    .offset(x: x(lower))
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("range"))
                        .onChanged { g in lower = min(value(g.location.x), upper - minimumSpan) })
                    .accessibilityElement()
                    .accessibilityLabel("Start")
                    .accessibilityValue(Timecode.string(lower))
                    .accessibilityAdjustableAction { direction in
                        lower = direction == .increment ? min(lower + 1, upper - minimumSpan) : max(lower - 1, bounds.lowerBound)
                    }
                knob
                    .offset(x: x(upper))
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("range"))
                        .onChanged { g in upper = max(value(g.location.x), lower + minimumSpan) })
                    .accessibilityElement()
                    .accessibilityLabel("End")
                    .accessibilityValue(Timecode.string(upper))
                    .accessibilityAdjustableAction { direction in
                        upper = direction == .increment ? min(upper + 1, bounds.upperBound) : max(upper - 1, lower + minimumSpan)
                    }
            }
            .coordinateSpace(.named("range"))
            .frame(maxHeight: .infinity)
        }
        .frame(height: handle + 6)
    }

    private var knob: some View {
        Circle()
            .fill(.white)
            .frame(width: handle, height: handle)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.08)))
    }
}

/// A small text field that edits a time in "m:ss" and commits on Return or blur.
struct TimecodeField: View {
    @Binding var seconds: Double
    let range: ClosedRange<Double>
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0:00", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .frame(width: 76)
            .focused($focused)
            .onAppear { text = Timecode.string(seconds) }
            .onChange(of: seconds) { if !focused { text = Timecode.string(seconds) } }
            .onChange(of: focused) { if !focused { commit() } }
            .onSubmit(commit)
    }

    private func commit() {
        if let value = Timecode.parse(text) {
            seconds = min(max(value, range.lowerBound), range.upperBound)
        }
        text = Timecode.string(seconds)
    }
}

// MARK: - Misc

extension View {
    /// Opens Finder with the given files selected.
    func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

enum SystemSettings {
    nonisolated static func openAutomation() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
