use crate::{CoreError, ErrorCode, ErrorKind};
use serde::{Deserialize, Deserializer, Serialize};
use std::{
    fs::{self, OpenOptions},
    io::{Read, Write},
    path::Path,
    sync::atomic::{AtomicU64, Ordering},
};

const CURRENT_VERSION: u32 = 1;
const MAX_HISTORY: usize = 100;
const MAX_HISTORY_BYTES: usize = 1024 * 1024;
const MAX_CONFIG_BYTES: usize = 8 * 1024 * 1024;
const MAX_PORT_NAME_BYTES: usize = 4096;
const MIN_AUTO_SEND_INTERVAL_MS: u32 = 10;
const MAX_AUTO_SEND_INTERVAL_MS: u32 = 60_000;
const MIN_LOG_CAPACITY_BYTES: u64 = 16 * 1024 * 1024;
const MAX_LOG_CAPACITY_BYTES: u64 = 512 * 1024 * 1024;
static TEMP_ID: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum Parity {
    None,
    Odd,
    Even,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum Newline {
    None,
    Lf,
    Cr,
    CrLf,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub enum FlowControl {
    #[default]
    None,
    Hardware,
    Software,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SerialConfig {
    pub port_name: String,
    pub baud_rate: u32,
    pub data_bits: u8,
    pub parity: Parity,
    pub stop_bits: u8,
    pub auto_reconnect: bool,
    pub flow_control: FlowControl,
}

impl<'de> Deserialize<'de> for SerialConfig {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct StoredSerialConfig {
            port_name: String,
            baud_rate: u32,
            data_bits: u8,
            parity: Parity,
            stop_bits: u8,
            auto_reconnect: bool,
            #[serde(default, deserialize_with = "deserialize_non_null")]
            flow_control: Option<FlowControl>,
            #[serde(default, deserialize_with = "deserialize_non_null")]
            hardware_flow_control: Option<bool>,
        }

        let stored = StoredSerialConfig::deserialize(deserializer)?;
        Ok(Self {
            port_name: stored.port_name,
            baud_rate: stored.baud_rate,
            data_bits: stored.data_bits,
            parity: stored.parity,
            stop_bits: stored.stop_bits,
            auto_reconnect: stored.auto_reconnect,
            flow_control: stored.flow_control.unwrap_or_else(|| {
                if stored.hardware_flow_control.unwrap_or(false) {
                    FlowControl::Hardware
                } else {
                    FlowControl::None
                }
            }),
        })
    }
}
fn deserialize_non_null<'de, D, T>(deserializer: D) -> Result<Option<T>, D::Error>
where
    D: Deserializer<'de>,
    T: Deserialize<'de>,
{
    T::deserialize(deserializer).map(Some)
}

impl Default for SerialConfig {
    fn default() -> Self {
        Self {
            port_name: String::new(),
            baud_rate: 9600,
            data_bits: 8,
            parity: Parity::None,
            stop_bits: 1,
            auto_reconnect: true,
            flow_control: FlowControl::None,
        }
    }
}

impl SerialConfig {
    pub fn validate(&self, require_port: bool) -> Result<(), CoreError> {
        if require_port && self.port_name.trim().is_empty() {
            return Err(
                invalid("port name must not be empty").with_code(ErrorCode::PortNameRequired)
            );
        }
        if self.port_name.len() > MAX_PORT_NAME_BYTES {
            return Err(
                invalid("port name exceeds 4096 bytes").with_code(ErrorCode::PortNameTooLong)
            );
        }
        if self
            .port_name
            .chars()
            .any(|character| matches!(character, '\0' | '\n' | '\r'))
        {
            return Err(invalid("port name must not contain NUL or line breaks")
                .with_code(ErrorCode::PortNameInvalid));
        }
        if self.baud_rate == 0 {
            return Err(invalid("baud rate must be greater than zero")
                .with_code(ErrorCode::BaudRateInvalid));
        }
        if !(5..=8).contains(&self.data_bits) {
            return Err(
                invalid("data bits must be between 5 and 8").with_code(ErrorCode::DataBitsInvalid)
            );
        }
        if !matches!(self.stop_bits, 1 | 2) {
            return Err(invalid("stop bits must be 1 or 2").with_code(ErrorCode::StopBitsInvalid));
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SendSettings {
    pub hex: bool,
    pub newline: Newline,
    pub append_newline: bool,
    pub auto_send_enabled: bool,
    pub auto_send_interval_ms: u32,
}
impl Default for SendSettings {
    fn default() -> Self {
        Self {
            hex: false,
            newline: Newline::Lf,
            append_newline: false,
            auto_send_enabled: false,
            auto_send_interval_ms: 1000,
        }
    }
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
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

impl LegacyConfig {
    pub fn into_app_config(self) -> Result<AppConfig, CoreError> {
        let parity = match self.parity.unwrap_or(0) {
            0 => Parity::None,
            1 => Parity::Odd,
            2 => Parity::Even,
            value => {
                return Err(invalid(format!("invalid legacy parity {value}"))
                    .with_code(ErrorCode::LegacyConfigInvalid))
            }
        };
        let newline_mode = match self.newline_mode.unwrap_or(0) {
            0 => Newline::Lf,
            1 => Newline::Cr,
            2 => Newline::CrLf,
            value => {
                return Err(invalid(format!("invalid legacy newline mode {value}"))
                    .with_code(ErrorCode::LegacyConfigInvalid))
            }
        };
        let log_capacity_bytes = u64::try_from(self.log_buffer_megabytes.unwrap_or(128))
            .ok()
            .and_then(|value| value.checked_mul(1024 * 1024))
            .ok_or_else(|| {
                invalid("invalid legacy log buffer size").with_code(ErrorCode::LegacyConfigInvalid)
            })?;
        let config = AppConfig {
            version: CURRENT_VERSION,
            serial: SerialConfig {
                port_name: self.port_name.unwrap_or_default(),
                baud_rate: u32::try_from(self.baud_rate.unwrap_or(9600)).map_err(|_| {
                    invalid("invalid legacy baud rate").with_code(ErrorCode::LegacyConfigInvalid)
                })?,
                data_bits: u8::try_from(self.data_bits.unwrap_or(8)).map_err(|_| {
                    invalid("invalid legacy data bits").with_code(ErrorCode::LegacyConfigInvalid)
                })?,
                parity,
                stop_bits: u8::try_from(self.stop_bits.unwrap_or(1)).map_err(|_| {
                    invalid("invalid legacy stop bits").with_code(ErrorCode::LegacyConfigInvalid)
                })?,
                auto_reconnect: self.auto_reconnect.unwrap_or(true),
                flow_control: FlowControl::None,
            },
            send: SendSettings {
                hex: self.hex_send.unwrap_or(false),
                newline: newline_mode,
                append_newline: self.append_newline.unwrap_or(false),
                auto_send_enabled: self.auto_send_enabled.unwrap_or(false),
                auto_send_interval_ms: u32::try_from(self.auto_send_interval_ms.unwrap_or(1000))
                    .map_err(|_| {
                        invalid("invalid legacy auto-send interval")
                            .with_code(ErrorCode::LegacyConfigInvalid)
                    })?,
            },
            log_capacity_bytes,
            history: self.history.unwrap_or_default(),
        };
        config.validate()?;
        Ok(config)
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AppConfig {
    pub version: u32,
    pub serial: SerialConfig,
    pub send: SendSettings,
    pub log_capacity_bytes: u64,
    pub history: Vec<String>,
}
impl Default for AppConfig {
    fn default() -> Self {
        Self {
            version: CURRENT_VERSION,
            serial: SerialConfig::default(),
            send: SendSettings::default(),
            log_capacity_bytes: 128 * 1024 * 1024,
            history: Vec::new(),
        }
    }
}
impl AppConfig {
    pub fn validate(&self) -> Result<(), CoreError> {
        if self.version != CURRENT_VERSION {
            return Err(
                invalid(format!("unsupported config version {}", self.version))
                    .with_code(ErrorCode::ConfigVersionUnsupported),
            );
        }
        self.serial.validate(false)?;
        if self.send.newline == Newline::None {
            return Err(invalid(
                "stored newline mode must be LF, CR, or CRLF; use append_newline to disable it",
            )
            .with_code(ErrorCode::NewlineInvalid));
        }
        if !(MIN_AUTO_SEND_INTERVAL_MS..=MAX_AUTO_SEND_INTERVAL_MS)
            .contains(&self.send.auto_send_interval_ms)
        {
            return Err(
                invalid("auto-send interval must be between 10 and 60000 ms")
                    .with_code(ErrorCode::AutoSendIntervalInvalid),
            );
        }
        if !(MIN_LOG_CAPACITY_BYTES..=MAX_LOG_CAPACITY_BYTES).contains(&self.log_capacity_bytes) {
            return Err(invalid("log capacity must be between 16 and 512 MiB")
                .with_code(ErrorCode::LogCapacityInvalid));
        }
        if self.history.len() > MAX_HISTORY {
            return Err(
                invalid("send history exceeds 100 entries").with_code(ErrorCode::HistoryTooLong)
            );
        }
        if self.history.iter().any(|entry| entry.is_empty()) {
            return Err(invalid("send history entries must not be empty")
                .with_code(ErrorCode::HistoryEntryEmpty));
        }
        if self
            .history
            .iter()
            .fold(0usize, |bytes, entry| bytes.saturating_add(entry.len()))
            > MAX_HISTORY_BYTES
        {
            return Err(invalid("send history exceeds 1 MiB").with_code(ErrorCode::HistoryTooLarge));
        }
        Ok(())
    }

    pub fn load(directory: &Path, legacy: Option<LegacyConfig>) -> Result<AppConfig, CoreError> {
        let path = directory.join("config.json");
        match OpenOptions::new().read(true).open(&path) {
            Ok(file) => {
                let mut bytes = Vec::new();
                file.take((MAX_CONFIG_BYTES + 1) as u64)
                    .read_to_end(&mut bytes)
                    .map_err(|e| config_io("read config", e))?;
                if bytes.len() > MAX_CONFIG_BYTES {
                    return Err(invalid("persisted config exceeds 8 MiB")
                        .with_code(ErrorCode::ConfigTooLarge));
                }
                let config: Self = serde_json::from_slice(&bytes).map_err(|e| {
                    invalid(format!("invalid persisted config: {e}"))
                        .with_code(ErrorCode::ConfigInvalid)
                })?;
                config.validate()?;
                Ok(config)
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                let config = legacy.unwrap_or_default().into_app_config()?;
                config.save(directory)?;
                Ok(config)
            }
            Err(e) => Err(config_io("read config", e)),
        }
    }

    pub fn save(&self, directory: &Path) -> Result<(), CoreError> {
        self.validate()?;
        let bytes = serde_json::to_vec_pretty(self).map_err(|e| {
            invalid(format!("serialize config: {e}")).with_code(ErrorCode::ConfigInvalid)
        })?;
        fs::create_dir_all(directory).map_err(|e| config_io("create config directory", e))?;
        let path = directory.join("config.json");
        let (temporary, mut file) = loop {
            let id = TEMP_ID.fetch_add(1, Ordering::Relaxed);
            let candidate =
                directory.join(format!(".config.json.{}.{}.tmp", std::process::id(), id));
            match OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&candidate)
            {
                Ok(file) => break (candidate, file),
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(config_io("create temporary config", e)),
            }
        };
        let result = (|| {
            file.write_all(&bytes)
                .map_err(|e| config_io("write config", e))?;
            file.sync_all().map_err(|e| config_io("sync config", e))?;
            drop(file);
            replace_file(&temporary, &path).map_err(|e| config_io("replace config", e))?;
            if let Ok(dir) = OpenOptions::new().read(true).open(directory) {
                let _ = dir.sync_all();
            }
            Ok(())
        })();
        if result.is_err() {
            let _ = fs::remove_file(temporary);
        }
        result
    }
}

fn invalid(message: impl Into<String>) -> CoreError {
    CoreError::new(ErrorKind::InvalidArgument, message)
}
fn config_io(operation: &str, error: std::io::Error) -> CoreError {
    CoreError::new(ErrorKind::Internal, format!("{operation}: {error}"))
        .with_code(ErrorCode::ConfigIo)
}
#[cfg(not(windows))]
pub(crate) fn replace_file(temporary: &Path, destination: &Path) -> std::io::Result<()> {
    fs::rename(temporary, destination)
}

#[cfg(windows)]
pub(crate) fn replace_file(temporary: &Path, destination: &Path) -> std::io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    const MOVEFILE_REPLACE_EXISTING: u32 = 0x1;
    const MOVEFILE_WRITE_THROUGH: u32 = 0x8;
    #[link(name = "kernel32")]
    extern "system" {
        fn MoveFileExW(existing: *const u16, new: *const u16, flags: u32) -> i32;
    }
    let existing: Vec<u16> = temporary.as_os_str().encode_wide().chain(Some(0)).collect();
    let new: Vec<u16> = destination
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect();
    let success = unsafe {
        MoveFileExW(
            existing.as_ptr(),
            new.as_ptr(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        )
    };
    if success == 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn old_config_flow_control_migrates_and_canonical_mode_wins() {
        let directory = tempfile::tempdir().unwrap();
        let mut old_config = serde_json::to_value(AppConfig::default()).unwrap();
        old_config["serial"]["hardware_flow_control"] = true.into();
        old_config["serial"]
            .as_object_mut()
            .unwrap()
            .remove("flow_control");
        fs::write(
            directory.path().join("config.json"),
            serde_json::to_vec(&old_config).unwrap(),
        )
        .unwrap();

        let hardware = AppConfig::load(directory.path(), None).unwrap();
        assert_eq!(hardware.serial.flow_control, FlowControl::Hardware);
        hardware.save(directory.path()).unwrap();
        let saved: serde_json::Value =
            serde_json::from_slice(&fs::read(directory.path().join("config.json")).unwrap())
                .unwrap();
        assert_eq!(saved["serial"]["flow_control"], "Hardware");
        assert!(saved["serial"].get("hardware_flow_control").is_none());

        old_config["serial"]["hardware_flow_control"] = false.into();
        fs::write(
            directory.path().join("config.json"),
            serde_json::to_vec(&old_config).unwrap(),
        )
        .unwrap();
        assert_eq!(
            AppConfig::load(directory.path(), None)
                .unwrap()
                .serial
                .flow_control,
            FlowControl::None
        );
        old_config["serial"]
            .as_object_mut()
            .unwrap()
            .remove("hardware_flow_control");
        fs::write(
            directory.path().join("config.json"),
            serde_json::to_vec(&old_config).unwrap(),
        )
        .unwrap();
        assert_eq!(
            AppConfig::load(directory.path(), None)
                .unwrap()
                .serial
                .flow_control,
            FlowControl::None
        );

        old_config["serial"]["hardware_flow_control"] = true.into();
        old_config["serial"]["flow_control"] = "Software".into();
        fs::write(
            directory.path().join("config.json"),
            serde_json::to_vec(&old_config).unwrap(),
        )
        .unwrap();
        assert_eq!(
            AppConfig::load(directory.path(), None)
                .unwrap()
                .serial
                .flow_control,
            FlowControl::Software
        );

        old_config["serial"]["flow_control"] = "Invalid".into();
        fs::write(
            directory.path().join("config.json"),
            serde_json::to_vec(&old_config).unwrap(),
        )
        .unwrap();
        assert_eq!(
            AppConfig::load(directory.path(), None).unwrap_err().code,
            Some(ErrorCode::ConfigInvalid)
        );
        old_config["serial"]["flow_control"] = serde_json::Value::Null;
        fs::write(
            directory.path().join("config.json"),
            serde_json::to_vec(&old_config).unwrap(),
        )
        .unwrap();
        assert_eq!(
            AppConfig::load(directory.path(), None).unwrap_err().code,
            Some(ErrorCode::ConfigInvalid)
        );
    }
}
