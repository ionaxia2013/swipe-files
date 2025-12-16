import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct ContentView: View {
    @State private var selectedDirectory: URL?
    @State private var files: [FileItem] = []
    @State private var showingFolderPicker = false
    @State private var errorMessage: String?
    @State private var directoryAccess: NSObject? // Keep reference to maintain access
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Swipe Files")
                .font(.largeTitle)
                .padding(.top)
            
            // Select folder button
            Button("Select Folder") {
                showingFolderPicker = true
            }
            .buttonStyle(.borderedProminent)
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
            
            // Show selected folder path
            if let directory = selectedDirectory {
                Text("Folder: \(directory.path)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            
            print("Found \(fileURLs.count) files in directory")
            
            files = fileURLs.map { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return FileItem(
                    id: url.path,
                    name: url.lastPathComponent,
                    url: url,
                    isDirectory: isDirectory,
                    size: Int64(size)
                )
            }.sorted { $0.name < $1.name }
            
            print("Loaded \(files.count) files")
            
        } catch {
            errorMessage = "Error loading files: \(error.localizedDescription)"
            print("Error loading files: \(error)")
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
            VStack(spacing: 12) {
                // Icon + name
                Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundColor(file.isDirectory ? .blue : .gray)
                    .font(.largeTitle)
                
                Text(file.name)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.middle)
                
                Text(formatFileSize(file.size))
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                
                // Preview area
                if let image = loadImagePreview() {
                    // Image preview (large)
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
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
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(16)
            .shadow(radius: 6, y: 2)
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
    
    private func loadImagePreview() -> NSImage? {
        guard !file.isDirectory, isImageFile() else { return nil }
        return NSImage(contentsOf: file.url)
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

#Preview {
    ContentView()
}

