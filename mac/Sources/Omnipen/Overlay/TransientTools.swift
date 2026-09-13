import AppKit
import OmnipenCore
import OmnipenRender

/// The laser and the spotlight, which follow the cursor and leave no ink.
///
/// Both live in Core Animation layers rather than in the canvas's `draw`, because
/// they update on every mouse move: repainting the ink underneath at that rate
/// would be wasteful, and the spotlight covers the whole display so its dirty
/// rect would be the entire screen.
@MainActor
final class TransientTools {

    private weak var host: NSView?

    private let dim = CALayer()
    private let dimMask = CAShapeLayer()
    private let trail = CAShapeLayer()
    private let dot = CAShapeLayer()

    private var trailPoints: [(point: CGPoint, time: TimeInterval)] = []
    private var fadeTimer: Timer?

    private var tool: ToolKind = .pen
    private var isActive = false
    private var color = InkColor(red: 1, green: 0, blue: 0)
    private var width = Settings.defaultStrokeWidth

    init(host: NSView) {
        self.host = host
        guard let layer = host.layer else { return }

        dim.backgroundColor = CGColor(gray: 0, alpha: Settings.spotlightDimAlpha)
        dim.isHidden = true
        dimMask.fillRule = .evenOdd
        dimMask.fillColor = CGColor(gray: 0, alpha: 1)
        dim.mask = dimMask

        trail.fillColor = nil
        trail.lineCap = .round
        trail.lineJoin = .round
        trail.isHidden = true

        dot.isHidden = true
        dot.shadowOpacity = 0.9
        dot.shadowRadius = 6
        dot.shadowOffset = .zero

        layer.addSublayer(dim)
        layer.addSublayer(trail)
        layer.addSublayer(dot)
    }

    /// Also how the canvas knows to ignore drags rather than lay down ink.
    var handlesCurrentTool: Bool { tool == .laser || tool == .spotlight }

    func update(tool: ToolKind, isArmed: Bool, color: InkColor, width: Double) {
        self.tool = tool
        self.color = color
        self.width = width
        self.isActive = isArmed && (tool == .laser || tool == .spotlight)

        guard isActive else {
            deactivate()
            return
        }

        dim.frame = host?.bounds ?? .zero
        dim.isHidden = tool != .spotlight
        trail.isHidden = tool != .laser
        dot.isHidden = tool != .laser

        let stroke = StrokeRenderer.cgColor(color, opaque: true)
        trail.strokeColor = stroke
        trail.lineWidth = max(3, width * 0.8)
        dot.backgroundColor = stroke
        dot.shadowColor = stroke

        // Pick up the cursor immediately, so switching tool does not require a
        // move before anything appears.
        if let point = currentCursorPoint() {
            cursorMoved(to: point)
        }
    }

    func deactivate() {
        isActive = false
        dim.isHidden = true
        trail.isHidden = true
        dot.isHidden = true
        trailPoints.removeAll()
        stopFading()
    }

    func cursorMoved(to point: CGPoint) {
        guard isActive else { return }

        switch tool {
        case .spotlight:
            let radius = Settings.spotlightRadius(forWidth: width)
            let path = CGMutablePath()
            path.addRect(dim.bounds)
            path.addEllipse(
                in: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            // Even-odd winding turns the circle into a hole in the dimming.
            dimMask.frame = dim.bounds
            dimMask.path = path

        case .laser:
            let size = Settings.laserDotDiameter(forWidth: width)
            dot.frame = CGRect(
                x: point.x - size / 2,
                y: point.y - size / 2,
                width: size,
                height: size
            )
            dot.cornerRadius = size / 2

            trailPoints.append((point, Date.timeIntervalSinceReferenceDate))
            startFading()
            refreshTrail()

        default:
            break
        }
    }

    private func refreshTrail() {
        let now = Date.timeIntervalSinceReferenceDate
        trailPoints.removeAll { now - $0.time > Settings.laserTrailDuration }

        guard trailPoints.count > 1 else {
            trail.path = nil
            return
        }

        let path = CGMutablePath()
        path.move(to: trailPoints[0].point)
        for entry in trailPoints.dropFirst() {
            path.addLine(to: entry.point)
        }
        trail.path = path

        // Fades as its newest point ages, so a stationary pointer settles to the
        // dot alone.
        let age = now - (trailPoints.last?.time ?? now)
        trail.opacity = Float(max(0, 1 - age / Settings.laserTrailDuration))
    }

    /// Runs only while a trail is still visible, so a parked laser costs nothing.
    private func startFading() {
        guard fadeTimer == nil else { return }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshTrail()
                if self.trailPoints.count <= 1 { self.stopFading() }
            }
        }
    }

    private func stopFading() {
        fadeTimer?.invalidate()
        fadeTimer = nil
    }

    private func currentCursorPoint() -> CGPoint? {
        guard let host, let window = host.window else { return nil }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let inView = host.convert(inWindow, from: nil)
        return host.bounds.contains(inView) ? inView : nil
    }
}
