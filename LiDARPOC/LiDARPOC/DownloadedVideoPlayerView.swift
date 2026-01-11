//
//  DownloadedVideoPlayerView.swift
//  LiDARPOC
//
//  Created by Siva Sandeep on 13/12/25.
//

import SwiftUI
import AVKit
import AVFoundation
class DownloadedViewPlayerViewModel: ObservableObject {
    @Published var capturedImage: UIImage?

}
struct DownloadedVideoPlayerView: View {
    @Environment(\.dismiss) var dismiss
    let videoURL: URL?
    let fileId: String?
    @StateObject var viewModel: DownloadedViewPlayerViewModel = DownloadedViewPlayerViewModel()
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var playerError: String?
    @State private var isDownloading = false
    @State private var downloadedVideoURL: URL?
    @State private var show2DViewer = false
    
    @StateObject private var apiService = APIService.shared
    
    init(videoURL: URL? = nil, fileId: String? = nil) {
        self.videoURL = videoURL
        self.fileId = fileId
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                // Top bar with close button
                HStack {
                    Button(action: {
                        player?.pause()
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .padding()
                    
                    Spacer()
                    if !isDownloading {
                        Button(action: {
                            // here capture the video frame at this instant and navigate to new screen with that image
                            captureFrameFromVideo()
                        }) {
                            HStack(spacing: 6) {
                                Text("Capture")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.85))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.trailing, 12)
                    }
                  
                }
                .padding(.top, 50)
                
                Spacer()
                
                // Video Player
                if isDownloading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Downloading video...")
                            .foregroundColor(.white)
                    }
                } else if let player = player {
                    VideoPlayerView(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = playerError {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                        Text("Error loading video")
                            .foregroundColor(.white)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                }
                
                Spacer()
                
                // Play/Pause controls
                HStack(spacing: 40) {
                    Button(action: {
                        guard let player = player else { return }
                        
                        if isPlaying {
                            player.pause()
                            isPlaying = false
                        } else {
                            player.play()
                            isPlaying = true
                        }
                    }) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 70))
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            if let fileId = fileId, downloadedVideoURL == nil {
                downloadVideo()
            } else if let url = effectiveVideoURL {
                setupPlayer(url: url)
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .fullScreenCover(isPresented: $show2DViewer) {
            if let image = viewModel.capturedImage, let fileId = fileId {
                Model2DViewerView(image: image, fileId: fileId)
            } else {
                // Debugging fallback
                VStack {
                    Text("Error: Missing Data")
                        .font(.title)
                        .foregroundColor(.red)
                    Text("Captured Image: \(viewModel.capturedImage != nil ? "Present" : "Nil")")
                    Text("File ID: \(fileId != nil ? "Present" : "Nil")")
                    Button("Close") {
                        show2DViewer = false
                    }
                }
                .onAppear {
                    print("⚠️ fullScreenCover - Image: \(viewModel.capturedImage != nil), FileID: \(fileId != nil)")
                }
            }
        }
    }
   
    
    private var effectiveVideoURL: URL? {
        downloadedVideoURL ?? videoURL
    }
    
    private func downloadVideo() {
        guard let fileId = fileId else { return }
        
        isDownloading = true
        playerError = nil
        
        apiService.downloadFile(fileId: fileId, fileType: "video") { result in
            DispatchQueue.main.async {
                isDownloading = false
                
                switch result {
                case .success(let url):
                    downloadedVideoURL = url
                    setupPlayer(url: url)
                    
                case .failure(let error):
                    playerError = "Failed to download video: \(error.localizedDescription)"
                    print("Error downloading video: \(error.localizedDescription)")
                }
            }
        }
    }
        
    private func captureFrameFromVideo() {
        print("📸 Starting frame capture...")
        guard let player = player, let currentItem = player.currentItem else { 
            print("❌ Player or item missing")
            return 
        }
        
        let currentTime = player.currentTime()
        print("⏱️ Time: \(currentTime.seconds)")
        let asset = currentItem.asset
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        Task {
            do {
                print("⏳ Generating image...")
                let (cgImage, actualTime) = try await generator.image(at: currentTime)
                print("✅ Image generated at \(actualTime.seconds)")
                let uiImage = UIImage(cgImage: cgImage)
                print("🖼️ UIImage created: \(uiImage.size)")
                
                await MainActor.run {
                    print("💾 Setting state: capturedImage = \(uiImage)")
                    self.viewModel.capturedImage = uiImage
                    
                    // Verify it was set
                    if self.viewModel.capturedImage != nil {
                         print("✅ capturedImage set successfully")
                         print("💾 Setting state: show2DViewer")
                         self.show2DViewer = true
                         player.pause()
                         self.isPlaying = false
                    } else {
                         print("❌ Failed to set capturedImage (it is nil after assignment?)")
                    }
                }
            } catch {
                print("❌ Error capturing frame: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupPlayer(url: URL) {
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        player = newPlayer
        
        // Observe player item status
        let statusObserver = playerItem.observe(\.status, options: [.new]) { [weak playerItem] item, _ in
            DispatchQueue.main.async {
                checkPlayerStatus(playerItem: item)
            }
        }
        
        // Observe playback end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak newPlayer] _ in
            guard let player = newPlayer else { return }
            player.seek(to: .zero)
            isPlaying = false
        }
        
        // Observe playback errors
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("ERROR: Video playback failed: \(error.localizedDescription)")
                self.playerError = error.localizedDescription
            }
        }
    }
    
    private func checkPlayerStatus(playerItem: AVPlayerItem) {
        switch playerItem.status {
        case .readyToPlay:
            print("Video player ready to play")
            playerError = nil
        case .failed:
            if let error = playerItem.error {
                print("ERROR: Player item failed: \(error.localizedDescription)")
                playerError = error.localizedDescription
            }
        case .unknown:
            print("Player item status unknown")
        @unknown default:
            break
        }
    }
}

