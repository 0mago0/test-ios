//
//  DrawingView.swift
//  a
//
//  主繪圖頁面
//

import SwiftUI
import PencilKit

/// 主繪圖頁面 View
struct DrawingView: View {
    @State private var pkDrawing = PKDrawing()
    @State private var questionBank: [String] = []
    @State private var currentIndex: Int = UserDefaults.standard.integer(forKey: "CurrentIndex")
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
                            Task { @MainActor in
                                updateQuestionBankFromLoader()
                            }
                        }

                        ZStack {
                            if usePencilKit {
                                PKCanvasViewWrapper(drawing: $pkDrawing, lineWidth: $brushWidth)
                                    .frame(width: 300, height: 300)
                                    .clipped()
                                    .overlay(canvasOverlay)
                            } else {
                                SimpleDrawingView(strokes: $simpleStrokes, currentStroke: $currentSimpleStroke, lineWidth: $brushWidth)
                                    .frame(width: 300, height: 300)
                                    .clipped()
                                    .overlay(canvasOverlay)
                            }
                        }
                    }
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
                    controlButtons
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
    
    // MARK: - Subviews
    
    /// 畫布上的覆蓋層（預覽字、邊框、十字線）
    @ViewBuilder
    private var canvasOverlay: some View {
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
            Crosshair(size: CGSize(width: 300, height: 300), lineColor: Color(UIColor.separator), lineWidth: 1, dash: [4, 4])
        }
    }
    
    /// 控制按鈕列
    private var controlButtons: some View {
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    refreshCompletionStatus(force: true)
                }
            }
            Spacer()
            Button("設定") {
                DispatchQueue.main.async {
                    print("[UI] Settings tapped")
                    showingSettings = true
                }
            }
            Button("匯出SVG") {
                handleExportSVG()
            }
            .disabled(isUploading)
        }
        .padding()
    }

    // MARK: - Actions
    
    private func handleExportSVG() {
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
        
        // 背景進行上傳
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
            
            self.saveAndUploadSVG(svg: svg, fileName: fileName, restoreState: restoreState)
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
            
            self.saveAndUploadSVG(svg: svg, fileName: fileName, restoreState: restoreState)
        }
    }
    
    /// 儲存並上傳 SVG
    private func saveAndUploadSVG(svg: String, fileName: String, restoreState: @escaping () -> Void) {
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
                
                GitHubService.upload(
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

        GitHubService.listSVGs(
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
            UserDefaults.standard.set(self.currentIndex, forKey: "CurrentIndex")
        }
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
    
    // MARK: - SVG Path Helpers
    
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

#Preview {
    DrawingView()
}
