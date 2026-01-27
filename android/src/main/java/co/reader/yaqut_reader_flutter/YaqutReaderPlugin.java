package co.reader.yaqut_reader_flutter;

import android.app.Activity;
import android.app.Application;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

import co.yaqut.reader.api.BookInfo;
import co.yaqut.reader.api.FileSizeInfo;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

import co.yaqut.reader.api.BookStorage;
import co.yaqut.reader.api.ReaderBuilder;
import co.yaqut.reader.api.ReaderStyle;
import co.yaqut.reader.api.SaveBookManager;
import co.yaqut.reader.api.ReaderManager;
import co.yaqut.reader.api.NotesAndMarks;

import okhttp3.Call;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.ResponseBody;

/**
 * Flutter plugin for Yaqut Reader integration.
 * Handles communication between Flutter and native Android reader library.
 */
public class YaqutReaderPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private MethodChannel channel;
    private Context applicationContext;
    private Activity activity;
    private ReaderBuilder readerBuilder;
    private static final String TAG = "YaqutReaderPlugin";
    private int bookId;

    // Flag to prevent double-open race condition
    private final AtomicBoolean isReaderOpening = new AtomicBoolean(false);
    private final AtomicBoolean isReaderOpen = new AtomicBoolean(false);

    // Download progress EventChannel
    private EventChannel downloadProgressEventChannel;
    private EventChannel.EventSink downloadProgressEventSink;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    // Download management
    private final ExecutorService downloadExecutor = Executors.newFixedThreadPool(2);
    private final OkHttpClient downloadClient = new OkHttpClient.Builder()
            .connectTimeout(60, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(60, java.util.concurrent.TimeUnit.SECONDS)
            .writeTimeout(60, java.util.concurrent.TimeUnit.SECONDS)
            .build();
    private final ConcurrentHashMap<Integer, Call> activeDownloads = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<Integer, DownloadProgressInfo> downloadProgress = new ConcurrentHashMap<>();

    // Download progress info class
    private static class DownloadProgressInfo {
        int bookId;
        double progress;
        String state;
        long bytesDownloaded;
        long totalBytes;
        String error;
        String destinationPath;

        DownloadProgressInfo(int bookId, double progress, String state, long bytesDownloaded, long totalBytes, String error, String destinationPath) {
            this.bookId = bookId;
            this.progress = progress;
            this.state = state;
            this.bytesDownloaded = bytesDownloaded;
            this.totalBytes = totalBytes;
            this.error = error;
            this.destinationPath = destinationPath;
        }
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        Log.i(TAG, "onAttachedToEngine: ");
        applicationContext = flutterPluginBinding.getApplicationContext();
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "yaqut_reader_plugin");
        channel.setMethodCallHandler(this);
        ChannelManager.getInstance().setChannel(channel);

        // Setup EventChannel for download progress
        downloadProgressEventChannel = new EventChannel(
                flutterPluginBinding.getBinaryMessenger(),
                "yaqut_reader_plugin/download_progress"
        );
        downloadProgressEventChannel.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink events) {
                downloadProgressEventSink = events;
            }

            @Override
            public void onCancel(Object arguments) {
                downloadProgressEventSink = null;
            }
        });

        if (applicationContext instanceof Application) {
            // Initialize ReaderManager with Application context
            ReaderManager.initialize((Application) applicationContext);
        } else {
            throw new IllegalStateException("Unable to obtain Application instance from context");
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        Log.i(TAG, "onDetachedFromEngine: ");
        channel.setMethodCallHandler(null);
        channel = null;
        ChannelManager.getInstance().setChannel(channel);

        // Cleanup download resources
        if (downloadProgressEventChannel != null) {
            downloadProgressEventChannel.setStreamHandler(null);
            downloadProgressEventChannel = null;
        }
        downloadProgressEventSink = null;

        // Cancel all active downloads
        for (Call call : activeDownloads.values()) {
            call.cancel();
        }
        activeDownloads.clear();
        downloadProgress.clear();

        // Shutdown executor (don't await termination to avoid blocking)
        downloadExecutor.shutdown();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        Log.d(TAG, "Method called: " + call.method);

        try {
            switch (call.method) {
                case "getPlatformVersion":
                    result.success("Android " + android.os.Build.VERSION.RELEASE);
                    break;

                case "startReader":
                    handleStartReader(call, result);
                    break;

                case "closeReader":
                    handleCloseReader(result);
                    break;

                case "checkIfLocal":
                    handleCheckIfLocal(call, result);
                    break;

                case "checkIfSample":
                    handleCheckIfSample(call, result);
                    break;

                case "getBookLength":
                    handleGetBookLength(call, result);
                    break;

                case "deleteSampleBook":
                    handleDeleteSampleBook(call, result);
                    break;

                case "getLocalBooks":
                    handleGetLocalBooks(result);
                    break;

                case "removeAllBooks":
                    handleRemoveAllBooks(result);
                    break;

                case "getLocalBooksInfo":
                    handleGetLocalBooksInfo(result);
                    break;

                case "hideReader":
                    ReaderBuilder.hideReader();
                    result.success(null);
                    break;

                case "showReader":
                    ReaderBuilder.showReader();
                    result.success(null);
                    break;

                case "updateMarks":
                    handleUpdateMarks(call, result);
                    break;

                case "startDownload":
                    handleStartDownload(call, result);
                    break;

                case "cancelDownload":
                    handleCancelDownload(call, result);
                    break;

                case "getDownloadStatus":
                    handleGetDownloadStatus(call, result);
                    break;

                default:
                    result.notImplemented();
            }
        } catch (Exception e) {
            Log.e(TAG, "Error handling method " + call.method + ": " + e.getMessage(), e);
            result.error("PLUGIN_ERROR", "Error in " + call.method + ": " + e.getMessage(), null);
        }
    }

    private void handleStartReader(MethodCall call, MethodChannel.Result result) {
        // Check for activity
        if (activity == null) {
            Log.e(TAG, "startReader: Activity is null");
            result.error("NO_ACTIVITY", "Activity context is not available. Reader cannot be started.", null);
            return;
        }

        // Prevent double-open race condition
        if (!isReaderOpening.compareAndSet(false, true)) {
            Log.w(TAG, "startReader: Reader is already being opened, ignoring duplicate request");
            result.error("READER_BUSY", "Reader is already being opened", null);
            return;
        }

        // If a reader is marked as open, close it first before opening a new one
        if (isReaderOpen.get()) {
            Log.i(TAG, "startReader: Previous reader was marked as open, closing it first");
            try {
                ReaderBuilder.closeReader();
            } catch (Exception e) {
                Log.w(TAG, "startReader: Error closing previous reader: " + e.getMessage());
            }
            isReaderOpen.set(false);
        }

        try {
            Map<String, Object> arguments = call.arguments();
            if (arguments == null) {
                result.error("INVALID_ARGUMENTS", "Arguments cannot be null", null);
                isReaderOpening.set(false);
                return;
            }

            String header = (String) arguments.get("header");
            String path = (String) arguments.get("path");
            String token = (String) arguments.get("access_token");
            String saved = (String) arguments.get("saved");
            Map<String, Object> book = (Map<String, Object>) arguments.get("book");
            Map<String, Object> style = (Map<String, Object>) arguments.get("style");

            if (book == null) {
                result.error("INVALID_ARGUMENTS", "Book data cannot be null", null);
                isReaderOpening.set(false);
                return;
            }

            startReader(header, path, token, book, style, saved);
            isReaderOpen.set(true);
            result.success(null);
        } catch (Exception e) {
            Log.e(TAG, "Error starting reader: " + e.getMessage(), e);
            result.error("START_READER_ERROR", e.getMessage(), null);
        } finally {
            isReaderOpening.set(false);
        }
    }

    private void handleCloseReader(MethodChannel.Result result) {
        try {
            ReaderBuilder.hideReader();
            isReaderOpen.set(false);
            result.success(null);
        } catch (Exception e) {
            Log.e(TAG, "Error closing reader: " + e.getMessage(), e);
            result.error("CLOSE_READER_ERROR", e.getMessage(), null);
        }
    }

    private void handleCheckIfLocal(MethodCall call, MethodChannel.Result result) {
        Map<String, Object> checkArgs = call.arguments();
        if (checkArgs == null || !checkArgs.containsKey("book_id")) {
            result.error("INVALID_ARGUMENTS", "book_id is required", null);
            return;
        }
        Object bookIdObj = checkArgs.get("book_id");
        if (!(bookIdObj instanceof Integer)) {
            result.error("INVALID_ARGUMENTS", "book_id must be an integer", null);
            return;
        }
        int bookId = (Integer) bookIdObj;
        boolean isLocal = BookStorage.isBookLocal(applicationContext, bookId);
        result.success(isLocal);
    }

    private void handleCheckIfSample(MethodCall call, MethodChannel.Result result) {
        if (!(call.arguments instanceof Map)) {
            result.error("INVALID_ARGUMENTS", "Arguments must be a map", null);
            return;
        }
        Map<String, Object> arguments = (Map<String, Object>) call.arguments;
        if (!arguments.containsKey("book_id") || !(arguments.get("book_id") instanceof Integer)) {
            result.error("INVALID_ARGUMENTS", "book_id must be an integer", null);
            return;
        }
        int bookId = (Integer) arguments.get("book_id");
        BookInfo bookInfo = BookStorage.getBookInfo(applicationContext, bookId);
        if (bookInfo == null) {
            result.success(false); // Book not found, treat as not sample
            return;
        }
        result.success(bookInfo.isSample());
    }

    private void handleGetBookLength(MethodCall call, MethodChannel.Result result) {
        if (!(call.arguments instanceof Map)) {
            result.success(0);
            return;
        }
        Map<String, Object> arguments = (Map<String, Object>) call.arguments;
        if (!arguments.containsKey("book_id") || !(arguments.get("book_id") instanceof Integer)) {
            result.success(0);
            return;
        }
        int bookId = (Integer) arguments.get("book_id");
        BookInfo bookInfo = BookStorage.getBookInfo(applicationContext, bookId);
        if (bookInfo == null) {
            result.success(0);
            return;
        }
        result.success(bookInfo.getLength());
    }

    private void handleDeleteSampleBook(MethodCall call, MethodChannel.Result result) {
        if (!(call.arguments instanceof Map)) {
            result.error("INVALID_ARGUMENTS", "Arguments must be a map", null);
            return;
        }
        Map<String, Object> arguments = (Map<String, Object>) call.arguments;
        if (!arguments.containsKey("book_id") || !(arguments.get("book_id") instanceof Integer)) {
            result.error("INVALID_ARGUMENTS", "book_id must be an integer", null);
            return;
        }
        int bookId = (Integer) arguments.get("book_id");
        try {
            BookStorage.deleteBook(applicationContext, bookId);
            result.success(true);
        } catch (Exception e) {
            Log.e(TAG, "Error deleting book: " + e.getMessage(), e);
            result.error("DELETE_ERROR", e.getMessage(), null);
        }
    }

    private void handleGetLocalBooks(MethodChannel.Result result) {
        try {
            int[] localBooks = BookStorage.getLocalBooks(applicationContext);
            result.success(localBooks);
        } catch (Exception e) {
            Log.e(TAG, "Error getting local books: " + e.getMessage(), e);
            result.success(new int[0]); // Return empty array on error
        }
    }

    private void handleRemoveAllBooks(MethodChannel.Result result) {
        try {
            int[] localBooks = BookStorage.getLocalBooks(applicationContext);
            if (localBooks != null) {
                for (int bookId : localBooks) {
                    BookStorage.deleteBook(applicationContext, bookId);
                }
            }
            result.success(true);
        } catch (Exception e) {
            Log.e(TAG, "Error removing all books: " + e.getMessage(), e);
            result.error("REMOVE_ALL_ERROR", e.getMessage(), null);
        }
    }

    private void handleGetLocalBooksInfo(MethodChannel.Result result) {
        try {
            List<FileSizeInfo> filesInfo = BookStorage.getLocalBookFilesInfo(applicationContext);
            List<Map<String, Object>> serializedFilesInfo = new ArrayList<>();

            if (filesInfo != null) {
                for (FileSizeInfo fileInfo : filesInfo) {
                    if (fileInfo != null) {
                        Map<String, Object> fileData = new HashMap<>();
                        fileData.put("id", fileInfo.getId());
                        fileData.put("size", fileInfo.getFileSize());
                        serializedFilesInfo.add(fileData);
                    }
                }
            }
            result.success(serializedFilesInfo);
        } catch (Exception e) {
            Log.e(TAG, "Error getting local books info: " + e.getMessage(), e);
            result.success(new ArrayList<>()); // Return empty list on error
        }
    }

    private void handleUpdateMarks(MethodCall call, MethodChannel.Result result) {
        if (readerBuilder == null) {
            result.error("READER_NOT_INITIALIZED", "Reader has not been initialized", null);
            return;
        }
        if (!(call.arguments instanceof Map)) {
            result.error("INVALID_ARGUMENTS", "Arguments must be a map", null);
            return;
        }
        Map<String, Object> arguments = (Map<String, Object>) call.arguments;
        if (!arguments.containsKey("marks")) {
            result.error("INVALID_ARGUMENTS", "marks field is required", null);
            return;
        }
        try {
            List<Map<String, Object>> notesAndMarksData = (List<Map<String, Object>>) arguments.get("marks");
            List<NotesAndMarks> notesAndMarks = getNotesAndMarks(notesAndMarksData);
            readerBuilder.updateNotesAndMarks(notesAndMarks);
            result.success(null);
        } catch (Exception e) {
            Log.e(TAG, "Error updating marks: " + e.getMessage(), e);
            result.error("UPDATE_MARKS_ERROR", e.getMessage(), null);
        }
    }

    private void startReader(String header, String path, String token, Map<String, Object> bookData, Map<String, Object> styleData, String saved) {
        if (activity == null || channel == null) {
            Log.e(TAG, "Cannot start reader: Activity or Channel is null");
            ChannelManager.getInstance().sendError("READER_ERROR", "Activity or Channel is null", null);
            return;
        }

        // Extract book data with null safety
        bookId = getIntValue(bookData, "bookId", 0);
        String title = (String) bookData.get("title");
        int bookFileId = getIntValue(bookData, "bookFileId", 0);
        double previewPercentage = getDoubleValue(bookData, "previewPercentage", 0.15);
        int position = getIntValue(bookData, "position", 0);
        String cover = (String) bookData.get("coverThumbUrl");

        // Get notes and marks with null safety
        List<Map<String, Object>> notesAndMarksData = (List<Map<String, Object>>) bookData.get("notesAndMarks");
        List<NotesAndMarks> notesAndMarks = getNotesAndMarks(notesAndMarksData);

        // Handle Reader Style with null safety
        int readerColor = 0;
        int textSize = 22;
        boolean isJustified = true;
        int lineSpacing = 1;
        int font = 0;

        if (styleData != null) {
            readerColor = getIntValue(styleData, "readerColor", 0);
            textSize = getIntValue(styleData, "textSize", 22);
            isJustified = getBooleanValue(styleData, "isJustified", true);
            lineSpacing = getIntValue(styleData, "lineSpacing", 1);
            font = getIntValue(styleData, "font", 0);
        }

        ReaderStyle readerStyle = new ReaderStyle(textSize, readerColor, isJustified ? 1 : 0, lineSpacing, font);

        // Create reader listener that will mark reader as closed when closed callback is received
        ReaderListenerImpl readerListener = new ReaderListenerImpl(bookId) {
            @Override
            public void onReaderClosed(int position) {
                Log.d(TAG, "onReaderClosed: Resetting isReaderOpen flag");
                isReaderOpen.set(false);
                super.onReaderClosed(position);
            }

            @Override
            public void onBookForceEnd(int position) {
                Log.d(TAG, "onBookForceEnd: Resetting isReaderOpen flag");
                isReaderOpen.set(false);
                super.onBookForceEnd(position);
            }

            @Override
            public void onSampleEnded() {
                Log.d(TAG, "onSampleEnded: Resetting isReaderOpen flag");
                isReaderOpen.set(false);
                super.onSampleEnded();
            }
        };

        readerBuilder = new ReaderBuilder(activity, bookId);
        readerBuilder.setReaderStyle(readerStyle)
                .setTitle(title != null ? title : "")
                .setCover(cover != null ? cover : "")
                .setPosition(position)
                .setPercentageView((float) previewPercentage)
                .setReaderListener(readerListener)
                .setNotesAndMarks(notesAndMarks)
                .setReadingStatsListener(new StatsSessionListenerImpl())
                .setFileId(bookFileId);

        // Set save state
        if ("true".equals(saved)) {
            readerBuilder.setSaveState(ReaderBuilder.SAVE_STATE_SAVED);
            readerBuilder.setDownloadEnabled(true);
        } else if ("false".equals(saved)) {
            readerBuilder.setSaveState(ReaderBuilder.SAVE_STATE_NOT_SAVED);
            readerBuilder.setDownloadEnabled(true);
        } else {
            readerBuilder.setSaveState(ReaderBuilder.SAVE_STATE_DISABLED);
            readerBuilder.setDownloadEnabled(false);
        }

        // Build reader
        if (path == null || path.isEmpty()) {
            readerBuilder.build();
        } else {
            boolean isSaved = saveBook(bookId, path, header, token);
            if (isSaved) {
                readerBuilder.build();
            } else {
                isReaderOpen.set(false);
                ChannelManager.getInstance().sendError("SAVE_BOOK_ERROR", "Failed to save book before opening", null);
            }
        }
    }

    /**
     * Safely get int value from map with default fallback
     */
    private int getIntValue(Map<String, Object> map, String key, int defaultValue) {
        if (map == null || !map.containsKey(key)) return defaultValue;
        Object value = map.get(key);
        if (value instanceof Integer) return (Integer) value;
        if (value instanceof Number) return ((Number) value).intValue();
        return defaultValue;
    }

    /**
     * Safely get double value from map with default fallback
     */
    private double getDoubleValue(Map<String, Object> map, String key, double defaultValue) {
        if (map == null || !map.containsKey(key)) return defaultValue;
        Object value = map.get(key);
        if (value instanceof Double) return (Double) value;
        if (value instanceof Number) return ((Number) value).doubleValue();
        return defaultValue;
    }

    /**
     * Safely get boolean value from map with default fallback
     */
    private boolean getBooleanValue(Map<String, Object> map, String key, boolean defaultValue) {
        if (map == null || !map.containsKey(key)) return defaultValue;
        Object value = map.get(key);
        if (value instanceof Boolean) return (Boolean) value;
        return defaultValue;
    }

    /**
     * Convert Flutter note/mark data to native NotesAndMarks objects.
     * Returns empty list instead of null for null safety.
     */
    private static @NonNull ArrayList<NotesAndMarks> getNotesAndMarks(List<Map<String, Object>> notesAndMarksData) {
        if (notesAndMarksData == null || notesAndMarksData.isEmpty()) {
            return new ArrayList<>();
        }

        ArrayList<NotesAndMarks> notesAndMarks = new ArrayList<>(notesAndMarksData.size());
        for (Map<String, Object> item : notesAndMarksData) {
            if (item == null) continue;

            int fromOffset = getIntValueStatic(item, "location", 0);
            int toOffset = getIntValueStatic(item, "length", 0);
            int markColor = getIntValueStatic(item, "color", 0);
            String displayText = (String) item.getOrDefault("note", "");
            int type = getIntValueStatic(item, "type", 0);
            int deleted = getIntValueStatic(item, "deleted", 0);

            NotesAndMarks noteAndMark = new NotesAndMarks(fromOffset, toOffset, type,
                    displayText != null ? displayText : "", markColor, deleted);
            notesAndMarks.add(noteAndMark);
        }
        return notesAndMarks;
    }

    /**
     * Static version for use in static context
     */
    private static int getIntValueStatic(Map<String, Object> map, String key, int defaultValue) {
        if (map == null || !map.containsKey(key)) return defaultValue;
        Object value = map.get(key);
        if (value instanceof Integer) return (Integer) value;
        if (value instanceof Number) return ((Number) value).intValue();
        return defaultValue;
    }


    private boolean saveBook(int bookId, String bodyPath, String header, String accessToken) {
        return SaveBookManager.save(applicationContext, bookId, bodyPath, header, accessToken);
    }

    // MARK: - Download Methods

    private void handleStartDownload(MethodCall call, MethodChannel.Result result) {
        Map<String, Object> arguments = call.arguments();
        if (arguments == null) {
            result.error("INVALID_ARGUMENTS", "Arguments cannot be null", null);
            return;
        }

        Object bookIdObj = arguments.get("book_id");
        Object urlObj = arguments.get("url");

        if (!(bookIdObj instanceof Integer) || !(urlObj instanceof String)) {
            result.error("INVALID_ARGUMENTS", "book_id and url are required", null);
            return;
        }

        int bookId = (Integer) bookIdObj;
        String url = (String) urlObj;

        @SuppressWarnings("unchecked")
        Map<String, String> headers = (Map<String, String>) arguments.get("headers");
        String destinationPath = (String) arguments.get("destination_path");

        // Cancel any existing download for this book
        Call existingCall = activeDownloads.get(bookId);
        if (existingCall != null) {
            existingCall.cancel();
            activeDownloads.remove(bookId);
        }

        // Initialize progress tracking
        downloadProgress.put(bookId, new DownloadProgressInfo(
                bookId, 0.0, "started", 0, 0, null, destinationPath
        ));

        // Send started event
        sendProgressEvent(bookId, 0.0, "started", 0, 0, null);

        // Start download on background thread
        downloadExecutor.execute(() -> performDownload(bookId, url, headers, destinationPath));

        result.success(true);
    }

    private void performDownload(int bookId, String url, Map<String, String> headers, String destinationPath) {
        Request.Builder requestBuilder = new Request.Builder().url(url);

        if (headers != null) {
            for (Map.Entry<String, String> entry : headers.entrySet()) {
                requestBuilder.addHeader(entry.getKey(), entry.getValue());
            }
        }

        Request request = requestBuilder.build();
        Call call = downloadClient.newCall(request);
        activeDownloads.put(bookId, call);

        try {
            Response response = call.execute();
            if (!response.isSuccessful()) {
                sendProgressEvent(bookId, 0.0, "failed", 0, 0, "HTTP " + response.code());
                activeDownloads.remove(bookId);
                downloadProgress.remove(bookId);
                return;
            }

            ResponseBody body = response.body();
            if (body == null) {
                sendProgressEvent(bookId, 0.0, "failed", 0, 0, "Empty response body");
                activeDownloads.remove(bookId);
                downloadProgress.remove(bookId);
                return;
            }

            long totalBytes = body.contentLength();
            long downloadedBytes = 0;

            // Determine destination file
            File destFile;
            if (destinationPath != null && !destinationPath.isEmpty()) {
                destFile = new File(destinationPath);
            } else {
                File documentsDir = applicationContext.getFilesDir();
                destFile = new File(documentsDir, "book_" + bookId + ".epub");
            }

            // Ensure parent directory exists
            File parentDir = destFile.getParentFile();
            if (parentDir != null && !parentDir.exists()) {
                parentDir.mkdirs();
            }

            // Stream download to file
            try (InputStream inputStream = body.byteStream();
                 FileOutputStream outputStream = new FileOutputStream(destFile)) {

                byte[] buffer = new byte[8192];
                int bytesRead;
                long lastProgressUpdate = System.currentTimeMillis();

                while ((bytesRead = inputStream.read(buffer)) != -1) {
                    // Check if cancelled
                    if (call.isCanceled()) {
                        outputStream.close();
                        destFile.delete();
                        return;
                    }

                    outputStream.write(buffer, 0, bytesRead);
                    downloadedBytes += bytesRead;

                    // Update progress (throttle to every 100ms)
                    long now = System.currentTimeMillis();
                    if (now - lastProgressUpdate >= 100) {
                        double progress = totalBytes > 0 ? (double) downloadedBytes / totalBytes : 0.0;
                        downloadProgress.put(bookId, new DownloadProgressInfo(
                                bookId, progress, "downloading", downloadedBytes, totalBytes, null, destFile.getAbsolutePath()
                        ));
                        sendProgressEvent(bookId, progress, "downloading", downloadedBytes, totalBytes, null);
                        lastProgressUpdate = now;
                    }
                }
            }

            // Download completed successfully
            downloadProgress.put(bookId, new DownloadProgressInfo(
                    bookId, 1.0, "completed", totalBytes, totalBytes, null, destFile.getAbsolutePath()
            ));
            sendProgressEvent(bookId, 1.0, "completed", totalBytes, totalBytes, null);

        } catch (IOException e) {
            if (!call.isCanceled()) {
                Log.e(TAG, "Download failed: " + e.getMessage(), e);
                sendProgressEvent(bookId, 0.0, "failed", 0, 0, e.getMessage());
            }
        } finally {
            activeDownloads.remove(bookId);
            downloadProgress.remove(bookId);
        }
    }

    private void handleCancelDownload(MethodCall call, MethodChannel.Result result) {
        Map<String, Object> arguments = call.arguments();
        if (arguments == null) {
            result.error("INVALID_ARGUMENTS", "Arguments cannot be null", null);
            return;
        }

        Object bookIdObj = arguments.get("book_id");
        if (!(bookIdObj instanceof Integer)) {
            result.error("INVALID_ARGUMENTS", "book_id is required", null);
            return;
        }

        int bookId = (Integer) bookIdObj;
        Call call1 = activeDownloads.get(bookId);

        if (call1 != null) {
            call1.cancel();
            activeDownloads.remove(bookId);
            downloadProgress.remove(bookId);
            sendProgressEvent(bookId, 0.0, "cancelled", 0, 0, null);
            result.success(true);
        } else {
            result.success(false);
        }
    }

    private void handleGetDownloadStatus(MethodCall call, MethodChannel.Result result) {
        Map<String, Object> arguments = call.arguments();
        if (arguments == null) {
            result.error("INVALID_ARGUMENTS", "Arguments cannot be null", null);
            return;
        }

        Object bookIdObj = arguments.get("book_id");
        if (!(bookIdObj instanceof Integer)) {
            result.error("INVALID_ARGUMENTS", "book_id is required", null);
            return;
        }

        int bookId = (Integer) bookIdObj;
        DownloadProgressInfo progressInfo = downloadProgress.get(bookId);

        if (progressInfo != null) {
            Map<String, Object> statusMap = new HashMap<>();
            statusMap.put("book_id", progressInfo.bookId);
            statusMap.put("progress", progressInfo.progress);
            statusMap.put("state", progressInfo.state);
            statusMap.put("bytes_downloaded", progressInfo.bytesDownloaded);
            statusMap.put("total_bytes", progressInfo.totalBytes);
            if (progressInfo.error != null) {
                statusMap.put("error", progressInfo.error);
            }
            result.success(statusMap);
        } else {
            result.success(null);
        }
    }

    private void sendProgressEvent(int bookId, double progress, String state, long bytesDownloaded, long totalBytes, @Nullable String error) {
        mainHandler.post(() -> {
            if (downloadProgressEventSink != null) {
                Map<String, Object> eventMap = new HashMap<>();
                eventMap.put("book_id", bookId);
                eventMap.put("progress", progress);
                eventMap.put("state", state);
                eventMap.put("bytes_downloaded", bytesDownloaded);
                eventMap.put("total_bytes", totalBytes);
                if (error != null) {
                    eventMap.put("error", error);
                }
                downloadProgressEventSink.success(eventMap);
            }
        });
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        activity = null;
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivity() {
        activity = null;
    }

}
