//
//  StrokePoint.swift
//  InkTrace
//
//  筆畫點資料模型
//

import Foundation
import CoreGraphics

/// 繪圖筆畫點，包含位置與壓力資訊
struct StrokePoint {
    var point: CGPoint
    var force: CGFloat
}
