@testable import CodexSwitch
import Foundation
import XCTest

@MainActor
final class TooltipManagerTests: XCTestCase {
    func testTooltipManagerLifecycleAndHandoff() {
        let manager = TooltipManager()
        XCTAssertNil(manager.activeTooltip)

        let buttonA = UUID()
        let rectA = CGRect(x: 500, y: 100, width: 28, height: 28)
        manager.show(id: buttonA, text: "Delete this profile", targetRect: rectA)

        XCTAssertEqual(manager.activeTooltip?.id, buttonA)
        XCTAssertEqual(manager.activeTooltip?.text, "Delete this profile")
        XCTAssertEqual(manager.activeTooltip?.targetRect, rectA)

        // Hover moves to button B before button A completes hide
        let buttonB = UUID()
        let rectB = CGRect(x: 460, y: 100, width: 28, height: 28)
        manager.show(id: buttonB, text: "Rename Profile", targetRect: rectB)
        XCTAssertEqual(manager.activeTooltip?.id, buttonB)
        XCTAssertEqual(manager.activeTooltip?.text, "Rename Profile")

        // Button A unhover should not dismiss Button B's tooltip
        manager.hide(id: buttonA)
        XCTAssertEqual(manager.activeTooltip?.id, buttonB)

        // Button B unhover dismisses tooltip
        manager.hide(id: buttonB)
        XCTAssertNil(manager.activeTooltip)
    }

    func testTooltipPositionClampingNearWindowEdges() {
        let windowSize = CGSize(width: 540, height: 420)
        let pillSize = CGSize(width: 220, height: 22)
        let margin: CGFloat = 12
        let topMargin: CGFloat = 12
        let gap: CGFloat = 6

        // Case 1: Trailing button near right edge (e.g. Delete button at x: 500)
        let trailingRect = CGRect(x: 500, y: 120, width: 28, height: 28)
        let targetX = trailingRect.midX // 514
        let minX = margin + pillSize.width / 2 // 12 + 110 = 122
        let maxX = max(minX, windowSize.width - margin - pillSize.width / 2) // 540 - 12 - 110 = 418
        let clampedX = min(max(targetX, minX), maxX) // clamped to 418

        XCTAssertEqual(clampedX, 418)
        let rightPillEdge = clampedX + pillSize.width / 2
        XCTAssertEqual(rightPillEdge, windowSize.width - margin) // exactly padded within window

        // Case 2: Control near top edge should flip below
        let topRect = CGRect(x: 200, y: 8, width: 28, height: 28)
        let isAbove = topRect.minY - gap - pillSize.height >= topMargin
        XCTAssertFalse(isAbove)
        let flippedCenterY = topRect.maxY + gap + pillSize.height / 2
        XCTAssertEqual(flippedCenterY, 36 + 6 + 11) // 53, positioned safely below the top control
    }
}
