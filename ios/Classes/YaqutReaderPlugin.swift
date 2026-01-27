import Flutter
import UIKit
import YaqutReader

public class YaqutReaderPlugin: NSObject, FlutterPlugin {
    var readerBuilder: ReaderBuilder?
    var channel: FlutterMethodChannel?
    var bookId: Int?

    // Download progress EventChannel
    private var downloadProgressEventChannel: FlutterEventChannel?
    private var downloadProgressEventSink: FlutterEventSink?

    // Download management
    private var downloadSession: URLSession?
    private var activeDownloads: [Int: URLSessionDownloadTask] = [:]
    private var downloadProgress: [Int: DownloadProgressInfo] = [:]

    private struct DownloadProgressInfo {
        var bookId: Int
        var progress: Double
        var state: String
        var bytesDownloaded: Int64
        var totalBytes: Int64
        var error: String?
        var destinationPath: String?
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = YaqutReaderPlugin()
        instance.setAppearnce()
        instance.channel = FlutterMethodChannel(name: "yaqut_reader_plugin", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: instance.channel!)

        // Setup EventChannel for download progress
        instance.downloadProgressEventChannel = FlutterEventChannel(
            name: "yaqut_reader_plugin/download_progress",
            binaryMessenger: registrar.messenger()
        )
        instance.downloadProgressEventChannel?.setStreamHandler(instance)

        // Setup URLSession for background downloads
        instance.setupDownloadSession()
    }

    private func setupDownloadSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600 // 1 hour for large files
        downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "startReader":
            if let arguments = call.arguments as? [String: Any],
               let book = arguments["book"] as? [String: Any],
               let style = arguments["style"] as? [String: Any] {
                let header = arguments["header"] as? String
                let path = arguments["path"] as? String
                let token = arguments["access_token"] as? String
                let saved = arguments["saved"] as? String
                print("startReader invoked iOS saved: \(saved)")
                self.startReader(header: header, path: path, accessToken: token, bookData: book, style: style, saved: saved == nil ? "disabled" : saved!)
            }
        case "checkIfLocal":
            if let arguments = call.arguments as? [String: Any] {
                if let bookId = arguments["book_id"] as? Int, let bookFileId = arguments["book_file_id"] as? Int {
                    let bookStorage = BookStorage()
                    let isLocal = bookStorage.isBookLocal(bookId: bookId)
//                     let data: [String: Any] = [
//                         "is_local": isLocal,
//                         "book_id": bookId,
//                         "book_file_id": bookFileId,
//                     ]
                    result(isLocal)
                    return
                }
                result("AppDelegate Falied response")
            }
        case "checkIfSample":
            if let arguments = call.arguments as? [String: Any] {
                if let bookId = arguments["book_id"] as? Int {
                    let bookStorage = BookStorage()
                    let bookInfo = bookStorage.getBookInfo(bookId: bookId)
                    result(bookInfo.isSample)
                    return
               }
                result("AppDelegate Falied response")
           }

           case "getBookLength":
               if let arguments = call.arguments as? [String: Any] {
                   if let bookId = arguments["book_id"] as? Int {
                       let bookStorage = BookStorage()
                       let bookInfo = bookStorage.getBookInfo(bookId: bookId)
                       result(bookInfo.length)
                       return
                   }
                   result(0) // or result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing book_id", details: nil))
               } else {
                   result(0)
               }
        case "deleteSampleBook":
            if let arguments = call.arguments as? [String: Any] {
                if let bookId = arguments["book_id"] as? Int {
                    let bookStorage = BookStorage()
                    let success = bookStorage.deleteBook(bookId: bookId)
                    result(success)
                    return
                }
                result("AppDelegate Falied response")
            }
        case "getLocalBooks":
            let bookStorage = BookStorage()
            let localBooks = bookStorage.getLocalBooks()
            result(localBooks)
            return
        case "removeAllBooks":
            let bookStorage = BookStorage()
            bookStorage.removeAllBooks()
            return
        case "getLocalBooksInfo":
            let bookStorage = BookStorage()
            let filesInfo = bookStorage.checkDeviceFreeSpace()
            let serializedFilesInfo = filesInfo.map { fileInfo in
                return [
                    "id": fileInfo.id,
                    "size": fileInfo.size
                ] as [String: Any]
            }
            result(serializedFilesInfo) // Returning a JSON-serializable array
            return
        case "hideReader":
            self.readerBuilder?.hideReaderView()
            return
        case "showReader":
            self.readerBuilder?.showReaderView()
            return
        case "closeReader":
             self.readerBuilder?.closeBook()
             return
        case "updateMarks":
            if let arguments = call.arguments as? [String: Any], let marks = arguments["marks"] as? [[String: Any]] {
                self.updateMarks(notesAndMarksData: marks)
            }
            return
        case "startDownload":
            handleStartDownload(call: call, result: result)
            return
        case "cancelDownload":
            handleCancelDownload(call: call, result: result)
            return
        case "getDownloadStatus":
            handleGetDownloadStatus(call: call, result: result)
            return
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Download Methods

