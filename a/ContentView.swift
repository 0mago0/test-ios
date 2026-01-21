
import SwiftUI
import UIKit
import Security
import PencilKit

// MARK: - 字分組（可自行編輯）

struct StrokePoint {
    var point: CGPoint
    var force: CGFloat
}

// Crosshair dashed lines for center guidance
struct Crosshair: View {
    var size: CGSize
    var lineColor: Color = Color(UIColor.systemGray3)
    var lineWidth: CGFloat = 1
    var dash: [CGFloat] = [6, 6]

    var body: some View {
        Canvas { ctx, sz in
            let w = size.width
            let h = size.height
            // horizontal
            var hPath = Path()
            hPath.move(to: CGPoint(x: 0, y: h / 2))
            hPath.addLine(to: CGPoint(x: w, y: h / 2))
            // vertical
            var vPath = Path()
            vPath.move(to: CGPoint(x: w / 2, y: 0))
            vPath.addLine(to: CGPoint(x: w / 2, y: h))

            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dash)
            ctx.stroke(hPath, with: .color(lineColor), style: style)
            ctx.stroke(vPath, with: .color(lineColor), style: style)

            // dashed concentric squares
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
            
            Spacer(minLength: 0) // 填充水平空間
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
        .padding(.horizontal, 24) // 螢幕左右邊距
        .padding(.top, 10)
        .fixedSize(horizontal: false, vertical: true) // 關鍵：防止高度被撐開
    }
}

