import SwiftUI
import UIKit

/// 弹幕渲染层：用播放器时间轴做锚点，TimelineView 以 30fps 重绘
struct DanmakuOverlay: View {
    let comments: [DanmakuComment]
    let currentTime: Double      // 播放器每 0.25s 校时一次
    let isPlaying: Bool
    var fontSize: CGFloat = 15
    var opacity: Double = 0.9
    var scrollDuration: Double = 8

    @State private var layout = DanmakuLayout()
    @State private var anchorTime: Double = 0
    @State private var anchorDate = Date()

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let laneCount = max(3, Int((height * 0.55) / (fontSize + 8)))
            let items = layout.items(comments: comments,
                                     width: width,
                                     fontSize: fontSize,
                                     laneCount: laneCount,
                                     scrollDuration: scrollDuration)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let now = anchorTime + (isPlaying ? timeline.date.timeIntervalSince(anchorDate) : 0)
                ZStack(alignment: .topLeading) {
                    ForEach(items.filter { now >= $0.start && now <= $0.end }) { item in
                        Text(item.comment.text)
                            .font(.system(size: fontSize, weight: .medium))
                            .foregroundStyle(Color(uiColor: UIColor(hex: item.comment.colorHex) ?? .white))
                            .shadow(color: .black.opacity(0.75), radius: 1.5, x: 0, y: 0)
                            .fixedSize()
                            .position(x: xPosition(item: item, now: now, width: width),
                                      y: yPosition(item: item, height: height))
                    }
                }
                .frame(width: width, height: height, alignment: .topLeading)
            }
            .opacity(opacity)
            .onChange(of: currentTime) { newValue in
                // 用播放器时间纠正本地锚点，避免长时间漂移
                anchorTime = newValue
                anchorDate = Date()
            }
            .onAppear {
                anchorTime = currentTime
                anchorDate = Date()
            }
            .clipped()
        }
    }

    private func xPosition(item: DanmakuLayout.PositionedComment, now: Double, width: CGFloat) -> CGFloat {
        switch item.comment.mode {
        case .scroll:
            let duration = max(1, item.end - item.start)
            let progress = max(0, min(1, (now - item.start) / duration))
            let travel = width + item.comment.width
            return width - progress * travel + item.comment.width / 2
        case .top, .bottom:
            return item.x + item.comment.width / 2
        }
    }

    private func yPosition(item: DanmakuLayout.PositionedComment, height: CGFloat) -> CGFloat {
        if item.comment.mode == .bottom {
            let lane = CGFloat(item.comment.lane)
            return height - 24 - lane * (fontSize + 8) - fontSize / 2
        }
        return item.y + fontSize / 2
    }
}
