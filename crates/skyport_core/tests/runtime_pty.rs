#![cfg(target_os = "linux")]

use skyport_core::{
    AppCore, AppOptions, Command, ConfigPatch, ConnectionState, ErrorCode, ErrorKind, EventKind,
    FlowControl, LegacyConfig, Newline,
};
use std::{
    ffi::CStr,
    fs,
    os::fd::{AsRawFd, RawFd},
    path::PathBuf,
    thread,
    time::{Duration, Instant},
};

struct Pty {
    master: Option<RawFd>,
    slave: PathBuf,
    observed: Vec<u8>,
}
impl Pty {
    fn new() -> Self {
        unsafe {
            let mut master = -1;
            let mut slave = -1;
            assert_eq!(
                libc::openpty(
                    &mut master,
                    &mut slave,
                    std::ptr::null_mut(),
                    std::ptr::null(),
                    std::ptr::null()
                ),
                0
            );
            let mut name = [0 as libc::c_char; 256];
            assert_eq!(libc::ttyname_r(slave, name.as_mut_ptr(), name.len()), 0);
            let path = CStr::from_ptr(name.as_ptr()).to_string_lossy().into_owned();
            libc::close(slave);
            let flags = libc::fcntl(master, libc::F_GETFL);
            libc::fcntl(master, libc::F_SETFL, flags | libc::O_NONBLOCK);
            Self {
                master: Some(master),
                slave: PathBuf::from(path),
                observed: Vec::new(),
            }
        }
    }
    fn fd(&self) -> RawFd {
        self.master.expect("PTY is open")
    }
    fn close(&mut self) {
        if let Some(fd) = self.master.take() {
            unsafe {
                libc::close(fd);
            }
        }
    }
    fn has_bytes(&mut self, expected: &[u8]) -> bool {
        let mut out = [0u8; 4096];
        let n = unsafe { libc::read(self.fd(), out.as_mut_ptr().cast(), out.len()) };
        if n > 0 {
            self.observed.extend_from_slice(&out[..n as usize]);
        }
        self.observed == expected
    }
    fn contains_bytes(&mut self, expected: &[u8]) -> bool {
        let mut out = [0u8; 4096];
        let n = unsafe { libc::read(self.fd(), out.as_mut_ptr().cast(), out.len()) };
        if n > 0 {
            self.observed.extend_from_slice(&out[..n as usize]);
        }
        self.observed
            .windows(expected.len())
            .any(|window| window == expected)
    }
    fn write(&self, data: &[u8]) {
        unsafe {
            libc::write(self.fd(), data.as_ptr().cast(), data.len());
        }
    }
}
impl Drop for Pty {
    fn drop(&mut self) {
        self.close();
    }
}
fn wait_for(mut condition: impl FnMut() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(4);
    while Instant::now() < deadline {
        if condition() {
            return;
        }
        thread::sleep(Duration::from_millis(10));
    }
    panic!("condition timed out");
}
fn options(dir: PathBuf, port: String) -> AppOptions {
    AppOptions {
        data_directory: dir,
        legacy_config: Some(LegacyConfig {
            port_name: Some(port),
            ..LegacyConfig::default()
        }),
        command_capacity: 16,
        event_capacity: 64,
    }
}

