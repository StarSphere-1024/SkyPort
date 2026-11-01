#[cfg(target_os = "linux")]
const DEVPTS_SUPER_MAGIC: libc::c_long = 0x1cd1;
use crate::{
    CoreError, ErrorCode, ErrorKind, FlowControl as ConfigFlowControl, Newline, Parity,
    SerialConfig,
};
use serialport::{DataBits, Parity as PortParity, StopBits};
use std::{
    io::{Read, Write},
    time::Duration,
};

pub trait TransportPort: Read + Write + Send {
    fn timeout(&self) -> Duration;
    fn set_timeout(&mut self, timeout: Duration) -> Result<(), CoreError>;
    /// Consume transport-specific failure details, including partial write progress.
    fn take_write_error(&mut self) -> Option<CoreError> {
        None
    }
}

impl<T: serialport::SerialPort> TransportPort for T {
    fn timeout(&self) -> Duration {
        serialport::SerialPort::timeout(self)
    }
    fn set_timeout(&mut self, timeout: Duration) -> Result<(), CoreError> {
        serialport::SerialPort::set_timeout(self, timeout)
            .map_err(|e| CoreError::new(ErrorKind::WriteFailed, e.to_string()))
    }
}

pub trait SerialBackend: Send + Sync {
    fn ports(&self) -> Result<Vec<String>, CoreError>;
    fn open(&self, config: &SerialConfig) -> Result<Box<dyn TransportPort>, CoreError>;
}

pub(crate) struct NativeBackend;

impl SerialBackend for NativeBackend {
    fn ports(&self) -> Result<Vec<String>, CoreError> {
        ports()
    }
    fn open(&self, config: &SerialConfig) -> Result<Box<dyn TransportPort>, CoreError> {
        native_open(config)
    }
}

// Bound command waiting while the single worker polls serial input.
pub(crate) const READ_POLL_TIMEOUT: Duration = Duration::from_millis(5);

pub(crate) fn ports() -> Result<Vec<String>, CoreError> {
    serialport::available_ports()
        .map(|ports| {
            ports
                .into_iter()
                .map(|p| p.port_name)
                .filter(|name| is_listed_port(name))
                .collect()
        })
        .map_err(|e| {
            CoreError::new(
                ErrorKind::TaskFailed,
                format!("enumerate serial ports: {e}"),
            )
        })
}

fn is_listed_port(name: &str) -> bool {
    !cfg!(target_os = "linux") || name.starts_with("/dev/ttyUSB") || name.starts_with("/dev/ttyACM")
}

