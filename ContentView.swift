import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import AVKit

enum SortOption: String, CaseIterable {
    case alphabetical = "Alphabetical"
    case oldest = "Oldest First"
    case largest = "Largest First"
}

struct ContentView: View {
    @State private var selectedDirectory: URL?
    @State private var files: [FileItem] = []
    @State private var showingFolderPicker = false
    @State private var errorMessage: String?
    @State private var directoryAccess: NSObject? 
    @State private var sortOption: SortOption = .alphabetical
    
    var body: some View {
        VStack(spacing: 24) {
            // Header with better styling
            VStack(spacing: 8) {
                Text("Swipe Files")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.top, 8)
                
                Text("Swipe left to delete • Swipe right to keep")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Select folder button with better styling
            Button(action: {
                showingFolderPicker = true
            }) {
                HStack {
                    Image(systemName: "folder.fill")
                    Text("Select Folder")
                        .font(.system(size: 16, weight: .semibold))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .fileImporter(
                isPresented: $showingFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        // Start accessing security-scoped resource and keep it active
                        let hasAccess = url.startAccessingSecurityScopedResource()
                        if hasAccess {
                            selectedDirectory = url
                            // Keep a reference to maintain access
                            directoryAccess = url as NSObject
                            loadFiles(from: url)
                        } else {
                            errorMessage = "Could not access selected folder"
                        }
                    }
                case .failure(let error):
                    errorMessage = "Error selecting folder: \(error.localizedDescription)"
                    print("Error selecting folder: \(error)")
                }
            }
            
            // Show selected folder path with better styling
            if let directory = selectedDirectory {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text(directory.lastPathComponent)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    // Sort options picker with better styling
                    if !files.isEmpty {
                        Picker("Sort by", selection: $sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 40)
                        .onChange(of: sortOption) { _ in
                            sortFiles()
                        }
                    }
                }
            }
            
            // Error message
            if let error = errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            }
            
            // Single file view (one at a time)
            if files.isEmpty && selectedDirectory != nil && errorMessage == nil {
                Text("No files found in this folder")
                    .foregroundColor(.secondary)
                    .padding()
            } else if let currentFile = files.first {
                SwipeableFileCard(
                    file: currentFile,
                    onDelete: { deleteFile(currentFile) },
                    onKeep: { keepFile(currentFile) }
                )
                .padding(.top, 12)
            }
            
            Spacer()
        }
        .frame(width: 700, height: 820)
        .padding()
        .background {
            // Subtle gradient background
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color(NSColor.windowBackgroundColor).opacity(0.8)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    // Load files from directory
    func loadFiles(from url: URL) {
        files = []
        errorMessage = nil
        
        do {
            // Access is already started when folder is selected, but ensure it's active
            let hasAccess = url.startAccessingSecurityScopedResource()
            guard hasAccess else {
                errorMessage = "Could not access folder"
                return
            }
            
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            print("Found \(fileURLs.count) files in directory")
            
            files = fileURLs.map { url in
                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                let isDirectory = resourceValues?.isDirectory ?? false
                let size = resourceValues?.fileSize ?? 0
                let modifiedDate = resourceValues?.contentModificationDate ?? Date.distantPast
                return FileItem(
                    id: url.path,
                    name: url.lastPathComponent,
                    url: url,
                    isDirectory: isDirectory,
                    size: Int64(size),
                    modifiedDate: modifiedDate
                )
            }
            
            sortFiles()
            
            print("Loaded \(files.count) files")
            
        } catch {
            errorMessage = "Error loading files: \(error.localizedDescription)"
            print("Error loading files: \(error)")
        }
    }
    
    // Sort files based on selected option
    func sortFiles() {
        switch sortOption {
        case .alphabetical:
            files.sort { $0.name < $1.name }
        case .oldest:
            files.sort { $0.modifiedDate < $1.modifiedDate }
        case .largest:
            files.sort { $0.size > $1.size }
        }
    }
    
    // Format file size
    func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // Delete file (moves to Trash)
    func deleteFile(_ file: FileItem) {
        // Make sure we have access to the parent directory
        guard let parentDir = selectedDirectory else {
            errorMessage = "No directory selected"
            return
        }
        
        // Ensure we have security-scoped access (should already be active, but ensure it)
        let hasAccess = parentDir.startAccessingSecurityScopedResource()
        guard hasAccess else {
            errorMessage = "Lost access to folder. Please select it again."
            return
        }
        
        // Remove from list immediately for better UX
        files.removeAll { $0.id == file.id }
        
        // Move file to Trash instead of permanently deleting
        do {
            let fileManager = FileManager.default
            
            // Check if file exists
            guard fileManager.fileExists(atPath: file.url.path) else {
                print("File doesn't exist: \(file.name)")
                return
            }
            
            // Move to Trash
            var resultingURL: NSURL?
            try fileManager.trashItem(at: file.url, resultingItemURL: AutoreleasingUnsafeMutablePointer<NSURL?>(&resultingURL))
            print("Moved to Trash: \(file.name)")
        } catch {
            errorMessage = "Failed to move \(file.name) to Trash: \(error.localizedDescription)"
            print("Trash error: \(error)")
            print("File path: \(file.url.path)")
            // Re-add to list if deletion failed
            files.append(file)
            files.sort { $0.name < $1.name }
        }
    }
    
    // Keep file (just remove from list, file stays)
    func keepFile(_ file: FileItem) {
        files.removeAll { $0.id == file.id }
        print("Kept: \(file.name)")
    }
}

