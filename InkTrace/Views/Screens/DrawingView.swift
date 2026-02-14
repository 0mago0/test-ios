//
//  DrawingView.swift
//  InkTrace
//
//  主繪圖頁面
//

import SwiftUI
import PencilKit

/// 主繪圖頁面 View
struct DrawingView: View {
    private enum UploadTaskState {
        case uploading
        case success
        case failed
    }

    private struct UploadTask: Identifiable {
        let id: UUID
        let index: Int
        let character: String
        var state: UploadTaskState
        var message: String?
    }

    @State private var pkDrawing = PKDrawing()
    @State private var questionBank: [String] = []
    @State private var currentIndex: Int = UserDefaults.standard.integer(forKey: "CurrentIndex")
    @AppStorage(GHKeys.owner)  private var ghOwner: String = ""
    @AppStorage(GHKeys.repo)   private var ghRepo: String = ""
    @AppStorage(GHKeys.branch) private var ghBranch: String = "main"
    @AppStorage(GHKeys.prefix) private var ghPrefix: String = "handwriting"
    @AppStorage("HideInstructionsOnStartup") private var hideInstructionsOnStartup: Bool = false
    @State private var showingSettings = false
    @State private var hasScrolledToBottom = false // 用於判斷是否已閱讀完畢說明
    @State private var toastMessage: String? = nil
    @State private var toastType: ToastType = .success
    @State private var showingProgressDialog = false
    @State private var showingHelp = false
    @State private var brushWidth: CGFloat = 5
    @State private var usePencilKit: Bool = true
    @State private var canvasScalePercent: Int = 100 // 50-100%
    @State private var completedCharacters: Set<Int> = [] // 儲存已完成的字符索引
    @State private var isLoadingCompletions = false
    @State private var completionError: String? = nil
    @State private var failedCharacters: Set<Int> = []
    @State private var dragOffset: CGFloat = 0  // 記錄滑動偏移量
    @State private var visualIndex: Double = Double(UserDefaults.standard.integer(forKey: "CurrentIndex")) // 用於平滑動畫的顯示索引
    @State private var uploadTasks: [UploadTask] = []
    @State private var hasSyncedFromGitHub = false
    
    // Simple drawing data for non-PencilKit mode
    @State private var simpleStrokes: [[StrokePoint]] = []
    @State private var currentSimpleStroke: [StrokePoint] = []
    // Undo support
    @State private var canvasUndoManager: UndoManager? = nil
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
                    topNavigationBar
                    promptCard
                    
                    Spacer()
                    
