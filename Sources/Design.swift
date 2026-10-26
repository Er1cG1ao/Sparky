import AppKit
import SwiftUI

private typealias DesignState<Value> = SwiftUI.State<Value>

// Small, shared native surfaces. Semantic colors adapt to the system appearance.
struct SparkySurface<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(contrast == .increased ? 0.32 : 0.08)))
    }
}

struct SparkySection<Content: View>: View {
    let title: String
    var footer: String = ""
    let content: Content
    init(_ title: String, footer: String = "", @ViewBuilder content: () -> Content) {
        self.title = title; self.footer = footer; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            SparkySurface { content }
            if !footer.isEmpty { Text(footer).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4) }
        }
    }
}

struct SparkyIcon: View {
    let symbol: String
    var color: Color = .orange
    var body: some View {
        Image(systemName: symbol).font(.system(size: 14, weight: .medium))
            .foregroundStyle(color).frame(width: 30, height: 30)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

struct SparkyMark: View {
    var size: CGFloat = 38
    private static let artwork = Bundle.main.url(forResource: "Sparky", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
    var body: some View {
        Group {
            if let artwork = Self.artwork { Image(nsImage: artwork).resizable().scaledToFit() }
            else { Image(systemName: "flame.fill").foregroundStyle(.orange) }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct SparkyEmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    let description: String
    let actions: Actions
    init(_ title: String, symbol: String, description: String, @ViewBuilder actions: () -> Actions) {
        self.title = title; self.symbol = symbol; self.description = description; self.actions = actions()
    }
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(title).font(.title3.weight(.semibold))
                Text(description).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 340)
            }
            actions
        }.padding(36).frame(maxWidth: .infinity)
    }
}

struct SparkyRowStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        RowBody(label: configuration.label, pressed: configuration.isPressed, selected: selected, enabled: enabled, reduceMotion: reduceMotion)
    }
    private struct RowBody: View {
        let label: ButtonStyleConfiguration.Label
        let pressed: Bool
        let selected: Bool
        let enabled: Bool
        let reduceMotion: Bool
        @Environment(\.colorSchemeContrast) private var contrast
        @DesignState private var hovered = false
        var body: some View {
            label.contentShape(Rectangle())
                .background(background, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected && contrast == .increased ? Color.orange : Color.clear))
                .opacity(enabled ? 1 : 0.5)
                .onHover { hovered = $0 }
                // Only hover color interpolates; press and keyboard selection are immediate.
                .animation(reduceMotion || pressed ? nil : .easeOut(duration: 0.12), value: hovered)
        }
        private var background: Color {
            if pressed && enabled { return Color.primary.opacity(0.12) }
            if selected { return Color.orange.opacity(0.12) }
            return hovered && enabled ? Color.primary.opacity(0.045) : .clear
        }
    }
}

// A real window backdrop, rather than blurring an opaque in-window surface.
struct SidebarBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = 0.88
        view.identifier = NSUserInterfaceItemIdentifier("sidebar.backdrop")
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { }
}
