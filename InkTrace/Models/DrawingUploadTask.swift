//
//  DrawingUploadTask.swift
//  InkTrace
//

import Foundation

enum UploadTaskState {
    case uploading
    case success
    case failed
}

struct UploadTask: Identifiable {
    let id: UUID
    let index: Int
    let character: String
    var state: UploadTaskState
    var message: String?
}
