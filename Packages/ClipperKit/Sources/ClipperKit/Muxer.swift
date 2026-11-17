import AVFoundation

/// Combines separate DASH video and audio files (Reddit) into one MP4 without re-encoding.
enum Muxer {
    static func merge(video: URL, audio: URL, to output: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)

        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ClipperError.noVideo("The downloaded file has no video track.") }

        let duration = try await videoAsset.load(.duration)
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
        compVideo.preferredTransform = try await videoTrack.load(.preferredTransform)

        if let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
           let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let audioDuration = try await audioAsset.load(.duration)
            try compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: min(duration, audioDuration)), of: audioTrack, at: .zero)
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw ClipperError.noVideo("Couldn't merge the video and audio.")
        }
        try? FileManager.default.removeItem(at: output)
        if #available(iOS 18, macOS 15, *) {
            try await export.export(to: output, as: .mp4)
        } else {
            export.outputURL = output
            export.outputFileType = .mp4
            await export.export()
            if let error = export.error { throw error }
        }
    }
}