// MARK: - Drawing View
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
    @State private var questionBank: [String] = []
    @State private var currentIndex: Int = UserDefaults.standard.integer(forKey: "CurrentIndex") // 讀取存檔
    @AppStorage(GHKeys.owner)  private var ghOwner: String = ""
    @AppStorage(GHKeys.repo)   private var ghRepo: String = ""
    @AppStorage(GHKeys.branch) private var ghBranch: String = "main"
    @AppStorage(GHKeys.prefix) private var ghPrefix: String = "handwriting"
    @State private var showingSettings = false
    @State private var toastMessage: String? = nil
    @State private var toastType: ToastType = .success
    @State private var isUploading = false
    @State private var showingProgressDialog = false
    @State private var brushWidth: CGFloat = 5
    @State private var usePencilKit: Bool = true
    @State private var completedCharacters: Set<String> = []
    @State private var isLoadingCompletions = false
    @State private var completionError: String? = nil
    // Simple drawing data for non-PencilKit mode
    @State private var simpleStrokes: [[StrokePoint]] = []
    @State private var currentSimpleStroke: [StrokePoint] = []
    // 監聽字庫載入器的變化
    @StateObject private var characterLoader = CharacterLoader.shared

    var targetText: String {
        guard !questionBank.isEmpty else { return "題庫載入中..." }
        return "請寫：" + questionBank[currentIndex]
    }
    
    var previewCharacter: String? {
        guard !questionBank.isEmpty,
              currentIndex >= 0,
              currentIndex < questionBank.count else { return nil }
        return questionBank[currentIndex]
    }

    init() {
        let initial = CharacterLoader.shared.loadedCharacters
        self._questionBank = State(initialValue: initial)
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
                        // 模式切換
                        Picker("Mode", selection: $usePencilKit) {
                            Text("有壓感").tag(true)
                            Text("無壓感").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .onChange(of: characterLoader.loadedText) { _ in
                            // 當字庫更新時，同步更新題庫
                            // 使用 Task 延遲狀態修改，避免在 view update 期間修改狀態
                            Task { @MainActor in
                                updateQuestionBankFromLoader()
                            }
                        }

                        ZStack {
                            if usePencilKit {
                                PKCanvasViewWrapper(drawing: $pkDrawing, lineWidth: $brushWidth)
                                    .frame(width: 300, height: 300)
                                    .clipped()
                                    .overlay(
                                        ZStack {
                                            if let previewCharacter {
                                                Text(previewCharacter)
                                                    .font(.system(size: 220, weight: .regular))
                                                    .foregroundColor(.black.opacity(0.08))
                                                    .minimumScaleFactor(0.1)
                                                    .lineLimit(1)
                                                    .allowsHitTesting(false)
                                                    .accessibilityHidden(true)
                                            }
                                            Rectangle()
                                                .stroke(Color(UIColor.separator), lineWidth: 1)
                                            Crosshair(size: CGSize(width: 300, height: 300), lineColor: Color(UIColor.separator), lineWidth: 1, dash: [4,4])
                                        }
                                    )
                            } else {
                                SimpleDrawingView(strokes: $simpleStrokes, currentStroke: $currentSimpleStroke, lineWidth: $brushWidth)
                                    .frame(width: 300, height: 300)
                                    .clipped()
                                    .overlay(
                                        ZStack {
                                            if let previewCharacter {
                                                Text(previewCharacter)
                                                    .font(.system(size: 220, weight: .regular))
                                                    .foregroundColor(.black.opacity(0.08))
                                                    .minimumScaleFactor(0.1)
                                                    .lineLimit(1)
                                                    .allowsHitTesting(false)
                                                    .accessibilityHidden(true)
                                            }
                                            Rectangle()
                                                .stroke(Color(UIColor.separator), lineWidth: 1)
                                            Crosshair(size: CGSize(width: 300, height: 300), lineColor: Color(UIColor.separator), lineWidth: 1, dash: [4,4])
                                        }
                                    )
                            }
                        }
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
                            if usePencilKit {
                                pkDrawing = PKDrawing()
                            } else {
                                simpleStrokes = []
                                currentSimpleStroke = []
                            }
                        }
                        Button("進度") {
                            DispatchQueue.main.async {
                                showingProgressDialog = true
                            }
                            // 在狀態設定後再刷新
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                refreshCompletionStatus(force: true)
                            }
                        }
                        Spacer()
                        Button("設定") {
                            // 先關閉任何打開的 sheet
                            DispatchQueue.main.async {
                                print("[UI] Settings tapped")
                                showingSettings = true
                            }
                        }
                        Button("匯出SVG") {
                            guard !isUploading else { return }
                            let name = questionBank.isEmpty ? "handwriting" : questionBank[currentIndex]
                            
                            // 儲存當前狀態（失敗時可恢復）
                            let savedIndex = currentIndex
                            let savedPKDrawing = pkDrawing
                            let savedSimpleStrokes = simpleStrokes
                            let currentUsePencilKit = usePencilKit
                            
                            // 顯示上傳中提示
                            isUploading = true
                            toastMessage = "⏳ 上傳中..."
                            toastType = .success
                            
                            // 立即清除畫布並跳到下一題（樂觀更新）
                            DispatchQueue.main.async {
                                goToNextQuestion()
                            }
                            
                            // 背景進行上傳，傳入恢復所需資訊
                            if currentUsePencilKit {
                                exportSVGInBackground(
                                    drawing: savedPKDrawing,
                                    fileName: name,
                                    savedIndex: savedIndex,
                                    savedDrawing: savedPKDrawing
                                )
                            } else {
                                exportSVGFromSimpleStrokesInBackground(
                                    strokes: savedSimpleStrokes,
                                    fileName: name,
                                    savedIndex: savedIndex,
                                    savedStrokes: savedSimpleStrokes
                                )
                            }
                        }
                        .disabled(isUploading)
                    }
                    .padding()
                }
                .frame(height: geo.size.height * 2 / 3)
            }
        }
        .sheet(isPresented: $showingSettings) {
            GitHubSettingsView()
        }
        .sheet(isPresented: $showingProgressDialog) {
            ProgressSheetView(
                currentIndex: currentIndex,
                questions: questionBank,
                completedCharacters: completedCharacters,
                isLoading: isLoadingCompletions,
                errorMessage: completionError,
                onSelect: { index in
                    jumpToQuestion(index: index)
                },
                onReset: {
                    resetProgress()
                },
                onRefresh: {
                    refreshCompletionStatus(force: true)
                }
            )
        }
        .overlay(alignment: .top) {
            if let message = toastMessage {
                ToastView(message: message, type: toastType)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - 背景上傳版本（樂觀更新，失敗時恢復）
    func exportSVGInBackground(drawing: PKDrawing, fileName: String, savedIndex: Int, savedDrawing: PKDrawing) {
        DispatchQueue.global(qos: .userInitiated).async {
            var svgShapes = ""
            
            for stroke in drawing.strokes {
                let samples = self.interpolatedPoints(from: stroke.path)
                guard !samples.isEmpty else { continue }
                if samples.count == 1 {
                    let point = samples[0]
                    let radius = max(0.5, point.size.width / 2)
                    svgShapes += "<circle cx=\"\(self.svgNumber(point.location.x))\" cy=\"\(self.svgNumber(point.location.y))\" r=\"\(self.svgNumber(radius))\" fill=\"black\" />\n"
                    continue
                }
                
                guard let filledPath = self.filledCGPath(for: samples) else { continue }
                let d = self.svgPathData(from: filledPath)
                svgShapes += """
<path d="\(d)"
      fill="black"
      fill-rule="nonzero" />
"""
            }
            
            let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="300" height="300" viewBox="0 0 300 300">
            \(svgShapes)</svg>
            """
            
            // 恢復到原來題目的輔助函式
            let restoreState = {
                DispatchQueue.main.async {
                    self.currentIndex = savedIndex
                    UserDefaults.standard.set(savedIndex, forKey: "CurrentIndex")
                    self.pkDrawing = savedDrawing
                }
            }
            
            let fileManager = FileManager.default
            if let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = docDir.appendingPathComponent("\(fileName).svg")
                do {
                    try svg.write(to: fileURL, atomically: true, encoding: .utf8)
                    print("✅ SVG 已儲存: \(fileURL)")
                    let token = KeychainHelper.read(key: GHKeys.tokenK) ?? ""
                    guard !self.ghOwner.isEmpty, !self.ghRepo.isEmpty, !token.isEmpty else {
                        print("❌ GitHub 設定未完成")
                        restoreState()
                        DispatchQueue.main.async {
                            self.isUploading = false
                            self.toastMessage = "請先完成 GitHub 設定"
                            self.toastType = .error
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                self.toastMessage = nil
                            }
                        }
                        return
                    }
                    let pathInRepo: String = {
                        let base = self.ghPrefix.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        return base.isEmpty ? fileURL.lastPathComponent : "\(base)/\(fileURL.lastPathComponent)"
                    }()
                    uploadToGitHub(
                        fileURL: fileURL,
                        repoOwner: self.ghOwner,
                        repoName: self.ghRepo,
                        branch: self.ghBranch,
                        pathInRepo: pathInRepo,
                        token: token,
                        onSuccess: {
                            DispatchQueue.main.async {
                                self.isUploading = false
                                self.toastMessage = "✅ 已上傳"
                                self.toastType = .success
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    self.toastMessage = nil
                                }
                            }
                        },
                        onError: { error in
                            // 上傳失敗：恢復到原來的題目和繪圖
                            restoreState()
                            DispatchQueue.main.async {
                                self.isUploading = false
                                self.toastMessage = "❌ \(error)"
                                self.toastType = .error
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    self.toastMessage = nil
                                }
                            }
                        }
                    )
                } catch {
                    print("❌ 儲存失敗: \(error)")
                    restoreState()
                    DispatchQueue.main.async {
                        self.isUploading = false
                        self.toastMessage = "儲存失敗：\(error.localizedDescription)"
                        self.toastType = .error
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            self.toastMessage = nil
                        }
                    }
                }
            }
        }
    }

    func exportSVGFromSimpleStrokesInBackground(strokes: [[StrokePoint]], fileName: String, savedIndex: Int, savedStrokes: [[StrokePoint]]) {
        DispatchQueue.global(qos: .userInitiated).async {
            var svgShapes = ""
            for stroke in strokes {
                guard !stroke.isEmpty else { continue }
                if stroke.count == 1 {
                    let p = stroke[0]
                    let r = max(0.5, p.force / 2)
                    svgShapes += "<circle cx=\"\(p.point.x)\" cy=\"\(p.point.y)\" r=\"\(r)\" fill=\"black\" />\n"
                    continue
                }
                var d = "M \(stroke[0].point.x) \(stroke[0].point.y) "
                for i in 1..<stroke.count {
                    d += "L \(stroke[i].point.x) \(stroke[i].point.y) "
                }
                let width = max(0.5, stroke.first?.force ?? 1)
                svgShapes += "<path d=\"\(d)\" stroke=\"black\" fill=\"none\" stroke-width=\"\(width)\" stroke-linecap=\"round\" stroke-linejoin=\"round\" />\n"
            }
            
            let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="300" height="300" viewBox="0 0 300 300">
            \(svgShapes)</svg>
            """
            
            // 恢復到原來題目的輔助函式
            let restoreState = {
                DispatchQueue.main.async {
                    self.currentIndex = savedIndex
                    UserDefaults.standard.set(savedIndex, forKey: "CurrentIndex")
                    self.simpleStrokes = savedStrokes
                }
            }
            
            let fileManager = FileManager.default
            if let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = docDir.appendingPathComponent("\(fileName).svg")
                do {
                    try svg.write(to: fileURL, atomically: true, encoding: .utf8)
                    print("✅ SVG 已儲存: \(fileURL)")
                    let token = KeychainHelper.read(key: GHKeys.tokenK) ?? ""
                    guard !self.ghOwner.isEmpty, !self.ghRepo.isEmpty, !token.isEmpty else {
                        print("❌ GitHub 設定未完成")
                        restoreState()
                        DispatchQueue.main.async {
                            self.isUploading = false
                            self.toastMessage = "請先完成 GitHub 設定"
                            self.toastType = .error
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                self.toastMessage = nil
                            }
                        }
                        return
                    }
                    let pathInRepo: String = {
                        let base = self.ghPrefix.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        return base.isEmpty ? fileURL.lastPathComponent : "\(base)/\(fileURL.lastPathComponent)"
                    }()
                    uploadToGitHub(
                        fileURL: fileURL,
                        repoOwner: self.ghOwner,
                        repoName: self.ghRepo,
                        branch: self.ghBranch,
                        pathInRepo: pathInRepo,
                        token: token,
                        onSuccess: {
                            DispatchQueue.main.async {
                                self.isUploading = false
                                self.toastMessage = "✅ 已上傳"
                                self.toastType = .success
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    self.toastMessage = nil
                                }
                            }
                        },
                        onError: { error in
                            // 上傳失敗：恢復到原來的題目和繪圖
                            restoreState()
                            DispatchQueue.main.async {
                                self.isUploading = false
                                self.toastMessage = "❌ \(error)"
                                self.toastType = .error
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    self.toastMessage = nil
                                }
                            }
                        }
                    )
                } catch {
                    print("❌ 儲存失敗: \(error)")
                    restoreState()
                    DispatchQueue.main.async {
                        self.isUploading = false
                        self.toastMessage = "儲存失敗：\(error.localizedDescription)"
                        self.toastType = .error
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            self.toastMessage = nil
                        }
                    }
                }
            }
        }
    }

    func jumpToQuestion(index: Int) {
        guard !questionBank.isEmpty else { return }
        let clamped = max(0, min(index, questionBank.count - 1))
        if currentIndex != clamped {
            currentIndex = clamped
            UserDefaults.standard.set(currentIndex, forKey: "CurrentIndex")
        }
        clearDrawings()
    }

    func refreshCompletionStatus(force: Bool = false) {
        if isLoadingCompletions && !force { return }
        let owner = ghOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = ghRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = ghBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "main" : ghBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = ghPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = KeychainHelper.read(key: GHKeys.tokenK) ?? ""

        guard !owner.isEmpty, !repo.isEmpty else {
            DispatchQueue.main.async {
                self.completionError = "請先完成 GitHub 設定"
                self.completedCharacters = []
            }
            return
        }
        guard !token.isEmpty else {
            DispatchQueue.main.async {
                self.completionError = "找不到 GitHub Token"
                self.completedCharacters = []
            }
            return
        }

        DispatchQueue.main.async {
            self.isLoadingCompletions = true
            self.completionError = nil
        }

        listGitHubSVGs(
            owner: owner,
            repo: repo,
            branch: branch,
            prefix: prefix,
            token: token
        ) { result in
            DispatchQueue.main.async {
                self.isLoadingCompletions = false
                switch result {
                case .success(let names):
                    let valid = names.filter { self.questionBank.contains($0) }
                    self.completedCharacters = Set(valid)
                    self.completionError = nil
                case .failure(let error):
                    self.completionError = error.localizedDescription
                }
            }
        }
    }

    func goToNextQuestion() {
        if !self.questionBank.isEmpty {
            if self.currentIndex < self.questionBank.count - 1 {
                self.currentIndex += 1
            } else {
                self.currentIndex = 0
            }
            // 存到 UserDefaults
            UserDefaults.standard.set(self.currentIndex, forKey: "CurrentIndex")
        }
        // 切換題目時重置上傳狀態，防止卡住
        self.isUploading = false
        self.clearDrawings()
    }

    func resetProgress() {
        currentIndex = 0
        UserDefaults.standard.set(currentIndex, forKey: "CurrentIndex")
        isUploading = false
        clearDrawings()
    }

    func clearDrawings() {
        self.pkDrawing = PKDrawing()
        self.simpleStrokes = []
        self.currentSimpleStroke = []
        self.showingProgressDialog = false
    }
    
    /// 當字庫變更時更新題庫
    func updateQuestionBankFromLoader() {
        self.questionBank = characterLoader.loadedCharacters
        self.currentIndex = 0
        UserDefaults.standard.set(0, forKey: "CurrentIndex")
        self.clearDrawings()
    }
    
    private func interpolatedPoints(from path: PKStrokePath) -> [PKStrokePoint] {
        if #available(iOS 14.0, *) {
            let slice = path.interpolatedPoints(in: nil, by: .distance(1))
            let interpolated = Array(slice)
            if !interpolated.isEmpty {
                return interpolated
            }
        }
        return Array(path)
    }
    
    private func filledCGPath(for points: [PKStrokePoint]) -> CGPath? {
        guard points.count > 1 else { return nil }
        let union = CGMutablePath()
        var added = false
        for idx in 0..<(points.count - 1) {
            let current = points[idx]
            let next = points[idx + 1]
            let dx = next.location.x - current.location.x
            let dy = next.location.y - current.location.y
            let distance = hypot(dx, dy)
            if distance < 0.05 { continue }
            let segment = CGMutablePath()
            segment.move(to: current.location)
            segment.addLine(to: next.location)
            let width = max(0.5, (current.size.width + next.size.width) / 2)
            let stroked = segment.copy(strokingWithWidth: width,
                                       lineCap: .round,
                                       lineJoin: .round,
                                       miterLimit: 2)
            union.addPath(stroked)
            added = true
        }
        return added ? union : nil
    }
    
    private func svgPathData(from path: CGPath) -> String {
        var d = ""
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                let p = e.points[0]
                d += "M \(svgNumber(p.x)) \(svgNumber(p.y)) "
            case .addLineToPoint:
                let p = e.points[0]
                d += "L \(svgNumber(p.x)) \(svgNumber(p.y)) "
            case .addQuadCurveToPoint:
                let c = e.points[0]
                let p = e.points[1]
                d += "Q \(svgNumber(c.x)) \(svgNumber(c.y)) \(svgNumber(p.x)) \(svgNumber(p.y)) "
            case .addCurveToPoint:
                let c1 = e.points[0]
                let c2 = e.points[1]
                let p = e.points[2]
                d += "C \(svgNumber(c1.x)) \(svgNumber(c1.y)) \(svgNumber(c2.x)) \(svgNumber(c2.y)) \(svgNumber(p.x)) \(svgNumber(p.y)) "
            case .closeSubpath:
                d += "Z "
            @unknown default:
                break
            }
        }
        return d.trimmingCharacters(in: .whitespaces)
    }
    
    private func svgNumber(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}