#[test]
fn clearing_a_configured_target_disconnects_and_cancels_reconnection() {
    let dir = tempfile::tempdir().unwrap();
    let mut pty = Pty::new();
    let core = AppCore::create(options(
        dir.path().into(),
        pty.slave.to_string_lossy().into_owned(),
    ))
    .unwrap();
    let (_, events) = core.subscribe().unwrap();
    let complete = |command| {
        let id = core.dispatch(command).unwrap();
        let deadline = Instant::now() + Duration::from_secs(3);
        loop {
            assert!(Instant::now() < deadline, "command did not finish");
            if let Some(event) = events.recv_timeout(Duration::from_millis(50)).unwrap() {
                match event.kind {
                    EventKind::CommandCompleted { request_id } if request_id == id => break,
                    EventKind::CommandFailed { request_id, error } if request_id == id => {
                        panic!("valid target update failed: {error:?}")
                    }
                    _ => {}
                }
            }
        }
    };
    complete(Command::Connect);
    complete(Command::UpdateConfig(ConfigPatch {
        port_name: Some(String::new()),
        ..ConfigPatch::default()
    }));
    assert_eq!(
        core.snapshot().unwrap().connection,
        ConnectionState::Disconnected
    );
    complete(Command::UpdateConfig(ConfigPatch {
        port_name: Some(pty.slave.to_string_lossy().into_owned()),
        ..ConfigPatch::default()
    }));
    complete(Command::Connect);
    pty.close();
    wait_for(|| core.snapshot().unwrap().connection == ConnectionState::Reconnecting);
    complete(Command::UpdateConfig(ConfigPatch {
        port_name: Some(String::new()),
        ..ConfigPatch::default()
    }));
    thread::sleep(Duration::from_millis(1100));
    let snapshot = core.snapshot().unwrap();
    assert!(snapshot.config.serial.port_name.is_empty());
    assert_eq!(snapshot.connection, ConnectionState::Disconnected);
    core.close().unwrap();
}
#[test]
fn queued_config_patches_merge_against_latest_state() {
    let dir = tempfile::tempdir().unwrap();
    let core = AppCore::create(AppOptions {
        data_directory: dir.path().into(),
        ..AppOptions::default()
    })
    .unwrap();
    core.dispatch(Command::UpdateConfig(ConfigPatch {
        baud_rate: Some(115200),
        ..ConfigPatch::default()
    }))
    .unwrap();
    core.dispatch(Command::UpdateConfig(ConfigPatch {
        data_bits: Some(7),
        ..ConfigPatch::default()
    }))
    .unwrap();
    core.dispatch(Command::UpdateConfig(ConfigPatch {
        auto_send_enabled: Some(false),
        ..ConfigPatch::default()
    }))
    .unwrap();
    core.dispatch(Command::UpdateConfig(ConfigPatch {
        auto_send_input: Some("new draft".into()),
        ..ConfigPatch::default()
    }))
    .unwrap();
    wait_for(|| {
        core.snapshot().is_ok_and(|snapshot| {
            snapshot.config.serial.baud_rate == 115200
                && snapshot.config.serial.data_bits == 7
                && !snapshot.config.send.auto_send_enabled
                && snapshot.auto_send_input == "new draft"
        })
    });
    core.close().unwrap();
}

