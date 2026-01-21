//
//  Crosshair.swift
//  InkTrace
//
//  畫布十字線輔助線 View
//

import SwiftUI

/// 十字虛線輔助線，用於中心對齊參考
struct Crosshair: View {
    var size: CGSize
    var lineColor: Color = Color(UIColor.systemGray3)
    var lineWidth: CGFloat = 1
    var dash: [CGFloat] = [6, 6]

    var body: some View {
        Canvas { ctx, sz in
            let w = size.width
            let h = size.height
            
            // 水平線
            var hPath = Path()
            hPath.move(to: CGPoint(x: 0, y: h / 2))
            hPath.addLine(to: CGPoint(x: w, y: h / 2))
            
            // 垂直線
            var vPath = Path()
            vPath.move(to: CGPoint(x: w / 2, y: 0))
            vPath.addLine(to: CGPoint(x: w / 2, y: h))

            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dash)
            ctx.stroke(hPath, with: .color(lineColor), style: style)
            ctx.stroke(vPath, with: .color(lineColor), style: style)

            // 虛線同心方框
            let center = CGPoint(x: w/2, y: h/2)
            let sizes: [CGFloat] = [150, 225]
            for s in sizes {
                var sq = Path()
                let origin = CGPoint(x: center.x - s/2, y: center.y - s/2)
                sq.addRect(CGRect(x: origin.x, y: origin.y, width: s, height: s))
                ctx.stroke(sq, with: .color(lineColor), style: style)
            }
        }
        .allowsHitTesting(false)
    }
}