struct ContentView: View {
    var body: some View {
        DrawingView()
    }
}

// Progress sheet with selectable targets and GitHub completion hints
struct ProgressSheetView: View {
    let currentIndex: Int
    let questions: [String]
    let completedCharacters: Set<String>
    let isLoading: Bool
    let errorMessage: String?
    let onSelect: (Int) -> Void
    let onReset: () -> Void
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text(progressText)
                        .font(.headline)
                    if let character = currentCharacter {
                        Text("目前目標：『\(character)』")
                            .foregroundColor(.secondary)
                    } else {
                        Text("題庫載入中...")
                            .foregroundColor(.secondary)
                    }
                }

                if let errorMessage {
                    Section("GitHub 狀態") {
                        Text(errorMessage)
                            .foregroundColor(.red)
                        Button("重新整理") {
                            onRefresh()
                        }
                    }
                } else if isLoading {
                    Section("GitHub 狀態") {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }

                Section("題目列表") {
                    if questions.isEmpty {
                        Text("題庫載入中...")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(questions.enumerated()), id: \.0) { index, char in
                            Button {
                                onSelect(index)
                                dismiss()
                            } label: {
                                HStack {
                                    Text("\(index + 1). \(char)")
                                    Spacer()
                                    if completedCharacters.contains(char) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                    if index == currentIndex {
                                        Text("目前")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.accentColor.opacity(0.15))
                                            .cornerRadius(6)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onReset()
                        dismiss()
                    } label: {
                        Text("重置進度（回到第 1 字）")
                    }
                    Button("關閉") {
                        dismiss()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("目前進度")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("重新整理") {
                        onRefresh()
                    }
                }
            }
        }
    }

    private var progressText: String {
        let total = max(questions.count, 1)
        return "進度：\(min(currentIndex + 1, total)) / \(total)"
    }

    private var currentCharacter: String? {
        guard currentIndex >= 0, currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }
}