    private func handleStartDownload(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let bookId = arguments["book_id"] as? Int,
              let urlString = arguments["url"] as? String,
              let url = URL(string: urlString) else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "book_id and url are required", details: nil))
            return
        }

        // Cancel any existing download for this book
        if let existingTask = activeDownloads[bookId] {
            existingTask.cancel()
            activeDownloads.removeValue(forKey: bookId)
        }

        let headers = arguments["headers"] as? [String: String] ?? [:]
        let destinationPath = arguments["destination_path"] as? String

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Initialize progress tracking
        downloadProgress[bookId] = DownloadProgressInfo(
            bookId: bookId,
            progress: 0.0,
            state: "started",
            bytesDownloaded: 0,
            totalBytes: 0,
            error: nil,
            destinationPath: destinationPath
        )

        // Send started event
        sendProgressEvent(bookId: bookId, progress: 0.0, state: "started", bytesDownloaded: 0, totalBytes: 0, error: nil)

        // Create download task
        let downloadTask = downloadSession?.downloadTask(with: request)
        downloadTask?.taskDescription = "\(bookId)"
        activeDownloads[bookId] = downloadTask
        downloadTask?.resume()

        result(true)
    }

    private func handleCancelDownload(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let bookId = arguments["book_id"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "book_id is required", details: nil))
            return
        }

        if let task = activeDownloads[bookId] {
            task.cancel()
            activeDownloads.removeValue(forKey: bookId)
            downloadProgress.removeValue(forKey: bookId)
            sendProgressEvent(bookId: bookId, progress: 0.0, state: "cancelled", bytesDownloaded: 0, totalBytes: 0, error: nil)
            result(true)
        } else {
            result(false)
        }
    }

    private func handleGetDownloadStatus(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let bookId = arguments["book_id"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "book_id is required", details: nil))
            return
        }

        if let progressInfo = downloadProgress[bookId] {
            let statusDict: [String: Any] = [
                "book_id": progressInfo.bookId,
                "progress": progressInfo.progress,
                "state": progressInfo.state,
                "bytes_downloaded": progressInfo.bytesDownloaded,
                "total_bytes": progressInfo.totalBytes,
                "error": progressInfo.error ?? NSNull()
            ]
            result(statusDict)
        } else {
            result(nil)
        }
    }

    private func sendProgressEvent(bookId: Int, progress: Double, state: String, bytesDownloaded: Int64, totalBytes: Int64, error: String?) {
        DispatchQueue.main.async { [weak self] in
            // Send event to Flutter via EventChannel
            var eventDict: [String: Any] = [
                "book_id": bookId,
                "progress": progress,
                "state": state,
                "bytes_downloaded": bytesDownloaded,
                "total_bytes": totalBytes
            ]
            if let error = error {
                eventDict["error"] = error
            }
            self?.downloadProgressEventSink?(eventDict)

            // Note: Native reader progress UI updates are handled via the EventChannel
            // The Flutter app's DownloadController listens to these events
        }
    }

    private func updateMarks(notesAndMarksData: [[String: Any]]) {
        var notesAndMarks = [NotesAndMarks]()
        for item in notesAndMarksData {
            let newItem: [String: Any] = ["bookId": bookId, "markId": item["id"] as? Int ?? 0, "fromOffset": item["location"] as? Int ?? 0, "toOffset": item["length"] as? Int ?? 0, "markColor": item["color"] as? Int ?? 0, "displayText": item["note"] as? String ?? "", "type": item["type"] as? Int ?? 0, "deleted": item["deleted"] as? Int ?? 0, "local": 1]
            let noteAndMark = NotesAndMarks(data: newItem)
            notesAndMarks.append(noteAndMark)
        }
        self.readerBuilder?.updateMarks(allMarks: notesAndMarks)
    }

    private func startReader(header: String?, path: String?, accessToken: String?, bookData: [String: Any], style: [String: Any], saved: String) {
        print("startReader function saved: \(saved)")
        let bookId = bookData["bookId"] as? Int ?? 0
        let bookFileId = bookData["bookFileId"] as? Int ?? 0
        let title = bookData["title"] as? String ?? ""
        let previewPercentage = bookData["previewPercentage"] as? Double ?? 0.15
        let position = bookData["position"] as? Int ?? 0
        self.bookId = bookId
        self.readerBuilder = ReaderBuilder(bookId: bookId, language: Language.arabic)
        self.readerBuilder?.setReaderDelegate(withReaderDelegate: self)
        self.readerBuilder?.setReadingStatsDelegate(withStatsSessionDelegate: self)
        self.readerBuilder?.setMiniPlayerMargin(miniPlayerMargin: 77)
        self.readerBuilder?.setTitle(bookTitle: title)
        self.readerBuilder?.setFileId(fileId: bookFileId)
        if let coverUrl = bookData["coverThumbUrl"] as? String {
            self.readerBuilder?.setCover(coverURL: coverUrl)
        }
        self.readerBuilder?.setPosition(startPosition: position)
        self.readerBuilder?.setPercentageView(previewPercentage: previewPercentage)
        self.readerBuilder?.setDownloadEnabled(downloadEnabled: true)
        print("setSaveState saved: \(saved)")
        if saved == "true" {
            self.readerBuilder?.setSaveState(saveState: .SAVED)
        } else if saved == "false" {
            self.readerBuilder?.setSaveState(saveState: .NOT_SAVED)
        } else {
            self.readerBuilder?.setSaveState(saveState: .DISABLED)
        }
        let notesAndMarksData = bookData["notesAndMarks"] as? [[String: Any]] ?? []
        var notesAndMarks = [NotesAndMarks]()
        for item in notesAndMarksData {
            let newItem: [String: Any] = ["bookId": bookId, "markId": item["id"] as? Int ?? 0, "fromOffset": item["location"] as? Int ?? 0, "toOffset": item["length"] as? Int ?? 0, "markColor": item["color"] as? Int ?? 0, "displayText": item["note"] as? String ?? "", "type": item["type"] as? Int ?? 0, "deleted": item["deleted"] as? Int ?? 0, "local": 1]
            let noteAndMark = NotesAndMarks(data: newItem)
            notesAndMarks.append(noteAndMark)
        }
        self.readerBuilder?.setMarks(allMarks: notesAndMarks)
        
        let readerColor = style["readerColor"] as? Int ?? 0
        let textSize = style["textSize"] as? Int ?? 22
        let isJustified = style["isJustified"] as? Bool ?? true
        let lineSpacingValue = style["lineSpacing"] as? Int ?? 1
        let lineSpacing = LineSpacing(rawValue: lineSpacingValue) ?? LineSpacing.LINESPACE_MEDIUM
        let font = style["font"] as? Int ?? 0
        let readerStyle = ReaderStyle(readerColor: readerColor, readerTextSize: textSize, isJustified: isJustified, lineSpacing: lineSpacing, font: font)
        self.readerBuilder?.setReaderStyle(readerStyle: readerStyle)
        if (path ?? "") == "" {
            self.readerBuilder?.build()
            return
        }
        let saveBookManager = SaveBookManager(bookId: bookId, bodyPath: path ?? "", header: header == "" ? nil : header, token: accessToken == "" ? nil : accessToken)
        let saveBook = saveBookManager.save()
        if saveBook {
            self.readerBuilder?.build()
        }
    }
    
    private func setAppearnce() {
        
        UITableViewHeaderFooterView.appearance().backgroundColor = .blue
        
        UITabBar.appearance().tintColor = UIColor(red: 0.843, green: 0, blue: 0.212, alpha: 1)
        UITabBar.appearance().unselectedItemTintColor = UIColor.darkGray
        UITabBar.appearance().barTintColor = UIColor.white
        UITabBar.appearance().backgroundColor = UIColor.white
        
        let coconDescriptor = UIFontDescriptor(fontAttributes: [UIFontDescriptor.AttributeName.family: "Tajawal", UIFontDescriptor.AttributeName.face: "Regular"])
        let tajaDescriptor = UIFontDescriptor(fontAttributes: [UIFontDescriptor.AttributeName.family: "CoconÆ Next Arabic", UIFontDescriptor.AttributeName.face: "Regular"])
        
        UITabBarItem.appearance().setTitleTextAttributes([NSAttributedString.Key.font: UIFont(descriptor: tajaDescriptor, size: 14.0)], for: .normal)
        
        UIBarButtonItem.appearance(whenContainedInInstancesOf: [UISearchBar.self]).setTitleTextAttributes([NSAttributedString.Key.foregroundColor: UIColor(red: 0.071, green: 0.071, blue: 0.071, alpha: 1), NSAttributedString.Key.font: UIFont(descriptor: coconDescriptor, size: 15)], for: .normal)
        UIBarButtonItem.appearance(whenContainedInInstancesOf: [UISearchBar.self]).title = "إلغاء"
        
        UINavigationBar.appearance().tintColor = UIColor(red: 0.071, green: 0.071, blue: 0.071, alpha: 1)
        UINavigationBar.appearance().barTintColor = UIColor.white
        UINavigationBar.appearance().backgroundColor = UIColor.white
        UINavigationBar.appearance().isTranslucent = false
        UINavigationBar.appearance().titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor(red: 0.071, green: 0.071, blue: 0.071, alpha: 1), NSAttributedString.Key.font: UIFont(descriptor: coconDescriptor, size: 20.0)]
        if #available(iOS 13.0, *) {
            let app = UINavigationBarAppearance()
            app.backgroundColor = UIColor.white
            app.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor(red: 0.071, green: 0.071, blue: 0.071, alpha: 1), NSAttributedString.Key.font: UIFont(descriptor: coconDescriptor, size: 20.0)]
            let img = UIImage(systemName: "chevron.forward")?.withTintColor(UIColor(red: 0.071, green: 0.071, blue: 0.071, alpha: 1), renderingMode: .alwaysOriginal)
            app.setBackIndicatorImage(img, transitionMaskImage: img)
            UINavigationBar.appearance().standardAppearance = app
            UINavigationBar.appearance().scrollEdgeAppearance = app
            UINavigationBar.appearance().compactAppearance = app
        }
        
        UISearchBar.appearance().semanticContentAttribute = .forceRightToLeft
        UISearchBar.appearance().barTintColor = UIColor.white
        UISearchBar.appearance().backgroundColor = UIColor.white
        UISearchBar.appearance().searchBarStyle = .minimal
        UISearchBar.appearance().showsCancelButton = true
        
        UIView.appearance().semanticContentAttribute = .forceRightToLeft
    }
}

