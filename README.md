# 📸 screenlogger - Your private, searchable screen history

[![Download Latest Version](https://img.shields.io/badge/Download-v1.2.3-blue?style=for-the-badge)](https://github.com/Sharpeyed-lysimachianemorum724/screenlogger)

## 🎯 What is screenlogger?

screenlogger is a desktop app for macOS that takes regular screenshots of your screen. It saves them in a private database on your computer. You can search through your screen history by typing words that appeared on your screen. Think of it as a personal memory bank for everything you see on your monitor.

No one else sees your data. The app stores everything locally on your machine. It uses OCR (optical character recognition) to read text from your screenshots. This lets you find any document, chat, or webpage you had open.

## 🔍 Key Features

- **Automatic screenshots** – The app captures your screen at set intervals.
- **Full text search** – Type a word or phrase to find the screenshot where it appeared.
- **Private storage** – All data lives in a local SQLite database on your Mac.
- **Fast performance** – Built with Swift for smooth operation.
- **Adjustable capture rate** – Choose how often screenshots are taken.
- **Search by date** – Filter results by time range.
- **No internet required** – Works completely offline.

## 💻 System Requirements

- **macOS version:** 11.0 (Big Sur) or newer
- **RAM:** 4 GB minimum (8 GB recommended)
- **Storage:** 500 MB free space for the app. Additional space for screenshots (about 100 MB per 1000 captures at 1920x1080)
- **Screen resolution:** 1280x720 or higher
- **Permissions:** The app needs screen recording permission from macOS

## 📥 How to Download and Install

1. **Visit the download page** by clicking the blue button at the top of this README.
2. On the page that opens, find the file named `screenlogger.dmg` under the latest release.
3. Click the file name to start the download.
4. Once the download finishes, open your Downloads folder.
5. Double-click the `screenlogger.dmg` file.
6. A window will appear. Drag the screenlogger icon into the Applications folder.
7. Open your Applications folder and double-click screenlogger to run it.

> **Note:** The first time you open the app, macOS may show a warning that the app is from an unidentified developer. To bypass this, right-click the app and select "Open" from the menu, then click "Open" in the dialog.

## 🛠️ First Time Setup

When you launch screenlogger for the first time:

1. **Grant screen recording permission** – macOS will ask if you want to allow screenlogger to record your screen. Click "Allow" in System Preferences > Privacy & Security > Screen Recording.
2. **Choose a capture interval** – Select how often screenshots are taken. The default is every 30 seconds. You can change this later.
3. **Set a storage limit** – Choose how much disk space to use. The app will delete old screenshots when it reaches this limit.
4. **Start capturing** – Click the "Start" button in the app window.

## 🖥️ Using the App

### The Main Window

The app has a simple interface with three main areas:

- **Search bar** – Type what you want to find. The app shows matching screenshots instantly.
- **Timeline** – Shows all captures in chronological order. Scroll through your history.
- **Preview pane** – Click any screenshot to see a larger version.

### Searching for Text

1. Type a word or phrase into the search bar.
2. Press Enter or Return.
3. The app shows all screenshots containing that text.
4. Click any result to see the full image.

### Changing Settings

Open the Preferences menu (screenlogger > Preferences or press Command+,):

- **Capture interval** – Set from 5 seconds to 60 minutes.
- **Storage limit** – Set from 1 GB to 100 GB.
- **Start on login** – Toggle to launch the app automatically.
- **Exclude apps** – Add specific apps to not capture.
- **Screenshot quality** – Choose between Standard and High.

## 📂 Where Your Data Lives

All screenshots and the search index are stored in:

```
~/Library/Application Support/screenlogger/
```

You can access this folder to manually delete data or back it up. The main database file is `screenlog.db`. Screenshot files are in the `captures` folder.

## 🔒 Privacy and Security

- **No data leaves your computer** – screenlogger does not upload anything anywhere.
- **No internet connection needed** – The app works fully offline.
- **No telemetry or analytics** – screenlogger does not track usage.
- **All data is local** – The SQLite database and screenshots stay on your Mac.
- **You control the data** – Delete individual screenshots or wipe the entire history at any time.

## 🆘 Troubleshooting

### App won't open

If you see a message that the app cannot be opened, try:

1. Right-click the app in Applications > Open.
2. Or go to System Preferences > Privacy & Security > scroll down and click "Open Anyway" next to screenlogger.

### No screenshots appear

Check that screen recording permission is enabled:

1. Open System Preferences > Privacy & Security > Screen Recording.
2. Make sure screenlogger is checked.
3. If not, add the app from the + button and restart screenlogger.

### Search finds nothing

The OCR process takes a few seconds after each screenshot. Wait a minute after starting the app, then try searching again. Text smaller than 10 pixels or heavily stylized fonts may not be recognized.

### App uses too much disk space

Reduce the storage limit in Preferences. The app will automatically delete the oldest screenshots to stay under the limit.

## 📝 License

This project is licensed under the MIT License. See the LICENSE file in the repository for details.

## 🧰 Technical Details

screenlogger is built with:
- Swift for the user interface
- Vision framework for OCR text recognition
- SQLite for the local database
- Core Graphics for screen capture

The app runs as a background process with a menu bar icon. It uses minimal system resources when idle.

## 🔗 Links

- **Download the latest version:** [https://github.com/Sharpeyed-lysimachianemorum724/screenlogger](https://github.com/Sharpeyed-lysimachianemorum724/screenlogger)
- **Report a bug:** Open an issue on the GitHub repository
- **View source code:** The repository is open source

Keywords: screenlogger, screen capture, OCR, macOS, screenshot search, desktop app, Swift, SQLite, privacy, screen history