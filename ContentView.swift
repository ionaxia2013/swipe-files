import SwiftUI
import UniformTypeIdentifiers

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
            
            // File list
            if files.isEmpty && selectedDirectory != nil && errorMessage == nil {
                Text("No files found in this folder")
                    .foregroundColor(.secondary)
                    .padding()
            } else if !files.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(files) { file in
                            SwipeableFileRow(
                                file: file,
                                onDelete: {
                                    deleteFile(file)
                                },
                                onKeep: {
                                    keepFile(file)
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 400)
            }
            
            Spacer()
        }
        .frame(width: 600, height: 600)
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

// Swipeable file row component
struct SwipeableFileRow: View {
    let file: FileItem
    let onDelete: () -> Void
    let onKeep: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    private let swipeThreshold: CGFloat = 100
    private let deleteThreshold: CGFloat = -150
    private let keepThreshold: CGFloat = 150
    
    var body: some View {
        ZStack {
            // Background colors that show when swiping
            HStack {
                Spacer()
                if dragOffset < -50 {
                    // Red background for delete (swipe left)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.3))
                        .overlay(
                            HStack {
                                Image(systemName: "trash.fill")
                                    .foregroundColor(.red)
                                    .font(.title2)
                                Text("Delete")
                                    .foregroundColor(.red)
                                    .fontWeight(.bold)
                            }
                        )
                } else if dragOffset > 50 {
                    // Green background for keep (swipe right)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.3))
                        .overlay(
                            HStack {
                                Text("Keep")
                                    .foregroundColor(.green)
                                    .fontWeight(.bold)
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)
                            }
                        )
                }
            }
            
            // File row content
            HStack {
                Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundColor(file.isDirectory ? .blue : .gray)
                    .frame(width: 30)
                
                Text(file.name)
                    .lineLimit(1)
                
                Spacer()
                
                Text(formatFileSize(file.size))
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .offset(x: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        isDragging = false
                        
                        // Check if swipe was far enough
                        if dragOffset < deleteThreshold {
                            // Swipe left - delete
                            withAnimation {
                                dragOffset = -500
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onDelete()
                            }
                        } else if dragOffset > keepThreshold {
                            // Swipe right - keep
                            withAnimation {
                                dragOffset = 500
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onKeep()
                            }
                        } else {
                            // Not far enough - snap back
                            withAnimation(.spring()) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
        .frame(height: 60)
    }
    
    func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    ContentView()
}