// File item model
struct FileItem: Identifiable {
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let modifiedDate: Date
}

// Single card for one-file-at-a-time swiping
struct SwipeableFileCard: View {
    let file: FileItem
    let onDelete: () -> Void
    let onKeep: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    private let deleteThreshold: CGFloat = -150
    private let keepThreshold: CGFloat = 150
    
    var body: some View {
        ZStack {
            // Background indicators
            HStack {
                Spacer()
                if dragOffset < -50 {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.red.opacity(0.25))
                        .overlay(
                            HStack {
                                Image(systemName: "trash.fill")
                                    .foregroundColor(.red)
                                    .font(.title)
                                Text("Delete")
                                    .foregroundColor(.red)
                                    .fontWeight(.bold)
                            }
                        )
                } else if dragOffset > 50 {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.green.opacity(0.25))
                        .overlay(
                            HStack {
                                Text("Keep")
                                    .foregroundColor(.green)
                                    .fontWeight(.bold)
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title)
                            }
                        )
                }
            }
            
            // Card content
            VStack(spacing: 16) {
                // Icon + name with better styling
                VStack(spacing: 8) {
                    Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                        .foregroundStyle(
                            LinearGradient(
                                colors: file.isDirectory ? [.blue, .cyan] : [.gray, .secondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .font(.system(size: 48, weight: .medium))
                    
                    Text(file.name)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .foregroundColor(.primary)
                    
                    Text(formatFileSize(file.size))
                        .foregroundColor(.secondary)
                        .font(.system(size: 13, weight: .medium))
                }
                
                // Preview area
                if let image = loadImagePreview() {
                    // Image preview (large)
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 520)
                        .cornerRadius(12)
                } else if isVideoFile() {
                    // Video preview (large)
                    VideoPreviewView(url: file.url)
                        .frame(maxHeight: 520)
                        .cornerRadius(12)
                } else if isPDFFile() {
                    // PDF preview (large)
                    PDFPreviewView(url: file.url)
                        .frame(maxHeight: 520)
                        .cornerRadius(12)
                } else if let text = loadTextPreview() {
                    // Text preview (first lines)
                    ScrollView {
                        Text(text)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                }

                // Open in default app
                Button {
                    openInDefaultApp()
                } label: {
                    Label("Open in Default App", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
            }
            .offset(x: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.width
                    }
                    .onEnded { _ in
                        if dragOffset < deleteThreshold {
                            withAnimation {
                                dragOffset = -600
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                onDelete()
                                dragOffset = 0
                            }
                        } else if dragOffset > keepThreshold {
                            withAnimation {
                                dragOffset = 600
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                onKeep()
                                dragOffset = 0
                            }
                        } else {
                            withAnimation(.spring()) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
        .frame(height: 580)
        .padding(.horizontal, 32)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Preview helpers
    
    // Simple image type check
    private func isImageFile() -> Bool {
        let ext = file.url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "tiff", "bmp", "webp"].contains(ext)
    }
    
    // Simple text type check
    private func isTextFile() -> Bool {
        let ext = file.url.pathExtension.lowercased()
        return ["txt", "md", "json", "csv", "log", "xml", "html", "swift", "py", "js", "ts"].contains(ext)
    }
    
    private func isPDFFile() -> Bool {
        file.url.pathExtension.lowercased() == "pdf"
    }
    
    private func isVideoFile() -> Bool {
        let ext = file.url.pathExtension.lowercased()
        return ["mp4", "mov", "avi", "mkv", "m4v", "webm", "flv", "wmv", "mpg", "mpeg", "3gp"].contains(ext)
    }
    
    private func loadImagePreview() -> NSImage? {
        guard !file.isDirectory, isImageFile() else { return nil }
        
        // Check file size - skip if larger than 50MB to prevent memory issues
        let maxFileSize: Int64 = 50 * 1024 * 1024 // 50MB
        if file.size > maxFileSize {
            print("Skipping image preview - file too large: \(file.size) bytes")
            return nil
        }
        
        // Load image
        guard let originalImage = NSImage(contentsOf: file.url) else {
            return nil
        }
        
        // Resize if image is too large (max 2000px on longest side)
        let maxDimension: CGFloat = 2000
        let originalSize = originalImage.size
        let maxSize = max(originalSize.width, originalSize.height)
        
        // If image is already small enough, return as-is
        if maxSize <= maxDimension {
            return originalImage
        }
        
        // Calculate new size maintaining aspect ratio
        let scale = maxDimension / maxSize
        let newSize = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)
        
        // Create resized image
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        originalImage.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        resizedImage.unlockFocus()
        
        return resizedImage
    }
    
    private func loadTextPreview() -> String? {
        guard !file.isDirectory, isTextFile() else { return nil }
        do {
            let content = try String(contentsOf: file.url, encoding: .utf8)
            // Limit to first ~40 lines / 2KB
            let lines = content.split(separator: "\n")
            let previewLines = lines.prefix(40)
            var preview = previewLines.joined(separator: "\n")
            if preview.count > 2000 {
                preview = String(preview.prefix(2000))
            }
            if preview.count < content.count {
                preview += "\n\n… (truncated preview)"
            }
            return preview
        } catch {
            return nil
        }
    }

    private func openInDefaultApp() {
        // Ensure security-scoped access
        _ = file.url.startAccessingSecurityScopedResource()
        NSWorkspace.shared.open(file.url)
    }
}

// PDF preview using PDFKit
struct PDFPreviewView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayBox = .cropBox
        pdfView.backgroundColor = NSColor.clear
        
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }
        
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        // No dynamic updates needed for now
    }
}

// Video preview using AVKit
struct VideoPreviewView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        let player = AVPlayer(url: url)
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = false
        playerView.showsSharingServiceButton = false
        
        // Store player and observer in context
        context.coordinator.player = player
        context.coordinator.playerView = playerView
        
        // Auto-play and loop
        player.play()
        player.actionAtItemEnd = .none
        
        // Loop the video
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        
        context.coordinator.observer = observer
        
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Update if URL changes
        if nsView.player?.currentItem?.asset as? AVURLAsset != AVURLAsset(url: url) {
            // Stop old player
            context.coordinator.stop()
            
            // Create new player
            let newPlayer = AVPlayer(url: url)
            nsView.player = newPlayer
            context.coordinator.player = newPlayer
            context.coordinator.playerView = nsView
            
            // Setup loop observer
            let observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: newPlayer.currentItem,
                queue: .main
            ) { _ in
                newPlayer.seek(to: .zero)
                newPlayer.play()
            }
            context.coordinator.observer = observer
            
            newPlayer.play()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.stop()
    }
    
    class Coordinator {
        var player: AVPlayer?
        var playerView: AVPlayerView?
        var observer: NSObjectProtocol?
        
        func stop() {
            // Remove observer
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            
            // Stop and cleanup player
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
            playerView = nil
        }
        
        deinit {
            stop()
        }
    }
}

#Preview {
    ContentView()
}

