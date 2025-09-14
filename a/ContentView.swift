import SwiftUI
import UIKit
import Security

// MARK: - Keychain helper & keys
enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
}

enum GHKeys {
    static let owner  = "GH_OWNER"
    static let repo   = "GH_REPO"
    static let branch = "GH_BRANCH"
    static let prefix = "GH_PATH_PREFIX"
    static let tokenK = "GH_TOKEN"
}

struct DrawingView: View {
    @State private var points: [CGPoint] = []
    @State private var paths: [[CGPoint]] = []
    @State private var showingShareSheet = false
    @State private var exportURL: URL? = nil
    @State private var questionBank: [String] = []
    @State private var currentIndex: Int = UserDefaults.standard.integer(forKey: "CurrentIndex") // 讀取存檔
    @AppStorage(GHKeys.owner)  private var ghOwner: String = ""
    @AppStorage(GHKeys.repo)   private var ghRepo: String = ""
    @AppStorage(GHKeys.branch) private var ghBranch: String = "main"
    @AppStorage(GHKeys.prefix) private var ghPrefix: String = "handwriting"
    @State private var showingSettings = false
    @State private var showUploadHint = false

    var targetText: String {
        guard !questionBank.isEmpty else { return "題庫載入中..." }
        return "請仿寫：" + questionBank[currentIndex]
    }

    init() {
        self._questionBank = State(initialValue: commonChineseCharacters2500.map { String($0) })
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // 上方 1/3：顯示要書寫的文字
                ZStack {
                    Color(UIColor.systemGroupedBackground)
                    Text(targetText)
                        .font(.system(size: 28, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .frame(height: geo.size.height / 3)

                // 下方 2/3：畫布 + 控制列
                VStack(spacing: 0) {
                    ZStack {
                        Color.white
                        Path { path in
                            for stroke in paths {
                                if let first = stroke.first {
                                    path.move(to: first)
                                    for p in stroke.dropFirst() {
                                        path.addLine(to: p)
                                    }
                                }
                            }
                            if let first = points.first {
                                path.move(to: first)
                                for p in points.dropFirst() {
                                    path.addLine(to: p)
                                }
                            }
                        }
                        .stroke(Color.black, lineWidth: 2)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                points.append(value.location)
                            }
                            .onEnded { _ in
                                paths.append(points)
                                points.removeAll()
                            }
                    )

                    // 控制按鈕列
                    HStack {
                        Button("清除") {
                            points.removeAll()
                            paths.removeAll()
                        }
                        Spacer()
                        Button("設定") {
                            // 若分享面板尚未關閉，先關閉以避免同時存在兩個 sheet 導致無法彈出
                            if showingShareSheet { showingShareSheet = false }
                            print("[UI] Settings tapped")
                            DispatchQueue.main.async {
                                showingSettings = true
                            }
                        }
                        Button("匯出SVG") {
                            let name = questionBank.isEmpty ? "handwriting" : questionBank[currentIndex]
                            exportSVG(paths: paths, fileName: name)
                        }
                        Button("分享") {
                            if let _ = exportURL {
                                showingShareSheet = true
                            }
                        }
                    }
                    .padding()
                }
                .frame(height: geo.size.height * 2 / 3)
            }
        }
        .sheet(isPresented: $showingSettings) {
            GitHubSettingsView()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportURL {
                ActivityViewController(activityItems: [url])
            }
        }
        .alert("請先完成 GitHub 設定", isPresented: $showUploadHint) {
            Button("前往設定") { showingSettings = true }
            Button("取消", role: .cancel) {}
        }
    }

