package dev.skyport.app;

import android.content.Intent;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;


import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public final class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "skyport/android";
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private UsbSerialBackend backend;
    private MethodChannel channel;
    private MethodChannel host;
    private boolean closing;
    private MethodChannel.Result exportResult;
    private File pendingExport;
    private boolean foreground;


    @Override
    public void configureFlutterEngine(FlutterEngine engine) {
        System.loadLibrary("skyport_flutter_bridge");
        backend = new UsbSerialBackend(this);
        backend.install();
        backend.setForeground(foreground);
        super.configureFlutterEngine(engine);
        channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        host = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "skyport/host");
        channel.setMethodCallHandler((call, result) -> {
            if ("isForeground".equals(call.method)) {
                result.success(foreground);
            } else if ("exportFile".equals(call.method)) {
                exportFile(call.arguments, result);
            } else {
                result.notImplemented();
            }
        });
    }

    @Override
    protected void onStart() {
        super.onStart();
        foreground = true;
        if (backend != null) backend.setForeground(true);
    }

    @Override
    protected void onStop() {
        if (backend != null) backend.setForeground(false);
        foreground = false;
        if (channel != null) channel.invokeMethod("suspend", null);
        super.onStop();
    }
    @Override
    public boolean popSystemNavigator() {
        if (host == null) return false;
        if (closing) return true;
        closing = true;
        host.invokeMethod("requestClose", null, new MethodChannel.Result() {
            @Override public void success(Object result) {
                if (Boolean.TRUE.equals(result)) finish();
                else closing = false;
            }
            @Override public void error(String code, String message, Object details) {
                closing = false;
                Log.e("SkyPort", "Core shutdown failed: " + message);
            }
            @Override public void notImplemented() {
                closing = false;
                Log.e("SkyPort", "Core shutdown handler is unavailable");
            }
        });
        return true;
    }


    @Override
    protected void onDestroy() {
        if (backend != null) backend.shutdown();
        io.shutdown();
        if (exportResult != null) {
            exportResult.error("export_cancelled", "Activity was destroyed", null);
            exportResult = null;
        }
        super.onDestroy();
    }

    private void exportFile(Object arguments, MethodChannel.Result result) {
        if (exportResult != null) {
            result.error("export_in_progress", "Another export is already in progress", null);
            return;
        }
        if (!(arguments instanceof Map)) {
            result.error("invalid_arguments", "Expected path and suggestedName", null);
            return;
        }
        Object path = ((Map<?, ?>) arguments).get("path");
        Object name = ((Map<?, ?>) arguments).get("suggestedName");
        if (!(path instanceof String) || !(name instanceof String) || ((String) name).isEmpty()) {
            result.error("invalid_arguments", "Expected path and suggestedName", null);
            return;
        }
        exportResult = result;
        pendingExport = new File((String) path);
        try {
            Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("text/plain")
                    .putExtra(Intent.EXTRA_TITLE, (String) name);
            startActivityForResult(intent, 1001);
        } catch (RuntimeException e) {
            pendingExport = null;
            exportResult = null;
            result.error("export_failed", e.getMessage(), null);
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == 1001) {
            onDocumentCreated(resultCode == RESULT_OK && data != null ? data.getData() : null);
        }
    }

    private void onDocumentCreated(Uri uri) {
        final MethodChannel.Result result = exportResult;
        final File source = pendingExport;
        exportResult = null;
        pendingExport = null;
        if (result == null) return;
        if (uri == null) {
            result.success(null);
            return;
        }
        try {
            File privateRoot = getDataDir().getCanonicalFile();
            File input = source.getCanonicalFile();
            if (!input.toPath().startsWith(privateRoot.toPath())) {
                throw new IOException("Export source must be app-private");
            }
            io.execute(() -> {
                try {
                    try (InputStream in = new FileInputStream(input);
                         OutputStream out = getContentResolver().openOutputStream(uri, "w")) {
                        if (out == null) throw new IOException("Unable to open destination");
                        byte[] buffer = new byte[8192];
                        int count;
                        while ((count = in.read(buffer)) != -1) out.write(buffer, 0, count);
                    }
                    main.post(() -> result.success(uri.toString()));
                } catch (IOException | RuntimeException e) {
                    Log.e("SkyPort", "Export failed", e);
                    main.post(() -> result.error("export_failed", e.getMessage(), null));
                }
            });
        } catch (IOException e) {
            result.error("export_failed", e.getMessage(), null);
        }
    }
}