#[test]
fn pty_connect_disconnect_and_reconfigure_keep_hangup_disabled() {
    let dir = tempfile::tempdir().unwrap();
    let mut pty = Pty::new();
    let observer = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(&pty.slave)
        .unwrap();
    let mut settings = std::mem::MaybeUninit::<libc::termios>::uninit();
    assert_eq!(
        unsafe { libc::tcgetattr(observer.as_raw_fd(), settings.as_mut_ptr()) },
        0
    );
    let mut settings = unsafe { settings.assume_init() };
    settings.c_cflag |= libc::HUPCL;
    assert_eq!(
        unsafe { libc::tcsetattr(observer.as_raw_fd(), libc::TCSANOW, &settings) },
        0
    );
    let core = AppCore::create(options(
        dir.path().into(),
        pty.slave.to_string_lossy().into_owned(),
    ))
    .unwrap();
    for _ in 0..3 {
        core.dispatch(Command::Connect).unwrap();
        wait_for(|| core.snapshot().unwrap().connection == ConnectionState::Connected);
        let mut config = core.snapshot().unwrap().config;
        config.serial.baud_rate += 1200;
        config.serial.flow_control = FlowControl::Hardware;
        let baud_rate = config.serial.baud_rate;
        core.dispatch(Command::SetConfig(config)).unwrap();
        wait_for(|| {
            core.snapshot()
                .unwrap()
                .applied_config
                .is_some_and(|config| {
                    config.baud_rate == baud_rate && config.flow_control == FlowControl::Hardware
                })
        });
        #[cfg(target_os = "linux")]
        {
            assert_eq!(
                unsafe { libc::tcgetattr(observer.as_raw_fd(), &mut settings) },
                0
            );
            assert_ne!(settings.c_cflag & libc::CRTSCTS, 0);
        }
        core.dispatch(Command::SendHex {
            input: "00 FF".into(),
        })
        .unwrap();
        wait_for(|| pty.has_bytes(&[0, 0xff]));
        pty.observed.clear();
        core.dispatch(Command::Disconnect).unwrap();
        wait_for(|| core.snapshot().unwrap().connection == ConnectionState::Disconnected);
        assert_eq!(
            unsafe { libc::tcgetattr(observer.as_raw_fd(), &mut settings) },
            0
        );
        assert_eq!(settings.c_cflag & libc::HUPCL, 0);
    }
    core.close().unwrap();
}
#[test]
fn pty_software_flow_control_pauses_and_resumes_output() {
    let dir = tempfile::tempdir().unwrap();
    let mut pty = Pty::new();
    let observer = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(&pty.slave)
        .unwrap();
    let core = AppCore::create(options(
        dir.path().into(),
        pty.slave.to_string_lossy().into_owned(),
    ))
    .unwrap();
    core.dispatch(Command::Connect).unwrap();
    wait_for(|| core.snapshot().unwrap().connection == ConnectionState::Connected);
    core.dispatch(Command::UpdateConfig(ConfigPatch {
        flow_control: Some(FlowControl::Software),
        ..ConfigPatch::default()
    }))
    .unwrap();
    wait_for(|| {
        core.snapshot()
            .unwrap()
            .applied_config
            .is_some_and(|config| config.flow_control == FlowControl::Software)
    });

    let mut settings = std::mem::MaybeUninit::<libc::termios>::uninit();
    assert_eq!(
        unsafe { libc::tcgetattr(observer.as_raw_fd(), settings.as_mut_ptr()) },
        0
    );
    let settings = unsafe { settings.assume_init() };
    assert_eq!(
        settings.c_iflag & (libc::IXON | libc::IXOFF),
        libc::IXON | libc::IXOFF
    );
    assert_eq!(settings.c_cc[libc::VSTART] as u8, 0x11);
    assert_eq!(settings.c_cc[libc::VSTOP] as u8, 0x13);

    pty.write(&[0x13]);
    core.dispatch(Command::SendText {
        text: "paused".into(),
        newline: Newline::None,
    })
    .unwrap();
    thread::sleep(Duration::from_millis(100));
    assert!(!pty.contains_bytes(b"paused"));
    assert!(pty.observed.is_empty());

    pty.write(&[0x11]);
    wait_for(|| pty.contains_bytes(b"paused"));
    core.close().unwrap();
}

#[test]
fn pty_receive_rate_samples_idle_and_clear_reset() {
    let dir = tempfile::tempdir().unwrap();
    let mut pty = Pty::new();
    let mut app_options = options(dir.path().into(), pty.slave.to_string_lossy().into_owned());
    app_options.legacy_config.as_mut().unwrap().auto_reconnect = Some(false);
    let core = AppCore::create(app_options).unwrap();
    core.dispatch(Command::Connect).unwrap();
    wait_for(|| core.snapshot().unwrap().connection == ConnectionState::Connected);

    pty.write(&[0x55; 100]);
    wait_for(|| core.snapshot().unwrap().rx_bytes == 100);
    wait_for(|| core.snapshot().unwrap().rx_bytes_per_second > 0.0);
    wait_for(|| core.snapshot().unwrap().rx_bytes_per_second == 0.0);

    pty.write(&[0x33; 100]);
    wait_for(|| core.snapshot().unwrap().rx_bytes == 200);
    wait_for(|| core.snapshot().unwrap().rx_bytes_per_second > 0.0);
    core.dispatch(Command::ClearLog).unwrap();
    wait_for(|| {
        let snapshot = core.snapshot().unwrap();
        snapshot.rx_bytes == 0 && snapshot.rx_bytes_per_second == 0.0
    });
    pty.close();
    wait_for(|| core.snapshot().unwrap().connection == ConnectionState::Disconnected);
    core.close().unwrap();
}

