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
    
    @Environment(\.colorScheme) var colorScheme
    
    var themeColor: Color {
        type == .success ? Color.blue : Color.red
    }
    
    var iconName: String {
        type == .success ? "checkmark" : "exclamationmark"
    }
    
    var titleTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.8)
    }
    
    var messageTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.6)
    }
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color(UIColor.systemGray6) : themeColor.opacity(0.12)
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
                    .foregroundColor(titleTextColor)
                
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(messageTextColor)
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
                backgroundColor
                Rectangle()
                    .fill(themeColor)
                    .frame(width: 5)
            }
        )
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 2)
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
