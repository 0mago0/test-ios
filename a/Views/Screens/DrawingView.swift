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
    @State private var canvasScalePercent: Int = 100 // 50-100%
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
    
    var canvasScale: CGFloat {
        CGFloat(canvasScalePercent) / 100.0
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
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // MARK: Top Navigation Bar
                    HStack {
                        Button {
                            DispatchQueue.main.async {
                                showingSettings = true
                            }
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .foregroundColor(.primary)
                                .padding(10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        Text("手寫採集")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button {
                            DispatchQueue.main.async {
                                showingProgressDialog = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                refreshCompletionStatus(force: true)
                            }
                        } label: {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.title3)
                                .foregroundColor(.primary)
                                .padding(10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    
                    // MARK: Prompt Card
                    VStack(spacing: 8) {
                        Text(questionBank.isEmpty ? "載入中..." : "請寫")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(previewCharacter ?? "...")
                            .font(.system(size: 80, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(height: 100)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // MARK: Canvas Area
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
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 6)
                    .scaleEffect(canvasScale)
                    
                    Spacer()
                    
                    // MARK: Bottom Control Panel
                    VStack(spacing: 20) {
                        // Slider & Scale
                        HStack(spacing: 16) {
                            // Brush Size
                            HStack {
                                Image(systemName: "scribble")
                                    .foregroundColor(.secondary)
                                Slider(value: $brushWidth, in: 1...20, step: 1)
                                Text("\(Int(brushWidth))")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                                    .frame(width: 25)
                            }
                            .padding(10)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                            
                            // Scale
                            HStack(spacing: 0) {
                                Button(action: { canvasScalePercent = max(50, canvasScalePercent - 10) }) {
                                    Image(systemName: "minus")
                                        .frame(width: 30, height: 30)
                                }
                                Text("\(canvasScalePercent)%")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .frame(width: 40)
                                Button(action: { canvasScalePercent = min(100, canvasScalePercent + 10) }) {
                                    Image(systemName: "plus")
                                        .frame(width: 30, height: 30)
                                }
                            }
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                            .foregroundColor(.primary)
                        }
                        
                        // Mode Segment
                        Picker("Mode", selection: $usePencilKit) {
                            Text("有壓感").tag(true)
                            Text("無壓感").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: characterLoader.loadedText) { _ in
                            // 當字庫更新時，同步更新題庫
                            Task { @MainActor in
                                updateQuestionBankFromLoader()
                            }
                        }
                        
                        // Action Buttons
                        HStack(spacing: 16) {
                            Button(action: {
                                withAnimation {
                                    if usePencilKit {
                                        pkDrawing = PKDrawing()
                                    } else {
                                        simpleStrokes = []
                                        currentSimpleStroke = []
                                    }
                                }
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("清除")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(16)
                            }
                            
                            Button(action: { handleExportSVG() }) {
                                HStack {
                                    if isUploading {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                        Text("送出")
                                    }
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(isUploading ? Color.gray : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(16)
                            }
                            .disabled(isUploading)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(24)
                    .shadow(color: Color.black.opacity(0.1), radius: 10, y: 5)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
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
                        .padding(.top, 50)
                }
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
                var d = ""
                for (i, point) in stroke.enumerated() {
                    if i == 0 {
                        d = "M \(point.point.x) \(point.point.y) "
                    } else {
                        d += "L \(point.point.x) \(point.point.y) "
                    }
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