                    // MARK: Canvas Area
                    Group {
                        if geo.size.width >= 1000 {
                            HStack(alignment: .top, spacing: 14) {
                                drawingCanvas
                                uploadStatusCard
                            }
                        } else {
                            VStack(spacing: 12) {
                                drawingCanvas
                                uploadStatusCard
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // MARK: Bottom Control Panel
                    VStack(spacing: 12) {
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
                        .background(Color(UIColor.systemGroupedBackground))
                        .cornerRadius(12)
                        
                        HStack(spacing: 12) {
                            // Scale
                            HStack(spacing: 0) {
                                Button(action: { canvasScalePercent = max(50, canvasScalePercent - 10) }) {
                                    Image(systemName: "minus")
                                        .frame(width: 32, height: 32)
                                }
                                Text("\(canvasScalePercent)%")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .frame(width: 40)
                                Button(action: { canvasScalePercent = min(100, canvasScalePercent + 10) }) {
                                    Image(systemName: "plus")
                                        .frame(width: 32, height: 32)
                                }
                            }
                            .background(Color(UIColor.systemGroupedBackground))
                            .cornerRadius(12)
                            .foregroundColor(.primary)
                            
                            // Mode Segment
                            Picker("Mode", selection: $usePencilKit) {
                                Text("有壓感").tag(true)
                                Text("無壓感").tag(false)
                            }
                            .pickerStyle(.segmented)
                        }
                        .onChange(of: characterLoader.loadedText) { _ in
                            // 當字庫更新時，同步更新題庫
                            Task { @MainActor in
                                updateQuestionBankFromLoader()
                            }
                        }
                        
                        // Action Buttons
                        HStack(spacing: 12) {
                            // Undo Button
                            Button(action: {
                                withAnimation {
                                    if usePencilKit {
                                        canvasUndoManager?.undo()
                                    } else {
                                        if !simpleStrokes.isEmpty {
                                            simpleStrokes.removeLast()
                                        }
                                    }
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.uturn.backward")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange.opacity(0.1))
                                .foregroundColor(.orange)
                                .cornerRadius(16)
                            }
                            
                            // Clear Button
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
                                    if hasActiveUploads {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                    }
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(16)
                            }
                        }
                    }
                    .padding()
                    .frame(width: 300)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(24)
                    .shadow(color: Color.black.opacity(0.1), radius: 10, y: 5)
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
                    failedCharacters: failedCharacters,
                    onSelect: { index in
                        jumpToQuestion(index: index)
                    },
                    onReset: {
                        resetProgress()
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
            .sheet(isPresented: $showingHelp) {
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
                        }.onAppear {
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
            .task {
                if !hideInstructionsOnStartup {
                    // 延遲一點點讓 UI 先準備好
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    hasScrolledToBottom = false
                    showingHelp = true
                }
                syncCompletionStatusOnLaunchIfNeeded()
            }
        }
    }
    
    // MARK: - Subviews

    private var topNavigationBar: some View {
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
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(Circle())
            }

            Spacer()

            Button {
                hasScrolledToBottom = false
                showingHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title3)
                    .foregroundColor(.primary)
                    .padding(10)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(Circle())
            }

            Button {
                DispatchQueue.main.async {
                    showingProgressDialog = true
                }
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title3)
                    .foregroundColor(.primary)
                    .padding(10)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var promptCard: some View {
        VStack(spacing: 8) {
            Text(questionBank.isEmpty ? "載入中..." : "請寫")
                .font(.subheadline)
                .foregroundColor(.secondary)

            promptCarousel
        }
        .frame(maxWidth: 500)
        .padding(.vertical, 20)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
    }

    private var promptCarousel: some View {
        GeometryReader { geo in
            let center = geo.size.width / 2
            let baseItemWidth: CGFloat = 40
            let centerIndex = Int(round(visualIndex))
            let range = 50
            let minIndex = max(0, centerIndex - range)
            let maxIndex = min(questionBank.count - 1, centerIndex + range)
            let visibleIndices: [Int] = minIndex <= maxIndex ? Array(minIndex...maxIndex) : []

            ZStack {
                ForEach(visibleIndices, id: \.self) { index in
                    carouselItemView(
                        index: index,
                        centerX: center,
                        centerY: geo.size.height / 2,
                        baseItemWidth: baseItemWidth
                    )
                }
            }
        }
        .frame(height: 100)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    let baseItemWidth: CGFloat = 40
                    let currentVisualPos = visualIndex - (value.translation.width / baseItemWidth)
                    let predictedPos = currentVisualPos - (value.velocity.width * 0.1 / baseItemWidth)

                    var targetIndex = Int(round(predictedPos))
                    targetIndex = max(0, min(targetIndex, questionBank.count - 1))

                    let maxJump = 15
                    let currentIndexInt = Int(round(currentVisualPos))
                    let jumpDist = targetIndex - currentIndexInt
                    if abs(jumpDist) > maxJump {
                        targetIndex = currentIndexInt + (jumpDist > 0 ? maxJump : -maxJump)
                    }

                    let distanceToTravel = abs(Double(targetIndex) - currentVisualPos)
                    let response = min(0.8, max(0.4, 0.3 + (distanceToTravel * 0.02)))

                    withAnimation(.spring(response: response, dampingFraction: 1.0)) {
                        visualIndex = Double(targetIndex)
                        dragOffset = 0
                    }

                    if targetIndex != currentIndex {
                        jumpToQuestion(index: targetIndex)
                    }
                }
        )
    }

    private func carouselItemView(index: Int, centerX: CGFloat, centerY: CGFloat, baseItemWidth: CGFloat) -> some View {
        let effectiveVisualIndex = CGFloat(visualIndex) - (dragOffset / baseItemWidth)
        let offsetFromVisualCenter = CGFloat(index) - effectiveVisualIndex
        let logicalOffset = offsetFromVisualCenter * baseItemWidth
        let sign: CGFloat = logicalOffset > 0 ? 1 : -1
        let maxShift: CGFloat = 60
        let decay: CGFloat = 60
        let shift = sign * maxShift * (1 - exp(-abs(logicalOffset) / decay))
        let visualPos = logicalOffset + shift
        let dist = abs(visualPos)
        let scale = max(0.4, 1.0 - (dist / 220))
        let opacity = max(0.2, 1.0 - (dist / 180))

        let color: Color = failedCharacters.contains(index)
            ? .yellow
            : (completedCharacters.contains(index) ? .green : .white)

        return Text(questionBank[index])
            .font(.system(size: 80, weight: .bold))
            .foregroundColor(color)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(x: centerX + visualPos, y: centerY)
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    jumpToQuestion(index: index)
                    visualIndex = Double(index)
                }
            }
    }
    
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

    private var drawingCanvas: some View {
        ZStack {
            if usePencilKit {
                PKCanvasViewWrapper(drawing: $pkDrawing, lineWidth: $brushWidth, onUndoManagerReady: { undoManager in
                    self.canvasUndoManager = undoManager
                })
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
    }

    private var uploadStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("上傳狀態")
                .font(.caption)
                .foregroundColor(.secondary)

            if uploadTasks.isEmpty {
                Text("等待送出")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(uploadTasks.prefix(4)) { task in
                    HStack(spacing: 8) {
                        if task.state == .uploading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: iconName(for: task.state))
                                .font(.caption)
                                .foregroundColor(color(for: task.state))
                        }

                        Text(statusText(for: task))
                            .font(.caption)
                            .foregroundColor(color(for: task.state))
                            .lineLimit(2)
                    }
                }
            }
        }
        .frame(width: 180, alignment: .leading)
        .padding(10)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }

    private var hasActiveUploads: Bool {
        uploadTasks.contains { $0.state == .uploading }
    }

    private func statusText(for task: UploadTask) -> String {
        switch task.state {
        case .uploading:
            return "上傳中：\(task.character)"
        case .success:
            return "已上傳：\(task.character)"
        case .failed:
            return "失敗：\(task.character)"
        }
    }

    private func iconName(for state: UploadTaskState) -> String {
        switch state {
        case .uploading:
            return "arrow.up.circle"
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        }
    }

    private func color(for state: UploadTaskState) -> Color {
        switch state {
        case .uploading:
            return .blue
        case .success:
            return .green
        case .failed:
            return .yellow
        }
    }
    
    // MARK: - Actions
    
    private func handleExportSVG() {
        guard !questionBank.isEmpty, currentIndex >= 0, currentIndex < questionBank.count else { return }
        let name = questionBank.isEmpty ? "handwriting" : questionBank[currentIndex]
        let submittedIndex = currentIndex
        let taskID = UUID()
        
        let savedPKDrawing = pkDrawing
        let savedSimpleStrokes = simpleStrokes
        let currentUsePencilKit = usePencilKit
        
        // 顯示上傳中提示
        uploadTasks.insert(UploadTask(id: taskID, index: submittedIndex, character: name, state: .uploading, message: nil), at: 0)
        completedCharacters.insert(submittedIndex)
        failedCharacters.remove(submittedIndex)
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
                submittedIndex: submittedIndex,
                taskID: taskID
            )
        } else {
            exportSVGFromSimpleStrokesInBackground(
                strokes: savedSimpleStrokes,
                fileName: name,
                submittedIndex: submittedIndex,
                taskID: taskID
            )
        }
    }

    // MARK: - 背景上傳版本（樂觀更新，不回跳）
    
    func exportSVGInBackground(drawing: PKDrawing, fileName: String, submittedIndex: Int, taskID: UUID) {
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

            self.saveAndUploadSVG(svg: svg, fileName: fileName, submittedIndex: submittedIndex, taskID: taskID)
        }
    }

    func exportSVGFromSimpleStrokesInBackground(strokes: [[StrokePoint]], fileName: String, submittedIndex: Int, taskID: UUID) {
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

            self.saveAndUploadSVG(svg: svg, fileName: fileName, submittedIndex: submittedIndex, taskID: taskID)
        }
    }
    
    /// 儲存並上傳 SVG
    private func saveAndUploadSVG(svg: String, fileName: String, submittedIndex: Int, taskID: UUID) {
        let fileManager = FileManager.default
        if let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            // 清理檔案名稱以避免特殊字符問題
            let sanitizedName = FileNameUtility.sanitizedFileName(from: fileName)
            let fileURL = docDir.appendingPathComponent("\(sanitizedName).svg")
            do {
                try svg.write(to: fileURL, atomically: true, encoding: .utf8)
                print("✅ SVG 已儲存: \(fileURL)")
                let token = KeychainHelper.read(key: GHKeys.tokenK) ?? ""
                guard !self.ghOwner.isEmpty, !self.ghRepo.isEmpty, !token.isEmpty else {
                    print("❌ GitHub 設定未完成")
                    DispatchQueue.main.async {
                        self.completedCharacters.remove(submittedIndex)
                        self.failedCharacters.insert(submittedIndex)
                        self.updateUploadTask(id: taskID, state: .failed, message: "GitHub 設定未完成")
                        self.toastMessage = "請先完成 GitHub 設定"
                        self.toastType = .error
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.toastMessage = nil
                        }
                    }
                    return
                }
                let folderPath = self.ghPrefix.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let fileName = fileURL.lastPathComponent
                
                // 檢查去重後的檔案路徑
                GitHubService.getUniquePathForFile(
                    fileName: fileName,
                    repoOwner: self.ghOwner,
                    repoName: self.ghRepo,
                    branch: self.ghBranch,
                    folderPath: folderPath,
                    token: token
                ) { uniquePath in
                    print("📝 將上傳到路徑: \(uniquePath)")
                    
                    GitHubService.upload(
                        fileURL: fileURL,
                        repoOwner: self.ghOwner,
                        repoName: self.ghRepo,
                        branch: self.ghBranch,
                        pathInRepo: uniquePath,
                        token: token,
                        onSuccess: {
                            DispatchQueue.main.async {
                                self.failedCharacters.remove(submittedIndex)
                                self.completedCharacters.insert(submittedIndex)
                                self.updateUploadTask(id: taskID, state: .success, message: nil)
                                self.toastMessage = "✅ 已上傳"
                                self.toastType = .success
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    self.toastMessage = nil
                                }
                            }
                        },
                        onError: { error in
                            DispatchQueue.main.async {
                                self.completedCharacters.remove(submittedIndex)
                                self.failedCharacters.insert(submittedIndex)
                                self.updateUploadTask(id: taskID, state: .failed, message: error)
                                self.toastMessage = "❌ \(error)"
                                self.toastType = .error
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    self.toastMessage = nil
                                }
                            }
                        }
                    )
                }
            } catch {
                print("❌ 儲存失敗: \(error)")
                DispatchQueue.main.async {
                    self.completedCharacters.remove(submittedIndex)
                    self.failedCharacters.insert(submittedIndex)
                    self.updateUploadTask(id: taskID, state: .failed, message: "本機儲存失敗")
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
            visualIndex = Double(clamped)  // 同步 visualIndex
            UserDefaults.standard.set(currentIndex, forKey: "CurrentIndex")
        }
        clearDrawings()
    }

    func syncCompletionStatusOnLaunchIfNeeded() {
        if hasSyncedFromGitHub || isLoadingCompletions { return }
        hasSyncedFromGitHub = true

        let owner = ghOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = ghRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = ghBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "main" : ghBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = ghPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = KeychainHelper.read(key: GHKeys.tokenK) ?? ""

        guard !owner.isEmpty, !repo.isEmpty else {
            DispatchQueue.main.async {
                self.completionError = "請先完成 GitHub 設定"
            }
            return
        }
        guard !token.isEmpty else {
            DispatchQueue.main.async {
                self.completionError = "找不到 GitHub Token"
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
                    // 根據字庫順序計算已完成的字符索引
                    // 每個字根據它是第幾個出現來檢查對應的版本
                    print("📋 GitHub 文件列表: \(names)")
                    
                    // 解碼所有檔案名稱（可能包含 URL encoding）
                    let decodedNames = names.map { FileNameUtility.decodeFileName($0) }
                    
                    var completedIndices: Set<Int> = []
                    var characterCount: [String: Int] = [:] // 追蹤每個字出現的次數
                    
                    for (index, char) in self.questionBank.enumerated() {
                        let occurrenceNumber = (characterCount[char] ?? 0)
                        characterCount[char] = occurrenceNumber + 1
                        
                        // 檢查對應的版本是否存在
                        let fileNameToCheck: String
                        if occurrenceNumber == 0 {
                            // 第一個出現時檢查原始名稱
                            fileNameToCheck = char
                        } else {
                            // 第二個及之後檢查帶後綴的版本
                            fileNameToCheck = "\(char)-\(occurrenceNumber)"
                        }
                        
                        let isCompleted = decodedNames.contains(fileNameToCheck)
                        print("🔍 字 '\(char)' (次數:\(occurrenceNumber)) → 檢查 '\(fileNameToCheck)' → \(isCompleted ? "✓" : "✗")")
                        
                        if isCompleted {
                            completedIndices.insert(index)
                        }
                    }
                    self.completedCharacters.formUnion(completedIndices)
                    self.failedCharacters.subtract(completedIndices)
                    self.completionError = nil
                case .failure(let error):
                    self.completionError = error.localizedDescription
                }
            }
        }
    }

    private func updateUploadTask(id: UUID, state: UploadTaskState, message: String?) {
        guard let index = uploadTasks.firstIndex(where: { $0.id == id }) else { return }
        uploadTasks[index].state = state
        uploadTasks[index].message = message
    }

    func goToNextQuestion() {
        if !self.questionBank.isEmpty {
            if self.currentIndex < self.questionBank.count - 1 {
                self.currentIndex += 1
            } else {
                self.currentIndex = 0
            }
            UserDefaults.standard.set(self.currentIndex, forKey: "CurrentIndex")
            // 同步 visualIndex 以便 Carousel 自動捲動到下一題
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.visualIndex = Double(self.currentIndex)
            }
        }
        self.clearDrawings()
    }

    func resetProgress() {
        currentIndex = 0
        UserDefaults.standard.set(currentIndex, forKey: "CurrentIndex")
        completedCharacters = []
        failedCharacters = []
        uploadTasks = []
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
        self.visualIndex = 0 // 重置 visualIndex
        UserDefaults.standard.set(0, forKey: "CurrentIndex")
        self.completedCharacters = []
        self.failedCharacters = []
        self.uploadTasks = []
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
