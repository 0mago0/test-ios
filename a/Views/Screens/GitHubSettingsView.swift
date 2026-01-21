//
//  GitHubSettingsView.swift
//  a
//
//  GitHub 設定頁面
//

import SwiftUI

/// GitHub 與字庫來源設定頁面
struct GitHubSettingsView: View {
    @AppStorage(GHKeys.owner)  private var owner: String = ""
    @AppStorage(GHKeys.repo)   private var repo: String = ""
    @AppStorage(GHKeys.branch) private var branch: String = "main"
    @AppStorage(GHKeys.prefix) private var prefix: String = "handwriting"

    @State private var token: String = KeychainHelper.read(key: GHKeys.tokenK) ?? ""
    @Environment(\.dismiss) private var dismiss
    @State private var showSaved = false
    
    // 字庫網址相關
    @StateObject private var characterLoader = CharacterLoader.shared
    @State private var characterURL: String = CharacterLoader.shared.savedURL
    @State private var isLoadingCharacters = false
    @State private var loadResult: String? = nil
    @State private var loadResultIsError = false
    
    var body: some View {
        NavigationView {
            Form {
                // 字庫來源設定
                Section(header: Text("字庫來源")) {
                    TextField("字庫 TXT 網址", text: $characterURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    
                    HStack {
                        Button(action: loadCharactersFromURL) {
                            if isLoadingCharacters {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Text("從網址載入")
                            }
                        }
                        .disabled(isLoadingCharacters)
                        
                        Spacer()
                        
                        Button("恢復預設") {
                            characterLoader.resetToDefault()
                            characterURL = ""
                            loadResult = "已恢復為預設字庫"
                            loadResultIsError = false
                        }
                        .foregroundColor(.orange)
                    }
                    
                    if let result = loadResult {
                        Text(result)
                            .font(.footnote)
                            .foregroundColor(loadResultIsError ? .red : .green)
                    }
                    
                    Text("目前字庫：\(characterLoader.loadedText.count) 字")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    Text("輸入 .txt 檔案的網址，內容應為純文字漢字。留空則使用預設字庫。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Repository")) {
                    TextField("Owner（使用者或組織）", text: $owner)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Repo 名稱", text: $repo)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Branch（預設 main）", text: $branch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("路徑前綴（可留空）", text: $prefix)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(header: Text("認證")) {
                    SecureField("GitHub Token (需 repo 權限)", text: $token)
                    Text("建議使用 Fine-grained Token，對目標 repo 開啟 contents:write 權限。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        KeychainHelper.save(key: GHKeys.tokenK, value: token)
                        showSaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            dismiss()
                        }
                    }
                }
            }
            .alert("已儲存", isPresented: $showSaved) {
                Button("OK", role: .cancel) {}
            }
        }
    }
    
    private func loadCharactersFromURL() {
        isLoadingCharacters = true
        loadResult = nil
        
        characterLoader.loadFromURL(characterURL) { success, errorMessage in
            isLoadingCharacters = false
            if success {
                loadResult = "載入成功！共 \(characterLoader.loadedText.count) 字"
                loadResultIsError = false
            } else {
                loadResult = errorMessage ?? "載入失敗"
                loadResultIsError = true
            }
        }
    }
}

#Preview {
    GitHubSettingsView()
}