extension YaqutReaderPlugin: ReaderDelegate {
    public func onStyleChanged(style: ReaderStyle) {
        let linespace = style.lineSpacing.rawValue
        let readerColor = style.readerColor
        let fontIndex = style.font
        let fontSize = style.textSize
        let layout = style.isJustified ? 1 : 2
        let data: [String: Int] = [
             "line_space": linespace,
             "reader_color": readerColor,
             "font": fontIndex,
             "font_size": fontSize,
             "layout": layout,
             "book_id": self.bookId ?? 0
         ]
         channel?.invokeMethod("onStyleChanged", arguments: data)
    }

    public func onPositionChanged(position: Int) {
        let data:[String: Int] = ["position": position, "book_id": self.bookId ?? 0]
        channel?.invokeMethod("onPositionChanged", arguments: data)
    }

    public func onBookDetailsCLicked() {
        channel?.invokeMethod("onBookDetailsClicked", arguments: [:])
    }

    public func onSaveBookClicked(position: Int) {
        let data:[String: Int] = ["position": position, "book_id": self.bookId ?? 0]
        channel?.invokeMethod("onSaveBookClicked", arguments: data)
    }

    public func onShareBook() {
        channel?.invokeMethod("onShareBook", arguments: [:])
    }

    public func onShareQuotes(text: String) {
        channel?.invokeMethod("onShareQuotes", arguments: ["text": text])
    }

