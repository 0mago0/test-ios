//
//  DrawingHelpSheetView.swift
//  InkTrace
//

import SwiftUI

struct DrawingHelpSheetView: View {
    @Binding var showingHelp: Bool
    @Binding var hideInstructionsOnStartup: Bool
    @Binding var hasScrolledToBottom: Bool

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("GitHub 設定教學")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Group {
                            Text("1. 取得 Token")
                                .font(.headline)
                            Text("前往 GitHub Settings > Developer settings > Personal access tokens > Fine-grained tokens，產生新的 Token。")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Group {
                            Text("2. 設定權限")
                                .font(.headline)
                            Text("• Repository access: 選取 Only select repositories 並選擇您的儲存庫。\n• Permissions: 展開 Repository permissions，將 `Contents` 設為 `Read and write`。")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Group {
                            Text("3. 填寫資訊")
                                .font(.headline)
                            Text("點擊本 App 左上角的齒輪按鈕，填入 Owner (帳號)、Repo (倉庫名) 與 Token。")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("介面導覽")) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.gray)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("設定")
                                .font(.headline)
                            Text("設定 GitHub 連線資訊")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Image(systemName: "chart.bar.xaxis")
                            .foregroundColor(.gray)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("進度")
                                .font(.headline)
                            Text("查看蒐集進度與快速跳轉")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.gray)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("說明")
                                .font(.headline)
                            Text("顯示此操作說明頁面")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("操作說明")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "hand.draw")
                                .foregroundColor(.blue)
                            Text("書寫")
                                .font(.headline)
                        }
                        Text("在中央白色畫布區域手寫上方提示的文字。寫完後點擊「送出」會自動保存並跳至下一題。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.left.and.right.circle")
                                .foregroundColor(.green)
                            Text("選字")
                                .font(.headline)
                        }
                        Text("滑動上方的文字轉盤可以快速切換到想寫的字。點擊文字可以直接跳轉。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.orange)
                            Text("工具")
                                .font(.headline)
                        }
                        Text("下方控制列可調整筆畫粗細 (1-20) 和畫布縮放比例 (50-100%)。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.uturn.backward")
                                .foregroundColor(.orange)
                            Text("復原")
                                .font(.headline)
                        }
                        Text("寫錯了？按下「復原」按鈕可以回到上一步，逐筆撤銷筆畫。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("注意事項")) {
                    Label("請盡量將字寫在格線中央", systemImage: "squareshape.split.2x2.dotted")
                    Label("綠色字體代表已經寫過並上傳成功", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Label("若網路不穩，請先完成 GitHub 設定以確保資料同步", systemImage: "wifi.exclamationmark")
                    Label("建議筆畫粗細：有壓感 10pt 以下，無壓感 5pt 以下", systemImage: "scribble")
                    Label("若無壓感模式無法書寫，請多按幾下「清除」鍵重試", systemImage: "exclamationmark.triangle")
                }
                .onAppear {
                    hasScrolledToBottom = true
                }
            }
            .navigationTitle("使用說明")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Toggle("不再顯示此視窗", isOn: $hideInstructionsOnStartup)
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                            .font(.subheadline)

                        Spacer()

                        Button("知道了") {
                            showingHelp = false
                        }
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(hasScrolledToBottom ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .disabled(!hasScrolledToBottom)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .interactiveDismissDisabled(!hasScrolledToBottom)
    }
}
