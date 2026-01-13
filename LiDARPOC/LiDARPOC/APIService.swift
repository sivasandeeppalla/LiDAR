//
//  APIService.swift
//  LiDARPOC
//
//  Created for API communication
//

import Foundation
import UIKit

// Import DepthFrameData from DepthDataModel for upload processing
// Note: DepthFrameData is defined in DepthDataModel.swift

struct UploadedFile: Codable, Identifiable {
    let id: String
    let timestamp: String
    let isProcessed: Bool
    
    var localTimestamp: Date? {
        // Parse ISO 8601 timestamp
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Try with fractional seconds first
        if let date = formatter.date(from: timestamp) {
            return date
        }
        
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: timestamp) {
            return date
        }
        
        // Try RFC3339 format
        let rfc3339Formatter = DateFormatter()
        rfc3339Formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        rfc3339Formatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let date = rfc3339Formatter.date(from: timestamp) {
            return date
        }
        
        rfc3339Formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        if let date = rfc3339Formatter.date(from: timestamp) {
            return date
        }
        
        // Try simple format
        rfc3339Formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return rfc3339Formatter.date(from: timestamp)
    }
}

struct UploadedFilesResponse: Codable {
    let files: [UploadedFile]?
}

class APIService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = APIService()
    
    private let baseURL = "http://106.51.37.159:8001"
    private let historyDownloadsFolderName = "HistoryDownloads"
    
    private var downloadProgressHandlers: [Int: (Double) -> Void] = [:]
    private var downloadCompletionHandlers: [Int: (Result<URL, Error>) -> Void] = [:]
    private var downloadTaskToFileType: [Int: String] = [:]
    private var downloadTaskToFileId: [Int: String] = [:]
    
    // Upload progress (tracked via URLSessionTask.progress)
    private var uploadProgressHandlers: [Int: (Double) -> Void] = [:]
    private var uploadProgressObservations: [Int: NSKeyValueObservation] = [:]
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    private override init() {
        super.init()
        // Ensure history downloads folder exists on initialization
        ensureHistoryDownloadsFolder()
    }
    
    /// Get the URL for the history downloads folder
    func getHistoryDownloadsFolder() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let historyFolder = documentsPath.appendingPathComponent(historyDownloadsFolderName)
        return historyFolder
    }
    
    /// Ensure the history downloads folder exists
    private func ensureHistoryDownloadsFolder() {
        let folderURL = getHistoryDownloadsFolder()
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            print("📁 Created history downloads folder: \(folderURL.path)")
        }
    }
    
    /// Clear all files in the history downloads folder
    func clearHistoryDownloads() {
        let folderURL = getHistoryDownloadsFolder()
        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            print("📁 History downloads folder doesn't exist, nothing to clear")
            return
        }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
            
            print("🗑️ Cleared \(files.count) file(s) from history downloads folder")
        } catch {
            print("⚠️ Error clearing history downloads: \(error.localizedDescription)")
        }
    }
    
    /// Check if a file exists in the history downloads cache
    func getCachedFile(fileId: String, fileType: String) -> URL? {
        let folderURL = getHistoryDownloadsFolder()
        let extensionKey = fileType == "processed" ? "obj" : "mov"
        let fileName = "\(fileId).\(extensionKey)"
        let cachedFileURL = folderURL.appendingPathComponent(fileName)
        
        if FileManager.default.fileExists(atPath: cachedFileURL.path) {
            print("✅ Found cached file: \(fileName)")
            return cachedFileURL
        }
        
        return nil
    }
    
    /// Depth frame data structure for upload (with base64-encoded depth and image data)
    struct DepthFrameDataForUpload: Codable {
        let timestamp: TimeInterval
        let intrinsics: [Float]
        let cameraTransform: [Float]
        let transform: [Float]
        let position: [Float]
        let orientation: [Float]
        let eulerAngles: [Float]
        let capturedImageWidth: Int
        let capturedImageHeight: Int
        let depthToImageScale: [Float]
        let depthMapData: String?  // Base64 encoded depth map data
        let depthMapWidth: Int
        let depthMapHeight: Int
        let imageData: String?  // Base64 encoded image data
    }
    
    /// Upload video and JSON files to server using memory-efficient streaming
    /// - Parameters:
    ///   - videoURL: URL of the video file to upload
    ///   - jsonURL: URL of the JSON file to upload
    ///   - progress: Upload progress callback (0.0 - 1.0)
    ///   - completion: Completion handler with result containing response string or error
    func uploadFiles(videoURL: URL, jsonURL: URL, progress: ((Double) -> Void)? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video file not found"])))
            return
        }
        
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "JSON file not found"])))
            return
        }
        
        // Prepare JSON file with base64-encoded depth and image data (writes to temp file)
        guard let tempJSONURL = prepareJSONForUpload(jsonURL: jsonURL) else {
            completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare JSON for upload"])))
            return
        }
        
        guard let url = URL(string: "\(baseURL)/upload") else {
            // Clean up temp JSON file
            try? FileManager.default.removeItem(at: tempJSONURL)
            completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        
        // Create multipart body file (streaming, memory-efficient)
        guard let multipartBodyURL = createMultipartBodyFile(
            boundary: boundary,
            jsonFileURL: tempJSONURL,
            jsonFilename: jsonURL.lastPathComponent,
            videoURL: videoURL
        ) else {
            // Clean up temp JSON file
            try? FileManager.default.removeItem(at: tempJSONURL)
            completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create multipart body"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Use uploadTask with file URL for memory-efficient streaming upload
        let session = URLSession(configuration: .default)
        var task: URLSessionUploadTask?
        task = session.uploadTask(with: request, fromFile: multipartBodyURL) { [weak self] data, response, error in
            guard let self = self else { return }
            // Clean up temporary files
            try? FileManager.default.removeItem(at: tempJSONURL)
            try? FileManager.default.removeItem(at: multipartBodyURL)
            
            // Clean up upload progress tracking
            if let taskId = task?.taskIdentifier {
                self.uploadProgressObservations[taskId]?.invalidate()
                self.uploadProgressObservations.removeValue(forKey: taskId)
                self.uploadProgressHandlers.removeValue(forKey: taskId)
            }
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server responded with status \(httpResponse.statusCode)"])))
                return
            }
            
            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                completion(.success(responseString))
            } else {
                completion(.success("Upload successful (no response data)"))
            }
        }
        
        guard let task = task else {
            // Clean up temp JSON file and multipart body file
            try? FileManager.default.removeItem(at: tempJSONURL)
            try? FileManager.default.removeItem(at: multipartBodyURL)
            completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create upload task"])))
            return
        }
        
        // Track upload progress (0.0 - 1.0)
        if let progressHandler = progress {
            uploadProgressHandlers[task.taskIdentifier] = progressHandler
            DispatchQueue.main.async {
                progressHandler(0.0)
            }
            
            let observation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] p, _ in
                guard let self = self else { return }
                let frac = min(max(p.fractionCompleted, 0.0), 1.0)
                if let handler = self.uploadProgressHandlers[task.taskIdentifier] {
                    DispatchQueue.main.async {
                        handler(frac)
                    }
                }
            }
            uploadProgressObservations[task.taskIdentifier] = observation
        }
        
        task.resume()
    }
    
    /// Prepare JSON for upload by reading referenced .bin and .jpg files
    /// Both depth maps and images: base64 encoded strings
    /// Writes JSON to a temporary file and returns the file URL (memory-efficient streaming)
    private func prepareJSONForUpload(jsonURL: URL) -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Create temporary file for JSON output
        let tempDir = FileManager.default.temporaryDirectory
        let tempJSONURL = tempDir.appendingPathComponent("upload_\(UUID().uuidString).json")
        
        // Read the original JSON file
        guard let jsonData = try? Data(contentsOf: jsonURL),
              let originalFrames = try? JSONDecoder().decode([DepthFrameData].self, from: jsonData) else {
            print("❌ Failed to read or decode JSON file")
            return nil
        }
        
        print("📦 Preparing \(originalFrames.count) frames for upload...")
        
        // Convert each frame: read .bin and .jpg files, convert both to base64
        // Process frames one at a time to minimize memory usage
        var uploadFrames: [DepthFrameDataForUpload] = []
        
        for (index, frame) in originalFrames.enumerated() {
            var depthMapBase64: String? = nil
            var imageBase64: String? = nil
            
            // Read depth map .bin file and convert to base64
            if let depthMapFilePath = frame.depthMapFilePath {
                let depthFileURL = documentsPath.appendingPathComponent(depthMapFilePath)
                if FileManager.default.fileExists(atPath: depthFileURL.path) {
                    if let depthData = try? Data(contentsOf: depthFileURL) {
                        depthMapBase64 = depthData.base64EncodedString()
                        if index % 10 == 0 {
                            print("✅ Loaded depth map (\(depthData.count) bytes) for frame \(index)/\(originalFrames.count)")
                        }
                    } else {
                        print("⚠️ Failed to read depth map file: \(depthMapFilePath)")
                    }
                } else {
                    print("⚠️ Depth map file not found: \(depthMapFilePath)")
                }
            }
            
            // Read and convert image .jpg file to base64
            if let imageFilePath = frame.imageFilePath {
                let imageFileURL = documentsPath.appendingPathComponent(imageFilePath)
                if FileManager.default.fileExists(atPath: imageFileURL.path) {
                    if let imageData = try? Data(contentsOf: imageFileURL) {
                        imageBase64 = imageData.base64EncodedString()
                        if index % 10 == 0 {
                            print("✅ Loaded image (\(imageData.count) bytes) for frame \(index)/\(originalFrames.count)")
                        }
                    } else {
                        print("⚠️ Failed to read image file: \(imageFilePath)")
                    }
                } else {
                    print("⚠️ Image file not found: \(imageFilePath)")
                }
            }
            
            // Create upload frame with base64-encoded depth map and image data
            let uploadFrame = DepthFrameDataForUpload(
                timestamp: frame.timestamp,
                intrinsics: frame.intrinsics,
                cameraTransform: frame.cameraTransform,
                transform: frame.transform,
                position: frame.position,
                orientation: frame.orientation,
                eulerAngles: frame.eulerAngles,
                capturedImageWidth: frame.capturedImageWidth,
                capturedImageHeight: frame.capturedImageHeight,
                depthToImageScale: frame.depthToImageScale,
                depthMapData: depthMapBase64,  // Base64 encoded depth map
                depthMapWidth: frame.depthMapWidth,
                depthMapHeight: frame.depthMapHeight,
                imageData: imageBase64  // Base64 encoded image
            )
            
            uploadFrames.append(uploadFrame)
        }
        
        // Encode to JSON and write to temp file
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        do {
            let uploadJSONData = try encoder.encode(uploadFrames)
            try uploadJSONData.write(to: tempJSONURL)
            print("✅ Prepared JSON for upload: \(uploadJSONData.count) bytes written to \(tempJSONURL.lastPathComponent)")
            return tempJSONURL
        } catch {
            print("❌ Failed to encode or write JSON for upload: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Create multipart form data body and write to temporary file (memory-efficient streaming)
    /// - Returns: URL of temporary file containing multipart body, or nil on error
    private func createMultipartBodyFile(boundary: String, jsonFileURL: URL, jsonFilename: String, videoURL: URL) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let tempBodyURL = tempDir.appendingPathComponent("multipart_\(UUID().uuidString).tmp")
        
        do {
            // Create empty file first
            FileManager.default.createFile(atPath: tempBodyURL.path, contents: nil, attributes: nil)
            
            guard let fileHandle = try? FileHandle(forWritingTo: tempBodyURL) else {
                print("❌ Failed to open temporary file for multipart body")
                return nil
            }
            
            defer {
                do {
                    try fileHandle.close()
                } catch {
                    print("⚠️ Error closing multipart body file handle: \(error.localizedDescription)")
                }
            }
            
            let videoFilename = videoURL.lastPathComponent
            
            // JSON part (with base64 data)
            if let jsonPart = "--\(boundary)\r\nContent-Disposition: form-data; name=\"json_file\"; filename=\"\(jsonFilename)\"\r\nContent-Type: application/json\r\n\r\n".data(using: .utf8) {
                fileHandle.write(jsonPart)
            }
            
            // Stream JSON file content
            do {
                let jsonFileHandle = try FileHandle(forReadingFrom: jsonFileURL)
                defer {
                    do {
                        try jsonFileHandle.close()
                    } catch {
                        print("⚠️ Error closing JSON file handle: \(error.localizedDescription)")
                    }
                }
                
                let chunkSize = 64 * 1024 // 64KB chunks
                while true {
                    let chunk = jsonFileHandle.readData(ofLength: chunkSize)
                    if chunk.isEmpty { break }
                    fileHandle.write(chunk)
                }
            } catch {
                print("❌ Failed to read JSON file for multipart body: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: tempBodyURL)
                return nil
            }
            
            if let newline = "\r\n".data(using: .utf8) {
                fileHandle.write(newline)
            }
            
            // Video part
            if let videoPart = "--\(boundary)\r\nContent-Disposition: form-data; name=\"video_file\"; filename=\"\(videoFilename)\"\r\nContent-Type: video/mp4\r\n\r\n".data(using: .utf8) {
                fileHandle.write(videoPart)
            }
            
            // Stream video file content (memory-efficient)
            do {
                let videoFileHandle = try FileHandle(forReadingFrom: videoURL)
                defer {
                    do {
                        try videoFileHandle.close()
                    } catch {
                        print("⚠️ Error closing video file handle: \(error.localizedDescription)")
                    }
                }
                
                let chunkSize = 64 * 1024 // 64KB chunks
                while true {
                    let chunk = videoFileHandle.readData(ofLength: chunkSize)
                    if chunk.isEmpty { break }
                    fileHandle.write(chunk)
                }
            } catch {
                print("❌ Failed to read video file for multipart body: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: tempBodyURL)
                return nil
            }
            
            if let newline = "\r\n".data(using: .utf8) {
                fileHandle.write(newline)
            }
            
            // Closing boundary
            if let closing = "--\(boundary)--\r\n".data(using: .utf8) {
                fileHandle.write(closing)
            }
            
            // Flush and get file size
            try fileHandle.synchronize()
            if let attributes = try? FileManager.default.attributesOfItem(atPath: tempBodyURL.path),
               let fileSize = attributes[.size] as? Int64 {
                print("✅ Created multipart body file: \(fileSize) bytes at \(tempBodyURL.lastPathComponent)")
            }
            
            return tempBodyURL
        } catch {
            print("❌ Error creating multipart body file: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempBodyURL)
            return nil
        }
    }
    
    /// Parse .obj file URL from upload response string
    func parseObjURL(from response: String) -> URL? {
        // Try to extract URL from response string
        // Common formats: "obj_url": "http://...", "objUrl": "http://...", or plain URL
        if let urlRange = response.range(of: "http[s]?://[^\\s\"}]+", options: .regularExpression) {
            let urlString = String(response[urlRange])
            return URL(string: urlString)
        }
        return nil
    }
    
    /// Extract .obj file URL from JSON response data
    func extractObjURL(from data: Data) -> URL? {
        // Try to parse as JSON
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Try multiple possible keys for obj URL
            let possibleKeys = ["obj_url", "objUrl", "obj_file_url", "objFileUrl", "model_url", "modelUrl", "file_url", "fileUrl"]
            
            for key in possibleKeys {
                if let objURLString = json[key] as? String,
                   let objURL = URL(string: objURLString) {
                    return objURL
                }
            }
        }
        return nil
    }
    
    /// Fetch all uploaded files from server
    func getAllFiles(completion: @escaping (Result<[UploadedFile], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/get_all_files") else {
            completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "accept")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            do {
                // Try to decode as array directly
                if let files = try? JSONDecoder().decode([UploadedFile].self, from: data) {
                    completion(.success(files))
                    return
                }
                
                // Try to decode as object with files array
                if let response = try? JSONDecoder().decode(UploadedFilesResponse.self, from: data),
                   let files = response.files {
                    completion(.success(files))
                    return
                }
                
                // Try to decode as dictionary with files key
                if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let filesArray = dict["data"] as? [[String: Any]] {
                    let files = filesArray.compactMap { fileDict -> UploadedFile? in
                        guard let id = fileDict["id"] as? String,
                              let timestamp = fileDict["timestamp"] as? String,
                              let isProcessed = fileDict["is_processed"] as? Bool else {
                            return nil
                        }
                        return UploadedFile(id: id, timestamp: timestamp, isProcessed: isProcessed)
                    }
                    completion(.success(files))
                    return
                }
                
                completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to parse response"])))
            } catch {
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    /// Download processed file (.obj) from server
    /// First checks cache, only downloads if not cached
    func downloadFile(fileId: String, fileType: String = "processed", progress: ((Double) -> Void)? = nil, completion: @escaping (Result<URL, Error>) -> Void) {
        // Check cache first
        if let cachedFile = getCachedFile(fileId: fileId, fileType: fileType) {
            progress?(1.0)
            completion(.success(cachedFile))
            return
        }
        
        // File not in cache, download it
        guard let url = URL(string: "\(baseURL)/download_file?file_id=\(fileId)&file_type=\(fileType)") else {
            completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "accept")
        
        print("📥 Downloading file: \(fileId).\(fileType == "processed" ? "obj" : "mov")")
        
        let task = session.downloadTask(with: request)
        
        // Store handlers
        downloadProgressHandlers[task.taskIdentifier] = progress
        downloadCompletionHandlers[task.taskIdentifier] = completion
        downloadTaskToFileType[task.taskIdentifier] = fileType
        downloadTaskToFileId[task.taskIdentifier] = fileId
        
        task.resume()
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            if let handler = downloadProgressHandlers[downloadTask.taskIdentifier] {
                DispatchQueue.main.async {
                    handler(progress)
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let completion = downloadCompletionHandlers[downloadTask.taskIdentifier],
              let fileType = downloadTaskToFileType[downloadTask.taskIdentifier],
              let fileId = downloadTaskToFileId[downloadTask.taskIdentifier] else { return }
        
        // Clean up handlers (except completion call, cleaned after)
        
        // Move file (logic copied from original)
        let historyFolder = self.getHistoryDownloadsFolder()
        let extensionkey = fileType == "processed" ? "obj" : "mov"
        let fileName = "\(fileId).\(extensionkey)"
        let destinationURL = historyFolder.appendingPathComponent(fileName)
        
        do {
            // Ensure folder exists
            try? FileManager.default.createDirectory(at: historyFolder, withIntermediateDirectories: true)
            
            // Remove existing file if any
            try? FileManager.default.removeItem(at: destinationURL)
            
            // Move downloaded file to history folder
            try FileManager.default.moveItem(at: location, to: destinationURL)
            print("✅ Downloaded and cached file: \(fileName)")
            
            // Clean up and callback
            cleanupHandlers(for: downloadTask.taskIdentifier)
            DispatchQueue.main.async {
                completion(.success(destinationURL))
            }
        } catch {
            print("❌ Error saving downloaded file: \(error.localizedDescription)")
            
            // Clean up and callback
            cleanupHandlers(for: downloadTask.taskIdentifier)
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, let completion = downloadCompletionHandlers[task.taskIdentifier] {
            // Only handle error here. Success is handled in didFinishDownloadingTo
            cleanupHandlers(for: task.taskIdentifier)
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }
    
    private func cleanupHandlers(for identifier: Int) {
        downloadProgressHandlers.removeValue(forKey: identifier)
        downloadCompletionHandlers.removeValue(forKey: identifier)
        downloadTaskToFileType.removeValue(forKey: identifier)
        downloadTaskToFileId.removeValue(forKey: identifier)
    }
    // MARK: - Aruco Marker Processing
    
    struct ArucoRequestBody: Codable {
        let image: String
        let click_points: [[Int]]
        let label_points: [Int]
        let record_id: String
        let label: String?
        let marker_size_cm: Int?
    }
    
    struct ArucoRefinedRequestBody: Codable {
        let image: String
        let points: [SwapPointsRequest]
        let record_id: String
        let marker_size_cm: Int?
    }
    
    
    struct ArucoAPIResponse: Codable {
        let image: String // Base64
        let prediction: Prediction?
        let measurement: MeasurementResponse?
    }
    
    struct MeasurementResponse: Codable {
        let perimeter_cm: Double?
        let height_cm: Double?
        let confidence: Double?
        let width_cm: Double?
        let area_cm2: Double?
        
    }
    
    struct Prediction: Codable {
        let box: Box
        let rotated_bbox: [SwapPointsRequest]
    }

    
    
    struct Box: Codable, Equatable {
        let xmin: Double
        let ymin: Double
        let xmax: Double
        let ymax: Double
    }
    
    func processArucoMarkerImage(image: UIImage, clickPoint: CGPoint, fileId: String, completion: @escaping (Result<ArucoAPIResponse, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/process_aruco_marker_image") else {
            completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])))
            return
        }
        let base64Image = imageData.base64EncodedString()
        
        // Prepare request body
        // Coordinates should be integers
        let x = Int(clickPoint.x)
        let y = Int(clickPoint.y)
        
        let body = ArucoRequestBody(
            image: base64Image,
            click_points: [[x, y]],
            label_points: [1], // 1 for positive point
            record_id: fileId,
            label: nil, // "object",
            marker_size_cm: nil // 5 s
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        
        do {
            let jsonData = try JSONEncoder().encode(body)
            request.httpBody = jsonData
            printJSON(jsonData, prefix: "📤 REQUEST BODY:")
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    completion(.failure(NSError(domain: "APIService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error: \(statusCode)"])))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                self.printJSON(data, prefix: "📥 RAW RESPONSE:")
                
                
                
                do {
                    let responseObj = try JSONDecoder().decode(ArucoAPIResponse.self, from: data)
                    print("Success Response \(responseObj)")
                    completion(.success(responseObj))
                } catch {
                    print("❌ Error decoding response: \(error)")
                    // Try to print the string response for debugging
                    if let str = String(data: data, encoding: .utf8) {
                        print("Start of response: \(str.prefix(500))")
                    }
                    completion(.failure(error))
                }
            }
            task.resume()
        } catch {
            completion(.failure(error))
        }
    }
    
    
    func redefinedAkroImage(image: UIImage, adjustedPoints: [SwapPointsRequest], fileId: String, completion: @escaping (Result<ArucoAPIResponse, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/process_aruco_marker_image_refined") else {
            completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])))
            return
        }
        let base64Image = imageData.base64EncodedString()
        
        let body = ArucoRefinedRequestBody(
            image: base64Image,
            points: adjustedPoints,
            record_id: fileId,
            marker_size_cm: nil // 5 s
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        
        do {
            let jsonData = try JSONEncoder().encode(body)
            request.httpBody = jsonData
            printJSON(jsonData, prefix: "📤 REQUEST BODY:")
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    completion(.failure(NSError(domain: "APIService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error: \(statusCode)"])))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                self.printJSON(data, prefix: "📥 RAW RESPONSE:")
                
                
                
                do {
                    let responseObj = try JSONDecoder().decode(ArucoAPIResponse.self, from: data)
                    print("Success Response \(responseObj)")
                    completion(.success(responseObj))
                } catch {
                    print("❌ Error decoding response: \(error)")
                    // Try to print the string response for debugging
                    if let str = String(data: data, encoding: .utf8) {
                        print("Start of response: \(str.prefix(500))")
                    }
                    completion(.failure(error))
                }
            }
            task.resume()
        } catch {
            completion(.failure(error))
        }
    }

    
    func printJSON(_ data: Data, prefix: String = "") {
        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(
            withJSONObject: json,
            options: .prettyPrinted
           ),
           let string = String(data: pretty, encoding: .utf8) {
            print("\(prefix)\n\(string)")
        } else if let string = String(data: data, encoding: .utf8) {
            print("\(prefix)\n\(string)")
        }
    }
    
    struct SwapImageRequestBody: Codable {
        let input_image: String
        let swap_image: String
        let hormonization_flag: Bool
        let points: [SwapPointsRequest]
        
    }
    
    struct SwapPointsRequest: Codable {
        let x: Double
        let y: Double
    }
    
    struct SwapImageResponse: Codable {
        let image_1: String? // Base64
        let image_2: String? // Base 64
    }
    
    func processSwapImage(inputImage: String, swapImage: String, points: [SwapPointsRequest] ,completion: @escaping (Result<SwapImageResponse, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/process_swap_image") else {
            completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        // Prepare request body
        let body = SwapImageRequestBody(
            input_image: inputImage,
            swap_image: swapImage,
            hormonization_flag: false,
            points: points
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        
        do {
            let jsonData = try JSONEncoder().encode(body)
            request.httpBody = jsonData
            printJSON(jsonData, prefix: "📤 SWAP REQUEST BODY:") // Uncomment for debug if needed, body might be huge
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    completion(.failure(NSError(domain: "APIService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error: \(statusCode)"])))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                 self.printJSON(data, prefix: "📥 SWAP RAW RESPONSE:")
                
                do {
                    if let responseObj = try? JSONDecoder().decode(SwapImageResponse.self, from: data) {
                        completion(.success(responseObj))
                        return
                    } else {
                        completion(.failure(NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown response format"])))
                    }
                    
                }
            }
            task.resume()
        } catch {
            completion(.failure(error))
        }
    }
}

