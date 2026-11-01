package dev.skyport.app;

public final class UsbSerialException extends Exception {
    public final String kind;
    public final long bytesWritten;

    public UsbSerialException(String kind, String message) {
        this(kind, message, 0);
    }

    public UsbSerialException(String kind, String message, long bytesWritten) {
        super(message);
        this.kind = kind;
        this.bytesWritten = bytesWritten;
    }
}