    // 匯出 SVG
    func exportSVG(paths: [[CGPoint]], fileName: String) {
        var svgPaths = ""
        for stroke in paths {
            if let first = stroke.first {
                svgPaths += "M \(first.x) \(first.y) "
                for p in stroke.dropFirst() {
                    svgPaths += "L \(p.x) \(p.y) "
                }
            }
        }

        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="400" height="800" viewBox="0 0 400 800">
            <path d="\(svgPaths)" fill="none" stroke="black" stroke-width="2"/>
        </svg>
        """

        let fileManager = FileManager.default
        if let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = docDir.appendingPathComponent("\(fileName).svg")
            do {
                try svg.write(to: fileURL, atomically: true, encoding: .utf8)
                print("✅ SVG 已儲存: \(fileURL)")
                exportURL = fileURL
                showingShareSheet = true
                let token = KeychainHelper.read(key: GHKeys.tokenK) ?? ""
                guard !ghOwner.isEmpty, !ghRepo.isEmpty, !token.isEmpty else {
                    print("❌ GitHub 設定未完成：owner/repo/token 缺一不可")
                    showUploadHint = true
                    return
                }
                let pathInRepo: String = {
                    let base = ghPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
                    return base.isEmpty ? fileURL.lastPathComponent : "\(base)/\(fileURL.lastPathComponent)"
                }()
                uploadToGitHub(
                    fileURL: fileURL,
                    repoOwner: ghOwner,
                    repoName: ghRepo,
                    branch: ghBranch,
                    pathInRepo: pathInRepo,
                    token: token
                )
                goToNextQuestion()
            } catch {
                print("❌ 儲存失敗: \(error)")
            }
        }
    }

    func goToNextQuestion() {
        if !questionBank.isEmpty {
            if currentIndex < questionBank.count - 1 {
                currentIndex += 1
            } else {
                currentIndex = 0
            }
            // 存到 UserDefaults
            UserDefaults.standard.set(currentIndex, forKey: "CurrentIndex")
        }
        points.removeAll()
        paths.removeAll()
    }
}

struct ContentView: View {
    var body: some View {
        DrawingView()
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

// MARK: - GitHub Upload (Create/Update file via REST API)
private func uploadToGitHub(fileURL: URL,
                            repoOwner: String,
                            repoName: String,
                            branch: String,
                            pathInRepo: String,
                            token: String) {
    guard !token.isEmpty else {
        print("❌ 缺少 GitHub Token")
        return
    }
    do {
        let data = try Data(contentsOf: fileURL)
        let base64 = data.base64EncodedString()
        let session = URLSession(configuration: .default)

        // 1) 檢查檔案是否已存在以取得 sha（更新時需要）
        getFileSHAIfExists(repoOwner: repoOwner,
                           repoName: repoName,
                           pathInRepo: pathInRepo,
                           branch: branch,
                           token: token) { sha in
            var payload: [String: Any] = [
                "message": "Add \(fileURL.lastPathComponent)",
                "content": base64,
                "branch": branch
            ]
            if let sha = sha {
                payload["sha"] = sha // update
            }

            guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/contents/\(pathInRepo)") else {
                print("❌ URL 生成失敗")
                return
            }
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            req.addValue("token \(token)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

            let task = session.dataTask(with: req) { data, resp, err in
                if let err = err {
                    print("❌ 上傳失敗: \(err)")
                    return
                }
                if let http = resp as? HTTPURLResponse {
                    print("ℹ️ GitHub 回應狀態碼: \(http.statusCode)")
                    if http.statusCode == 201 || http.statusCode == 200 {
                        print("✅ 已上傳到 GitHub: \(pathInRepo)")
                    } else if let data = data, let text = String(data: data, encoding: .utf8) {
                        print("❌ 上傳失敗，回應：\(text)")
                    }
                }
            }
            task.resume()
        }
    } catch {
        print("❌ 讀取檔案失敗: \(error)")
    }
}

// 取得既有檔案 SHA（若檔案不存在會回傳 nil）
private func getFileSHAIfExists(repoOwner: String,
                                repoName: String,
                                pathInRepo: String,
                                branch: String,
                                token: String,
                                completion: @escaping (String?) -> Void) {
    guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/contents/\(pathInRepo)?ref=\(branch)") else {
        completion(nil)
        return
    }
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.addValue("token \(token)", forHTTPHeaderField: "Authorization")

    URLSession.shared.dataTask(with: req) { data, resp, err in
        if let http = resp as? HTTPURLResponse, http.statusCode == 404 {
            completion(nil) // 檔案不存在
            return
        }
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = json["sha"] as? String else {
            completion(nil)
            return
        }
        completion(sha)
    }.resume()
}

struct GitHubSettingsView: View {
    @AppStorage(GHKeys.owner)  private var owner: String = ""
    @AppStorage(GHKeys.repo)   private var repo: String = ""
    @AppStorage(GHKeys.branch) private var branch: String = "main"
    @AppStorage(GHKeys.prefix) private var prefix: String = "handwriting"

    @State private var token: String = KeychainHelper.read(key: GHKeys.tokenK) ?? ""
    @Environment(\.dismiss) private var dismiss
    @State private var showSaved = false

    var body: some View {
        NavigationView {
            Form {
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
            .navigationTitle("GitHub 設定")
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
}
