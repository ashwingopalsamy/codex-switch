import AppKit
import SwiftUI

@MainActor
@Observable
final class TooltipManager {
    struct TooltipItem: Equatable {
        let id: UUID
        let text: String
        let targetRect: CGRect
    }

    var activeTooltip: TooltipItem?

    func show(id: UUID, text: String, targetRect: CGRect) {
        activeTooltip = TooltipItem(id: id, text: text, targetRect: targetRect)
    }

    func hide(id: UUID) {
        if activeTooltip?.id == id {
            activeTooltip = nil
        }
    }
}

private struct TooltipManagerKey: EnvironmentKey {
    static let defaultValue: TooltipManager? = nil
}

extension EnvironmentValues {
    var tooltipManager: TooltipManager? {
        get { self[TooltipManagerKey.self] }
        set { self[TooltipManagerKey.self] = newValue }
    }
}

private struct TooltipAnchorReader: View {
    let onFrameChange: (CGRect) -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    onFrameChange(geo.frame(in: .named("instantTooltipWindow")))
                }
                .onChange(of: geo.frame(in: .named("instantTooltipWindow"))) { _, newFrame in
                    onFrameChange(newFrame)
                }
        }
    }
}

private struct TooltipPillView: View {
    let item: TooltipManager.TooltipItem
    let windowSize: CGSize
    @State private var pillSize: CGSize

    init(item: TooltipManager.TooltipItem, windowSize: CGSize) {
        self.item = item
        self.windowSize = windowSize
        _pillSize = State(initialValue: Self.estimatePillSize(for: item.text))
    }

    private static func estimatePillSize(for text: String) -> CGSize {
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(textSize.width) + 20, height: 22)
    }

    private var clampedPosition: CGPoint {
        let tw = pillSize.width
        let th = pillSize.height
        let margin: CGFloat = 12
        let topMargin: CGFloat = 12
        let gap: CGFloat = 6

        let minX = margin + tw / 2
        let maxX = max(minX, windowSize.width - margin - tw / 2)
        let clampedX = min(max(item.targetRect.midX, minX), maxX)

        let targetY: CGFloat
        if item.targetRect.minY - gap - th >= topMargin {
            // Above
            targetY = item.targetRect.minY - gap - th / 2
        } else {
            // Flip below
            targetY = item.targetRect.maxY + gap + th / 2
        }

        let maxCenterY = max(topMargin + th / 2, windowSize.height - margin - th / 2)
        let clampedY = min(max(targetY, topMargin + th / 2), maxCenterY)

        return CGPoint(x: clampedX, y: clampedY)
    }

    var body: some View {
        Text(item.text)
            .font(.system(.caption2, design: .rounded))
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(Color(nsColor: .darkGray).opacity(0.92))
                    .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)
            }
            .fixedSize()
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            pillSize = geo.size
                        }
                        .onChange(of: geo.size) { _, newSize in
                            pillSize = newSize
                        }
                }
            }
            .position(clampedPosition)
            .allowsHitTesting(false)
    }
}

struct TooltipContainerModifier: ViewModifier {
    @State private var manager = TooltipManager()

    func body(content: Content) -> some View {
        GeometryReader { windowGeo in
            ZStack(alignment: .topLeading) {
                content
                    .frame(width: windowGeo.size.width, height: windowGeo.size.height)
                    .environment(\.tooltipManager, manager)
                    .coordinateSpace(name: "instantTooltipWindow")

                if let active = manager.activeTooltip {
                    TooltipPillView(
                        item: active,
                        windowSize: windowGeo.size
                    )
                    .id(active.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(99999)
                }
            }
        }
    }
}

struct InstantTooltipModifier: ViewModifier {
    let text: String
    @Environment(\.tooltipManager) private var manager
    @State private var id = UUID()
    @State private var currentFrame: CGRect = .zero
    @State private var isHovered = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if let manager {
            content
                .background {
                    TooltipAnchorReader { frame in
                        currentFrame = frame
                        if isHovered {
                            manager.show(id: id, text: text, targetRect: frame)
                        }
                    }
                }
                .onHover { hovering in
                    isHovered = hovering
                    withAnimation(.easeOut(duration: 0.12)) {
                        if hovering {
                            manager.show(id: id, text: text, targetRect: currentFrame)
                        } else {
                            manager.hide(id: id)
                        }
                    }
                }
        } else {
            // Standalone / Preview fallback
            content
                .overlay(alignment: .top) {
                    if isHovered {
                        Text(text)
                            .font(.system(.caption2, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background {
                                Capsule()
                                    .fill(Color(nsColor: .darkGray).opacity(0.92))
                                    .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)
                            }
                            .fixedSize()
                            .offset(y: -28)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .allowsHitTesting(false)
                            .zIndex(100)
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHovered = hovering
                    }
                }
        }
    }
}

extension View {
    @ViewBuilder
    func instantTooltip(_ text: String) -> some View {
        if text.isEmpty {
            self
        } else {
            modifier(InstantTooltipModifier(text: text))
        }
    }

    func instantTooltipContainer() -> some View {
        modifier(TooltipContainerModifier())
    }
}
