use std::{path::PathBuf, sync::Mutex, time::Duration};

use skyport_core as core;

pub struct CoreHandle(core::AppCore);
pub struct SubscriptionHandle(Mutex<core::EventSubscription>);

#[derive(Clone, Copy, Debug)]
pub enum Parity {
    None,
    Odd,
    Even,
}
#[derive(Clone, Copy, Debug)]
pub enum Newline {
    None,
    Lf,
    Cr,
    CrLf,
}
#[derive(Clone, Copy, Debug)]
pub enum FlowControl {
    None,
    Hardware,
    Software,
}
#[derive(Clone, Debug)]
pub struct SerialConfig {
    pub port_name: String,
    pub baud_rate: u32,
    pub data_bits: u8,
    pub parity: Parity,
    pub stop_bits: u8,
    pub auto_reconnect: bool,
    pub flow_control: FlowControl,
}
#[derive(Clone, Debug)]
pub struct SendSettings {
    pub hex: bool,
    pub newline: Newline,
    pub append_newline: bool,
    pub auto_send_enabled: bool,
    pub auto_send_interval_ms: u32,
}
#[derive(Clone, Debug)]
pub struct AppConfig {
    pub version: u32,
    pub serial: SerialConfig,
    pub send: SendSettings,
    pub log_capacity_bytes: u64,
    pub history: Vec<String>,
}
#[derive(Clone, Debug)]
pub struct LegacyConfig {
    pub port_name: Option<String>,
    pub baud_rate: Option<i64>,
    pub data_bits: Option<i64>,
    pub parity: Option<i64>,
    pub stop_bits: Option<i64>,
    pub auto_reconnect: Option<bool>,
    pub hex_send: Option<bool>,
    pub append_newline: Option<bool>,
    pub newline_mode: Option<i64>,
    pub auto_send_enabled: Option<bool>,
    pub auto_send_interval_ms: Option<i64>,
    pub log_buffer_megabytes: Option<i64>,
    pub history: Option<Vec<String>>,
}
impl From<LegacyConfig> for core::config::LegacyConfig {
    fn from(value: LegacyConfig) -> Self {
        Self {
            port_name: value.port_name,
            baud_rate: value.baud_rate,
            data_bits: value.data_bits,
            parity: value.parity,
            stop_bits: value.stop_bits,
            auto_reconnect: value.auto_reconnect,
            hex_send: value.hex_send,
            append_newline: value.append_newline,
            newline_mode: value.newline_mode,
            auto_send_enabled: value.auto_send_enabled,
            auto_send_interval_ms: value.auto_send_interval_ms,
            log_buffer_megabytes: value.log_buffer_megabytes,
            history: value.history,
        }
    }
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
impl From<ConfigPatch> for core::ConfigPatch {
    fn from(value: ConfigPatch) -> Self {
        Self {
            port_name: value.port_name,
            baud_rate: value.baud_rate,
            data_bits: value.data_bits,
            parity: value.parity.map(Into::into),
            stop_bits: value.stop_bits,
            auto_reconnect: value.auto_reconnect,
            flow_control: value.flow_control.map(Into::into),
            hex_send: value.hex_send,
            newline: value.newline.map(Into::into),
            append_newline: value.append_newline,
            auto_send_enabled: value.auto_send_enabled,
            auto_send_interval_ms: value.auto_send_interval_ms,
            log_capacity_bytes: value.log_capacity_bytes,
            auto_send_input: value.auto_send_input,
        }
    }
}
#[derive(Clone, Copy, Debug)]
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
#[derive(Clone, Copy, Debug)]
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
#[derive(Clone, Debug)]
pub struct CoreError {
    pub kind: ErrorKind,
    pub code: Option<ErrorCode>,
    pub message: String,
    pub bytes_written: u64,
}
#[derive(Clone, Copy, Debug)]
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
#[derive(Clone, Copy, Debug)]
pub enum Direction {
    Received,
    Sent,
}
#[derive(Clone, Debug)]
pub struct LogRecord {
    pub id: u64,
    pub timestamp_ms: i64,
    pub direction: Direction,
    pub data: Vec<u8>,
    pub pending: bool,
}
#[derive(Clone, Debug)]
pub struct LogSnapshot {
    pub records: Vec<LogRecord>,
    pub total_bytes: u64,
    pub trimmed_bytes: u64,
    pub trimmed_records: u64,
    pub incomplete: bool,
}
#[derive(Clone, Debug)]
pub struct LogDelta {
    pub upsert: Vec<LogRecord>,
    pub removed_ids: Vec<u64>,
    pub earliest_id: u64,
    pub total_bytes: u64,
    pub trimmed_bytes: u64,
    pub trimmed_records: u64,
    pub incomplete: bool,
}
#[derive(Clone, Debug)]
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
#[derive(Clone, Debug)]
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
#[derive(Clone, Copy, Debug)]
pub struct ExportOptions {
    pub show_sent: bool,
    pub hex: bool,
    pub timestamps: bool,
    pub strip_ansi: bool,
}
#[derive(Clone, Copy, Debug)]
pub enum EventType {
    StateChanged,
    PortsChanged,
    LogChanged,
    DataReceived,
    DataSent,
    WriteFailed,
    Disconnected,
    Reconnecting,
    QueueOverflow,
    TaskFailed,
    CommandCompleted,
    CommandFailed,
}
#[derive(Clone, Debug)]
pub struct Event {
    pub sequence: u64,
    pub kind: EventType,
    pub state: Option<AppState>,
    pub ports: Option<Vec<String>>,
    pub data: Option<Vec<u8>>,
    pub log: Option<LogDelta>,
    pub rx_bytes: Option<u64>,
    pub tx_bytes: Option<u64>,
    pub last_rx_bytes: Option<u64>,
    pub request_id: Option<u64>,
    pub error: Option<CoreError>,
}

pub struct CreateCoreReply {
    pub handle: Option<CoreHandle>,
    pub error: Option<CoreError>,
}
pub struct SnapshotReply {
    pub snapshot: Option<AppSnapshot>,
    pub error: Option<CoreError>,
}
pub struct SubscribeReply {
    pub snapshot: Option<AppSnapshot>,
    pub subscription: Option<SubscriptionHandle>,
    pub error: Option<CoreError>,
}
pub struct EventsReply {
    pub events: Vec<Event>,
    pub error: Option<CoreError>,
}
pub struct DispatchReply {
    pub request_id: Option<u64>,
    pub error: Option<CoreError>,
}
pub struct CloseReply {
    pub error: Option<CoreError>,
}

impl From<core::CoreError> for CoreError {
    fn from(error: core::CoreError) -> Self {
        Self {
            kind: error.kind.into(),
            code: error.code.map(Into::into),
            message: error.message,
            bytes_written: error.bytes_written,
        }
    }
}
impl From<core::ErrorCode> for ErrorCode {
    fn from(code: core::ErrorCode) -> Self {
        match code {
            core::ErrorCode::InvalidHexCharacter => Self::InvalidHexCharacter,
            core::ErrorCode::IncompleteHexByte => Self::IncompleteHexByte,
            core::ErrorCode::PortNameRequired => Self::PortNameRequired,
            core::ErrorCode::PortNameTooLong => Self::PortNameTooLong,
            core::ErrorCode::PortNameInvalid => Self::PortNameInvalid,
            core::ErrorCode::BaudRateInvalid => Self::BaudRateInvalid,
            core::ErrorCode::DataBitsInvalid => Self::DataBitsInvalid,
            core::ErrorCode::StopBitsInvalid => Self::StopBitsInvalid,
            core::ErrorCode::LegacyConfigInvalid => Self::LegacyConfigInvalid,
            core::ErrorCode::ConfigVersionUnsupported => Self::ConfigVersionUnsupported,
            core::ErrorCode::NewlineInvalid => Self::NewlineInvalid,
            core::ErrorCode::AutoSendIntervalInvalid => Self::AutoSendIntervalInvalid,
            core::ErrorCode::LogCapacityInvalid => Self::LogCapacityInvalid,
            core::ErrorCode::HistoryTooLong => Self::HistoryTooLong,
            core::ErrorCode::HistoryEntryEmpty => Self::HistoryEntryEmpty,
            core::ErrorCode::HistoryTooLarge => Self::HistoryTooLarge,
            core::ErrorCode::ConfigTooLarge => Self::ConfigTooLarge,
            core::ErrorCode::ConfigInvalid => Self::ConfigInvalid,
            core::ErrorCode::ConfigIo => Self::ConfigIo,
            core::ErrorCode::SendTooLarge => Self::SendTooLarge,
            core::ErrorCode::SendInputTooLarge => Self::SendInputTooLarge,
            core::ErrorCode::AutoSendTooLarge => Self::AutoSendTooLarge,
            core::ErrorCode::SendEmpty => Self::SendEmpty,
            core::ErrorCode::NoLogsToExport => Self::NoLogsToExport,
            core::ErrorCode::ExportFailed => Self::ExportFailed,
            core::ErrorCode::QueueCapacityInvalid => Self::QueueCapacityInvalid,
        }
    }
}
impl From<core::ErrorKind> for ErrorKind {
    fn from(kind: core::ErrorKind) -> Self {
        match kind {
            core::ErrorKind::InvalidArgument => Self::InvalidArgument,
            core::ErrorKind::PortNotFound => Self::PortNotFound,
            core::ErrorKind::OpenFailed => Self::OpenFailed,
            core::ErrorKind::PermissionDenied => Self::PermissionDenied,
            core::ErrorKind::UnsupportedConfiguration => Self::UnsupportedConfiguration,
            core::ErrorKind::ReadFailed => Self::ReadFailed,
            core::ErrorKind::Disconnected => Self::Disconnected,
            core::ErrorKind::WriteFailed => Self::WriteFailed,
            core::ErrorKind::Timeout => Self::Timeout,
            core::ErrorKind::Closed => Self::Closed,
            core::ErrorKind::QueueOverflow => Self::QueueOverflow,
            core::ErrorKind::TaskFailed => Self::TaskFailed,
            core::ErrorKind::Internal => Self::Internal,
        }
    }
}
impl From<Parity> for core::Parity {
    fn from(value: Parity) -> Self {
        match value {
            Parity::None => Self::None,
            Parity::Odd => Self::Odd,
            Parity::Even => Self::Even,
        }
    }
}
impl From<core::Parity> for Parity {
    fn from(value: core::Parity) -> Self {
        match value {
            core::Parity::None => Self::None,
            core::Parity::Odd => Self::Odd,
            core::Parity::Even => Self::Even,
        }
    }
}
impl From<FlowControl> for core::FlowControl {
    fn from(value: FlowControl) -> Self {
        match value {
            FlowControl::None => Self::None,
            FlowControl::Hardware => Self::Hardware,
            FlowControl::Software => Self::Software,
        }
    }
}
impl From<core::FlowControl> for FlowControl {
    fn from(value: core::FlowControl) -> Self {
        match value {
            core::FlowControl::None => Self::None,
            core::FlowControl::Hardware => Self::Hardware,
            core::FlowControl::Software => Self::Software,
        }
    }
}
impl From<Newline> for core::Newline {
    fn from(value: Newline) -> Self {
        match value {
            Newline::None => Self::None,
            Newline::Lf => Self::Lf,
            Newline::Cr => Self::Cr,
            Newline::CrLf => Self::CrLf,
        }
    }
}
impl From<core::Newline> for Newline {
    fn from(value: core::Newline) -> Self {
        match value {
            core::Newline::None => Self::None,
            core::Newline::Lf => Self::Lf,
            core::Newline::Cr => Self::Cr,
            core::Newline::CrLf => Self::CrLf,
        }
    }
}
impl From<SerialConfig> for core::SerialConfig {
    fn from(value: SerialConfig) -> Self {
        Self {
            port_name: value.port_name,
            baud_rate: value.baud_rate,
            data_bits: value.data_bits,
            parity: value.parity.into(),
            stop_bits: value.stop_bits,
            auto_reconnect: value.auto_reconnect,
            flow_control: value.flow_control.into(),
        }
    }
}
impl From<core::SerialConfig> for SerialConfig {
    fn from(value: core::SerialConfig) -> Self {
        Self {
            port_name: value.port_name,
            baud_rate: value.baud_rate,
            data_bits: value.data_bits,
            parity: value.parity.into(),
            stop_bits: value.stop_bits,
            auto_reconnect: value.auto_reconnect,
            flow_control: value.flow_control.into(),
        }
    }
}
impl From<AppConfig> for core::AppConfig {
    fn from(value: AppConfig) -> Self {
        Self {
            version: value.version,
            serial: value.serial.into(),
            send: core::SendSettings {
                hex: value.send.hex,
                newline: value.send.newline.into(),
                append_newline: value.send.append_newline,
                auto_send_enabled: value.send.auto_send_enabled,
                auto_send_interval_ms: value.send.auto_send_interval_ms,
            },
            log_capacity_bytes: value.log_capacity_bytes,
            history: value.history,
        }
    }
}
impl From<core::AppConfig> for AppConfig {
    fn from(value: core::AppConfig) -> Self {
        Self {
            version: value.version,
            serial: value.serial.into(),
            send: SendSettings {
                hex: value.send.hex,
                newline: value.send.newline.into(),
                append_newline: value.send.append_newline,
                auto_send_enabled: value.send.auto_send_enabled,
                auto_send_interval_ms: value.send.auto_send_interval_ms,
            },
            log_capacity_bytes: value.log_capacity_bytes,
            history: value.history,
        }
    }
}
impl From<core::ConnectionState> for ConnectionState {
    fn from(value: core::ConnectionState) -> Self {
        match value {
            core::ConnectionState::Disconnected => Self::Disconnected,
            core::ConnectionState::Connecting => Self::Connecting,
            core::ConnectionState::Connected => Self::Connected,
            core::ConnectionState::Reconfiguring => Self::Reconfiguring,
            core::ConnectionState::Disconnecting => Self::Disconnecting,
            core::ConnectionState::Reconnecting => Self::Reconnecting,
            core::ConnectionState::Closing => Self::Closing,
            core::ConnectionState::Closed => Self::Closed,
        }
    }
}
impl From<core::logging::Direction> for Direction {
    fn from(value: core::logging::Direction) -> Self {
        match value {
            core::logging::Direction::Received => Self::Received,
            core::logging::Direction::Sent => Self::Sent,
        }
    }
}
impl From<core::LogRecord> for LogRecord {
    fn from(value: core::LogRecord) -> Self {
        Self {
            id: value.id,
            timestamp_ms: value.timestamp_ms,
            direction: value.direction.into(),
            data: value.data,
            pending: value.pending,
        }
    }
}
impl From<core::LogSnapshot> for LogSnapshot {
    fn from(value: core::LogSnapshot) -> Self {
        Self {
            records: value.records.into_iter().map(Into::into).collect(),
            total_bytes: value.total_bytes,
            trimmed_bytes: value.trimmed_bytes,
            trimmed_records: value.trimmed_records,
            incomplete: value.incomplete,
        }
    }
}
impl From<core::LogDelta> for LogDelta {
    fn from(value: core::LogDelta) -> Self {
        Self {
            upsert: value.upsert.into_iter().map(Into::into).collect(),
            removed_ids: value.removed_ids,
            earliest_id: value.earliest_id,
            total_bytes: value.total_bytes,
            trimmed_bytes: value.trimmed_bytes,
            trimmed_records: value.trimmed_records,
            incomplete: value.incomplete,
        }
    }
}
impl From<core::AppSnapshot> for AppSnapshot {
    fn from(value: core::AppSnapshot) -> Self {
        Self {
            sequence: value.sequence,
            config: value.config.into(),
            connection: value.connection.into(),
            applied_config: value.applied_config.map(Into::into),
            connected_at_ms: value.connected_at_ms,
            ports: value.ports,
            rx_bytes: value.rx_bytes,
            tx_bytes: value.tx_bytes,
            last_rx_bytes: value.last_rx_bytes,
            rx_bytes_per_second: value.rx_bytes_per_second,
            error: value.error.map(Into::into),
            auto_send_error: value.auto_send_error.map(Into::into),
            log: value.log.into(),
            auto_send_input: value.auto_send_input,
        }
    }
}
impl From<core::AppState> for AppState {
    fn from(value: core::AppState) -> Self {
        Self {
            sequence: value.sequence,
            config: value.config.into(),
            connection: value.connection.into(),
            applied_config: value.applied_config.map(Into::into),
            connected_at_ms: value.connected_at_ms,
            ports: value.ports,
            rx_bytes: value.rx_bytes,
            tx_bytes: value.tx_bytes,
            last_rx_bytes: value.last_rx_bytes,
            rx_bytes_per_second: value.rx_bytes_per_second,
            error: value.error.map(Into::into),
            auto_send_error: value.auto_send_error.map(Into::into),
            auto_send_input: value.auto_send_input,
        }
    }
}
impl From<core::Event> for Event {
    fn from(value: core::Event) -> Self {
        let mut event = Self {
            sequence: value.sequence,
            kind: EventType::Reconnecting,
            state: None,
            ports: None,
            data: None,
            log: None,
            rx_bytes: None,
            tx_bytes: None,
            last_rx_bytes: None,
            request_id: None,
            error: None,
        };
        match value.kind {
            core::EventKind::StateChanged(state) => {
                event.kind = EventType::StateChanged;
                event.state = Some(state.into());
            }
            core::EventKind::PortsChanged(ports) => {
                event.kind = EventType::PortsChanged;
                event.ports = Some(ports);
            }
            core::EventKind::LogChanged(log) => {
                event.kind = EventType::LogChanged;
                event.log = Some(log.into());
            }
            core::EventKind::DataReceived {
                data,
                log,
                rx_bytes,
                last_rx_bytes,
            } => {
                event.kind = EventType::DataReceived;
                event.data = Some(data);
                event.log = Some(log.into());
                event.rx_bytes = Some(rx_bytes);
                event.last_rx_bytes = Some(last_rx_bytes);
            }
            core::EventKind::DataSent {
                request_id,
                data,
                log,
                tx_bytes,
            } => {
                event.kind = EventType::DataSent;
                event.request_id = Some(request_id);
                event.data = Some(data);
                event.log = Some(log.into());
                event.tx_bytes = Some(tx_bytes);
            }
            core::EventKind::WriteFailed { request_id, error } => {
                event.kind = EventType::WriteFailed;
                event.request_id = Some(request_id);
                event.error = Some(error.into());
            }
            core::EventKind::Disconnected(error) => {
                event.kind = EventType::Disconnected;
                event.error = Some(error.into());
            }
            core::EventKind::Reconnecting => event.kind = EventType::Reconnecting,
            core::EventKind::QueueOverflow(error) => {
                event.kind = EventType::QueueOverflow;
                event.error = Some(error.into());
            }
            core::EventKind::TaskFailed(error) => {
                event.kind = EventType::TaskFailed;
                event.error = Some(error.into());
            }
            core::EventKind::CommandCompleted { request_id } => {
                event.kind = EventType::CommandCompleted;
                event.request_id = Some(request_id);
            }
            core::EventKind::CommandFailed { request_id, error } => {
                event.kind = EventType::CommandFailed;
                event.request_id = Some(request_id);
                event.error = Some(error.into());
            }
        }
        event
    }
}

pub fn create_core(data_directory: String, legacy_config: Option<LegacyConfig>) -> CreateCoreReply {
    match core::AppCore::create(core::AppOptions {
        data_directory: PathBuf::from(data_directory),
        legacy_config: legacy_config.map(Into::into),
        ..core::AppOptions::default()
    }) {
        Ok(value) => CreateCoreReply {
            handle: Some(CoreHandle(value)),
            error: None,
        },
        Err(error) => CreateCoreReply {
            handle: None,
            error: Some(error.into()),
        },
    }
}
pub fn close_core(handle: &CoreHandle) -> CloseReply {
    CloseReply {
        error: handle.0.close().err().map(Into::into),
    }
}
pub fn snapshot(handle: &CoreHandle) -> SnapshotReply {
    match handle.0.snapshot() {
        Ok(value) => SnapshotReply {
            snapshot: Some(value.into()),
            error: None,
        },
        Err(error) => SnapshotReply {
            snapshot: None,
            error: Some(error.into()),
        },
    }
}
pub fn subscribe(handle: &CoreHandle) -> SubscribeReply {
    match handle.0.subscribe() {
        Ok((snapshot, subscription)) => SubscribeReply {
            snapshot: Some(snapshot.into()),
            subscription: Some(SubscriptionHandle(Mutex::new(subscription))),
            error: None,
        },
        Err(error) => SubscribeReply {
            snapshot: None,
            subscription: None,
            error: Some(error.into()),
        },
    }
}
pub fn next_events(subscription: &SubscriptionHandle) -> EventsReply {
    let result = (|| {
        let receiver = subscription.0.lock().map_err(|_| {
            core::CoreError::new(core::ErrorKind::Internal, "subscription lock poisoned")
        })?;
        let mut batch = Vec::new();
        for index in 0..32 {
            let timeout = if index == 0 {
                Duration::from_millis(250)
            } else {
                Duration::ZERO
            };
            match receiver.recv_timeout(timeout)? {
                Some(event) => batch.push(event.into()),
                None => break,
            }
        }
        Ok::<_, core::CoreError>(batch)
    })();
    match result {
        Ok(events) => EventsReply {
            events,
            error: None,
        },
        Err(error) => EventsReply {
            events: Vec::new(),
            error: Some(error.into()),
        },
    }
}
pub fn cancel_subscription(subscription: &SubscriptionHandle) {
    subscription
        .0
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .cancel();
}
fn dispatch(handle: &CoreHandle, command: core::Command) -> DispatchReply {
    match handle.0.dispatch(command) {
        Ok(id) => DispatchReply {
            request_id: Some(id),
            error: None,
        },
        Err(error) => DispatchReply {
            request_id: None,
            error: Some(error.into()),
        },
    }
}
pub fn list_ports(handle: &CoreHandle) -> DispatchReply {
    dispatch(handle, core::Command::ListPorts)
}
pub fn set_config(handle: &CoreHandle, config: AppConfig) -> DispatchReply {
    dispatch(handle, core::Command::SetConfig(config.into()))
}
pub fn update_config(handle: &CoreHandle, patch: ConfigPatch) -> DispatchReply {
    dispatch(handle, core::Command::UpdateConfig(patch.into()))
}
pub fn connect(handle: &CoreHandle) -> DispatchReply {
    dispatch(handle, core::Command::Connect)
}
pub fn disconnect(handle: &CoreHandle) -> DispatchReply {
    dispatch(handle, core::Command::Disconnect)
}
pub fn send_text(handle: &CoreHandle, text: String, newline: Newline) -> DispatchReply {
    dispatch(
        handle,
        core::Command::SendText {
            text,
            newline: newline.into(),
        },
    )
}
pub fn send_hex(handle: &CoreHandle, input: String) -> DispatchReply {
    dispatch(handle, core::Command::SendHex { input })
}
pub fn send_input(handle: &CoreHandle, input: String) -> DispatchReply {
    dispatch(handle, core::Command::SendInput { input })
}
pub fn clear_log(handle: &CoreHandle) -> DispatchReply {
    dispatch(handle, core::Command::ClearLog)
}
pub fn set_auto_reconnect(handle: &CoreHandle, enabled: bool) -> DispatchReply {
    dispatch(handle, core::Command::SetAutoReconnect(enabled))
}
pub fn set_auto_send(
    handle: &CoreHandle,
    enabled: bool,
    interval_ms: u32,
    input: String,
    hex: bool,
    newline: Newline,
) -> DispatchReply {
    dispatch(
        handle,
        core::Command::SetAutoSend {
            enabled,
            interval_ms,
            input,
            hex,
            newline: newline.into(),
        },
    )
}
pub fn export_log(handle: &CoreHandle, path: String, options: ExportOptions) -> DispatchReply {
    dispatch(
        handle,
        core::Command::ExportLog {
            path,
            options: core::ExportOptions {
                show_sent: options.show_sent,
                hex: options.hex,
                timestamps: options.timestamps,
                strip_ansi: options.strip_ansi,
            },
        },
    )
}