#[test]
fn pty_binary_roundtrip_timeout_disconnect_and_close() {
    let dir = tempfile::tempdir().unwrap();
    let mut pty = Pty::new();
    let mut app_options = options(dir.path().into(), pty.slave.to_string_lossy().into_owned());
    app_options.legacy_config.as_mut().unwrap().auto_reconnect = Some(false);
    let core = AppCore::create(app_options).unwrap();
    let (initial, events) = core.subscribe().unwrap();
    assert_eq!(initial.connection, ConnectionState::Disconnected);
    core.dispatch(Command::Connect).unwrap();
    wait_for(|| core.snapshot().unwrap().connection == ConnectionState::Connected);
    let id = core
        .dispatch(Command::SendHex {
            input: "00 7F FF".into(),
        })
        .unwrap();
    wait_for(|| pty.has_bytes(&[0, 0x7f, 0xff]));
    let mut saw_sent = false;
    let deadline = Instant::now() + Duration::from_secs(2);
    while Instant::now() < deadline {
        if let Some(event) = events.recv_timeout(Duration::from_millis(40)).unwrap() {
            if let EventKind::DataSent {
                request_id, data, ..
            } = event.kind
            {
                if request_id == id {
                    saw_sent = data == [0, 0x7f, 0xff];
                    break;
                }
            }
        }
    }
    assert!(saw_sent);
    let incoming = [0x80, 0, 0xff];
    pty.write(&incoming);
    wait_for(|| core.snapshot().unwrap().rx_bytes == incoming.len() as u64);
    let mut saw_received = false;
    let deadline = Instant::now() + Duration::from_secs(2);
    while Instant::now() < deadline {
        if let Some(event) = events.recv_timeout(Duration::from_millis(40)).unwrap() {
            if let EventKind::DataReceived { data, .. } = event.kind {
                if data == incoming {
                    saw_received = true;
                    break;
                }
            }
        }
    }
    assert!(saw_received);
    assert!(events
        .recv_timeout(Duration::from_millis(80))
        .unwrap()
        .is_none());
    pty.close();
    wait_for(|| core.snapshot().unwrap().connection == ConnectionState::Disconnected);
    assert!(core.snapshot().unwrap().log.incomplete);
    core.close().unwrap();
    core.close().unwrap();
    assert_eq!(core.snapshot().unwrap_err().kind, ErrorKind::Closed);
}

