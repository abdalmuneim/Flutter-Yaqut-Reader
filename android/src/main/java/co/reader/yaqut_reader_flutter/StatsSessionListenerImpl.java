package co.reader.yaqut_reader_flutter;

import android.os.Parcel;
import android.os.Parcelable;
import io.flutter.plugin.common.MethodChannel;
import co.yaqut.reader.api.StatsSessionListener;
import co.yaqut.reader.api.ReadingSession;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

import android.util.Log;
import org.json.JSONArray;

public class StatsSessionListenerImpl implements StatsSessionListener, Parcelable {

    private static final String TAG = "StatsSessionListenerImpl";

    // Constructor
    public StatsSessionListenerImpl() {
        // Channel will be retrieved from ChannelManager when needed
    }

    // Parcelable implementation
    @Override
    public int describeContents() {
        return 0;
    }

    @Override
    public void writeToParcel(@NonNull Parcel dest, int flags) {
        // Write any necessary data to the parcel here
    }

    protected StatsSessionListenerImpl(Parcel in) {
        // Read any data from the parcel here
    }

    public static final Creator<StatsSessionListenerImpl> CREATOR = new Creator<StatsSessionListenerImpl>() {
        @Override
        public StatsSessionListenerImpl createFromParcel(Parcel in) {
            return new StatsSessionListenerImpl(in);
        }

        @Override
        public StatsSessionListenerImpl[] newArray(int size) {
            return new StatsSessionListenerImpl[size];
        }
    };

    // Implement the StatsSessionListener methods here
    @Override
    public void onReadingSessionEnd(ReadingSession session) {
        Log.d(TAG, "onReadingSessionEnd 123");
        Map<String, Object> data = new HashMap<>();
        data.put("book_id", session.getBookId());
        data.put("book_file_id", session.getBookFileId());
        data.put("pages_read", session.getPagesRead());
        data.put("start_offset", session.getStartOffset());
        data.put("end_offset", session.getEndOffset());
        // Convert potential JSONArray to a Java List for StandardMessageCodec compatibility
        data.put("covered_offset", toIntegerList(session.getCoveredOffset()));
        data.put("covered_length", toIntegerList(session.getCoveredLength()));
        data.put("start_time", session.getStartTime());
        data.put("end_time", session.getEndTime());
        data.put("md5", session.getMd5());
        data.put("uuid", session.getUuid());

        MethodChannel channel = ChannelManager.getInstance().getChannel();
        if (channel != null) {
            channel.invokeMethod("onReadingSessionEnd", data);
        }

    }

    private static List<Integer> toIntegerList(Object source) {
        if (source == null) return Collections.emptyList();

        if (source instanceof List) {
            // Assume already a List of Numbers/Integers
            List<?> list = (List<?>) source;
            // Flatten one level if it's a single nested list like [[..]]
            if (list.size() == 1 && list.get(0) instanceof List) {
                list = (List<?>) list.get(0);
            }
            List<Integer> out = new ArrayList<>(list.size());
            for (Object item : list) {
                if (item instanceof Number) {
                    out.add(((Number) item).intValue());
                } else if (item instanceof String) {
                    try {
                        out.add(Integer.parseInt((String) item));
                    } catch (NumberFormatException ignored) {
                        // ignore values that cannot be parsed to integer
                    }
                } else if (item instanceof List) {
                    // If nested list appears, flatten its items too (one level)
                    for (Object nested : (List<?>) item) {
                        if (nested instanceof Number) {
                            out.add(((Number) nested).intValue());
                        } else if (nested instanceof String) {
                            try {
                                out.add(Integer.parseInt((String) nested));
                            } catch (NumberFormatException ignored) {
                                // ignore
                            }
                        }
                    }
                }
            }
            return out;
        }

        if (source instanceof int[]) {
            int[] arr = (int[]) source;
            List<Integer> out = new ArrayList<>(arr.length);
            for (int v : arr) out.add(v);
            return out;
        }

        if (source instanceof JSONArray) {
            JSONArray jsonArray = (JSONArray) source;
            // Flatten one level if it's a nested array like [[..]]
            if (jsonArray.length() == 1 && jsonArray.opt(0) instanceof JSONArray) {
                jsonArray = (JSONArray) jsonArray.opt(0);
            }
            List<Integer> out = new ArrayList<>(jsonArray.length());
            for (int i = 0; i < jsonArray.length(); i++) {
                Object value = jsonArray.opt(i);
                if (value instanceof Number) {
                    out.add(((Number) value).intValue());
                } else if (value instanceof String) {
                    try {
                        out.add(Integer.parseInt((String) value));
                    } catch (NumberFormatException ignored) {
                        // ignore values that cannot be parsed to integer
                    }
                } else if (value instanceof JSONArray) {
                    // Flatten one level
                    JSONArray inner = (JSONArray) value;
                    for (int j = 0; j < inner.length(); j++) {
                        Object innerVal = inner.opt(j);
                        if (innerVal instanceof Number) {
                            out.add(((Number) innerVal).intValue());
                        } else if (innerVal instanceof String) {
                            try {
                                out.add(Integer.parseInt((String) innerVal));
                            } catch (NumberFormatException ignored) {
                                // ignore
                            }
                        }
                    }
                }
            }
            return out;
        }

        // Fallback: not a supported type
        return Collections.emptyList();
    }
}