// MARK: - PencilKit Canvas Wrapper
struct PKCanvasViewWrapper: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var lineWidth: CGFloat
    
    // Small PKCanvasView subclass to observe trait changes
    class CustomPKCanvasView: PKCanvasView {
        var onTraitChange: ((UIUserInterfaceStyle) -> Void)?
        // store pen width to reapply when enforcing black pen
        var penWidth: CGFloat = 5
        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            // Always enforce black pen when traits change to avoid unexpected white ink
            if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
                onTraitChange?(traitCollection.userInterfaceStyle)
                self.tool = PKInkingTool(.pen, color: .black, width: penWidth)
            }
        }

        // Also enforce black pen on user interaction start (covers runtime cases where tool might flip)
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            self.tool = PKInkingTool(.pen, color: .black, width: penWidth)
        }
    }
    
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = CustomPKCanvasView()
        // Force the canvas to use light appearance so PencilKit doesn't invert ink colors in dark mode
        if #available(iOS 13.0, *) {
            canvas.overrideUserInterfaceStyle = .light
        }
        canvas.drawing = drawing
    // Keep canvas opaque and use a fixed white background so strokes are always visible
    canvas.isOpaque = true
    canvas.backgroundColor = .white
        canvas.drawingPolicy = .anyInput
        // Use fixed black pen color
        canvas.tool = PKInkingTool(.pen, color: .black, width: lineWidth)
        if let c = canvas as? CustomPKCanvasView {
            c.penWidth = lineWidth
        }
        // Keep observer but set fixed black when trait changes (no-op for color)
        if let c = canvas as? CustomPKCanvasView {
            c.onTraitChange = { _ in
                DispatchQueue.main.async {
                    c.tool = PKInkingTool(.pen, color: .black, width: self.lineWidth)
                }
            }
        }
        canvas.delegate = context.coordinator
        canvas.isScrollEnabled = false
        return canvas
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
        // Ensure pen remains black
        uiView.tool = PKInkingTool(.pen, color: .black, width: lineWidth)
        if let c = uiView as? CustomPKCanvasView {
            c.penWidth = lineWidth
            c.tool = PKInkingTool(.pen, color: .black, width: c.penWidth)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PKCanvasViewWrapper
        init(_ parent: PKCanvasViewWrapper) { self.parent = parent }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // 使用 Task 延遲狀態更新，避免在 view update 期間修改狀態
            Task { @MainActor in
                self.parent.drawing = canvasView.drawing
            }
        }
    }
}

