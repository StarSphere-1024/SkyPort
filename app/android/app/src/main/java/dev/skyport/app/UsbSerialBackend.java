package dev.skyport.app;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.os.SystemClock;

import com.hoho.android.usbserial.driver.UsbSerialDriver;
import com.hoho.android.usbserial.driver.UsbSerialPort;
import com.hoho.android.usbserial.driver.UsbSerialProber;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

public final class UsbSerialBackend {
    private static final String PERMISSION = "dev.skyport.app.USB_PERMISSION";
    private final Context context;
    private final UsbManager manager;
    private final Map<String, PortRef> ports = new HashMap<>();
    private final Map<Long, Session> sessions = new HashMap<>();
    private final Set<Integer> requested = new HashSet<>();
    private long nextHandle = 1;
    private boolean foreground;
    private boolean shutdown;

    public UsbSerialBackend(Activity activity) {
        context = activity.getApplicationContext();
        manager = (UsbManager) context.getSystemService(Context.USB_SERVICE);
        IntentFilter filter = new IntentFilter(PERMISSION);
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED);
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
        else context.registerReceiver(receiver, filter);
    }

    public native void install();

    private final BroadcastReceiver receiver = new BroadcastReceiver() {
        @Override public void onReceive(Context ignored, Intent intent) {
            UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
            if (device == null) return;
            synchronized (UsbSerialBackend.this) {
                if (UsbManager.ACTION_USB_DEVICE_DETACHED.equals(intent.getAction())) {
                    sessions.entrySet().removeIf(entry -> {
                        if (entry.getValue().ref.deviceId != device.getDeviceId()) return false;
                        entry.getValue().close();
                        return true;
                    });
                    ports.values().removeIf(ref -> ref.deviceId == device.getDeviceId());
                    requested.remove(device.getDeviceId());
                } else if (PERMISSION.equals(intent.getAction()) &&
                        intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                    requested.remove(device.getDeviceId());
                }
            }
        }
    };

    private static final class PortRef {
        final UsbSerialPort port;
        final int deviceId;
        final String attachmentKey;
        PortRef(UsbSerialPort port) {
            this.port = port;
            deviceId = port.getDevice().getDeviceId();
            attachmentKey = port.getDevice().getDeviceName() + "#" + port.getPortNumber();
        }
    }

    private static final class Session implements Runnable {
        final PortRef ref;
        final UsbDeviceConnection connection;
        final byte[] ring = new byte[1024 * 1024];
        final Thread reader;
        int head, size;
        boolean closed;
        boolean suspended;
        String failure;
        Session(PortRef ref, UsbDeviceConnection connection) {
            this.ref = ref;
            this.connection = connection;
            reader = new Thread(this, "skyport-usb-reader");
        }
        @Override public void run() {
            byte[] input = new byte[8192];
            try {
                while (true) {
                    synchronized (this) { if (closed || failure != null) return; }
                    // Infinite USB-request read avoids Android bulkTransfer short-timeout data loss.
                    int count = ref.port.read(input, 0);
                    if (count <= 0) continue;
                    synchronized (this) {
                        if (closed) return;
                        if (count > ring.length - size) {
                            failure = "USB receive buffer overflow; data was lost";
                            notifyAll();
                            return;
                        }
                        int tail = (head + size) % ring.length;
                        int first = Math.min(count, ring.length - tail);
                        System.arraycopy(input, 0, ring, tail, first);
                        System.arraycopy(input, first, ring, 0, count - first);
                        size += count;
                        notifyAll();
                    }
                }
            } catch (IOException | RuntimeException e) {
                synchronized (this) {
                    if (!closed) failure = e.toString();
                    notifyAll();
                }
            }
        }
        synchronized int read(byte[] destination, int length, int timeout) throws UsbSerialException {
            long deadline = SystemClock.elapsedRealtime() + Math.max(1, timeout);
            while (size == 0 && failure == null && !closed) {
                long remaining = deadline - SystemClock.elapsedRealtime();
                if (remaining <= 0) return 0;
                try { wait(remaining); }
                catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new UsbSerialException("readFailed", "USB read was interrupted");
                }
            }
            if (suspended) return 0; // Intentional lifecycle cancellation, not a lost USB link.
            if (failure != null) throw new UsbSerialException("readFailed", failure);
            if (closed) throw new UsbSerialException("disconnected", "USB serial session is closed");
            int count = Math.min(size, Math.min(destination.length, length));
            int first = Math.min(count, ring.length - head);
            System.arraycopy(ring, head, destination, 0, first);
            System.arraycopy(ring, 0, destination, first, count - first);
            head = (head + count) % ring.length;
            size -= count;
            return count;
        }
        void suspend() {
            synchronized (this) { suspended = true; }
            close();
        }
        void close() {
            synchronized (this) { closed = true; notifyAll(); }
            try { ref.port.close(); } catch (IOException ignored) { }
        }
    }

    public synchronized String[] ports() {
        if (shutdown) return new String[0];
        Map<String, String> existing = new HashMap<>();
        for (Map.Entry<String, PortRef> entry : ports.entrySet())
            existing.put(entry.getValue().attachmentKey, entry.getKey());
        Map<String, PortRef> discovered = new HashMap<>();
        List<String> names = new ArrayList<>();
        for (UsbSerialDriver driver : UsbSerialProber.getDefaultProber().findAllDrivers(manager)) {
            UsbDevice device = driver.getDevice();
            for (UsbSerialPort port : driver.getPorts()) {
                PortRef candidate = new PortRef(port);
                String name = existing.get(candidate.attachmentKey);
                if (name == null) {
                    // ponytail: attachment IDs require reselection after unplug/restart; use verified hardware serials if needed.
                    name = String.format("%s [%04X:%04X] #%d @%s", device.getProductName(),
                            device.getVendorId(), device.getProductId(), port.getPortNumber(), UUID.randomUUID().toString().substring(0, 8));
                } else candidate = ports.get(name);
                discovered.put(name, candidate);
                names.add(name);
            }
        }
        ports.clear();
        ports.putAll(discovered);
        names.sort(String::compareTo);
        return names.toArray(new String[0]);
    }

    public synchronized long open(String name, int baud, int dataBits, int parity, int stopBits, int flowControl) throws UsbSerialException {
        checkForeground();
        PortRef ref = ports.get(name);
        if (ref == null || !manager.getDeviceList().containsKey(ref.port.getDevice().getDeviceName()))
            throw new UsbSerialException("portNotFound", "USB serial port is no longer attached");
        UsbDevice device = ref.port.getDevice();
        if (!manager.hasPermission(device)) {
            if (requested.add(device.getDeviceId())) {
                Intent intent = new Intent(PERMISSION).setPackage(context.getPackageName());
                manager.requestPermission(device, PendingIntent.getBroadcast(context, device.getDeviceId(), intent,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE));
            }
            throw new UsbSerialException("permissionDenied", "Allow USB access then connect again; if denied, unplug and reconnect the device");
        }
        UsbDeviceConnection connection = manager.openDevice(device);
        if (connection == null) throw new UsbSerialException("openFailed", "USB device could not be opened");
        try {
            ref.port.open(connection);
            ref.port.setParameters(baud, dataBits, stopBits, parity);
            UsbSerialPort.FlowControl flow = flowControl == 1 ? UsbSerialPort.FlowControl.RTS_CTS :
                    flowControl == 2 ? UsbSerialPort.FlowControl.XON_XOFF : UsbSerialPort.FlowControl.NONE;
            ref.port.setFlowControl(flow);
            Session session = new Session(ref, connection);
            long handle = nextHandle++;
            sessions.put(handle, session);
            session.reader.start();
            return handle;
        } catch (UnsupportedOperationException | IllegalArgumentException e) {
            try { ref.port.close(); } catch (IOException ignored) { }
            connection.close();
            throw new UsbSerialException("unsupportedConfiguration", e.toString());
        } catch (IOException | RuntimeException e) {
            try { ref.port.close(); } catch (IOException ignored) { }
            connection.close();
            throw new UsbSerialException("openFailed", e.toString());
        }
    }

    public int read(long handle, byte[] bytes, int length, int timeoutMs) throws UsbSerialException {
        Session current;
        synchronized (this) {
            if (!foreground && !shutdown) return 0;
            current = session(handle);
        }
        return current.read(bytes, length, timeoutMs);
    }

    public int write(long handle, byte[] bytes, int length, int timeoutMs) throws UsbSerialException {
        Session session = session(handle);
        // One transfer exposes partial progress; driver write() can hide progress on disconnect.
        int count = session.connection.bulkTransfer(session.ref.port.getWriteEndpoint(),
                bytes, Math.min(length, 16384), Math.max(1, timeoutMs));
        if (count >= 0) return count;
        boolean attached = manager.getDeviceList().containsKey(session.ref.port.getDevice().getDeviceName());
        throw new UsbSerialException(attached ? "timeout" : "disconnected",
                "USB write failed; progress within the failed transfer is not reported by Android");
    }

    private synchronized Session session(long handle) throws UsbSerialException {
        checkForeground();
        Session session = sessions.get(handle);
        if (session == null) throw new UsbSerialException("disconnected", "USB serial session is closed");
        return session;
    }

    public synchronized void close(long handle) {
        Session session = sessions.remove(handle);
        if (session != null) session.close();
    }
    private void checkForeground() throws UsbSerialException {
        if (shutdown || !foreground) throw new UsbSerialException("disconnected", "USB serial access requires a visible application");
    }
    public synchronized void setForeground(boolean value) {
        foreground = value;
        if (!value) {
            for (Session session : sessions.values()) session.suspend();
            sessions.clear();
        }
    }
    public synchronized void shutdown() {
        if (shutdown) return;
        setForeground(false);
        shutdown = true;
        context.unregisterReceiver(receiver);
        ports.clear();
    }
}
