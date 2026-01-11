//
//  DepthDataModel.swift
//  LiDARPOC
//
//  Created by Siva Sandeep on 13/12/25.
//

import Foundation
import ARKit
import CoreVideo
import CoreImage

struct DepthFrameData: Codable {
    let timestamp: TimeInterval
    let intrinsics: [Float]  // 3x3 matrix flattened to array
    let cameraTransform: [Float]   // 4x4 matrix - frame.camera.transform
    let transform: [Float]   // 4x4 matrix - frame.transform (same as camera.transform but stored separately)
    let position: [Float]    // Camera position in world space [x, y, z]
    let orientation: [Float] // Camera orientation as quaternion [x, y, z, w]
    let eulerAngles: [Float] // Camera orientation as Euler angles [roll, pitch, yaw] in radians
    let capturedImageWidth: Int   // Width of camera image
    let capturedImageHeight: Int  // Height of camera image
    let depthToImageScale: [Float] // [scaleX, scaleY] to upscale depth to image size
    let depthMapFilePath: String?  // File path to saved depth map (saved separately to reduce JSON memory)
    let depthMapWidth: Int
    let depthMapHeight: Int
    let imageFilePath: String?  // File path to saved frame image (instead of base64 to save memory)
}

class DepthDataManager {
    static let shared = DepthDataManager()
    
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    private init() {}
    
    func saveDepthFrames(_ frames: [DepthFrameData], to url: URL) {
        do {
            // JSON encoding is now much more memory-efficient since depth maps are saved as separate files
            // Only metadata (transforms, timestamps, file paths) are stored in JSON
            let encoder = JSONEncoder()
            encoder.outputFormatting = [] // No pretty printing to save memory
            let data = try encoder.encode(frames)
            try data.write(to: url)
            print("Saved \(frames.count) depth frames to \(url.path) (depth maps saved as separate files)")
        } catch {
            print("Error saving depth frames: \(error.localizedDescription)")
        }
    }
    