    public func onDownloadBook() {
        channel?.invokeMethod("onDownloadBook", arguments: [:])
    }

    public func onSyncNotesAndMarks(list: [YaqutReader.NotesAndMarks]) {
        var items = [[String: Any]]()
        for mark in list {
            let item: [String: Any] = [
                "book_id": self.bookId ?? 0, "mark_id": mark.markId ?? 0,
                "from_offset": mark.fromOffset,
                "to_offset": mark.toOffset, "mark_color": mark.markColor ?? 0,
                "display_text": mark.displayText ?? "", "type": mark.type,
                "deleted": mark.deleted ?? 0, "local": mark.local ?? 1
            ]
            items.append(item)
        }

        channel?.invokeMethod("onSyncNotes", arguments: items)
    }

    public func onReaderClosed(position: Int) {
        let data:[String: Int] = ["position": position, "book_id": self.bookId ?? 0]
        channel?.invokeMethod("onReaderClosed", arguments: data)
        self.readerBuilder?.closeBook()
        self.readerBuilder = nil
    }

    public func onSampleEnded() {
        channel?.invokeMethod("onSampleEnded", arguments: [:])
    }

    public func onOrientationChanged() {
    print("**> onOrientationChanged")
        channel?.invokeMethod("onOrientationChanged", arguments: [:])
    }
}

