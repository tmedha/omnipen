import CoreGraphics
import Foundation
import Testing

@testable import OmnipenCore

@Suite("Smoothing")
struct SmoothingTests {

    @Test("simplify drops points inside the threshold")
    func simplifyThins() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0.2, y: 0),     // too close, dropped
            CGPoint(x: 0.4, y: 0),     // too close, dropped
            CGPoint(x: 10, y: 0),
        ]
        let result = Smoothing.simplify(points, minimumDistance: 1.5)
        #expect(result == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)])
    }

    @Test("simplify preserves the true endpoint")
    func simplifyKeepsEndpoint() {
        // The final point is within the threshold of its predecessor; without the
        // endpoint fix-up the stroke would visibly stop short of the lift-off.
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10.5, y: 0),
        ]
        let result = Smoothing.simplify(points, minimumDistance: 1.5)
        #expect(result.last == CGPoint(x: 10.5, y: 0))
    }

    @Test("simplify handles empty and single-point input")
    func simplifyDegenerate() {
        #expect(Smoothing.simplify([]).isEmpty)
        #expect(Smoothing.simplify([CGPoint(x: 3, y: 3)]) == [CGPoint(x: 3, y: 3)])
    }

    @Test("a tap becomes a zero-length segment the renderer can cap into a dot")
    func singlePointPath() {
        let path = Smoothing.path(for: [CGPoint(x: 5, y: 5)])
        #expect(path == [.move(CGPoint(x: 5, y: 5)), .line(CGPoint(x: 5, y: 5))])
    }

    @Test("two points stay a straight line")
    func twoPointPath() {
        let path = Smoothing.path(for: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)])
        #expect(path == [.move(CGPoint(x: 0, y: 0)), .line(CGPoint(x: 10, y: 0))])
    }

    @Test("interior points become control points, midpoints become anchors")
    func midpointSmoothing() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 20, y: 0),
        ]
        let path = Smoothing.path(for: points)

        #expect(path.count == 3)
        #expect(path[0] == .move(CGPoint(x: 0, y: 0)))
        // First curve ends at the midpoint of p1 and p2, controlled by p1.
        #expect(path[1] == .quad(to: CGPoint(x: 15, y: 5), control: CGPoint(x: 10, y: 10)))
        // Final leg runs out to the real endpoint.
        #expect(path[2] == .quad(to: CGPoint(x: 20, y: 0), control: CGPoint(x: 10, y: 10)))
    }

    @Test("the path always terminates on the last recorded point")
    func pathEndsOnLastPoint() {
        let points = (0..<20).map { CGPoint(x: Double($0) * 7, y: sin(Double($0)) * 30) }
        let path = Smoothing.path(for: points)

        let terminal: CGPoint? = switch path.last {
        case .move(let p), .line(let p): p
        case .quad(let to, _): to
        case nil: nil
        }
        #expect(terminal == points.last)
    }
}
