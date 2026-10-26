mod app;
pub mod config;
pub mod logging;
mod serial;

pub use app::{AppCore, EventSubscription};
pub use config::{
    AppConfig, FlowControl, LegacyConfig, Newline, Parity, SendSettings, SerialConfig,
};
pub use logging::{Direction, ExportOptions, LogDelta, LogRecord, LogSnapshot, LogStore};
use serde::{Deserialize, Serialize};
use std::{error::Error, fmt, path::PathBuf, time::Duration};

pub type RequestId = u64;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ErrorKind {
    InvalidArgument,
    PortNotFound,
    OpenFailed,
    PermissionDenied,
    UnsupportedConfiguration,
    ReadFailed,
    Disconnected,
    WriteFailed,
    Timeout,
    Closed,
    QueueOverflow,
    TaskFailed,
    Internal,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ErrorCode {
    InvalidHexCharacter,
    IncompleteHexByte,
    PortNameRequired,
    PortNameTooLong,
    PortNameInvalid,
    BaudRateInvalid,
    DataBitsInvalid,
    StopBitsInvalid,
    LegacyConfigInvalid,
    ConfigVersionUnsupported,
    NewlineInvalid,
    AutoSendIntervalInvalid,
    LogCapacityInvalid,
    HistoryTooLong,
    HistoryEntryEmpty,
    HistoryTooLarge,
    ConfigTooLarge,
    ConfigInvalid,
    ConfigIo,
    SendTooLarge,
    SendInputTooLarge,
    AutoSendTooLarge,
    SendEmpty,
    NoLogsToExport,
    ExportFailed,
    QueueCapacityInvalid,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CoreError {
    pub kind: ErrorKind,
    pub code: Option<ErrorCode>,
    pub message: String,
    pub bytes_written: u64,
}
impl CoreError {
    pub fn new(kind: ErrorKind, message: impl Into<String>) -> Self {
        Self {
            kind,
            code: None,
            message: message.into(),
            bytes_written: 0,
        }
    }
    pub fn with_code(mut self, code: ErrorCode) -> Self {
        self.code = Some(code);
        self
    }
    pub fn with_written(mut self, bytes_written: u64) -> Self {
        self.bytes_written = bytes_written;
        self
    }
}
impl fmt::Display for CoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)
    }
}
impl Error for CoreError {}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Reconfiguring,
    Disconnecting,
    Reconnecting,
    Closing,
    Closed,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AppSnapshot {
    pub sequence: u64,
    pub config: AppConfig,
    pub connection: ConnectionState,
    pub applied_config: Option<SerialConfig>,
    pub connected_at_ms: Option<i64>,
    pub ports: Vec<String>,
    pub rx_bytes: u64,
    pub tx_bytes: u64,
    pub last_rx_bytes: u64,
    pub rx_bytes_per_second: f64,
    pub error: Option<CoreError>,
    pub auto_send_error: Option<CoreError>,
    pub log: LogSnapshot,
    pub auto_send_input: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AppState {
    pub sequence: u64,
    pub config: AppConfig,
    pub connection: ConnectionState,
    pub applied_config: Option<SerialConfig>,
    pub connected_at_ms: Option<i64>,
    pub ports: Vec<String>,
    pub rx_bytes: u64,
    pub tx_bytes: u64,
    pub last_rx_bytes: u64,
    pub rx_bytes_per_second: f64,
    pub error: Option<CoreError>,
    pub auto_send_error: Option<CoreError>,
    pub auto_send_input: String,
}
#[derive(Clone, Debug, Default)]
pub struct ConfigPatch {
    pub port_name: Option<String>,
    pub baud_rate: Option<u32>,
    pub data_bits: Option<u8>,
    pub parity: Option<Parity>,
    pub stop_bits: Option<u8>,
    pub auto_reconnect: Option<bool>,
    pub flow_control: Option<FlowControl>,
    pub hex_send: Option<bool>,
    pub newline: Option<Newline>,
    pub append_newline: Option<bool>,
    pub auto_send_enabled: Option<bool>,
    pub auto_send_interval_ms: Option<u32>,
    pub log_capacity_bytes: Option<u64>,
    pub auto_send_input: Option<String>,
}
#[derive(Clone, Debug)]
pub enum Command {
    ListPorts,
    SetConfig(AppConfig),
    UpdateConfig(ConfigPatch),
    Connect,
    Disconnect,
    SendText {
        text: String,
        newline: Newline,
    },
    SendHex {
        input: String,
    },
    SendInput {
        input: String,
    },
    ClearLog,
    SetAutoReconnect(bool),
    SetAutoSend {
        enabled: bool,
        interval_ms: u32,
        input: String,
        hex: bool,
        newline: Newline,
    },
    ExportLog {
        path: String,
        options: ExportOptions,
    },
}

#[derive(Clone, Debug)]
pub struct Event {
    pub sequence: u64,
    pub kind: EventKind,
}
#[derive(Clone, Debug)]
pub enum EventKind {
    StateChanged(AppState),
    PortsChanged(Vec<String>),
    LogChanged(LogDelta),
    DataReceived {
        data: Vec<u8>,
        log: LogDelta,
        rx_bytes: u64,
        last_rx_bytes: u64,
    },
    DataSent {
        request_id: RequestId,
        data: Vec<u8>,
        log: LogDelta,
        tx_bytes: u64,
    },
    WriteFailed {
        request_id: RequestId,
        error: CoreError,
    },
    Disconnected(CoreError),
    Reconnecting,
    QueueOverflow(CoreError),
    TaskFailed(CoreError),
    CommandCompleted {
        request_id: RequestId,
    },
    CommandFailed {
        request_id: RequestId,
        error: CoreError,
    },
}

#[derive(Clone, Debug)]
pub struct AppOptions {
    pub data_directory: PathBuf,
    pub legacy_config: Option<LegacyConfig>,
    pub command_capacity: usize,
    pub event_capacity: usize,
}
impl Default for AppOptions {
    fn default() -> Self {
        Self {
            data_directory: PathBuf::from("."),
            legacy_config: None,
            command_capacity: 128,
            event_capacity: 256,
        }
    }
}

pub(crate) fn timestamp_ms() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::ZERO)
        .as_millis() as i64
}
