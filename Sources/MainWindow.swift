import AppKit

@MainActor
final class SparkyMainWindow: NSWindow {
    static let minimumContentSize = NSSize(width: 940, height: 760)
    private var enforcesMinimum = false
    private var controlsInstalled = false
    private var positioningControls = false
    private var minimizing = false
    private var heightZoomRestoreFrame: NSRect?
    private var heightZoomTargetFrame: NSRect?

    func configureWindowRules() {
        collectionBehavior.remove([.fullScreenPrimary, .fullScreenAuxiliary, .fullScreenAllowsTiling])
        collectionBehavior.insert([.fullScreenNone, .fullScreenDisallowsTiling])
        contentMinSize = Self.minimumContentSize
        minSize = frameRect(forContentRect: NSRect(origin: .zero, size: Self.minimumContentSize)).size
        enforcesMinimum = true
        configureHeightZoomControl()
    }

    func installWindowControls() {
        guard !controlsInstalled else { return }
        controlsInstalled = true
        positionWindowControls()
    }

    func positionWindowControls() {
        guard controlsInstalled, !positioningControls, !minimizing, !isMiniaturized else { return }
        positioningControls = true
        defer { positioningControls = false }
        contentView?.superview?.layoutSubtreeIfNeeded()
        for (type, x) in [(NSWindow.ButtonType.closeButton, CGFloat(18)), (.miniaturizeButton, CGFloat(38)), (.zoomButton, CGFloat(58))] {
            guard let button = standardWindowButton(type), let parent = button.superview else { continue }
            let point = parent.convert(NSPoint(x: x, y: frame.height - 18 - button.frame.height), from: nil)
            if abs(button.frame.minX - point.x) > 0.1 || abs(button.frame.minY - point.y) > 0.1 { button.setFrameOrigin(point) }
        }
        configureHeightZoomControl()
    }

    func constrainedFrameSize(_ proposed: NSSize) -> NSSize {
        guard enforcesMinimum, !minimizing, !isMiniaturized else { return proposed }
        let required = frameRect(forContentRect: NSRect(origin: .zero, size: Self.minimumContentSize)).size
        return NSSize(width: max(required.width, proposed.width), height: max(required.height, proposed.height))
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        rect.size = constrainedFrameSize(rect.size)
        rect.origin.y = frameRect.maxY - rect.height
        super.setFrame(rect, display: flag)
        positionWindowControls()
    }
    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate: Bool) {
        var rect = frameRect
        rect.size = constrainedFrameSize(rect.size)
        rect.origin.y = frameRect.maxY - rect.height
        super.setFrame(rect, display: flag, animate: animate)
        positionWindowControls()
    }
    override func setContentSize(_ size: NSSize) {
        let bounded = enforcesMinimum && !minimizing && !isMiniaturized ? NSSize(width: max(Self.minimumContentSize.width, size.width), height: max(Self.minimumContentSize.height, size.height)) : size
        super.setContentSize(bounded)
        positionWindowControls()
    }
    override func miniaturize(_ sender: Any?) {
        minimizing = true
        super.miniaturize(sender)
        minimizing = false
    }
    override func deminiaturize(_ sender: Any?) {
        super.deminiaturize(sender)
        minimizing = false
        positionWindowControls()
    }
    private var isHeightZoomed: Bool {
        guard heightZoomRestoreFrame != nil, let target = heightZoomTargetFrame else { return false }
        return abs(frame.height - target.height) < 1
    }
    override var isZoomed: Bool { isHeightZoomed }

    private func configureHeightZoomControl() {
        guard let button = standardWindowButton(.zoomButton) else { return }
        button.isHidden = false; button.isEnabled = true
        button.target = self; button.action = #selector(NSWindow.performZoom(_:))
        button.toolTip = isHeightZoomed ? "恢复窗口高度" : "拉高窗口"
        button.setAccessibilityLabel(button.toolTip)
    }

    private func toggleHeightZoom() {
        guard let workArea = screen?.visibleFrame,
              workArea.height >= constrainedFrameSize(.zero).height else { return }
        if isHeightZoomed, let previous = heightZoomRestoreFrame {
            heightZoomRestoreFrame = nil; heightZoomTargetFrame = nil
            var restored = frame
            restored.size.height = min(previous.height, workArea.height)
            restored.origin.y = min(max(previous.minY, workArea.minY), workArea.maxY - restored.height)
            setFrame(restored, display: true)
        } else {
            heightZoomRestoreFrame = frame
            var expanded = frame
            expanded.origin.y = workArea.minY; expanded.size.height = workArea.height
            heightZoomTargetFrame = expanded
            setFrame(expanded, display: true)
        }
    }
    override func toggleFullScreen(_ sender: Any?) { }
    override func zoom(_ sender: Any?) { toggleHeightZoom() }
    override func performZoom(_ sender: Any?) { toggleHeightZoom() }
}

