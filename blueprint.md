# Blueprint: Flutter Serial Port Debugging Assistant

## Overview

This document outlines the plan for creating a cross-platform serial port debugging assistant using Flutter. The application will provide a user-friendly interface for configuring serial port connections, sending data, and visualizing received data, all while adhering to Material Design 3 (M3) principles.

## Core Features & Style

*   **Framework:** Flutter 3.x
*   **Core Library:** `flutter_libserialport` for serial communication.
*   **UI Style:** Material Design 3 (M3).
*   **State Management:** `flutter_riverpod`.
*   **Layout:** Responsive two-column layout (fixed-width left panel for controls, flexible main area for data).

## Implemented Features & Design

*This section will be updated as features are implemented.*

### Initial Setup
-   Dependencies (`flutter_libserialport`, `flutter_riverpod`) added.
-   Basic project structure created.
-   Main application entry point configured with Riverpod's `ProviderScope`.

## Current Development Plan

### Step 1: Foundational Setup
1.  **Add Dependencies:** Add `flutter_libserialport` and `flutter_riverpod` to `pubspec.yaml`.
2.  **Project Structure:** Create folders for `providers`, `widgets`, and `models` to keep the code organized.
3.  **Main Layout:**
    *   Modify `lib/main.dart` to set up the main application widget.
    *   Create a `HomePage` widget that implements the two-column layout (Left Panel & Main Area) and a bottom status bar.
    *   Apply a basic Material 3 theme using `ThemeData(useMaterial3: true)`.

### Step 2: State Management with Riverpod
1.  **Create Providers File:** Create `lib/providers/serial_provider.dart`.
2.  **Define Core Providers:**
    *   `availablePortsProvider`: A `FutureProvider` to get the list of available serial ports.
    *   `serialConfigProvider`: A `StateNotifierProvider` to manage user-selected settings (port, baud rate, etc.).
    *   `serialConnectionProvider`: A `StateNotifierProvider` to manage the `SerialPort` instance, connection state, and data transmission.
    *   `dataLogProvider`: A `StateNotifierProvider` to hold the list of sent/received data messages.
    *   `settingsProvider`: A `StateNotifierProvider` to manage UI settings like Hex display/send.

### Step 3: Build UI Components
1.  **Left Panel (`lib/widgets/left_panel.dart`):**
    *   **Serial Port Settings Card:**
        *   Dropdown for Port Name, populated by `availablePortsProvider`.
        *   Refresh button to refetch ports.
        *   Dropdowns for Baud Rate, Data Bits, Parity, Stop Bits.
        *   A "Open" / "Close" button that interacts with `serialConnectionProvider`.
        *   Disable controls when the port is open.
    *   **Receive Settings Card:**
        *   "Hex Display" `SwitchListTile`.
        *   "Clear" button to clear the `dataLogProvider`.
    *   **Send Settings Card:**
        *   "Hex Send" `SwitchListTile`.
2.  **Right Panel (`lib/widgets/right_panel.dart`):**
    *   **Data Display Area:**
        *   An `Expanded` `Scrollbar` with a `ListView` that displays data from `dataLogProvider`.
        *   Differentiate between sent and received messages visually.
    *   **Input & Send Area:**
        *   A `TextField` for data input.
        *   A `FilledButton` with a send icon to trigger sending data via `serialConnectionProvider`.
3.  **Status Bar (`lib/widgets/status_bar.dart`):**
    *   Display Rx/Tx byte counts from `serialConnectionProvider`.
    *   Show connection status (e.g., "Disconnected", "Connected to COM3@9600").

### Step 4: Implement Core Logic
1.  **Flesh out `serialConnectionProvider`:**
    *   Implement the `open()` method to configure and open the serial port using settings from `serialConfigProvider`.
    *   Set up `SerialPortReader` to listen for incoming data and update the `dataLogProvider` and Rx count.
    *   Implement the `close()` method.
    *   Implement the `send()` method, which will handle potential Hex-to-byte conversion.
    *   Add robust error handling using `try-catch` for `SerialPortError`.

### Step 5: Refinement
1.  **Polish UI:** Ensure all components adhere to M3 guidelines.
2.  **Add Timestamps:** Optionally add timestamps to data logs.
3.  **Error Display:** Show errors to the user via `SnackBar` or `AlertDialog`.
4.  **Code Cleanup:** Review and format all code.
