import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:yaqut_reader_plugin/constants/constants.dart';
import 'package:yaqut_reader_plugin/models/yaqut_reader_book.dart';
import 'package:yaqut_reader_plugin/models/yaqut_reader_reading_session.dart';
import 'package:yaqut_reader_plugin/models/yaqut_reader_style.dart';

/// Download state enum for tracking download progress
enum DownloadState {
  idle,
  started,
  downloading,
  completed,
  failed,
  cancelled,
}

/// Download progress event model
class DownloadProgressEvent {
  final int bookId;
  final double progress; // 0.0 to 1.0
  final DownloadState state;
  final int bytesDownloaded;
  final int totalBytes;
  final String? error;

  DownloadProgressEvent({
    required this.bookId,
    required this.progress,
    required this.state,
    required this.bytesDownloaded,
    required this.totalBytes,
    this.error,
  });

  factory DownloadProgressEvent.fromMap(Map<String, dynamic> map) {
    return DownloadProgressEvent(
      bookId: map['book_id'] as int? ?? 0,
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      state: _parseState(map['state'] as String?),
      bytesDownloaded: map['bytes_downloaded'] as int? ?? 0,
      totalBytes: map['total_bytes'] as int? ?? 0,
      error: map['error'] as String?,
    );
  }

  static DownloadState _parseState(String? state) {
    switch (state) {
      case 'idle':
        return DownloadState.idle;
      case 'started':
        return DownloadState.started;
      case 'downloading':
        return DownloadState.downloading;
      case 'completed':
        return DownloadState.completed;
      case 'failed':
        return DownloadState.failed;
      case 'cancelled':
        return DownloadState.cancelled;
      default:
        return DownloadState.idle;
    }
  }

  @override
  String toString() {
    return 'DownloadProgressEvent(bookId: $bookId, progress: $progress, state: $state, '
        'bytesDownloaded: $bytesDownloaded, totalBytes: $totalBytes, error: $error)';
  }
}

class YaqutReaderPlugin {

  YaqutReaderPlugin._internal();
  static final YaqutReaderPlugin _instance = YaqutReaderPlugin._internal();
  factory YaqutReaderPlugin() => _instance;


  final methodChannel = const MethodChannel('yaqut_reader_plugin');

  /// EventChannel for receiving download progress updates from native side
  static const EventChannel _downloadProgressChannel =
      EventChannel('yaqut_reader_plugin/download_progress');

  /// Cached download progress stream
  Stream<DownloadProgressEvent>? _downloadProgressStream;

  final StreamController<YaqutReaderStyle> onStyleChangedStreamController =
  StreamController<YaqutReaderStyle>.broadcast();
  final StreamController<int> onPositionChangedStreamController =
  StreamController<int>.broadcast();
  final StreamController<List<dynamic>> onSyncNotesStreamController =
  StreamController<List<dynamic>>.broadcast();
  final StreamController<String> onBookDetailsClickedStreamController =
  StreamController<String>.broadcast();
  final StreamController<int> onSaveBookClickedStreamController =
  StreamController<int>.broadcast();
  final StreamController<String> onDownloadBookStreamController =
  StreamController<String>.broadcast();
  final StreamController<String> onShareBookStreamController =
  StreamController<String>.broadcast();
  final StreamController<String> onShareQuotesStreamController =
  StreamController<String>.broadcast();
  final StreamController<int> onReaderClosedStreamController =
  StreamController<int>.broadcast();
  
  final StreamController<int> onBookForceEndStreamController =
  StreamController<int>.broadcast();
  
  
  final StreamController<String> onSampleEndedStreamController =
  StreamController<String>.broadcast();
  final StreamController<YaqutReaderReadingSession>
  onSyncReadingSessionStreamController =
  StreamController<YaqutReaderReadingSession>.broadcast();
  final StreamController<String> onOrientationChangedStreamController =
  StreamController<String>.broadcast();

  /// Stream controller for error callbacks from native side
  final StreamController<Map<String, dynamic>> onErrorStreamController =
  StreamController<Map<String, dynamic>>.broadcast();

  /// Stream for receiving error events from native code
  Stream<Map<String, dynamic>> get onError => onErrorStreamController.stream;

  Stream<YaqutReaderStyle> get onStyleChanged =>
      onStyleChangedStreamController.stream;

  Stream<int> get onPositionChanged => onPositionChangedStreamController.stream;

  Stream<List<dynamic>> get onSyncNotes => onSyncNotesStreamController.stream;

  Stream<String> get onBookDetailsClicked =>
      onBookDetailsClickedStreamController.stream;

  Stream<int> get onSaveBookClicked =>
      onSaveBookClickedStreamController.stream;

  Stream<String> get onShareBook => onShareBookStreamController.stream;

  Stream<String> get onShareQuotes => onShareQuotesStreamController.stream;

  Stream<String> get onDownloadBook => onDownloadBookStreamController.stream;

  Stream<int> get onReaderClosed => onReaderClosedStreamController.stream;

  Stream<int> get onBookForceEnd => onBookForceEndStreamController.stream;

