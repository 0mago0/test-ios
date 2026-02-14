//
//  DrawingSubmissionService.swift
//  InkTrace
//

import Foundation
import PencilKit

struct GitHubUploadConfig {
    let owner: String
    let repo: String
    let branch: String
    let prefix: String
    let token: String
}

enum DrawingSubmissionError: LocalizedError {
    case missingGitHubConfiguration
    case saveFailed(String)
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingGitHubConfiguration:
            return "GitHub 設定未完成"
        case .saveFailed(let message):
            return message
        case .uploadFailed(let message):
            return message
        }
    }
}

enum DrawingSubmissionService {
    static func submit(
        drawing: PKDrawing,
        fileName: String,
        config: GitHubUploadConfig,
        completion: @escaping (Result<Void, DrawingSubmissionError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            var svgShapes = ""

            for stroke in drawing.strokes {
                let samples = interpolatedPoints(from: stroke.path)
                guard !samples.isEmpty else { continue }

                if samples.count == 1 {
                    let point = samples[0]
                    let radius = max(0.5, point.size.width / 2)
                    svgShapes += "<circle cx=\"\(svgNumber(point.location.x))\" cy=\"\(svgNumber(point.location.y))\" r=\"\(svgNumber(radius))\" fill=\"black\" />\n"
                    continue
                }

                guard let filledPath = filledCGPath(for: samples) else { continue }
                let d = svgPathData(from: filledPath)
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

            saveAndUploadSVG(svg: svg, fileName: fileName, config: config, completion: completion)
        }
    }

    static func submit(
        strokes: [[StrokePoint]],
        fileName: String,
        config: GitHubUploadConfig,
        completion: @escaping (Result<Void, DrawingSubmissionError>) -> Void
    ) {
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

            saveAndUploadSVG(svg: svg, fileName: fileName, config: config, completion: completion)
        }
    }

    private static func saveAndUploadSVG(
        svg: String,
        fileName: String,
        config: GitHubUploadConfig,
        completion: @escaping (Result<Void, DrawingSubmissionError>) -> Void
    ) {
        let fileManager = FileManager.default
        guard let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            notifyMain(.failure(.saveFailed("找不到文件目錄")), completion: completion)
            return
        }

        let sanitizedName = FileNameUtility.sanitizedFileName(from: fileName)
        let fileURL = docDir.appendingPathComponent("\(sanitizedName).svg")

        do {
            try svg.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            notifyMain(.failure(.saveFailed("儲存失敗：\(error.localizedDescription)")), completion: completion)
            return
        }

        guard !config.owner.isEmpty, !config.repo.isEmpty, !config.token.isEmpty else {
            notifyMain(.failure(.missingGitHubConfiguration), completion: completion)
            return
        }

        let folderPath = config.prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let localFileName = fileURL.lastPathComponent

        GitHubService.getUniquePathForFile(
            fileName: localFileName,
            repoOwner: config.owner,
            repoName: config.repo,
            branch: config.branch,
            folderPath: folderPath,
            token: config.token
        ) { uniquePath in
            GitHubService.upload(
                fileURL: fileURL,
                repoOwner: config.owner,
                repoName: config.repo,
                branch: config.branch,
                pathInRepo: uniquePath,
                token: config.token,
                onSuccess: {
                    notifyMain(.success(()), completion: completion)
                },
                onError: { errorMessage in
                    notifyMain(.failure(.uploadFailed(errorMessage)), completion: completion)
                }
            )
        }
    }

    private static func notifyMain(
        _ result: Result<Void, DrawingSubmissionError>,
        completion: @escaping (Result<Void, DrawingSubmissionError>) -> Void
    ) {
        DispatchQueue.main.async {
            completion(result)
        }
    }

    private static func interpolatedPoints(from path: PKStrokePath) -> [PKStrokePoint] {
        if #available(iOS 14.0, *) {
            let slice = path.interpolatedPoints(in: nil, by: .distance(1))
            let interpolated = Array(slice)
            if !interpolated.isEmpty {
                return interpolated
            }
        }
        return Array(path)
    }

    private static func filledCGPath(for points: [PKStrokePoint]) -> CGPath? {
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
            let stroked = segment.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 2)
            union.addPath(stroked)
            added = true
        }
        return added ? union : nil
    }

    private static func svgPathData(from path: CGPath) -> String {
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

    private static func svgNumber(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}