fn native_open(config: &SerialConfig) -> Result<Box<dyn TransportPort>, CoreError> {
    config.validate(true)?;
    let data_bits = match config.data_bits {
        5 => DataBits::Five,
        6 => DataBits::Six,
        7 => DataBits::Seven,
        8 => DataBits::Eight,
        _ => {
            return Err(CoreError::new(
                ErrorKind::UnsupportedConfiguration,
                "unsupported data bits",
            )
            .with_code(ErrorCode::DataBitsInvalid))
        }
    };
    let parity = match config.parity {
        Parity::None => PortParity::None,
        Parity::Odd => PortParity::Odd,
        Parity::Even => PortParity::Even,
    };
    let stop_bits = match config.stop_bits {
        1 => StopBits::One,
        2 => StopBits::Two,
        _ => {
            return Err(CoreError::new(
                ErrorKind::UnsupportedConfiguration,
                "unsupported stop bits",
            )
            .with_code(ErrorCode::StopBitsInvalid))
        }
    };
    let flow_control = match config.flow_control {
        ConfigFlowControl::None => serialport::FlowControl::None,
        ConfigFlowControl::Hardware => serialport::FlowControl::Hardware,
        ConfigFlowControl::Software => serialport::FlowControl::Software,
    };
    let builder = serialport::new(&config.port_name, config.baud_rate)
        .data_bits(data_bits)
        .parity(parity)
        .stop_bits(stop_bits)
        .flow_control(flow_control)
        .timeout(READ_POLL_TIMEOUT);
    #[cfg(unix)]
    {
        let port = builder
            .open_native()
            .map_err(|error| port_error(error, "open", &config.port_name, ErrorKind::OpenFailed))?;
        // serialport polls before write(), but a blocking POSIX write can still
        // stall on a large buffer after readiness. Preserve partial progress.
        use std::os::fd::AsRawFd;
        let fd = port.as_raw_fd();
        let flags = unsafe { libc::fcntl(fd, libc::F_GETFL) };
        if flags < 0 || unsafe { libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) } < 0 {
            return Err(CoreError::new(
                ErrorKind::OpenFailed,
                format!(
                    "set nonblocking serial descriptor: {}",
                    std::io::Error::last_os_error()
                ),
            ));
        }
        // Keep closing/reopening from dropping modem lines behind our back.
        let mut termios = std::mem::MaybeUninit::<libc::termios>::uninit();
        if unsafe { libc::tcgetattr(fd, termios.as_mut_ptr()) } < 0 {
            return Err(CoreError::new(
                ErrorKind::OpenFailed,
                format!(
                    "read serial hangup settings: {}",
                    std::io::Error::last_os_error()
                ),
            ));
        }
        let mut termios = unsafe { termios.assume_init() };
        termios.c_cflag &= !libc::HUPCL;
        if config.flow_control == ConfigFlowControl::Software {
            termios.c_cc[libc::VSTART] = 0x11;
            termios.c_cc[libc::VSTOP] = 0x13;
        }
        if unsafe { libc::tcsetattr(fd, libc::TCSANOW, &termios) } < 0 {
            return Err(CoreError::new(
                ErrorKind::OpenFailed,
                format!("disable serial hangup: {}", std::io::Error::last_os_error()),
            ));
        }
        #[cfg(target_os = "linux")]
        let devpts = is_devpts(&port);
        #[cfg(not(target_os = "linux"))]
        let devpts = false;
        if !devpts {
            // Preserve driver-owned RTS when hardware flow control is enabled.
            let lines: libc::c_int = libc::TIOCM_DTR
                | if config.flow_control == ConfigFlowControl::Hardware {
                    0
                } else {
                    libc::TIOCM_RTS
                };
            if unsafe { libc::ioctl(fd, libc::TIOCMBIC, &lines) } < 0 {
                return Err(CoreError::new(
                    ErrorKind::OpenFailed,
                    format!("clear serial DTR/RTS: {}", std::io::Error::last_os_error()),
                ));
            }
        }
        Ok(Box::new(port))
    }
    #[cfg(windows)]
    {
        let mut port = builder
            .open_native()
            .map_err(|error| port_error(error, "open", &config.port_name, ErrorKind::OpenFailed))?;
        disable_modem_lines(
            &mut port,
            &config.port_name,
            config.flow_control == ConfigFlowControl::Hardware,
        )?;
        Ok(Box::new(port))
    }
}
fn port_error(
    error: serialport::Error,
    operation: &str,
    name: &str,
    fallback: ErrorKind,
) -> CoreError {
    let kind = match error.kind {
        // NoDevice also represents Unix EBUSY and Windows ERROR_ACCESS_DENIED.
        serialport::ErrorKind::NoDevice if operation == "open" => fallback,
        serialport::ErrorKind::Io(std::io::ErrorKind::NotFound) if operation == "open" => {
            ErrorKind::PortNotFound
        }
        serialport::ErrorKind::NoDevice => ErrorKind::Disconnected,
        serialport::ErrorKind::Io(std::io::ErrorKind::PermissionDenied) => {
            ErrorKind::PermissionDenied
        }
        serialport::ErrorKind::InvalidInput => ErrorKind::UnsupportedConfiguration,
        _ => fallback,
    };
    CoreError::new(
        kind,
        format!("{operation} serial port {name}: {}", error.description),
    )
}

pub(crate) fn set_read_timeout(
    port: &mut dyn TransportPort,
    timeout: Duration,
) -> Result<(), CoreError> {
    port.set_timeout(timeout).map_err(|error| {
        CoreError::new(ErrorKind::ReadFailed, format!("set read timeout: {error}"))
    })
}

#[cfg(windows)]
fn disable_modem_lines(
    port: &mut dyn serialport::SerialPort,
    name: &str,
    hardware_flow_control: bool,
) -> Result<(), CoreError> {
    port.write_data_terminal_ready(false)
        .map_err(|error| port_error(error, "clear DTR on", name, ErrorKind::OpenFailed))?;
    if !hardware_flow_control {
        port.write_request_to_send(false)
            .map_err(|error| port_error(error, "clear RTS on", name, ErrorKind::OpenFailed))?;
    }
    Ok(())
}