// MARK: - GitHub Upload (Create/Update file via REST API)
private func uploadToGitHub(fileURL: URL,
                            repoOwner: String,
                            repoName: String,
                            branch: String,
                            pathInRepo: String,
                            token: String,
                            onSuccess: @escaping () -> Void,
                            onError: @escaping (String) -> Void) {
    guard !token.isEmpty else {
        print("❌ 缺少 GitHub Token")
        onError("缺少 GitHub Token")
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

            guard let encodedPath = encodeForGitHubPath(pathInRepo),
                  let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/contents/\(encodedPath)") else {
                print("❌ URL 生成失敗")
                onError("GitHub URL 生成失敗")
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
                    onError("上傳失敗：\(err.localizedDescription)")
                    return
                }
                if let http = resp as? HTTPURLResponse {
                    print("ℹ️ GitHub 回應狀態碼: \(http.statusCode)")
                    if http.statusCode == 201 || http.statusCode == 200 {
                        print("✅ 已上傳到 GitHub: \(pathInRepo)")
                        onSuccess()
                    } else if let data = data, let text = String(data: data, encoding: .utf8) {
                        print("❌ 上傳失敗，回應：\(text)")
                        if http.statusCode == 409 {
                             onError("版本衝突：檔案已被修改，請重試")
                        } else {
                             onError("上傳失敗 (HTTP \(http.statusCode))：\(text)")
                        }
                    } else {
                        onError("上傳失敗 (HTTP \(http.statusCode))")
                    }
                }
            }
            task.resume()
        }
    } catch {
        print("❌ 讀取檔案失敗: \(error)")
        onError("讀取檔案失敗：\(error.localizedDescription)")
    }
}

