//
//  DrawingView.swift
//  InkTrace
//
//  主繪圖頁面
//

import SwiftUI
import PencilKit
import CryptoKit

/// 主繪圖頁面 View
struct DrawingView: View {
    private static let localStatusFingerprintKey = "LocalCharacterStatusFingerprint"
    private static let localCompletedKey = "LocalCharacterStatusCompletedIndices"
    private static let localFailedKey = "LocalCharacterStatusFailedIndices"

    @State private var pkDrawing = PKDrawing()
    @State private var questionBank: [String] = []
    @State private var currentIndex: Int = UserDefaults.standard.integer(forKey: "CurrentIndex")
    @AppStorage(GHKeys.owner)  private var ghOwner: String = ""
    @AppStorage(GHKeys.repo)   private var ghRepo: String = ""
    @AppStorage(GHKeys.branch) private var ghBranch: String = "main"
    @AppStorage(GHKeys.prefix) private var ghPrefix: String = "handwriting"
    @AppStorage("HideInstructionsOnStartup") private var hideInstructionsOnStartup: Bool = false
    @State private var showingSettings = false
    @State private var hasScrolledToBottom = false
    @State private var toastMessage: String? = nil
    @State private var toastType: ToastType = .success
    @State private var showingProgressDialog = false
    @State private var showingHelp = false
    @State private var brushWidth: CGFloat = 5
    @State private var usePencilKit: Bool = true
    @State private var canvasScalePercent: Int = 100
    @State private var completedCharacters: Set<Int> = []
    @State private var failedCharacters: Set<Int> = []
    @State private var dragOffset: CGFloat = 0
    @State private var visualIndex: Double = Double(UserDefaults.standard.integer(forKey: "CurrentIndex"))
    @State private var uploadTasks: [UploadTask] = []
    @State private var topBarHeight: CGFloat = 0

    @State private var simpleStrokes: [[StrokePoint]] = []
    @State private var currentSimpleStroke: [StrokePoint] = []
    @State private var canvasUndoManager: UndoManager? = nil
    @StateObject private var characterLoader = CharacterLoader.shared

    var canvasScale: CGFloat {
        CGFloat(canvasScalePercent) / 100.0
    }