#[cfg(target_os = "linux")]
fn is_devpts(port: &serialport::TTYPort) -> bool {
    use std::os::fd::AsRawFd;
    let mut info = std::mem::MaybeUninit::<libc::statfs>::zeroed();
    if unsafe { libc::fstatfs(port.as_raw_fd(), info.as_mut_ptr()) } != 0 {
        return false;
    }
    unsafe { info.assume_init().f_type as u64 == DEVPTS_SUPER_MAGIC as u64 }
}

pub(crate) fn encode_text(text: &str, newline: Newline) -> Vec<u8> {
    let mut bytes = text.as_bytes().to_vec();
    match newline {
        Newline::None => {}
        Newline::Lf => bytes.push(b'\n'),
        Newline::Cr => bytes.push(b'\r'),
        Newline::CrLf => bytes.extend_from_slice(b"\r\n"),
    }
    bytes
}

pub(crate) fn validate_hex(input: &str) -> Result<(), CoreError> {
    let mut digits = input.bytes().filter(|b| !b.is_ascii_whitespace());
    while let Some(hi) = digits.next() {
        if hex_digit(hi).is_none() {
            return Err(CoreError::new(
                ErrorKind::InvalidArgument,
                "hex input contains a non-hexadecimal character",
            )
            .with_code(ErrorCode::InvalidHexCharacter));
        }
        let lo = digits.next().ok_or_else(|| {
            CoreError::new(
                ErrorKind::InvalidArgument,
                "hex input must contain complete byte pairs",
            )
            .with_code(ErrorCode::IncompleteHexByte)
        })?;
        if hex_digit(lo).is_none() {
            return Err(CoreError::new(
                ErrorKind::InvalidArgument,
                "hex input contains a non-hexadecimal character",
            )
            .with_code(ErrorCode::InvalidHexCharacter));
        }
    }
    Ok(())
}
pub(crate) fn decode_hex(input: &str) -> Result<Vec<u8>, CoreError> {
    let mut digits = input.bytes().filter(|b| !b.is_ascii_whitespace());
    let mut bytes = Vec::with_capacity(input.len() / 2);
    while let Some(hi) = digits.next() {
        let hi = hex_digit(hi).ok_or_else(|| {
            CoreError::new(
                ErrorKind::InvalidArgument,
                "hex input contains a non-hexadecimal character",
            )
            .with_code(ErrorCode::InvalidHexCharacter)
        })?;
        let lo = digits.next().ok_or_else(|| {
            CoreError::new(
                ErrorKind::InvalidArgument,
                "hex input must contain complete byte pairs",
            )
            .with_code(ErrorCode::IncompleteHexByte)
        })?;
        let lo = hex_digit(lo).ok_or_else(|| {
            CoreError::new(
                ErrorKind::InvalidArgument,
                "hex input contains a non-hexadecimal character",
            )
            .with_code(ErrorCode::InvalidHexCharacter)
        })?;
        bytes.push((hi << 4) | lo);
    }
    Ok(bytes)
}
fn hex_digit(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

pub(crate) fn write_all_accounted(
    port: &mut dyn TransportPort,
    bytes: &[u8],
) -> Result<(), CoreError> {
    let deadline = std::time::Instant::now() + Duration::from_millis(1000);
    let read_timeout = port.timeout();
    let mut written = 0usize;
    let result = (|| {
        while written < bytes.len() {
            let remaining = deadline.saturating_duration_since(std::time::Instant::now());
            if remaining.is_zero() {
                return Err(
                    CoreError::new(ErrorKind::Timeout, "serial write exceeded 1000 ms")
                        .with_written(written as u64),
                );
            }
            port.set_timeout(remaining).map_err(|error| {
                CoreError::new(
                    ErrorKind::WriteFailed,
                    format!("set serial write timeout: {error}"),
                )
                .with_written(written as u64)
            })?;
            let result = port.write(&bytes[written..]);
            if result.is_err() {
                if let Some(mut error) = port.take_write_error() {
                    error.bytes_written += written as u64;
                    return Err(error);
                }
            }
            match result {
                Ok(0) => {
                    return Err(CoreError::new(
                        ErrorKind::WriteFailed,
                        "serial write returned zero bytes",
                    )
                    .with_written(written as u64))
                }
                Ok(count) => written += count,
                Err(error)
                    if matches!(
                        error.kind(),
                        std::io::ErrorKind::Interrupted | std::io::ErrorKind::WouldBlock
                    ) =>
                {
                    continue
                }
                Err(error) if error.kind() == std::io::ErrorKind::TimedOut => {
                    return Err(CoreError::new(ErrorKind::Timeout, error.to_string())
                        .with_written(written as u64))
                }
                Err(error)
                    if matches!(
                        error.kind(),
                        std::io::ErrorKind::BrokenPipe
                            | std::io::ErrorKind::NotConnected
                            | std::io::ErrorKind::UnexpectedEof
                            | std::io::ErrorKind::ConnectionReset
                            | std::io::ErrorKind::ConnectionAborted
                    ) =>
                {
                    return Err(CoreError::new(ErrorKind::Disconnected, error.to_string())
                        .with_written(written as u64))
                }
                Err(error) => {
                    return Err(CoreError::new(ErrorKind::WriteFailed, error.to_string())
                        .with_written(written as u64))
                }
            }
        }
        Ok(())
    })();
    let restore = port.set_timeout(read_timeout).map_err(|error| {
        CoreError::new(
            ErrorKind::WriteFailed,
            format!("restore serial read timeout: {error}"),
        )
        .with_written(written as u64)
    });
    match result {
        Err(error) => Err(error),
        Ok(()) => restore,
    }
}

#[cfg(test)]
mod tests {
    use std::{
        io::{Read, Write},
        time::Duration,
    };
    #[test]
    fn ambiguous_open_errors_do_not_claim_the_port_is_missing() {
        for (source, operation, expected) in [
            (
                serialport::ErrorKind::NoDevice,
                "open",
                crate::ErrorKind::OpenFailed,
            ),
            (
                serialport::ErrorKind::Io(std::io::ErrorKind::NotFound),
                "open",
                crate::ErrorKind::PortNotFound,
            ),
            (
                serialport::ErrorKind::Io(std::io::ErrorKind::PermissionDenied),
                "open",
                crate::ErrorKind::PermissionDenied,
            ),
            (
                serialport::ErrorKind::NoDevice,
                "set read timeout on",
                crate::ErrorKind::Disconnected,
            ),
        ] {
            let error = super::port_error(
                serialport::Error::new(source, "native serial failure"),
                operation,
                "port",
                crate::ErrorKind::OpenFailed,
            );
            assert_eq!(error.kind, expected);
        }
    }

    struct PartialPort {
        timeout: Duration,
        calls: usize,
    }
    impl Read for PartialPort {
        fn read(&mut self, _: &mut [u8]) -> std::io::Result<usize> {
            Ok(0)
        }
    }
    impl Write for PartialPort {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            self.calls += 1;
            if self.calls == 1 {
                Ok(bytes.len().min(2))
            } else {
                Err(std::io::ErrorKind::BrokenPipe.into())
            }
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    impl super::TransportPort for PartialPort {
        fn timeout(&self) -> Duration {
            self.timeout
        }
        fn set_timeout(&mut self, timeout: Duration) -> Result<(), crate::CoreError> {
            self.timeout = timeout;
            Ok(())
        }
    }

    #[test]
    fn partial_transport_failure_preserves_written_byte_count() {
        let mut port = PartialPort {
            timeout: Duration::from_millis(5),
            calls: 0,
        };
        let error = super::write_all_accounted(&mut port, b"hello").unwrap_err();
        assert_eq!(error.kind, crate::ErrorKind::Disconnected);
        assert_eq!(error.bytes_written, 2);
        assert_eq!(port.timeout, Duration::from_millis(5));
    }
    #[test]
    fn port_listing_is_usb_only_on_linux() {
        for (name, linux_visible) in [
            ("/dev/ttyUSB0", true),
            ("/dev/ttyUSB12", true),
            ("/dev/ttyACM0", true),
            ("/dev/ttyACM12", true),
            ("/dev/ttyS0", false),
            ("/dev/ttyAMA0", false),
            ("/dev/rfcomm0", false),
            ("/dev/pts/1", false),
            ("COM3", false),
            ("/dev/cu.usbserial-1", false),
        ] {
            assert_eq!(
                super::is_listed_port(name),
                !cfg!(target_os = "linux") || linux_visible,
                "{name}"
            );
        }
    }
}