  Stream<String> get onSampleEnded => onSampleEndedStreamController.stream;

  Stream<YaqutReaderReadingSession> get onSyncReadingSession =>
      onSyncReadingSessionStreamController.stream;

  Stream<String> get onOrientationChanged =>
      onOrientationChangedStreamController.stream;

  /// Stream for receiving download progress events from native code
  /// Uses EventChannel for efficient continuous progress updates
  Stream<DownloadProgressEvent> get downloadProgress {
    _downloadProgressStream ??= _downloadProgressChannel
        .receiveBroadcastStream()
        .map((event) => DownloadProgressEvent.fromMap(
            Map<String, dynamic>.from(event as Map)));
    return _downloadProgressStream!;
  }

  /// Start downloading a book for offline use
  /// [bookId] - The ID of the book to download
  /// [url] - The URL to download the book from
  /// [headers] - Optional HTTP headers for authentication
  /// [destinationPath] - Optional custom destination path
  Future<bool> startDownload({
    required int bookId,
    required String url,
    Map<String, String>? headers,
    String? destinationPath,
  }) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('startDownload', {
        'book_id': bookId,
        'url': url,
        'headers': headers ?? {},
        'destination_path': destinationPath,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint("Failed to start download: '${e.message}'.");
      }
      return false;
    }
  }

  /// Cancel an ongoing download
  /// [bookId] - The ID of the book download to cancel
  Future<bool> cancelDownload({required int bookId}) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('cancelDownload', {
        'book_id': bookId,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint("Failed to cancel download: '${e.message}'.");
      }
      return false;
    }
  }

  /// Get current download status for a book
  /// Returns null if no download is in progress
  Future<DownloadProgressEvent?> getDownloadStatus({required int bookId}) async {
    try {
      final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>>('getDownloadStatus', {
        'book_id': bookId,
      });
      if (result != null) {
        return DownloadProgressEvent.fromMap(Map<String, dynamic>.from(result));
      }
      return null;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint("Failed to get download status: '${e.message}'.");
      }
      return null;
    }
  }

  void onStyleChangedCallback(YaqutReaderStyle style) {
    onStyleChangedStreamController.add(style);
  }

  void onPositionChangedCallback(int position) {
    onPositionChangedStreamController.add(position);
  }

  void onSyncNotesCallback(List<dynamic> notes) {
    onSyncNotesStreamController.add(notes);
  }

  void onBookDetailsClickedCallback() {
    onBookDetailsClickedStreamController.add('onBookDetailsClicked');
  }

  void onSaveBookClickedCallback(int position) {
    onSaveBookClickedStreamController.add(position);
  }

  void onShareBookCallback() {
    onShareBookStreamController.add('onShareBook');
  }

  void onShareQuotesCallback(String text) {
    onShareQuotesStreamController.add(text);
  }

  void onDownloadBookCallback() {
    onDownloadBookStreamController.add('onDownloadBook');
  }

  void onReaderClosedCallback(int position) {
    onReaderClosedStreamController.add(position);
  }

  void onBookForceEndCallback(int position) {
    onBookForceEndStreamController.add(position);
  }

  void onSampleEndedCallback() {
    onSampleEndedStreamController.add('onSampleEnded');
  }

  void onSyncReadingSessionCallback(YaqutReaderReadingSession session) {
    print('onSyncReadingSessionCallback session: $session');
    if (kDebugMode) {}
    onSyncReadingSessionStreamController.add(session);
  }

  void onOrientationChangedCallback() {
    print('==> onOrientationChangedCallback');
    onOrientationChangedStreamController.add('onOrientationChanged');
  }

  Future<void> startReader({required String? header,
    required String? path,
    required String? accessToken,
    required YaqutReaderBook book,
    required YaqutReaderStyle style,
    required String saved}) async {
    methodChannel.setMethodCallHandler(readerListener);
    try {
      await methodChannel.invokeMethod('startReader', {
        constHeader: header,
        constPath: path,
        constAccessToken: accessToken,
        constBook: book.toJson(),
        constStyle: style.toJson(),
        constSaved: saved,
      });
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint("Failed to call native method: '${e.message}'.");
      }
    }
  }


  void updateMarks(
      List<Map<String, dynamic>> marks,
      ) async {
    try {
      await methodChannel.invokeMethod('updateMarks', {
        'marks': marks,
      });
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint("Failed to call native method: '${e.message}'.");
      }
    }
  }

  Future<void> readerListener(MethodCall call) async {
    if (kDebugMode) {
      debugPrint(
          "$constYaqutReaderPluginTag readerListener Called method: ${call
              .method}");
    }
    switch (call.method) {
      case 'onStyleChanged':
        var data = call.arguments as Map;
        var lineSpace = data[constLineSpace];
        var layout = data[constLayout];
        var fontSize = data[constFontSize];
        var font = data[constFont];
        var readerColor = data[constReaderColor];
        YaqutReaderStyle style = YaqutReaderStyle(
            readerColor: readerColor,
            textSize: fontSize,
            isJustified: layout == 1 ? true : false,
            lineSpacing: lineSpace,
            font: font);
        onStyleChangedCallback(style);
        if (kDebugMode) {
          debugPrint("...onStyleChangedCallback...");
        }
      case 'onPositionChanged':
        var data = call.arguments as Map;
        int position = data[constPosition];
        onPositionChangedCallback(position);
      case 'onBookDetailsClicked':
        onBookDetailsClickedCallback();
      case 'onSaveBookClicked':
        var data = call.arguments as Map;
        int position = data[constPosition];
        onSaveBookClickedCallback(position);
      case 'onShareBook':
        onShareBookCallback();
      case 'onShareQuotes':
        // var data = call.arguments as Map;
        // String text = data[constText];
        // onShareQuotesCallback(text);
        final arguments = call.arguments;
        if (arguments is Map) {
          final String? text = arguments[constText];
          if (text != null) {
            onShareQuotesCallback(text);
          }
        } else {
          onShareQuotesCallback(arguments);
        }
      case 'onDownloadBook':
        onDownloadBookCallback();
      case 'onSyncNotes':
        List<dynamic> notes = call.arguments;
        onSyncNotesCallback(notes);
      case 'onReaderClosed':
        var data = call.arguments as Map;
        int position = data[constPosition];
        onReaderClosedCallback(position);
      case 'onSampleEnded':
        onSampleEndedCallback();
      case 'onReadingSessionEnd':
        print('onReadingSessionEnd');
        final Map<Object?, Object?> rawData =
        call.arguments as Map<Object?, Object?>;
        print('onReadingSessionEnd rawData: $rawData');
        final Map<String, dynamic> data = rawData.map(
              (key, value) => MapEntry(key as String, value),
        );
        print('onReadingSessionEnd data: $data');
        YaqutReaderReadingSession session =
        YaqutReaderReadingSession.fromJson(data);
        print('onReadingSessionEnd session: $session');
        onSyncReadingSessionCallback(session);
      case 'onOrientationChanged':
        print('==> onOrientationChanged');
        onOrientationChangedCallback();
      case 'onBookForceEnd':
        var data = call.arguments as Map;
        int position = data[constPosition];
        onBookForceEndCallback(position);
      case 'onError':
        // Handle error callback from native side
        if (call.arguments is Map) {
          final Map<Object?, Object?> rawData = call.arguments as Map<Object?, Object?>;
          final Map<String, dynamic> errorData = rawData.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          if (kDebugMode) {
            debugPrint('$constYaqutReaderPluginTag onError: $errorData');
          }
          onErrorStreamController.add(errorData);
        }
      default:
    }
  }

  Future<bool> checkIfLocal(int bookId, int bookFileId) async {
    bool? isLocal = false;
    try {
      isLocal = await methodChannel.invokeMethod<bool>('checkIfLocal', {
        'book_id': bookId,
        'book_file_id': bookFileId,
      });
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint("Failed to call native method: '${e.message}'.");
      }
    }
    return isLocal!;
  }

  Future<bool> checkIfSample(int bookId) async {
    bool? isSample = true;
    try {
      isSample = await methodChannel.invokeMethod<bool>('checkIfSample', {
        'book_id': bookId,
      });
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint("Failed to call native method: '${e.message}'.");
      }
    }
    return isSample!;
  }

  Future<int> getBookLength(int bookId) async {
    int? length = 0;
    try {
      length = await methodChannel.invokeMethod<int>('getBookLength', {
        'book_id': bookId,
      });

      if (kDebugMode) {
        debugPrint("getBookLength => bookId: $bookId, length: $length");
      }
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint("Failed to call native method: '${e.message}'.");
      }
    }
    return length!;
  }

  Future<bool> deleteSampleBook(int bookId) async {
    bool? success = false;
    try {
      success = await methodChannel.invokeMethod<bool>('deleteSampleBook', {
        'book_id': bookId,
      });
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint("Failed to call native method: '${e.message}'.");
      }
    }
    return success!;
  }

  Future<List<int>?> getLocalBooks() async {
    try {
      final List<Object?>? rawIds = await methodChannel.invokeMethod<
          List<Object?>>('getLocalBooks');
      return rawIds?.map((e) => e as int).toList();
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint("Failed to call native method: '${e.message}'.");
      }
      return null;
    }
  }

  Future<bool> removeAllBooks() async {
    await methodChannel.invokeMethod('removeAllBooks');
    return true;
  }

  Future<List<Map<String, dynamic>>?> getLocalBooksInfo() async {
    try {
      final List<dynamic>? rawFilesInfo = await methodChannel.invokeMethod<List<dynamic>>('getLocalBooksInfo');
      return rawFilesInfo?.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint("Failed to call native method: '${e.message}'.");
      }
      return null;
    }
  }

  void showReader() {
    methodChannel.invokeMethod('showReader');
  }

  void hideReader() {
    methodChannel.invokeMethod('hideReader');
  }

  void hideReaderForNavigation() {
    methodChannel.invokeMethod('hideReaderForNavigation');
  }

  void closeReader() {
    methodChannel.invokeMethod('closeReader');
  }

  getPlatformVersion() {}
}
