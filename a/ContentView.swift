
import SwiftUI
import UIKit
import Security
import PencilKit

struct StrokePoint {
    var point: CGPoint
    var force: CGFloat
}

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
    @State private var pkDrawing = PKDrawing()
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
    @State private var showingProgressDialog = false
    @State private var brushWidth: CGFloat = 5

    var targetText: String {
        guard !questionBank.isEmpty else { return "題庫載入中..." }
        return "請寫：" + questionBank[currentIndex]
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
                    VStack {
                        PKCanvasViewWrapper(drawing: $pkDrawing, lineWidth: $brushWidth)
                            .frame(width: 300, height: 300)
                            .clipped()
                            .overlay(
                                Rectangle()
                                    .stroke(Color(UIColor.separator), lineWidth: 1)
                            )
                    }
                    // 外層只負責留白與置中
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    HStack(spacing: 12) {
                        Text("粗細")
                        Slider(value: $brushWidth, in: 1...20, step: 1)
                            .frame(maxWidth: 220)
                        Text("\(Int(brushWidth)) pt")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)

                    // 控制按鈕列
                    HStack {
                        Button("清除") {
                            pkDrawing = PKDrawing()
                        }
                        Button("進度") {
                            showingProgressDialog = true
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
                            exportSVG(drawing: pkDrawing, fileName: name)
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
        .confirmationDialog(
            "目前進度：\(min(currentIndex + 1, max(1, questionBank.count))) / \(max(1, questionBank.count))",
            isPresented: $showingProgressDialog,
            titleVisibility: .visible
        ) {
            Button("重置進度（回到第 1 字）", role: .destructive) {
                resetProgress()
            }
            Button("關閉", role: .cancel) { }
        } message: {
            Text(questionBank.isEmpty ? "題庫載入中..." : "目前目標：『\(questionBank[currentIndex])』")
        }
    }

    // 匯出 SVG
    func exportSVG(drawing: PKDrawing, fileName: String) {
        let maxLineWidth: CGFloat = 10 // 與畫布筆刷寬度基準一致
        var svgShapes = ""
        
        for stroke in drawing.strokes {
            let path = stroke.path
            var points: [PKStrokePoint] = []
            path.forEach { p in
                points.append(p)
            }
            guard !points.isEmpty else { continue }

            // 單點筆劃：輸出為單一圓形
            if points.count == 1, let p = points.first {
                let r = max(0.25, p.size.width / 2)
                svgShapes += "<circle cx=\"\(p.location.x)\" cy=\"\(p.location.y)\" r=\"\(r)\" fill=\"black\" />\n"
                continue
            }

            // 多點筆劃：構建單一封閉多邊形 path
            var leftEdge: [CGPoint] = []
            var rightEdge: [CGPoint] = []
            let n = points.count

            func tangent(at i: Int) -> CGPoint {
                if i == 0 {
                    let a = points[0].location
                    let b = points[1].location
                    return CGPoint(x: b.x - a.x, y: b.y - a.y)
                } else if i == n - 1 {
                    let a = points[n - 2].location
                    let b = points[n - 1].location
                    return CGPoint(x: b.x - a.x, y: b.y - a.y)
                } else {
                    let a = points[i - 1].location
                    let c = points[i + 1].location
                    return CGPoint(x: c.x - a.x, y: c.y - a.y)
                }
            }

            for i in 0..<n {
                let p = points[i]
                var t = tangent(at: i)
                let len = max(0.0001, sqrt(t.x * t.x + t.y * t.y))
                t.x /= len; t.y /= len
                let nx = -t.y
                let ny =  t.x
                let w = max(0.5, p.size.width)
                let off = w / 2.0
                let lx = p.location.x + nx * off
                let ly = p.location.y + ny * off
                let rx = p.location.x - nx * off
                let ry = p.location.y - ny * off
                leftEdge.append(CGPoint(x: lx, y: ly))
                rightEdge.append(CGPoint(x: rx, y: ry))
            }

            // 封閉路徑：左邊正向，右邊反向
            var d = "M \(leftEdge[0].x) \(leftEdge[0].y) "
            for i in 1..<leftEdge.count {
                d += "L \(leftEdge[i].x) \(leftEdge[i].y) "
            }
            for i in stride(from: rightEdge.count - 1, through: 0, by: -1) {
                d += "L \(rightEdge[i].x) \(rightEdge[i].y) "
            }
            d += "Z"

            svgShapes += "<path d=\"\(d)\" fill=\"black\" />\n"
        }
        
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="300" height="300" viewBox="0 0 300 300">
        \(svgShapes)</svg>
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
        pkDrawing = PKDrawing()
    }

    func resetProgress() {
        currentIndex = 0
        UserDefaults.standard.set(currentIndex, forKey: "CurrentIndex")
        pkDrawing = PKDrawing()
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


// MARK: - PencilKit Canvas Wrapper
struct PKCanvasViewWrapper: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var lineWidth: CGFloat
    
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.isOpaque = false
        canvas.backgroundColor = .white
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: lineWidth)
        canvas.delegate = context.coordinator
        canvas.isScrollEnabled = false
        return canvas
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
        uiView.tool = PKInkingTool(.pen, color: .black, width: lineWidth)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PKCanvasViewWrapper
        init(_ parent: PKCanvasViewWrapper) { self.parent = parent }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
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

