//
//  RecordingsListView.swift
//  LiDARPOC
//
//  Created by Siva Sandeep on 13/12/25.
//

import SwiftUI
import AVKit

struct ServerFileItem: Identifiable {
    let id: String
    let timestamp: Date
    let isProcessed: Bool
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

struct LocalVideoItem: Identifiable {
    let id: String
    let videoURL: URL
    let jsonURL: URL?
    let timestamp: Date
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

struct RecordingsListView: View {
    @StateObject private var apiService = APIService.shared
    @State private var uploadedFiles: [ServerFileItem] = []
    @State private var localVideos: [LocalVideoItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var show3DViewer = false
    @State private var showVideoPlayer = false
    @State private var selectedFileId: String?
    @State private var selectedFileType: String? // "video" or "processed"
    @State private var selectedLocalVideo: LocalVideoItem?
    @State private var isNavigating = false // Guard to prevent multiple navigations
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading files...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        Text("Error Loading Files")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") {
                            loadFiles()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // Recently Captured section (local unsynced videos)
                        if !localVideos.isEmpty {
                            Section("Recently Captured") {
                                ForEach(localVideos) { localVideo in
                                    LocalVideoRow(
                                        localVideo: localVideo,
                                        onWatch: {
                                            selectedLocalVideo = localVideo
                                        },
                                        onDelete: {
                                            deleteLocalVideo(localVideo)
                                        }
                                    )
                                }
                            }
                        }
                        
                        // Server files section
                        if !uploadedFiles.isEmpty {
                            Section("Uploaded Files") {
                                ForEach(uploadedFiles) { file in
                                    ServerFileRow(
                                        file: file,
                                        isDownloading: selectedFileId == file.id && selectedFileType != nil,
                                        downloadingType: selectedFileType
                                    ) { fileType in
                                        navigateToFile(file, fileType: fileType)
                                    }
                                }
                            }
                        } else if localVideos.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No Uploaded Files")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Upload recordings to see them here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Uploaded Files")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadFiles()
                loadLocalVideos()
            }
            .refreshable {
                loadFiles()
                loadLocalVideos()
            }
            .sheet(isPresented: $show3DViewer) {
                if let fileId = selectedFileId {
                    Model3DViewerView(fileId: fileId)
                        .onDisappear {
                            selectedFileId = nil
                            selectedFileType = nil
                            show3DViewer = false
                            isNavigating = false
                        }
                        .interactiveDismissDisabled(true)
                }
            }
            .sheet(isPresented: $showVideoPlayer) {
                if let fileId = selectedFileId {
                    DownloadedVideoPlayerView(fileId: fileId)
                        .onDisappear {
                            selectedFileId = nil
                            selectedFileType = nil
                            showVideoPlayer = false
                            isNavigating = false
                        }
                        .interactiveDismissDisabled(true)
                }
            }
            .sheet(item: $selectedLocalVideo) { localVideo in
                VideoPlaybackView(videoURL: localVideo.videoURL, depthURL: localVideo.jsonURL)
                    .onDisappear {
                        // Refresh local videos list when sheet is dismissed (in case files were deleted after upload)
                        loadLocalVideos()
                        loadFiles() // Also refresh server files
                    }
                    .interactiveDismissDisabled(true)
            }
        }
    }
    
    private func loadFiles() {
        isLoading = true
        errorMessage = nil
        
        apiService.getAllFiles { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let files):
                    // Convert UploadedFile to ServerFileItem, filtering out invalid timestamps
                    let serverFiles = files.compactMap { file -> ServerFileItem? in
                        guard let localTimestamp = file.localTimestamp else {
                            print("⚠️ Skipping file with invalid timestamp: \(file.id)")
                            return nil
                        }
                        return ServerFileItem(id: file.id, timestamp: localTimestamp, isProcessed: file.isProcessed)
                    }
                    // Sort by timestamp (newest first)
                    uploadedFiles = serverFiles.sorted { $0.timestamp > $1.timestamp }
                    
                    // Reload local videos after server files are loaded (to filter out synced ones)
                    loadLocalVideos()
                    
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    print("Error loading files: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func navigateToFile(_ file: ServerFileItem, fileType: String) {
        print("🔵 navigateToFile called - fileId: \(file.id), fileType: \(fileType)")
        
        // Prevent multiple simultaneous navigations
        guard !isNavigating else {
            print("⚠️ Navigation already in progress, ignoring duplicate tap")
            return
        }
        
        isNavigating = true
        print("✅ Navigation guard set, proceeding with navigation")
        
        // Navigate immediately, download will happen in the destination view
        // Reset state first to avoid conflicts
        show3DViewer = false
        showVideoPlayer = false
        selectedFileId = nil
        selectedFileType = nil
        
        // Use a small delay to ensure state resets properly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Set new state
            selectedFileId = file.id
            selectedFileType = fileType
            
                    if fileType == "video" {
                print("📹 Opening video player for file: \(file.id)")
                        showVideoPlayer = true
                    } else {
                print("🎲 Opening 3D viewer for file: \(file.id)")
                        show3DViewer = true
                    }
                    
            // Reset navigation guard after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isNavigating = false
                print("✅ Navigation guard reset")
            }
        }
    }
    
    private func loadLocalVideos() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: documentsPath,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )
            
            // Find all .mov files
            let videoFiles = files.filter { $0.pathExtension.lowercased() == "mov" }
            
            // Get server file IDs to exclude synced videos
            let serverFileIds = Set(uploadedFiles.map { $0.id })
            
            // Create local video items, excluding those that are already on server
            var localItems: [LocalVideoItem] = []
            
            for videoURL in videoFiles {
                let baseName = videoURL.deletingPathExtension().lastPathComponent
                
                // Check if this video is already on server (by comparing base name with server IDs)
                // We assume the base name matches the server file ID
                if serverFileIds.contains(baseName) {
                    continue // Skip if already synced
                }
                
                // Look for corresponding JSON file
                let jsonURL = documentsPath.appendingPathComponent("\(baseName).json")
                let jsonFileExists = FileManager.default.fileExists(atPath: jsonURL.path)
                
                // Get file creation date
                let attributes = try? videoURL.resourceValues(forKeys: [.creationDateKey])
                let creationDate = attributes?.creationDate ?? Date()
                
                localItems.append(LocalVideoItem(
                    id: baseName,
                    videoURL: videoURL,
                    jsonURL: jsonFileExists ? jsonURL : nil,
                    timestamp: creationDate
                ))
            }
            
            // Sort by timestamp (newest first)
            localVideos = localItems.sorted { $0.timestamp > $1.timestamp }
        } catch {
            print("Error loading local videos: \(error.localizedDescription)")
            localVideos = []
        }
    }
    
    private func deleteLocalVideo(_ localVideo: LocalVideoItem) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let baseName = localVideo.videoURL.deletingPathExtension().lastPathComponent
        
        print("🗑️ Deleting local video: \(baseName)")
        
        do {
            // Delete video file
            if FileManager.default.fileExists(atPath: localVideo.videoURL.path) {
                try FileManager.default.removeItem(at: localVideo.videoURL)
                print("✅ Deleted video: \(localVideo.videoURL.lastPathComponent)")
            }
            
            // Delete JSON file if exists
            if let jsonURL = localVideo.jsonURL, FileManager.default.fileExists(atPath: jsonURL.path) {
                try FileManager.default.removeItem(at: jsonURL)
                print("✅ Deleted JSON: \(jsonURL.lastPathComponent)")
            }
            
            // Delete all associated frame images and depth maps
            let files = try FileManager.default.contentsOfDirectory(
                at: documentsPath,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            let frameImageFiles = files.filter { url in
                let fileName = url.lastPathComponent
                return url.pathExtension.lowercased() == "jpg" && 
                       fileName.hasPrefix("\(baseName)_frame_")
            }
            
            let depthMapFiles = files.filter { url in
                let fileName = url.lastPathComponent
                return url.pathExtension.lowercased() == "bin" && 
                       fileName.hasPrefix("\(baseName)_depth_")
            }
            
            for frameFile in frameImageFiles {
                try? FileManager.default.removeItem(at: frameFile)
                print("✅ Deleted frame image: \(frameFile.lastPathComponent)")
            }
            
            for depthFile in depthMapFiles {
                try? FileManager.default.removeItem(at: depthFile)
                print("✅ Deleted depth map: \(depthFile.lastPathComponent)")
            }
            
            print("✅ Deleted \(frameImageFiles.count) frame image(s) and \(depthMapFiles.count) depth map(s)")
            
            // Remove from local videos list and refresh
            loadLocalVideos()
        } catch {
            print("⚠️ Error deleting local video: \(error.localizedDescription)")
            errorMessage = "Failed to delete video: \(error.localizedDescription)"
        }
    }
}

