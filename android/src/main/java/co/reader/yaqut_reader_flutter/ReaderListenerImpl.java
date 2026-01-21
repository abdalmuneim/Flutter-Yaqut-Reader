package co.reader.yaqut_reader_flutter;

import android.os.Parcel;
import android.os.Parcelable;
import android.util.Log;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import co.yaqut.reader.api.ReaderStyle;
import co.yaqut.reader.api.NotesAndMarks;
import co.yaqut.reader.api.ReaderListener;

/**
 * Implementation of ReaderListener that bridges native reader events to Flutter.
 * All callbacks are dispatched to Flutter via ChannelManager which ensures main thread execution.
 */
public class ReaderListenerImpl implements ReaderListener, Parcelable {
    private static final String TAG = "ReaderListenerImpl";
    private final int bookId;

    // Constructor
    public ReaderListenerImpl(int bookId) {
        this.bookId = bookId;
        Log.d(TAG, "ReaderListenerImpl: initialized for bookId=" + bookId);
    }

    // Parcelable implementation
    protected ReaderListenerImpl(Parcel in) {
        this.bookId = in.readInt();
        Log.d(TAG, "ReaderListenerImpl: restored from parcel for bookId=" + bookId);
    }

    @Override
    public void writeToParcel(Parcel dest, int flags) {
        dest.writeInt(bookId);
    }

    public static final Creator<ReaderListenerImpl> CREATOR = new Creator<ReaderListenerImpl>() {
        @Override
        public ReaderListenerImpl createFromParcel(Parcel in) {
            return new ReaderListenerImpl(in);
        }

        @Override
        public ReaderListenerImpl[] newArray(int size) {
            return new ReaderListenerImpl[size];
        }
    };

    @Override
    public int describeContents() {
        return 0;
    }

    @Override
    public void onStyleChanged(ReaderStyle style) {
        if (style == null) {
            Log.w(TAG, "onStyleChanged: style is null");
            return;
        }
        Map<String, Integer> data = new HashMap<>();
        data.put("line_space", style.getLineSpacing());
        data.put("reader_color", style.getReaderColor());
        data.put("font", style.getFont());
        data.put("font_size", style.getTextSize());
        data.put("layout", style.isJustified());
        data.put("book_id", bookId);
        ChannelManager.getInstance().invokeMethod("onStyleChanged", data);
    }

    @Override
    public void onPositionChanged(int position) {
        Map<String, Integer> data = new HashMap<>();
        data.put("position", position);
        data.put("book_id", bookId);
        Log.d(TAG, "onPositionChanged: position=" + position + ", bookId=" + bookId);
        ChannelManager.getInstance().invokeMethod("onPositionChanged", data);
    }

    @Override
    public void onSyncNotesAndMarks(List<NotesAndMarks> list) {
        if (list == null) {
            Log.w(TAG, "onSyncNotesAndMarks: list is null");
            return;
        }
        List<Map<String, Object>> items = new ArrayList<>();
        for (NotesAndMarks mark : list) {
            if (mark == null) continue;
            Map<String, Object> item = new HashMap<>();
            item.put("book_id", bookId);
            item.put("from_offset", mark.getFromOffset());
            item.put("to_offset", mark.getToOffset());
            item.put("mark_color", mark.getColor());
            item.put("display_text", mark.getDisplayText() != null ? mark.getDisplayText() : "");
            item.put("type", mark.getType());
            item.put("deleted", mark.isDeleted() ? 1 : 0);
            items.add(item);
        }
        ChannelManager.getInstance().invokeMethod("onSyncNotes", items);
    }

    @Override
    public void onUpdateLastOpened(long timestamp) {
        ChannelManager.getInstance().invokeMethod("onUpdateLastOpened", timestamp);
    }

    @Override
    public void onShareBook(String quote) {
        if (quote == null || quote.isEmpty()) {
            ChannelManager.getInstance().invokeMethod("onShareBook", new HashMap<String, Object>());
        } else {
            ChannelManager.getInstance().invokeMethod("onShareQuotes", quote);
        }
    }

    @Override
    public void onBookDetailsCLicked() {
        ChannelManager.getInstance().invokeMethod("onBookDetailsClicked", new HashMap<String, Object>());
    }

    @Override
    public void onSaveBookClicked(int position) {
        Map<String, Integer> data = new HashMap<>();
        data.put("position", position);
        data.put("book_id", bookId);
        ChannelManager.getInstance().invokeMethod("onSaveBookClicked", data);
    }

    @Override
    public void onDownloadBook() {
        ChannelManager.getInstance().invokeMethod("onDownloadBook", new HashMap<String, Object>());
    }

    @Override
    public void onReaderClosed(int position) {
        Map<String, Integer> data = new HashMap<>();
        data.put("position", position);
        data.put("book_id", bookId);
        Log.d(TAG, "onReaderClosed: position=" + position + ", bookId=" + bookId);
        ChannelManager.getInstance().invokeMethod("onReaderClosed", data);
    }

    @Override
    public void onSampleEnded() {
        Log.d(TAG, "onSampleEnded: bookId=" + bookId);
        ChannelManager.getInstance().invokeMethod("onSampleEnded", new HashMap<String, Object>());
    }

    @Override
    public void onBookForceEnd(int position) {
        Map<String, Integer> data = new HashMap<>();
        data.put("position", position);
        data.put("book_id", bookId);
        Log.d(TAG, "onBookForceEnd: position=" + position + ", bookId=" + bookId);
        ChannelManager.getInstance().invokeMethod("onBookForceEnd", data);
    }
}
