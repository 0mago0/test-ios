//
//  ToastView.swift
//  a
//
//  Toast 提示訊息 View
//

import SwiftUI

// MARK: - Toast Message Type
enum ToastType {
    case success
    case error
}

// MARK: - Toast View
struct ToastView: View {
    let message: String
    let type: ToastType
    
    var themeColor: Color {
        type == .success ? Color.blue : Color.red
    }
    
    var iconName: String {
        type == .success ? "checkmark" : "exclamationmark"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 圖標圓圈
            ZStack {
                Circle()
                    .fill(themeColor)
                    .frame(width: 24, height: 24)
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // 文字內容
            VStack(alignment: .leading, spacing: 2) {
                Text(type == .success ? "Success" : "Error")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black.opacity(0.8))
                
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.black.opacity(0.6))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .background(
            ZStack(alignment: .leading) {
                themeColor.opacity(0.12)
                Rectangle()
                    .fill(themeColor)
                    .frame(width: 5)
            }
        )
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    VStack(spacing: 20) {
        ToastView(message: "已成功上傳", type: .success)
        ToastView(message: "上傳失敗，請重試", type: .error)
    }
    .padding()
}
