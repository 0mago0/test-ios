//
//  GitHubService.swift
//  InkTrace
//
//  GitHub API 服務
//

import Foundation

// MARK: - Simple Error
struct SimpleError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - GitHub Service
enum GitHubService {
    
    /// 上傳檔案到 GitHub（建立或更新）
    static func upload(
        fileURL: URL,
        repoOwner: String,
        repoName: String,
        branch: String,
        pathInRepo: String,
        token: String,
        onSuccess: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
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
            getFileSHAIfExists(
                repoOwner: repoOwner,
                repoName: repoName,
                pathInRepo: pathInRepo,
                branch: branch,
                token: token
            ) { sha in
                var payload: [String: Any] = [
                    "message": "Add \(fileURL.lastPathComponent)",
                    "content": base64,
                    "branch": branch
                ]
                if let sha = sha {
                    payload["sha"] = sha // update
                }

                guard let encodedPath = encodeForPath(pathInRepo),
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
    
    /// 取得既有檔案 SHA（若檔案不存在會回傳 nil）
    static func getFileSHAIfExists(
        repoOwner: String,
        repoName: String,
        pathInRepo: String,
        branch: String,
        token: String,
        completion: @escaping (String?) -> Void
    ) {
        guard let encodedPath = encodeForPath(pathInRepo),
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
    
    /// 列出 GitHub 目錄下的 SVG 檔案名稱
    static func listSVGs(
        owner: String,
        repo: String,
        branch: String,
        prefix: String,
        token: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedBranch = branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branch
        var urlString: String
        if trimmedPrefix.isEmpty {
            urlString = "https://api.github.com/repos/\(owner)/\(repo)/contents?ref=\(encodedBranch)"
        } else if let encodedPath = encodeForPath(trimmedPrefix) {
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
    
    // MARK: - Private Helpers
    
    /// 編碼 GitHub 路徑
    static func encodeForPath(_ path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encoded = components.compactMap { component -> String? in
            component.addingPercentEncoding(withAllowedCharacters: allowed)
        }
        guard encoded.count == components.count else { return nil }
        return encoded.joined(separator: "/")
    }
}

// MARK: - File Name Utilities
enum FileNameUtility {
    /// 建立分享用的檔案副本
    static func makeShareCopy(of originalURL: URL, originalName: String) -> URL? {
        let sanitizedName = sanitizedFileName(from: originalName) + ".svg"
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

    /// 清理檔案名稱（移除特殊字元）
    static func sanitizedFileName(from original: String) -> String {
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
}