#[test]
fn pty_configured_name_reconnect_and_subscription_overflow() {
    let dir = tempfile::tempdir().unwrap();
    let mut first = Pty::new();
    let stable = dir.path().join("configured-port");
    std::os::unix::fs::symlink(&first.slave, &stable).unwrap();
    let mut app_options = options(dir.path().into(), stable.to_string_lossy().into_owned());
    app_options.legacy_config.as_mut().unwrap().auto_reconnect = Some(true);
    let core = AppCore::create(app_options).unwrap();
    let (_, events) = core.subscribe().unwrap();
    core.dispatch(Command::Connect).unwrap();
    wait_for(|| core.snapshot().unwrap().connection == ConnectionState::Connected);
    first.close();
    let mut replacement = Pty::new();
    let next = dir.path().join("replacement");
    std::os::unix::fs::symlink(&replacement.slave, &next).unwrap();
    wait_for(|| core.snapshot().unwrap().connection == ConnectionState::Reconnecting);
    fs::remove_file(&stable).unwrap();
    std::os::unix::fs::symlink(&next, &stable).unwrap();
    wait_for(|| core.snapshot().unwrap().connection == ConnectionState::Connected);
    let id = core
        .dispatch(Command::SendText {
            text: "reconnected".into(),
            newline: Newline::None,
        })
        .unwrap();
    wait_for(|| replacement.has_bytes(b"reconnected"));
    assert!(id > 0);
    events.cancel();
    core.close().unwrap();

    let overflow_dir = tempfile::tempdir().unwrap();
    let mut overflow_options = options(overflow_dir.path().into(), String::new());
    overflow_options.event_capacity = 1;
    let overflow_core = AppCore::create(overflow_options).unwrap();
    let (_, slow) = overflow_core.subscribe().unwrap();
    overflow_core
        .dispatch(Command::UpdateConfig(ConfigPatch {
            baud_rate: Some(115200),
            ..ConfigPatch::default()
        }))
        .unwrap();
    wait_for(|| {
        overflow_core
            .snapshot()
            .is_ok_and(|snapshot| snapshot.config.serial.baud_rate == 115200)
    });
    overflow_core
        .dispatch(Command::UpdateConfig(ConfigPatch {
            data_bits: Some(7),
            ..ConfigPatch::default()
        }))
        .unwrap();
    wait_for(|| {
        overflow_core
            .snapshot()
            .is_ok_and(|snapshot| snapshot.config.serial.data_bits == 7)
    });
    wait_for(
        || matches!(slow.recv_timeout(Duration::from_millis(20)), Err(error) if error.kind == ErrorKind::QueueOverflow),
    );
    slow.cancel();
    overflow_core.close().unwrap();
}

#[test]
fn pty_auto_send_export_and_history() {
    let dir = tempfile::tempdir().unwrap();
    let mut pty = Pty::new();
    let core = AppCore::create(options(
        dir.path().into(),
        pty.slave.to_string_lossy().into_owned(),
    ))
    .unwrap();
    core.dispatch(Command::Connect).unwrap();
    wait_for(|| core.snapshot().unwrap().connection == ConnectionState::Connected);

    core.dispatch(Command::SetAutoSend {
        enabled: true,
        interval_ms: 10,
        input: "periodic".into(),
        hex: false,
        newline: Newline::None,
    })
    .unwrap();
    wait_for(|| pty.contains_bytes(b"periodic"));
    wait_for(|| {
        core.snapshot()
            .unwrap()
            .config
            .history
            .last()
            .is_some_and(|entry| entry == "periodic")
    });
    let export = dir.path().join("export.txt");
    core.dispatch(Command::ExportLog {
        path: export.to_string_lossy().into_owned(),
        options: skyport_core::ExportOptions {
            show_sent: true,
            hex: false,
            timestamps: false,
            strip_ansi: false,
        },
    })
    .unwrap();
    wait_for(|| {
        fs::read(&export)
            .map(|bytes| bytes.windows(13).any(|window| window == b"TX > periodic"))
            .unwrap_or(false)
    });
    core.close().unwrap();
}