    var previewCharacter: String? {
        guard !questionBank.isEmpty,
              currentIndex >= 0,
              currentIndex < questionBank.count else { return nil }
        return questionBank[currentIndex]
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
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
                    DrawingTopBarView(
                        onSettingsTap: { showingSettings = true },
                        onHelpTap: {
                            hasScrolledToBottom = false
                            showingHelp = true
                        },
                        onProgressTap: { showingProgressDialog = true }
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: TopBarHeightPreferenceKey.self, value: proxy.size.height)
                        }
                    )

                    promptCard

                    Spacer()

                    contentLayout(in: geo)

                    Spacer()

                    DrawingControlPanelView(
                        brushWidth: $brushWidth,
                        canvasScalePercent: $canvasScalePercent,
                        usePencilKit: $usePencilKit,
                        hasActiveUploads: hasActiveUploads,
                        onUndo: handleUndo,
                        onClear: clearDrawings,
                        onSubmit: handleExportSVG
                    )
                }
            }
            .overlay(alignment: .topLeading) {
                if isPad && geo.size.width > geo.size.height {
                    UploadStatusCardView(uploadTasks: uploadTasks)
                        .padding(.top, topBarHeight + 8)
                        .padding(.leading, 12)
                }
            }
            .onPreferenceChange(TopBarHeightPreferenceKey.self) { height in
                topBarHeight = height
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
                    onClearLocalStatus: {
                        clearLocalCharacterStatusKeepingPosition()
                    },
                    onReset: {
                        resetProgress()
                    }
                )
            }
            .sheet(isPresented: $showingHelp) {
                DrawingHelpSheetView(
                    showingHelp: $showingHelp,
                    hideInstructionsOnStartup: $hideInstructionsOnStartup,
                    hasScrolledToBottom: $hasScrolledToBottom
                )
            }
            .overlay(alignment: .top) {
                if let message = toastMessage {
                    ToastView(message: message, type: toastType)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 50)
                }
            }
            .onChange(of: characterLoader.loadedText) { _ in
                Task { @MainActor in
                    updateQuestionBankFromLoader()
                }
            }
            .task {
                if !hideInstructionsOnStartup {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    hasScrolledToBottom = false
                    showingHelp = true
                }
                restoreLocalCharacterStatusForCurrentBank()
            }
        }
    }

    private var promptCard: some View {
        VStack(spacing: 8) {
            Text(questionBank.isEmpty ? "載入中..." : "請寫")
                .font(.subheadline)
                .foregroundColor(.secondary)

            PromptCarouselView(
                questionBank: questionBank,
                currentIndex: currentIndex,
                visualIndex: $visualIndex,
                dragOffset: $dragOffset,
                completedCharacters: completedCharacters,
                failedCharacters: failedCharacters,
                onJumpToQuestion: jumpToQuestion(index:)
            )
        }
        .frame(maxWidth: 500)
        .padding(.vertical, 20)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
    }

    private var drawingCanvas: some View {
        DrawingCanvasCardView(
            pkDrawing: $pkDrawing,
            simpleStrokes: $simpleStrokes,
            currentSimpleStroke: $currentSimpleStroke,
            brushWidth: $brushWidth,
            usePencilKit: $usePencilKit,
            canvasScale: canvasScale,
            previewCharacter: previewCharacter,
            onUndoManagerReady: { undoManager in
                self.canvasUndoManager = undoManager
            }
        )
    }

    @ViewBuilder
    private func contentLayout(in geo: GeometryProxy) -> some View {
        if isPad {
            if geo.size.width > geo.size.height {
                drawingCanvas
            } else {
                VStack(spacing: 12) {
                    UploadStatusCardView(uploadTasks: uploadTasks)
                    drawingCanvas
                }
            }
        } else {
            if geo.size.height >= geo.size.width {
                VStack(spacing: 12) {
                    drawingCanvas
                    UploadStatusCardView(uploadTasks: uploadTasks, maxRows: 2, showTitle: false)
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    drawingCanvas
                    UploadStatusCardView(uploadTasks: uploadTasks, showTitle: false)
                }
            }
        }
    }

    private var hasActiveUploads: Bool {
        uploadTasks.contains { $0.state == .uploading }
    }

    private func handleUndo() {
        withAnimation {
            if usePencilKit {
                canvasUndoManager?.undo()
            } else if !simpleStrokes.isEmpty {
                simpleStrokes.removeLast()
            }
        }
    }

    private func handleExportSVG() {
        guard !questionBank.isEmpty, currentIndex >= 0, currentIndex < questionBank.count else { return }

        let name = questionBank[currentIndex]
        let submittedIndex = currentIndex
        let taskID = UUID()
        let savedPKDrawing = pkDrawing
        let savedSimpleStrokes = simpleStrokes
        let currentUsePencilKit = usePencilKit
        let config = GitHubUploadConfig(
            owner: ghOwner,
            repo: ghRepo,
            branch: ghBranch,
            prefix: ghPrefix,
            token: KeychainHelper.read(key: GHKeys.tokenK) ?? ""
        )

        uploadTasks.insert(UploadTask(id: taskID, index: submittedIndex, character: name, state: .uploading, message: nil), at: 0)
        completedCharacters.insert(submittedIndex)
        failedCharacters.remove(submittedIndex)
        saveLocalCharacterStatus()
        toastMessage = "⏳ 上傳中..."
        toastType = .success

        goToNextQuestion()

        let completion: (Result<Void, DrawingSubmissionError>) -> Void = { result in
            switch result {
            case .success:
                failedCharacters.remove(submittedIndex)
                completedCharacters.insert(submittedIndex)
                saveLocalCharacterStatus()
                updateUploadTask(id: taskID, state: .success, message: nil)
                toastMessage = "✅ 已上傳"
                toastType = .success
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    toastMessage = nil
                }

            case .failure(let error):
                completedCharacters.remove(submittedIndex)
                failedCharacters.insert(submittedIndex)
                saveLocalCharacterStatus()
                updateUploadTask(id: taskID, state: .failed, message: error.localizedDescription)

                if case .missingGitHubConfiguration = error {
                    toastMessage = "請先完成 GitHub 設定"
                } else {
                    toastMessage = "❌ \(error.localizedDescription)"
                }
                toastType = .error
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    toastMessage = nil
                }
            }
        }

        if currentUsePencilKit {
            DrawingSubmissionService.submit(
                drawing: savedPKDrawing,
                fileName: name,
                config: config,
                completion: completion
            )
        } else {
            DrawingSubmissionService.submit(
                strokes: savedSimpleStrokes,
                fileName: name,
                config: config,
                completion: completion
            )
        }
    }

    func jumpToQuestion(index: Int) {
        guard !questionBank.isEmpty else { return }
        let clamped = max(0, min(index, questionBank.count - 1))
        if currentIndex != clamped {
            currentIndex = clamped
            visualIndex = Double(clamped)
            UserDefaults.standard.set(currentIndex, forKey: "CurrentIndex")
        }
        clearDrawings()
    }

    private func restoreLocalCharacterStatusForCurrentBank() {
        guard !questionBank.isEmpty else {
            completedCharacters = []
            failedCharacters = []
            return
        }

        let defaults = UserDefaults.standard
        let fingerprint = questionBankFingerprint(questionBank)
        let savedFingerprint = defaults.string(forKey: Self.localStatusFingerprintKey)

        guard savedFingerprint == fingerprint else {
            completedCharacters = []
            failedCharacters = []
            saveLocalCharacterStatus()
            return
        }

        let maxIndex = questionBank.count - 1
        let completed = Set((defaults.array(forKey: Self.localCompletedKey) as? [Int] ?? []).filter { $0 >= 0 && $0 <= maxIndex })
        let failed = Set((defaults.array(forKey: Self.localFailedKey) as? [Int] ?? []).filter { $0 >= 0 && $0 <= maxIndex }).subtracting(completed)
        completedCharacters = completed
        failedCharacters = failed
    }

    private func saveLocalCharacterStatus() {
        guard !questionBank.isEmpty else { return }
        let defaults = UserDefaults.standard
        defaults.set(questionBankFingerprint(questionBank), forKey: Self.localStatusFingerprintKey)
        defaults.set(Array(completedCharacters).sorted(), forKey: Self.localCompletedKey)
        defaults.set(Array(failedCharacters).sorted(), forKey: Self.localFailedKey)
    }

    private func questionBankFingerprint(_ questions: [String]) -> String {
        let source = questions.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
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
        saveLocalCharacterStatus()
        clearDrawings()
    }

    private func clearLocalCharacterStatusKeepingPosition() {
        completedCharacters = []
        failedCharacters = []
        uploadTasks = []
        saveLocalCharacterStatus()
    }

    func clearDrawings() {
        self.pkDrawing = PKDrawing()
        self.simpleStrokes = []
        self.currentSimpleStroke = []
        self.showingProgressDialog = false
    }

    func updateQuestionBankFromLoader() {
        self.questionBank = characterLoader.loadedCharacters
        self.currentIndex = 0
        self.visualIndex = 0
        UserDefaults.standard.set(0, forKey: "CurrentIndex")
        self.uploadTasks = []
        self.restoreLocalCharacterStatusForCurrentBank()
        self.clearDrawings()
    }
}

private struct TopBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    DrawingView()
}