// 取得既有檔案 SHA（若檔案不存在會回傳 nil）
private func getFileSHAIfExists(repoOwner: String,
                                repoName: String,
                                pathInRepo: String,
                                branch: String,
                                token: String,
                                completion: @escaping (String?) -> Void) {
    guard let encodedPath = encodeForGitHubPath(pathInRepo),
          let encodedBranch = branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/contents/\(encodedPath)?ref=\(encodedBranch)") else {
        completion(nil)
        return
    }
    var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
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

private func encodeForGitHubPath(_ path: String) -> String? {
    let components = path.split(separator: "/").map(String.init)
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    let encoded = components.compactMap { component -> String? in
        component.addingPercentEncoding(withAllowedCharacters: allowed)
    }
    guard encoded.count == components.count else { return nil }
    return encoded.joined(separator: "/")
}

private func makeShareCopyForSharing(of originalURL: URL, originalName: String) -> URL? {
    let sanitizedName = sanitizedShareFileName(from: originalName) + ".svg"
    let shareURL = originalURL.deletingLastPathComponent().appendingPathComponent(sanitizedName)
    if shareURL == originalURL { return originalURL }
    do {
        if FileManager.default.fileExists(atPath: shareURL.path) {
            try FileManager.default.removeItem(at: shareURL)
        }
        try FileManager.default.copyItem(at: originalURL, to: shareURL)
        return shareURL
    } catch {
        print("⚠️ Share copy failed: \(error)")
        return nil
    }
}