#[test]
fn manual_connect_failure_does_not_start_configured_retries() {
    let dir = tempfile::tempdir().unwrap();
    let missing = dir.path().join("missing-port");
    let core = AppCore::create(options(
        dir.path().into(),
        missing.to_string_lossy().into_owned(),
    ))
    .unwrap();
    let mut config = core.snapshot().unwrap().config;
    config.serial.auto_reconnect = true;
    core.dispatch(Command::SetConfig(config)).unwrap();
    core.dispatch(Command::Connect).unwrap();
    wait_for(|| {
        core.snapshot().is_ok_and(|snapshot| {
            snapshot.connection == ConnectionState::Disconnected && snapshot.error.is_some()
        })
    });
    thread::sleep(Duration::from_millis(100));
    let sequence = core.snapshot().unwrap().sequence;
    thread::sleep(Duration::from_millis(1_100));
    assert_eq!(
        core.snapshot().unwrap().sequence,
        sequence,
        "manual connect failure must not trigger configured reconnect"
    );
    assert_eq!(
        core.dispatch(Command::SendHex {
            input: "00_11".into()
        })
        .unwrap_err()
        .kind,
        ErrorKind::InvalidArgument
    );
    assert_eq!(
        core.dispatch(Command::SetAutoSend {
            enabled: true,
            interval_ms: 10,
            input: "00_11".into(),
            hex: true,
            newline: Newline::None
        })
        .unwrap_err()
        .kind,
        ErrorKind::InvalidArgument
    );
    assert_eq!(
        core.dispatch(Command::SendHex { input: "0".into() })
            .unwrap_err()
            .code,
        Some(ErrorCode::IncompleteHexByte)
    );
    core.close().unwrap();
}

#[test]
fn rejected_send_reports_write_failure_and_concurrent_close_is_safe() {
    use std::sync::Arc;
    let dir = tempfile::tempdir().unwrap();
    let core = Arc::new(AppCore::create(options(dir.path().into(), String::new())).unwrap());
    let (_, events) = core.subscribe().unwrap();
    assert_eq!(
        core.dispatch(Command::SendHex { input: "0G".into() })
            .unwrap_err()
            .kind,
        ErrorKind::InvalidArgument
    );
    let request = core
        .dispatch(Command::SendText {
            text: "not connected".into(),
            newline: Newline::None,
        })
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(2);
    let mut failed = false;
    while Instant::now() < deadline {
        if let Some(event) = events.recv_timeout(Duration::from_millis(40)).unwrap() {
            match event.kind {
                EventKind::WriteFailed { request_id, error } if request_id == request => {
                    assert_eq!(error.kind, ErrorKind::Disconnected);
                    failed = true;
                    break;
                }
                EventKind::CommandFailed { request_id, .. }
                | EventKind::CommandCompleted { request_id }
                    if request_id == request =>
                {
                    panic!("send had an extra final outcome")
                }
                _ => {}
            }
        }
    }
    assert!(failed);
    events.cancel();
    assert_eq!(
        events.recv_timeout(Duration::ZERO).unwrap_err().kind,
        ErrorKind::Closed
    );
    let (_, terminal) = core.subscribe().unwrap();
    core.dispatch(Command::ListPorts).unwrap();
    let first = core.clone();
    let second = core.clone();
    let a = thread::spawn(move || first.close().unwrap());
    let b = thread::spawn(move || second.close().unwrap());
    a.join().unwrap();
    b.join().unwrap();
    let mut terminal_closed = false;
    for _ in 0..16 {
        match terminal.recv_timeout(Duration::from_millis(40)) {
            Ok(Some(_)) => {}
            Ok(None) => panic!("terminal subscription timed out after close"),
            Err(error) => {
                assert_eq!(error.kind, ErrorKind::Closed);
                terminal_closed = true;
                break;
            }
        }
    }
    assert!(terminal_closed);
    assert_eq!(
        core.dispatch(Command::ListPorts).unwrap_err().kind,
        ErrorKind::Closed
    );
}

#[test]
fn subscription_overflow_is_also_bounded_by_payload_bytes() {
    let dir = tempfile::tempdir().unwrap();
    let core = AppCore::create(AppOptions {
        data_directory: dir.path().into(),
        command_capacity: 16,
        event_capacity: 64,
        ..AppOptions::default()
    })
    .unwrap();
    let (_, slow) = core.subscribe().unwrap();
    for index in 0..10 {
        let input = format!("{index}{}", "x".repeat(1_048_575));
        core.dispatch(Command::SetAutoSend {
            enabled: false,
            interval_ms: 1000,
            input,
            hex: false,
            newline: Newline::None,
        })
        .unwrap();
    }
    wait_for(|| core.snapshot().unwrap().auto_send_input.starts_with('9'));
    assert_eq!(
        slow.recv_timeout(Duration::from_millis(20))
            .unwrap_err()
            .kind,
        ErrorKind::QueueOverflow
    );
    core.close().unwrap();
}