    /// Extract depth data from ARFrame and scale to target resolution
    /// - Parameters:
    ///   - frame: The ARFrame containing depth information
    ///   - targetWidth: Target width for depth map (low resolution to save memory)
    ///   - targetHeight: Target height for depth map (low resolution to save memory)
    ///   - videoWidth: Video/image width (for reference)
    ///   - videoHeight: Video/image height (for reference)
    ///   - baseName: Base name for saving depth map file (same as video/JSON)
    ///   - frameNumber: Frame number for unique file naming
    /// - Returns: DepthFrameData with scaled depth map saved to file
    func depthDataFromARFrame(_ frame: ARFrame, targetWidth: Int, targetHeight: Int, videoWidth: Int, videoHeight: Int, baseName: String, frameNumber: Int) -> DepthFrameData? {
        // Get intrinsics (3x3 matrix)
        let intrinsics = frame.camera.intrinsics
        var intrinsicsArray: [Float] = []
        for i in 0..<3 {
            for j in 0..<3 {
                intrinsicsArray.append(intrinsics[i][j])
            }
        }
        
        // Get camera transform (4x4 matrix) - frame.camera.transform
        let cameraTransform = frame.camera.transform
        var cameraTransformArray: [Float] = []
        for i in 0..<4 {
            for j in 0..<4 {
                cameraTransformArray.append(cameraTransform[i][j])
            }
        }
        
        // Get frame transform (4x4 matrix) - frame.transform
        // Note: In ARKit, frame.transform is the same as frame.camera.transform
        // But we'll capture it explicitly as requested
        let frameTransform = frame.camera.transform  // This is the transform property
        var frameTransformArray: [Float] = []
        for i in 0..<4 {
            for j in 0..<4 {
                frameTransformArray.append(frameTransform[i][j])
            }
        }
        
        // Extract position (translation) from transform matrix
        // Position is in column 3 (indices [3][0], [3][1], [3][2])
        let position = [
            frameTransform[3][0],  // x
            frameTransform[3][1],  // y
            frameTransform[3][2]   // z
        ]
        
        // Extract orientation from transform matrix
        // Orientation is the 3x3 rotation matrix (columns 0-2, rows 0-2)
        let rotationMatrix = simd_float3x3(
            simd_float3(frameTransform[0][0], frameTransform[0][1], frameTransform[0][2]),
            simd_float3(frameTransform[1][0], frameTransform[1][1], frameTransform[1][2]),
            simd_float3(frameTransform[2][0], frameTransform[2][1], frameTransform[2][2])
        )
        
        // Convert rotation matrix to quaternion
        let quaternion = quaternionFromRotationMatrix(rotationMatrix)
        
        // Convert rotation matrix to Euler angles
        let eulerAngles = eulerAnglesFromRotationMatrix(rotationMatrix)
        
        // Get depth map and captured image size
        var depthMapFilePath: String? = nil
        var depthWidth = targetWidth  // Low resolution depth (256x192)
        var depthHeight = targetHeight  // Low resolution depth (256x192)
        let capturedWidth = CVPixelBufferGetWidth(frame.capturedImage)
        let capturedHeight = CVPixelBufferGetHeight(frame.capturedImage)
        
        if let sceneDepth = frame.sceneDepth {
            let originalDepthMap = sceneDepth.depthMap
            let originalDepthWidth = CVPixelBufferGetWidth(originalDepthMap)
            let originalDepthHeight = CVPixelBufferGetHeight(originalDepthMap)
            
            // Scale depth map to low resolution (256x192) to save memory
            var depthMapToSave: CVPixelBuffer? = nil
            if let scaledDepthMap = upscaleDepthMap(originalDepthMap, toWidth: targetWidth, toHeight: targetHeight) {
                depthMapToSave = scaledDepthMap
                print("✅ Depth map scaled from \(originalDepthWidth)x\(originalDepthHeight) to \(targetWidth)x\(targetHeight)")
            } else {
                print("WARNING: Failed to scale depth map, using original resolution")
                depthMapToSave = originalDepthMap
                depthWidth = originalDepthWidth
                depthHeight = originalDepthHeight
            }
            
            // Save depth map to file immediately to avoid memory accumulation
            if let depthMap = depthMapToSave {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let timestamp = Int(frame.timestamp * 1000)
                let depthFileName = "\(baseName)_depth_\(frameNumber)_\(timestamp).bin"
                let depthFileURL = documentsPath.appendingPathComponent(depthFileName)
                
                CVPixelBufferLockBaseAddress(depthMap, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
                
                if let baseAddress = CVPixelBufferGetBaseAddress(depthMap) {
                    let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
                    let dataSize = depthHeight * bytesPerRow
                    let depthData = Data(bytes: baseAddress, count: dataSize)
                    
                    do {
                        try depthData.write(to: depthFileURL)
                        depthMapFilePath = depthFileName
                        print("💾 Saved depth map (\(depthWidth)x\(depthHeight)) to: \(depthFileName), \(dataSize) bytes")
                    } catch {
                        print("⚠️ Failed to save depth map: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            print("WARNING: sceneDepth is nil")
        }
        
        // Calculate scale from depth resolution to video/image resolution
        let depthToVideoScaleX = depthWidth > 0 ? Float(videoWidth) / Float(depthWidth) : 0
        let depthToVideoScaleY = depthHeight > 0 ? Float(videoHeight) / Float(depthHeight) : 0
        
        return DepthFrameData(
            timestamp: frame.timestamp,
            intrinsics: intrinsicsArray,
            cameraTransform: cameraTransformArray,
            transform: frameTransformArray,
            position: position,
            orientation: [quaternion.imag.x, quaternion.imag.y, quaternion.imag.z, quaternion.real],
            eulerAngles: eulerAngles,
            capturedImageWidth: videoWidth,  // Video/image resolution (1280x960)
            capturedImageHeight: videoHeight,  // Video/image resolution (1280x960)
            depthToImageScale: [depthToVideoScaleX, depthToVideoScaleY],  // Scale from depth (256x192) to video (1280x960)
            depthMapFilePath: depthMapFilePath,
            depthMapWidth: depthWidth,
            depthMapHeight: depthHeight,
            imageFilePath: nil  // Will be set later when frame image is saved
        )
    }
    
    // Convert rotation matrix to quaternion
    private func quaternionFromRotationMatrix(_ matrix: simd_float3x3) -> simd_quatf {
        return simd_quatf(matrix)
    }
    
    // Convert rotation matrix to Euler angles (roll, pitch, yaw) in radians
    private func eulerAnglesFromRotationMatrix(_ matrix: simd_float3x3) -> [Float] {
        // Extract Euler angles from rotation matrix
        // Using ZYX convention (yaw, pitch, roll)
        let m = matrix
        
        let sy = sqrt(m[0][0] * m[0][0] + m[1][0] * m[1][0])
        
        var roll: Float, pitch: Float, yaw: Float
        
        if sy > 1e-6 {
            roll = atan2(m[2][1], m[2][2])
            pitch = atan2(-m[2][0], sy)
            yaw = atan2(m[1][0], m[0][0])
        } else {
            roll = atan2(-m[1][2], m[1][1])
            pitch = atan2(-m[2][0], sy)
            yaw = 0
        }
        
        return [roll, pitch, yaw]  // [roll, pitch, yaw] in radians
    }
    
    /// Upscale depth map to target resolution using bilinear interpolation
    /// Depth maps are typically Float32 format, so we use vImage for efficient upscaling
    private func upscaleDepthMap(_ depthMap: CVPixelBuffer, toWidth: Int, toHeight: Int) -> CVPixelBuffer? {
        let sourceWidth = CVPixelBufferGetWidth(depthMap)
        let sourceHeight = CVPixelBufferGetHeight(depthMap)
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
        
        // If already at target resolution, return original
        if sourceWidth == toWidth && sourceHeight == toHeight {
            return depthMap
        }
        
        // Create output pixel buffer
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            toWidth,
            toHeight,
            pixelFormat,
            [
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                kCVPixelBufferMetalCompatibilityKey: true as CFBoolean
            ] as CFDictionary,
            &outputBuffer
        )
        
        guard status == kCVReturnSuccess, let output = outputBuffer else {
            print("ERROR: Failed to create output depth buffer")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(output, [])
        }
        
        // Use Core Image for upscaling (handles Float32 depth data well)
        let ciImage = CIImage(cvPixelBuffer: depthMap)
        let scaleTransform = CGAffineTransform(
            scaleX: CGFloat(toWidth) / CGFloat(sourceWidth),
            y: CGFloat(toHeight) / CGFloat(sourceHeight)
        )
        let scaledImage = ciImage.transformed(by: scaleTransform)
        
        ciContext.render(scaledImage, to: output)
        
        return output
    }
}