private func sanitizedShareFileName(from original: String) -> String {
    let transformed = original
        .applyingTransform(.toLatin, reverse: false)?
        .applyingTransform(.stripCombiningMarks, reverse: false) ?? original
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    var result = ""
    for scalar in transformed.unicodeScalars {
        if allowed.contains(scalar) {
            result.append(Character(scalar))
        } else if CharacterSet.whitespaces.contains(scalar) {
            result.append("-")
        }
    }
    if result.isEmpty {
        result = "export"
    }
    return result
}

private func listGitHubSVGs(owner: String,
                            repo: String,
                            branch: String,
                            prefix: String,
                            token: String,
                            completion: @escaping (Result<[String], Error>) -> Void) {
    let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    let encodedBranch = branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branch
    var urlString: String
    if trimmedPrefix.isEmpty {
        urlString = "https://api.github.com/repos/\(owner)/\(repo)/contents?ref=\(encodedBranch)"
    } else if let encodedPath = encodeForGitHubPath(trimmedPrefix) {
        urlString = "https://api.github.com/repos/\(owner)/\(repo)/contents/\(encodedPath)?ref=\(encodedBranch)"
    } else {
        completion(.failure(SimpleError("無法處理 GitHub 路徑：\(trimmedPrefix)")))
        return
    }

    guard let url = URL(string: urlString) else {
        completion(.failure(SimpleError("GitHub URL 生成失敗")))
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue("token \(token)", forHTTPHeaderField: "Authorization")
    request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            completion(.failure(error))
            return
        }
        guard let http = response as? HTTPURLResponse else {
            completion(.failure(SimpleError("未知的 GitHub 回應")))
            return
        }
        guard http.statusCode == 200, let data = data else {
            let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(http.statusCode)"
            completion(.failure(SimpleError("GitHub 讀取失敗：\(message)")))
            return
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data)
            var svgNames: [String] = []
            if let array = json as? [[String: Any]] {
                svgNames = array.compactMap { item in
                    guard let type = item["type"] as? String,
                          type == "file",
                          let name = item["name"] as? String,
                          name.lowercased().hasSuffix(".svg") else { return nil }
                    return String(name.dropLast(4))
                }
            } else if let dict = json as? [String: Any],
                      let type = dict["type"] as? String,
                      type == "file",
                      let name = dict["name"] as? String,
                      name.lowercased().hasSuffix(".svg") {
                svgNames = [String(name.dropLast(4))]
            } else {
                completion(.failure(SimpleError("解析 GitHub 回應失敗")))
                return
            }
            completion(.success(svgNames))
        } catch {
            completion(.failure(error))
        }
    }.resume()
}