#[test]
fn configured_send_and_invalid_auto_edits_use_current_core_settings() {
    let dir = tempfile::tempdir().unwrap();
    let mut pty = Pty::new();
    let core = AppCore::create(options(
        dir.path().into(),
        pty.slave.to_string_lossy().into_owned(),
    ))
    .unwrap();
    let (_, events) = core.subscribe().unwrap();
    core.dispatch(Command::Connect).unwrap();
    wait_for(|| core.snapshot().unwrap().connection == ConnectionState::Connected);
    let connected_at = core.snapshot().unwrap().connected_at_ms;
    let policy = core
        .dispatch(Command::UpdateConfig(ConfigPatch {
            auto_reconnect: Some(false),
            newline: Some(Newline::CrLf),
            append_newline: Some(true),
            ..Default::default()
        }))
        .unwrap();
    loop {
        if let Some(event) = events.recv_timeout(Duration::from_secs(2)).unwrap() {
            match event.kind {
                EventKind::StateChanged(state) => {
                    assert_ne!(state.connection, ConnectionState::Reconfiguring)
                }
                EventKind::CommandCompleted { request_id } if request_id == policy => break,
                _ => {}
            }
        } else {
            panic!("policy update did not complete");
        }
    }
    assert_eq!(core.snapshot().unwrap().connected_at_ms, connected_at);
    core.dispatch(Command::SendInput { input: "M".into() })
        .unwrap();
    wait_for(|| pty.has_bytes(b"M\r\n"));
    core.dispatch(Command::UpdateConfig(ConfigPatch {
        append_newline: Some(false),
        ..Default::default()
    }))
    .unwrap();
    core.dispatch(Command::SendInput { input: "N".into() })
        .unwrap();
    wait_for(|| pty.has_bytes(b"M\r\nN"));
    core.dispatch(Command::UpdateConfig(ConfigPatch {
        append_newline: Some(true),
        ..Default::default()
    }))
    .unwrap();
    core.dispatch(Command::SendInput { input: "O".into() })
        .unwrap();
    wait_for(|| pty.has_bytes(b"M\r\nNO\r\n"));
    core.dispatch(Command::UpdateConfig(ConfigPatch {
        auto_send_enabled: Some(true),
        auto_send_interval_ms: Some(10),
        hex_send: Some(true),
        auto_send_input: Some("41".into()),
        ..Default::default()
    }))
    .unwrap();
    wait_for(|| pty.contains_bytes(b"A"));
    core.dispatch(Command::UpdateConfig(ConfigPatch {
        auto_send_input: Some("0G".into()),
        ..Default::default()
    }))
    .unwrap();
    wait_for(|| core.snapshot().unwrap().auto_send_error.is_some());
    let paused = core.snapshot().unwrap();
    assert!(paused.config.send.auto_send_enabled);
    assert_eq!(paused.auto_send_input, "0G");
    assert_eq!(
        paused.auto_send_error.as_ref().unwrap().code,
        Some(ErrorCode::InvalidHexCharacter)
    );
    thread::sleep(Duration::from_millis(100));
    assert_eq!(core.snapshot().unwrap().tx_bytes, paused.tx_bytes);
    core.dispatch(Command::UpdateConfig(ConfigPatch {
        auto_send_enabled: Some(false),
        ..Default::default()
    }))
    .unwrap();
    core.dispatch(Command::UpdateConfig(ConfigPatch {
        auto_send_input: Some("42".into()),
        ..Default::default()
    }))
    .unwrap();
    wait_for(|| {
        let state = core.snapshot().unwrap();
        state.auto_send_error.is_none()
            && state.auto_send_input == "42"
            && !state.config.send.auto_send_enabled
    });
    thread::sleep(Duration::from_millis(100));
    assert_eq!(core.snapshot().unwrap().tx_bytes, paused.tx_bytes);
    core.dispatch(Command::UpdateConfig(ConfigPatch {
        auto_send_enabled: Some(true),
        ..Default::default()
    }))
    .unwrap();
    wait_for(|| pty.contains_bytes(b"B"));
    core.close().unwrap();
}

