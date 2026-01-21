package co.reader.yaqut_reader_flutter;

/**
 * Created by rula on 13,November,2024
 * Thread-safe singleton for managing MethodChannel communication
 */
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import io.flutter.plugin.common.MethodChannel;

public class ChannelManager {
    private static final String TAG = "ChannelManager";
    private static volatile ChannelManager instance;
    private MethodChannel channel;
    private final Handler mainHandler;

    private ChannelManager() {
        mainHandler = new Handler(Looper.getMainLooper());
    }

    public static ChannelManager getInstance() {
        if (instance == null) {
            synchronized (ChannelManager.class) {
                if (instance == null) {
                    instance = new ChannelManager();
                }
            }
        }
        return instance;
    }

    public void setChannel(MethodChannel channel) {
        synchronized (this) {
            this.channel = channel;
        }
    }

    public MethodChannel getChannel() {
        synchronized (this) {
            return channel;
        }
    }

    /**
     * Invoke method on Flutter side, ensuring execution on main thread.
     * This is required because MethodChannel.invokeMethod must be called from the main thread.
     *
     * @param method The method name to invoke
     * @param arguments The arguments to pass
     */
    public void invokeMethod(String method, Object arguments) {
        final MethodChannel ch;
        synchronized (this) {
            ch = channel;
        }

        if (ch == null) {
            Log.w(TAG, "invokeMethod: Channel is null, cannot invoke " + method);
            return;
        }

        if (Looper.myLooper() == Looper.getMainLooper()) {
            // Already on main thread
            try {
                ch.invokeMethod(method, arguments);
            } catch (Exception e) {
                Log.e(TAG, "Error invoking method " + method + ": " + e.getMessage());
            }
        } else {
            // Post to main thread
            mainHandler.post(() -> {
                try {
                    // Re-check channel in case it was cleared
                    MethodChannel currentChannel;
                    synchronized (ChannelManager.this) {
                        currentChannel = channel;
                    }
                    if (currentChannel != null) {
                        currentChannel.invokeMethod(method, arguments);
                    } else {
                        Log.w(TAG, "invokeMethod: Channel became null before posting " + method);
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error invoking method " + method + " on main thread: " + e.getMessage());
                }
            });
        }
    }

    /**
     * Send an error callback to Flutter
     *
     * @param errorCode Error code string
     * @param errorMessage Human-readable error message
     * @param errorDetails Optional error details
     */
    public void sendError(String errorCode, String errorMessage, Object errorDetails) {
        java.util.Map<String, Object> errorData = new java.util.HashMap<>();
        errorData.put("errorCode", errorCode);
        errorData.put("errorMessage", errorMessage);
        if (errorDetails != null) {
            errorData.put("errorDetails", errorDetails);
        }
        invokeMethod("onError", errorData);
    }
}