extension YaqutReaderPlugin: StatsSessionDelegate {
    public func onReadingSessionEnd(session: YaqutReader.RRReadingSession) {
        let data:[String: Any] = [
            "book_id": session.getBookId(),
            "book_file_id": session.getBookFileId(),
            "pages_read": session.getPagesRead(),
            "start_offset": session.getStartOffset(),
            "end_offset": session.getEndOffset(),
            "covered_offset": session.getCoveredOffset(),
            "covered_length": session.getCoveredLength(),
            "start_time": session.getStartTime(),
            "end_time": session.getEndTime(),
            "md5": session.getMd5(),
            "uuid": session.getUuid()
            ]
        channel?.invokeMethod("onReadingSessionEnd", arguments: data)
    }
}

// MARK: - FlutterStreamHandler for Download Progress EventChannel
extension YaqutReaderPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        downloadProgressEventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        downloadProgressEventSink = nil
        return nil
    }
}

// MARK: - URLSessionDownloadDelegate for Background Downloads
extension YaqutReaderPlugin: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let bookIdStr = downloadTask.taskDescription,
              let bookId = Int(bookIdStr) else { return }

        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            progress = 0.0
        }

        // Update progress tracking
        downloadProgress[bookId] = DownloadProgressInfo(
            bookId: bookId,
            progress: progress,
            state: "downloading",
            bytesDownloaded: totalBytesWritten,
            totalBytes: totalBytesExpectedToWrite,
            error: nil,
            destinationPath: downloadProgress[bookId]?.destinationPath
        )

        // Send progress event
        sendProgressEvent(
            bookId: bookId,
            progress: progress,
            state: "downloading",
            bytesDownloaded: totalBytesWritten,
            totalBytes: totalBytesExpectedToWrite,
            error: nil
        )
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let bookIdStr = downloadTask.taskDescription,
              let bookId = Int(bookIdStr) else { return }

        // Move downloaded file to permanent location
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

        var destinationURL: URL
        if let customPath = downloadProgress[bookId]?.destinationPath {
            destinationURL = URL(fileURLWithPath: customPath)
        } else {
            // Default: save to documents with book ID
            destinationURL = documentsURL.appendingPathComponent("book_\(bookId).epub")
        }

        // Remove existing file if present
        try? fileManager.removeItem(at: destinationURL)

        do {
            try fileManager.moveItem(at: location, to: destinationURL)

            // Update progress tracking
            let totalBytes = downloadProgress[bookId]?.totalBytes ?? 0
            downloadProgress[bookId] = DownloadProgressInfo(
                bookId: bookId,
                progress: 1.0,
                state: "completed",
                bytesDownloaded: totalBytes,
                totalBytes: totalBytes,
                error: nil,
                destinationPath: destinationURL.path
            )

            // Send completed event
            sendProgressEvent(
                bookId: bookId,
                progress: 1.0,
                state: "completed",
                bytesDownloaded: totalBytes,
                totalBytes: totalBytes,
                error: nil
            )
        } catch {
            // Send failed event
            sendProgressEvent(
                bookId: bookId,
                progress: 0.0,
                state: "failed",
                bytesDownloaded: 0,
                totalBytes: 0,
                error: error.localizedDescription
            )
        }

        // Cleanup
        activeDownloads.removeValue(forKey: bookId)
        downloadProgress.removeValue(forKey: bookId)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let bookIdStr = downloadTask.taskDescription,
              let bookId = Int(bookIdStr),
              let error = error else { return }

        // Only handle errors (successful completion is handled in didFinishDownloadingTo)
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled {
            // User cancelled - already handled in cancelDownload
            return
        }

        // Update progress tracking
        downloadProgress[bookId] = DownloadProgressInfo(
            bookId: bookId,
            progress: 0.0,
            state: "failed",
            bytesDownloaded: 0,
            totalBytes: 0,
            error: error.localizedDescription,
            destinationPath: nil
        )

        // Send failed event
        sendProgressEvent(
            bookId: bookId,
            progress: 0.0,
            state: "failed",
            bytesDownloaded: 0,
            totalBytes: 0,
            error: error.localizedDescription
        )

        // Cleanup
        activeDownloads.removeValue(forKey: bookId)
        downloadProgress.removeValue(forKey: bookId)
    }
}