private struct SimpleError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

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

// MARK: - Simple SwiftUI Drawing (原本寫法)
struct SimpleDrawingView: View {
    @Binding var strokes: [[StrokePoint]]
    @Binding var currentStroke: [StrokePoint]
    @Binding var lineWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                // fixed white background
                let rect = CGRect(origin: .zero, size: size)
                ctx.fill(Path(rect), with: .color(.white))

                // draw previous strokes
                for stroke in strokes {
                    var path = Path()
                    guard !stroke.isEmpty else { continue }
                    path.move(to: stroke[0].point)
                    for p in stroke.dropFirst() {
                        path.addLine(to: p.point)
                    }
                    // 固定粗細，圓頭圓角
                    let width = stroke.first?.force ?? lineWidth
                    let style = StrokeStyle(lineWidth: width,
                                            lineCap: .round,
                                            lineJoin: .round)
                    ctx.stroke(path, with: .color(.black), style: style)
                }

                // current stroke
                if !currentStroke.isEmpty {
                    var path = Path()
                    path.move(to: currentStroke[0].point)
                    for p in currentStroke.dropFirst() {
                        path.addLine(to: p.point)
                    }
                    // 固定粗細，圓頭圓角
                    let width = currentStroke.first?.force ?? lineWidth
                    let style = StrokeStyle(lineWidth: width,
                                            lineCap: .round,
                                            lineJoin: .round)
                    ctx.stroke(path, with: .color(.black), style: style)
                }
            }
            // ⬇️ gesture 掛在 Canvas 外面（很重要）
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        // 不用壓感，只吃 slider 的 lineWidth
                        let force: CGFloat = lineWidth
                        let pt = StrokePoint(point: value.location, force: force)
                        Task { @MainActor in
                            currentStroke.append(pt)
                        }
                    }
                    .onEnded { _ in
                        Task { @MainActor in
                            if !currentStroke.isEmpty {
                                strokes.append(currentStroke)
                                currentStroke = []
                            }
                        }
                    }
            )
        }
    }
}
