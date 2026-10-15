package com.azurekiln.qfli.core;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.provider.OpenableColumns;
import android.webkit.MimeTypeMap;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Collections;
import java.util.HashMap;
import java.util.IdentityHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/** Shared Android SAF boundary for project archives and application backups. */
public final class QfliPickerPlugin implements FlutterPlugin, ActivityAware,
        MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {
    private static final int PICK_DOCUMENT_REQUEST = 0x5146;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    // Accessed only on the main thread; detached engines complete each reply once.
    private final Set<MethodChannel.Result> pendingIo =
            Collections.newSetFromMap(new IdentityHashMap<>());
    private MethodChannel channel;
    private Context applicationContext;
    private ExecutorService ioExecutor;
    private ActivityPluginBinding activityBinding;
    private MethodChannel.Result pendingPicker;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        applicationContext = binding.getApplicationContext();
        ioExecutor = Executors.newSingleThreadExecutor();
        channel = new MethodChannel(binding.getBinaryMessenger(), "qflistudio/platform");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
        detachActivity();
        cancelPicker();
        for (MethodChannel.Result result : pendingIo) {
            result.error("PICKER_DETACHED", "The file service was detached.", null);
        }
        pendingIo.clear();
        ioExecutor.shutdownNow();
        ioExecutor = null;
        applicationContext = null;
    }

    @Override
    public void onAttachedToActivity(ActivityPluginBinding binding) {
        activityBinding = binding;
        binding.addActivityResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        // Keep the outstanding picker reply while the Activity is recreated.
        detachActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        detachActivity();
        cancelPicker();
    }

    private void detachActivity() {
        if (activityBinding != null) {
            activityBinding.removeActivityResultListener(this);
            activityBinding = null;
        }
    }

    private void cancelPicker() {
        if (pendingPicker != null) {
            MethodChannel.Result result = pendingPicker;
            pendingPicker = null;
            result.success(null);
        }
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "pickDocument":
                    Intent pick = new Intent(Boolean.TRUE.equals(call.argument("folder"))
                            ? Intent.ACTION_OPEN_DOCUMENT_TREE : Intent.ACTION_OPEN_DOCUMENT);
                    if (Intent.ACTION_OPEN_DOCUMENT.equals(pick.getAction())) {
                        // SAF providers do not share a MIME mapping for custom extensions.
                        // Let the Dart archive validator check .qsz/.qfliz after selection.
                        pick.addCategory(Intent.CATEGORY_OPENABLE);
                        pick.setType("*/*");
                    }
                    pick.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
                            | Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                            | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
                    launchPicker(pick, result);
                    break;
                case "saveDocument":
                    String name = call.argument("suggestedName");
                    if (name == null || name.isEmpty()) name = "qfli-project.json";
                    Intent save = new Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(mimeType(name))
                            .putExtra(Intent.EXTRA_TITLE, name);
                    save.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
                            | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
                    launchPicker(save, result);
                    break;
                case "readUri": {
                    Uri uri = requireUri(call);
                    ContentResolver resolver = applicationContext.getContentResolver();
                    runIo(result, () -> readBytes(resolver, uri));
                    break;
                }
                case "writeUri": {
                    Uri uri = requireUri(call);
                    Object value = call.argument("bytes");
                    if (!(value instanceof byte[])) {
                        throw new IllegalArgumentException("bytes must be binary data.");
                    }
                    byte[] bytes = (byte[]) value;
                    ContentResolver resolver = applicationContext.getContentResolver();
                    runIo(result, () -> {
                        writeBytes(resolver, uri, bytes);
                        return null;
                    });
                    break;
                }
                default:
                    result.notImplemented();
            }
        } catch (IllegalArgumentException | ClassCastException error) {
            result.error("INVALID_ARGUMENT", error.getMessage(), null);
        }
    }

    private void launchPicker(Intent intent, MethodChannel.Result result) {
        if (pendingPicker != null) {
            result.error("PICKER_BUSY", "Another document picker is already open.", null);
            return;
        }
        if (activityBinding == null) {
            result.error("NO_ACTIVITY", "A document picker requires an attached Activity.", null);
            return;
        }
        pendingPicker = result;
        try {
            activityBinding.getActivity().startActivityForResult(intent, PICK_DOCUMENT_REQUEST);
        } catch (RuntimeException error) {
            pendingPicker = null;
            result.error("PICKER_ERROR", error.getMessage(), null);
        }
    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != PICK_DOCUMENT_REQUEST || pendingPicker == null) return false;
        MethodChannel.Result result = pendingPicker;
        pendingPicker = null;
        Uri uri = data == null ? null : data.getData();
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null);
            return true;
        }
        ContentResolver resolver = applicationContext.getContentResolver();
        int grants = data.getFlags() & (Intent.FLAG_GRANT_READ_URI_PERMISSION
                | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        if (grants != 0 && (data.getFlags() & Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) != 0) {
            try {
                resolver.takePersistableUriPermission(uri, grants);
            } catch (SecurityException ignored) {
                // A temporary grant is still valid for this operation.
            }
        }
        runIo(result, () -> document(resolver, uri));
        return true;
    }

    private void runIo(MethodChannel.Result result, Callable<Object> operation) {
        pendingIo.add(result);
        try {
            ioExecutor.execute(() -> {
                try {
                    Object value = operation.call();
                    mainHandler.post(() -> {
                        if (pendingIo.remove(result)) result.success(value);
                    });
                } catch (Exception error) {
                    mainHandler.post(() -> {
                        if (pendingIo.remove(result)) {
                            result.error("PICKER_ERROR", error.getMessage(), null);
                        }
                    });
                }
            });
        } catch (RejectedExecutionException error) {
            pendingIo.remove(result);
            result.error("PICKER_DETACHED", "The file service was detached.", null);
        }
    }

    private static Uri requireUri(MethodCall call) {
        Object value = call.argument("uri");
        if (!(value instanceof String) || ((String) value).isEmpty()) {
            throw new IllegalArgumentException("uri must be a nonempty string.");
        }
        return Uri.parse((String) value);
    }

    private static String mimeType(String name) {
        int dot = name.lastIndexOf('.');
        String extension = dot < 0 ? "" : name.substring(dot + 1).toLowerCase(Locale.ROOT);
        if (extension.equals("qsz") || extension.equals("qfliz")) {
            return "application/octet-stream";
        }
        String type = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension);
        return type == null ? "application/octet-stream" : type;
    }

    private static Map<String, Object> document(ContentResolver resolver, Uri uri) {
        String name = uri.getLastPathSegment();
        try (Cursor cursor = resolver.query(uri,
                new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (index >= 0 && !cursor.isNull(index)) name = cursor.getString(index);
            }
        } catch (RuntimeException ignored) {
            // Folder providers may omit OpenableColumns; the URI remains usable.
        }
        Map<String, Object> value = new HashMap<>();
        value.put("uri", uri.toString());
        value.put("name", name == null ? "" : name);
        return value;
    }

    private static byte[] readBytes(ContentResolver resolver, Uri uri) throws IOException {
        try (InputStream input = resolver.openInputStream(uri);
                ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            if (input == null) throw new IOException("The document could not be opened.");
            byte[] buffer = new byte[65536];
            int count;
            while ((count = input.read(buffer)) != -1) {
                if (Thread.currentThread().isInterrupted()) throw new IOException("Read cancelled.");
                output.write(buffer, 0, count);
            }
            return output.toByteArray();
        }
    }

    private static void writeBytes(ContentResolver resolver, Uri uri, byte[] bytes)
            throws IOException {
        try (OutputStream output = resolver.openOutputStream(uri, "wt")) {
            if (output == null) throw new IOException("The document could not be opened.");
            for (int offset = 0; offset < bytes.length;) {
                if (Thread.currentThread().isInterrupted()) throw new IOException("Write cancelled.");
                int count = Math.min(65536, bytes.length - offset);
                output.write(bytes, offset, count);
                offset += count;
            }
        }
    }
}
