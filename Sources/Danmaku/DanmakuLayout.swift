import SwiftUI
import UIKit

/// 弹幕布局：按轨道分配，滚动弹幕用「前一条尾部离屏时间」判断轨道是否空闲
final class DanmakuLayout {
    private var cacheKey = ""
    private var positioned: [PositionedComment] = []

    struct PositionedComment: Identifiable {
        let id: UUID
        let comment: DanmakuComment
        let x: CGFloat
        let y: CGFloat
        let start: Double
        let end: Double
    }

    func items(comments: [DanmakuComment],
               width: CGFloat,
               fontSize: CGFloat,
               laneCount: Int,
               scrollDuration: Double) -> [PositionedComment] {
        guard width > 0, !comments.isEmpty else { return [] }
        let key = "\(comments.count)|\(comments.first?.text ?? "")|\(comments.last?.text ?? "")|\(Int(width))|\(Int(fontSize))|\(laneCount)|\(Int(scrollDuration * 10))"
        if key == cacheKey { return positioned }

        let lineHeight = fontSize + 8
        var scrollFree = [Double](repeating: 0, count: laneCount)
        var topLane = 0
        var bottomLane = 0
        var result: [PositionedComment] = []

        for original in comments.sorted(by: { $0.time < $1.time }) {
            var comment = original
            let textWidth = (comment.text as NSString)
                .size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize, weight: .medium)])
                .width
            comment.width = textWidth

            switch comment.mode {
            case .scroll:
                let lane = pickLane(&scrollFree, time: comment.time, width: textWidth, screen: width, duration: scrollDuration, laneCount: laneCount)
                comment.lane = lane
                let y = 8 + CGFloat(lane) * lineHeight
                result.append(PositionedComment(id: comment.id,
                                                comment: comment,
                                                x: 0,
                                                y: y,
                                                start: comment.time,
                                                end: comment.time + scrollDuration))
            case .top:
                comment.lane = topLane % max(1, laneCount)
                topLane += 1
                result.append(PositionedComment(id: comment.id,
                                                comment: comment,
                                                x: (width - textWidth) / 2,
                                                y: 8 + CGFloat(comment.lane) * lineHeight,
                                                start: comment.time,
                                                end: comment.time + 4))
            case .bottom:
                comment.lane = bottomLane % max(1, laneCount)
                bottomLane += 1
                result.append(PositionedComment(id: comment.id,
                                                comment: comment,
                                                x: (width - textWidth) / 2,
                                                y: -1,   // 渲染时按屏幕高度计算
                                                start: comment.time,
                                                end: comment.time + 4))
            }
        }

        positioned = result
        cacheKey = key
        return result
    }

    private func pickLane(_ free: inout [Double],
                          time: Double,
                          width: CGFloat,
                          screen: CGFloat,
                          duration: Double,
                          laneCount: Int) -> Int {
        var candidate = -1
        for lane in 0..<laneCount where free[lane] <= time {
            candidate = lane
            break
        }
        if candidate < 0 {
            var bestLane = 0
            var bestTime = Double.greatestFiniteMagnitude
            for lane in 0..<laneCount where free[lane] < bestTime {
                bestTime = free[lane]
                bestLane = lane
            }
            candidate = bestLane
        }

        let speed = (screen + width) / max(1, duration)      // px / 秒
        free[candidate] = max(free[candidate], time) + (width + 24) / max(1, speed)
        return candidate
    }
}
