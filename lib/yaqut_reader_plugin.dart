import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:yaqut_reader_plugin/constants/constants.dart';
import 'package:yaqut_reader_plugin/models/yaqut_reader_book.dart';
import 'package:yaqut_reader_plugin/models/yaqut_reader_reading_session.dart';
import 'package:yaqut_reader_plugin/models/yaqut_reader_style.dart';

class YaqutReaderPlugin {

  YaqutReaderPlugin._internal();
  static final YaqutReaderPlugin _instance = YaqutReaderPlugin._internal();
  factory YaqutReaderPlugin() => _instance;


  final methodChannel = const MethodChannel('yaqut_reader_plugin');

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
  final StreamController<String> onSampleEndedStreamController =
  StreamController<String>.broadcast();
  final StreamController<YaqutReaderReadingSession>
  onSyncReadingSessionStreamController =
  StreamController<YaqutReaderReadingSession>.broadcast();
  final StreamController<String> onOrientationChangedStreamController =
  StreamController<String>.broadcast();

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

  Stream<String> get onSampleEnded => onSampleEndedStreamController.stream;

  Stream<YaqutReaderReadingSession> get onSyncReadingSession =>
      onSyncReadingSessionStreamController.stream;

  Stream<String> get onOrientationChanged =>
      onOrientationChangedStreamController.stream;

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

  void onSampleEndedCallback() {
    onSampleEndedStreamController.add('onSampleEnded');
  }

  void onSyncReadingSessionCallback(YaqutReaderReadingSession session) {
    if (kDebugMode) {}
    onSyncReadingSessionStreamController.add(session);
  }

  void onOrientationChangedCallback() {
    onOrientationChangedStreamController.add('onOrientationChanged');
  }

  Future<void> startReader({required String? header,
    required String? path,
    required String? accessToken,
    required YaqutReaderBook book,
    required YaqutReaderStyle style,
    required bool saved}) async {
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
        var data = call.arguments as Map;
        String text = data[constText];
        onShareQuotesCallback(text);
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
        final Map<Object?, Object?> rawData =
        call.arguments as Map<Object?, Object?>;
        final Map<String, dynamic> data = rawData.map(
              (key, value) => MapEntry(key as String, value),
        );
        YaqutReaderReadingSession session =
        YaqutReaderReadingSession.fromJson(data);
        onSyncReadingSessionCallback(session);
      case 'onOrientationChanged':
        onOrientationChangedCallback();
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

  void closeReader() {
    methodChannel.invokeMethod('closeReader');
  }

  getPlatformVersion() {}
}