struct LocalVideoRow: View {
    let localVideo: LocalVideoItem
    let onWatch: () -> Void
    let onDelete: () -> Void
    @State private var showDeleteAlert = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "video.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.orange)
                    .frame(width: 50, height: 50)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local Recording")
                        .font(.headline)
                    
                    Text(localVideo.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Not uploaded")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                // Delete button - using highPriorityGesture to prevent propagation
                Image(systemName: "trash")
                    .font(.system(size: 18))
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        TapGesture()
                            .onEnded { _ in
                                showDeleteAlert = true
                            }
                    )
            }
            .allowsHitTesting(true)
            
            // Watch Video button
            Button(action: {
                onWatch()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 16))
                    Text("Watch Video")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.85))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .padding(.vertical, 8)
        .alert("Delete Recording?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This will permanently delete this local recording and all associated files. This action cannot be undone.")
        }
    }
}

struct ServerFileRow: View {
    let file: ServerFileItem
    let isDownloading: Bool
    let downloadingType: String?
    let onTap: (String) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "cube.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.blue)
                    .frame(width: 50, height: 50)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text("ID: \(file.id)")
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(file.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("isProcessed: \(file.isProcessed ? "✅" : "❌")")
                        .font(.caption2)
                }
                
                Spacer()
            }
            
            // Action buttons
            HStack(spacing: 12) {
                // Watch Video button
                Button(action: {
                    print("📹 Watch Video button tapped for file: \(file.id)")
                    onTap("video")
                }) {
                    HStack(spacing: 6) {
                        if isDownloading && downloadingType == "video" {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 16))
                        }
                        Text("Watch Video")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.85))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .disabled(isDownloading)
                
                // View 3D Object button
                Button(action: {
                    print("🎲 View 3D button tapped for file: \(file.id)")
                    onTap("processed")
                }) {
                    HStack(spacing: 6) {
                        if isDownloading && downloadingType == "processed" {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "cube.fill")
                                .font(.system(size: 16))
                        }
                        Text("View 3D Object")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.85))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .disabled(isDownloading)
            }
        }
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets()) // Prevent row tap gestures
    }
}

#Preview {
    RecordingsListView()
}
