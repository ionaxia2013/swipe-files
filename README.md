# Swipe Files

A macOS app to help manage files by swiping left to delete and right to keep.

## Setup

1. **Open in Xcode:**
   - Open Xcode
   - Go to File → Open
   - Select the `swipe-files` folder
   - Xcode will create an Xcode project for you

2. **Or create an Xcode project:**
   - Open Xcode
   - File → New → Project
   - Choose "macOS" → "App"
   - Name it "SwipeFiles"
   - Language: Swift
   - UI: SwiftUI
   - Then copy the Swift files into the project

3. **Add Entitlements (IMPORTANT for file deletion):**
   - In Xcode, click your project in the left sidebar
   - Select the "SwipeFiles" target
   - Go to the "Signing & Capabilities" tab
   - Click "+ Capability" at the top left
   - Add "App Sandbox"
   - In the App Sandbox section, check:
     - ✅ User Selected File (Read/Write)
     - ✅ Downloads Folder (Read/Write) - optional but helpful
   - OR manually add the entitlements file:
     - Go to "Build Settings" tab
     - Search for "Code Signing Entitlements"
     - Set it to: `SwipeFiles.entitlements`

4. **Run the app:**
   - Press ⌘R or click the Play button
   - The app window should open

## Current Status

- ✅ Basic app structure
- ⏳ File browser (coming next)
- ⏳ Swipe gestures
- ⏳ File deletion

## Next Steps

We'll build this step by step, starting with the ability to browse and display files.