#[test]
fn atomic_subscription_does_not_reapply_a_send_already_in_its_snapshot() {
    use std::sync::Arc;
    let dir = tempfile::tempdir().unwrap();
    let pty = Pty::new();
    let mut opts = options(dir.path().into(), pty.slave.to_string_lossy().into_owned());
    opts.command_capacity = 128;
    let core = Arc::new(AppCore::create(opts).unwrap());
    core.dispatch(Command::Connect).unwrap();
    wait_for(|| core.snapshot().unwrap().connection == ConnectionState::Connected);
    let producer = core.clone();
    let queued = thread::spawn(move || {
        for _ in 0..32 {
            producer
                .dispatch(Command::SendInput { input: "1".into() })
                .unwrap();
        }
    });
    loop {
        let (snapshot, subscription) = core.subscribe().unwrap();
        if snapshot.tx_bytes == 32 {
            break;
        }
        let mut expected_sequence = snapshot.sequence + 1;
        loop {
            let event = subscription
                .recv_timeout(Duration::from_secs(2))
                .unwrap()
                .expect("send event missing");
            assert_eq!(event.sequence, expected_sequence);
            expected_sequence += 1;
            if let EventKind::DataSent { tx_bytes, .. } = event.kind {
                assert_eq!(tx_bytes, snapshot.tx_bytes + 1);
                break;
            }
        }
    }
    queued.join().unwrap();
    core.close().unwrap();
}

#[test]
fn close_finishes_every_accepted_send_with_one_correlated_outcome() {
    use std::collections::HashSet;
    let dir = tempfile::tempdir().unwrap();
    let mut pty = Pty::new();
    let mut opts = options(dir.path().into(), pty.slave.to_string_lossy().into_owned());
    opts.command_capacity = 128;
    opts.event_capacity = 1024;
    let core = AppCore::create(opts).unwrap();
    let (_, events) = core.subscribe().unwrap();
    core.dispatch(Command::Connect).unwrap();
    wait_for(|| core.snapshot().unwrap().connection == ConnectionState::Connected);
    let first = core
        .dispatch(Command::SendText {
            text: "x".repeat(1_048_576),
            newline: Newline::None,
        })
        .unwrap();
    wait_for(|| pty.contains_bytes(b"x"));
    let mut accepted = HashSet::from([first]);
    for _ in 0..32 {
        accepted.insert(
            core.dispatch(Command::SendInput { input: "z".into() })
                .unwrap(),
        );
    }
    core.close().unwrap();
    let mut finished = HashSet::new();
    loop {
        match events.recv_timeout(Duration::from_secs(2)) {
            Ok(Some(event)) => match event.kind {
                EventKind::DataSent { request_id, .. }
                | EventKind::WriteFailed { request_id, .. }
                    if accepted.contains(&request_id) =>
                {
                    assert!(
                        finished.insert(request_id),
                        "request received duplicate final outcomes"
                    );
                }
                EventKind::CommandCompleted { request_id }
                | EventKind::CommandFailed { request_id, .. }
                    if accepted.contains(&request_id) =>
                {
                    panic!("send received a non-send final outcome")
                }
                _ => {}
            },
            Err(error) => {
                assert_eq!(error.kind, ErrorKind::Closed);
                break;
            }
            Ok(None) => panic!("closing left unresolved requests"),
        }
    }
    assert_eq!(finished, accepted);
}
