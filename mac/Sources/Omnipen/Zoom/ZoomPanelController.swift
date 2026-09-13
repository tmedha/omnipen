import AppKit

/// Opens and tracks zoom panels. Several can be open at once, which is useful
/// for comparing two parts of a screen side by side.
@MainActor
final class ZoomPanelController {

    private let state: AppState
    private var panels: [ZoomPanel] = []

    init(state: AppState) {
        self.state = state
    }

    var hasOpenPanels: Bool { !panels.isEmpty }

    /// Captures a screen region and floats it as a magnified, annotatable panel.
    func present(region screenRect: CGRect) {
        Task {
            do {
                let image = try await ScreenCapture.image(of: screenRect)
                openPanel(image: image, region: screenRect)
            } catch {
                ScreenCapture.reportFailure(error)
            }
        }
    }

    private func openPanel(image: CGImage, region: CGRect) {
        let magnification = Settings.zoomMagnification(for: region)

        let panel = ZoomPanel(
            image: image,
            regionSize: region.size,
            origin: origin(for: region, magnification: magnification),
            magnification: magnification,
            state: state
        ) { [weak self] panel in
            self?.close(panel)
        }

        panels.append(panel)
        panel.orderFrontRegardless()
    }

    /// Centres the panel on the captured region, then nudges it fully on screen so
    /// a capture near an edge is not half off the display.
    private func origin(for region: CGRect, magnification: CGFloat) -> CGPoint {
        let size = CGSize(
            width: region.width * magnification,
            height: region.height * magnification + 24
        )
        var origin = CGPoint(
            x: region.midX - size.width / 2,
            y: region.midY - size.height / 2
        )

        let visible = NSScreen.screens
            .first { $0.frame.intersects(region) }?
            .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        return origin
    }

    private func close(_ panel: ZoomPanel) {
        panel.dismiss()
        panels.removeAll { $0 === panel }
    }

    /// Closes the most recent panel, which is what Esc should reach first.
    @discardableResult
    func closeTopmost() -> Bool {
        guard let panel = panels.last else { return false }
        close(panel)
        return true
    }

    func closeAll() {
        for panel in panels { panel.dismiss() }
        panels.removeAll()
    }
}
