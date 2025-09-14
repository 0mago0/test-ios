import SwiftUI
import UIKit

struct DrawingView: View {
    @State private var points: [CGPoint] = []
    @State private var paths: [[CGPoint]] = []
    @State private var showingShareSheet = false
    @State private var exportURL: URL? = nil
    @State private var questionBank: [String] = []
    @State private var currentIndex: Int = 0

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
                        // 畫布背景
                        Color.white

                        // 畫線
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
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportURL {
                ActivityViewController(activityItems: [url])
            }
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
        
        // 存檔到 Documents
        let fileManager = FileManager.default
        if let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = docDir.appendingPathComponent("\(fileName).svg")
            do {
                try svg.write(to: fileURL, atomically: true, encoding: .utf8)
                print("✅ SVG 已儲存: \(fileURL)")
                exportURL = fileURL
                showingShareSheet = true
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
