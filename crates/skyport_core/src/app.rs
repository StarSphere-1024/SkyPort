use crate::{
    serial, timestamp_ms, AppConfig, AppOptions, AppSnapshot, AppState, Command, ConnectionState,
    CoreError, ErrorCode, ErrorKind, Event, EventKind, LogDelta, LogStore, Newline, RequestId,
    SerialConfig,
};
use std::{
    collections::HashMap,
    fs::{self, OpenOptions},
    io::{self, Read, Write},
    path::Path,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        mpsc::{self, Receiver, RecvTimeoutError, SyncSender, TrySendError},
        Arc, Condvar, Mutex,
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};

const MAX_SUBSCRIBER_BYTES: usize = 8 * 1024 * 1024;
struct Subscriber {
    tx: SyncSender<Event>,
    overflow: Arc<Mutex<Option<CoreError>>>,
    cancelled: Arc<AtomicBool>,
    queued_bytes: Arc<std::sync::atomic::AtomicUsize>,
}
struct AutoPayload {
    bytes: Arc<[u8]>,
    input: Arc<str>,
    history_attempted: bool,
}
struct State {
    snapshot: AppSnapshot,
    log: LogStore,
    auto_payload: Option<AutoPayload>,
    subscribers: HashMap<u64, Subscriber>,
    next_subscriber: u64,
}
struct Shared {
    state: Mutex<State>,
    event_capacity: usize,
    worker_error: Mutex<Option<CoreError>>,
}
struct Lifecycle {
    closing: bool,
    closed: bool,
    close_error: Option<CoreError>,
}
struct Inner {
    tx: SyncSender<(RequestId, Command)>,
    next_id: Mutex<RequestId>,
    shared: Arc<Shared>,
    lifecycle: Mutex<Lifecycle>,
    closed: Condvar,
    worker: Mutex<Option<JoinHandle<()>>>,
    stop: Arc<AtomicBool>,
}
pub struct AppCore {
    inner: Arc<Inner>,
}

impl AppCore {
    pub fn create(options: AppOptions) -> Result<Self, CoreError> {
        if !(1..=4096).contains(&options.command_capacity)
            || !(1..=4096).contains(&options.event_capacity)
        {
            return Err(CoreError::new(
                ErrorKind::InvalidArgument,
                "queue capacities must be between 1 and 4096",
            )
            .with_code(ErrorCode::QueueCapacityInvalid));
        }
        let config = AppConfig::load(&options.data_directory, options.legacy_config)?;
        let snapshot = AppSnapshot {
            sequence: 0,
            config: config.clone(),
            connection: ConnectionState::Disconnected,
            applied_config: None,
            connected_at_ms: None,
            ports: Vec::new(),
            rx_bytes: 0,
            tx_bytes: 0,
            last_rx_bytes: 0,
            rx_bytes_per_second: 0.0,
            error: None,
            auto_send_error: None,
            log: LogStore::new(config.log_capacity_bytes).snapshot(),
            auto_send_input: String::new(),
        };
        let shared = Arc::new(Shared {
            state: Mutex::new(State {
                snapshot,
                log: LogStore::new(config.log_capacity_bytes),
                auto_payload: None,
                subscribers: HashMap::new(),
                next_subscriber: 1,
            }),
            event_capacity: options.event_capacity,
            worker_error: Mutex::new(None),
        });
        let (tx, rx) = mpsc::sync_channel(options.command_capacity);
        let shared_for_worker = shared.clone();
        let stop = Arc::new(AtomicBool::new(false));
        let worker_stop = stop.clone();
        let worker = thread::Builder::new()
            .name("skyport-core".into())
            .spawn(move || {
                let failed = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    run_worker(
                        rx,
                        shared_for_worker.clone(),
                        options.data_directory,
                        worker_stop.clone(),
                    );
                }));
                if failed.is_err() {
                    let error = CoreError::new(
                        ErrorKind::TaskFailed,
                        "core worker panicked; application shutdown is required",
                    );
                    *shared_for_worker
                        .worker_error
                        .lock()
                        .expect("worker failure lock poisoned") = Some(error.clone());
                    worker_stop.store(true, Ordering::Release);
                    // Recover only to terminate consumers; a poisoned application is never resumed.
                    let mut state = shared_for_worker
                        .state
                        .lock()
                        .unwrap_or_else(|poisoned| poisoned.into_inner());
                    for subscriber in state.subscribers.values() {
                        *subscriber
                            .overflow
                            .lock()
                            .expect("subscription termination lock poisoned") = Some(error.clone());
                    }
                    state.subscribers.clear();
                }
            })
            .map_err(|e| CoreError::new(ErrorKind::Internal, format!("start core worker: {e}")))?;
        Ok(Self {
            inner: Arc::new(Inner {
                tx,
                next_id: Mutex::new(1),
                shared,
                lifecycle: Mutex::new(Lifecycle {
                    closing: false,
                    closed: false,
                    close_error: None,
                }),
                closed: Condvar::new(),
                worker: Mutex::new(Some(worker)),
                stop,
            }),
        })
    }

    pub fn dispatch(&self, command: Command) -> Result<RequestId, CoreError> {
        let life = self.inner.lifecycle.lock().map_err(lock_error)?;
        if life.closing || life.closed {
            return Err(CoreError::new(ErrorKind::Closed, "AppCore is closed"));
        }
        check_worker(&self.inner.shared)?;
        validate_command(&command)?;
        let mut next = self.inner.next_id.lock().map_err(lock_error)?;
        let id = *next;
        match self.inner.tx.try_send((id, command)) {
            Ok(()) => {
                *next = next.wrapping_add(1).max(1);
                Ok(id)
            }
            Err(TrySendError::Full(_)) => Err(CoreError::new(
                ErrorKind::QueueOverflow,
                "command queue is full",
            )),
            Err(TrySendError::Disconnected(_)) => {
                Err(CoreError::new(ErrorKind::Closed, "AppCore is closed"))
            }
        }
    }

    pub fn snapshot(&self) -> Result<AppSnapshot, CoreError> {
        let life = self.inner.lifecycle.lock().map_err(lock_error)?;
        if life.closing || life.closed {
            return Err(CoreError::new(ErrorKind::Closed, "AppCore is closed"));
        }
        check_worker(&self.inner.shared)?;
        let state = self.inner.shared.state.lock().map_err(lock_error)?;
        let mut snapshot = state.snapshot.clone();
        snapshot.log = state.log.snapshot();
        drop(life);
        Ok(snapshot)
    }

    pub fn subscribe(&self) -> Result<(AppSnapshot, EventSubscription), CoreError> {
        let life = self.inner.lifecycle.lock().map_err(lock_error)?;
        if life.closing || life.closed {
            return Err(CoreError::new(ErrorKind::Closed, "AppCore is closed"));
        }
        check_worker(&self.inner.shared)?;
        let mut state = self.inner.shared.state.lock().map_err(lock_error)?;
        let (tx, rx) = mpsc::sync_channel(self.inner.shared.event_capacity);
        let id = state.next_subscriber;
        state.next_subscriber = id.wrapping_add(1).max(1);
        let overflow = Arc::new(Mutex::new(None));
        let cancelled = Arc::new(AtomicBool::new(false));
        let queued_bytes = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        state.subscribers.insert(
            id,
            Subscriber {
                tx,
                overflow: overflow.clone(),
                cancelled: cancelled.clone(),
                queued_bytes: queued_bytes.clone(),
            },
        );
        let result = EventSubscription {
            id,
            rx,
            shared: Arc::downgrade(&self.inner.shared),
            overflow,
            cancelled,
            queued_bytes,
        };
        let mut snapshot = state.snapshot.clone();
        snapshot.log = state.log.snapshot();
        Ok((snapshot, result))
    }

    pub fn close(&self) -> Result<(), CoreError> {
        let mut life = self.inner.lifecycle.lock().map_err(lock_error)?;
        if life.closed {
            return life.close_error.clone().map_or(Ok(()), Err);
        }
        if life.closing {
            while !life.closed {
                life = self.inner.closed.wait(life).map_err(lock_error)?;
            }
            return life.close_error.clone().map_or(Ok(()), Err);
        }
        life.closing = true;
        self.inner.stop.store(true, Ordering::Release);
        publish_state(&self.inner.shared, ConnectionState::Closing, None);
        drop(life);
        let handle = self.inner.worker.lock().map_err(lock_error)?.take();
        let join_error = handle
            .and_then(|handle| handle.join().err())
            .map(|_| CoreError::new(ErrorKind::TaskFailed, "core worker panicked"))
            .or_else(|| {
                self.inner
                    .shared
                    .worker_error
                    .lock()
                    .ok()
                    .and_then(|error| error.clone())
            });
        if let Some(error) = join_error.as_ref() {
            publish_simple(&self.inner.shared, EventKind::TaskFailed(error.clone()));
        }
        mark_log_incomplete_if_pending(&self.inner.shared);
        publish_state(&self.inner.shared, ConnectionState::Closed, None);
        if let Ok(mut state) = self.inner.shared.state.lock() {
            state.subscribers.clear();
        }
        let mut life = self.inner.lifecycle.lock().map_err(lock_error)?;
        life.close_error = join_error;
        life.closed = true;
        self.inner.closed.notify_all();
        life.close_error.clone().map_or(Ok(()), Err)
    }
}

fn lock_error<T>(_: T) -> CoreError {
    CoreError::new(ErrorKind::Internal, "core synchronization lock poisoned")
}
fn check_worker(shared: &Shared) -> Result<(), CoreError> {
    shared
        .worker_error
        .lock()
        .map_err(lock_error)?
        .clone()
        .map_or(Ok(()), Err)
}

pub struct EventSubscription {
    id: u64,
    rx: Receiver<Event>,
    shared: std::sync::Weak<Shared>,
    overflow: Arc<Mutex<Option<CoreError>>>,
    cancelled: Arc<AtomicBool>,
    queued_bytes: Arc<std::sync::atomic::AtomicUsize>,
}
impl EventSubscription {
    pub fn recv_timeout(&self, timeout: Duration) -> Result<Option<Event>, CoreError> {
        let started = Instant::now();
        loop {
            if let Some(error) = self.overflow.lock().map_err(lock_error)?.take() {
                return Err(error);
            }
            if self.cancelled.load(Ordering::Acquire) {
                return Err(CoreError::new(
                    ErrorKind::Closed,
                    "event subscription is closed",
                ));
            }
            let remaining = timeout.saturating_sub(started.elapsed());
            match self
                .rx
                .recv_timeout(remaining.min(Duration::from_millis(10)))
            {
                Ok(event) => {
                    self.queued_bytes
                        .fetch_sub(event_weight(&event), Ordering::AcqRel);
                    if let Some(error) = self.overflow.lock().map_err(lock_error)?.take() {
                        return Err(error);
                    }
                    return Ok(Some(event));
                }
                Err(RecvTimeoutError::Timeout) if started.elapsed() >= timeout => return Ok(None),
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => {
                    if let Some(error) = self.overflow.lock().map_err(lock_error)?.take() {
                        return Err(error);
                    }
                    return Err(CoreError::new(
                        ErrorKind::Closed,
                        "event subscription is closed",
                    ));
                }
            }
        }
    }
    pub fn cancel(&self) {
        if !self.cancelled.swap(true, Ordering::AcqRel) {
            if let Some(shared) = self.shared.upgrade() {
                if let Ok(mut state) = shared.state.lock() {
                    state.subscribers.remove(&self.id);
                }
            }
        }
        while let Ok(event) = self.rx.try_recv() {
            self.queued_bytes
                .fetch_sub(event_weight(&event), Ordering::AcqRel);
        }
    }
}
impl Drop for EventSubscription {
    fn drop(&mut self) {
        self.cancel();
    }
}
fn event_weight(event: &Event) -> usize {
    let error_size = |error: &CoreError| error.message.len() + 32;
    let log_size = |log: &LogDelta| {
        log.upsert.iter().map(|r| r.data.len() + 48).sum::<usize>() + log.removed_ids.len() * 8 + 64
    };
    let state_size = |state: &AppState| {
        state.config.serial.port_name.len()
            + state.config.history.iter().map(String::len).sum::<usize>()
            + state.auto_send_input.len()
            + state.ports.iter().map(String::len).sum::<usize>()
            + state.error.as_ref().map_or(0, error_size)
            + state.auto_send_error.as_ref().map_or(0, error_size)
            + 512
    };
    match &event.kind {
        EventKind::StateChanged(state) => state_size(state),
        EventKind::PortsChanged(ports) => ports.iter().map(String::len).sum::<usize>() + 32,
        EventKind::LogChanged(log) => log_size(log),
        EventKind::DataReceived { data, log, .. } => data.len() + log_size(log) + 64,
        EventKind::DataSent { data, log, .. } => data.len() + log_size(log) + 64,
        EventKind::WriteFailed { error, .. } | EventKind::CommandFailed { error, .. } => {
            error_size(error) + 32
        }
        EventKind::Disconnected(error)
        | EventKind::QueueOverflow(error)
        | EventKind::TaskFailed(error) => error_size(error) + 32,
        EventKind::Reconnecting | EventKind::CommandCompleted { .. } => 32,
    }
}

fn run_worker(
    rx: Receiver<(RequestId, Command)>,
    shared: Arc<Shared>,
    data_directory: std::path::PathBuf,
    stop: Arc<AtomicBool>,
) {
    let mut port: Option<Box<dyn serialport::SerialPort>> = None;
    let mut reconnect_at: Option<Instant> = None;
    let mut link_lost = false;
    let mut rate_sample_at = Instant::now();
    let mut rate_sample_bytes = 0;
    let mut rate_connection = ConnectionState::Disconnected;
    let mut next_auto = Instant::now();
    let mut next_ports = Instant::now();
    let mut buf = [0u8; 8192];
    loop {
        if stop.load(Ordering::Acquire) {
            while let Ok((id, command)) = rx.try_recv() {
                let error =
                    CoreError::new(ErrorKind::Closed, "AppCore closed before command execution");
                match command {
                    Command::SendText { .. }
                    | Command::SendHex { .. }
                    | Command::SendInput { .. } => publish_write_failed(&shared, id, error),
                    _ => complete_failure(&shared, id, error),
                }
            }
            break;
        }
        match rx.recv_timeout(auto_wait(&shared, next_auto, Duration::from_millis(10))) {
            Ok((id, command)) => handle_command(
                id,
                command,
                &shared,
                &data_directory,
                &mut port,
                &mut reconnect_at,
                &mut next_auto,
                &mut link_lost,
            ),
            Err(RecvTimeoutError::Disconnected) => break,
            Err(RecvTimeoutError::Timeout) => {}
        }
        update_rx_rate(
            &shared,
            &mut rate_sample_at,
            &mut rate_sample_bytes,
            &mut rate_connection,
        );
        if stop.load(Ordering::Acquire) {
            continue;
        }
        if Instant::now() >= next_ports {
            next_ports = Instant::now() + Duration::from_secs(1);
            match serial::ports() {
                Ok(ports) => update_ports(&shared, ports),
                Err(error) => publish_simple(&shared, EventKind::TaskFailed(error)),
            }
        }
        if stop.load(Ordering::Acquire) {
            continue;
        }
        if let Some(open) = port.as_mut() {
            let timeout = auto_wait(&shared, next_auto, serial::READ_POLL_TIMEOUT)
                .max(Duration::from_millis(1));
            if let Err(error) = serial::set_read_timeout(open.as_mut(), timeout) {
                port = None;
                link_lost = true;
                let retry =
                    auto_reconnect_enabled(&shared).expect("core worker state lock poisoned");
                publish_disconnected(&shared, error, retry);
                reconnect_at = retry.then(|| Instant::now() + Duration::from_secs(1));
                continue;
            }
            let result = open.read(&mut buf);
            match result {
                Ok(0) => {}
                Ok(n) => publish_received(&shared, &buf[..n]),
                Err(e)
                    if e.kind() == io::ErrorKind::TimedOut
                        || e.kind() == io::ErrorKind::WouldBlock
                        || e.kind() == io::ErrorKind::Interrupted => {}
                Err(e) => {
                    let kind = if matches!(
                        e.kind(),
                        io::ErrorKind::BrokenPipe
                            | io::ErrorKind::NotConnected
                            | io::ErrorKind::UnexpectedEof
                            | io::ErrorKind::ConnectionReset
                            | io::ErrorKind::ConnectionAborted
                    ) {
                        ErrorKind::Disconnected
                    } else {
                        ErrorKind::ReadFailed
                    };
                    let error = CoreError::new(kind, format!("serial read failed: {e}"));
                    port = None;
                    link_lost = true;
                    let retry =
                        auto_reconnect_enabled(&shared).expect("core worker state lock poisoned");
                    publish_disconnected(&shared, error, retry);
                    reconnect_at = retry.then(|| Instant::now() + Duration::from_secs(1));
                }
            }
        } else if reconnect_at.is_some_and(|at| Instant::now() >= at)
            && !stop.load(Ordering::Acquire)
        {
            reconnect_at = None;
            let config = snapshot_config(&shared).expect("core worker state lock poisoned");
            if config.serial.auto_reconnect
                && !config.serial.port_name.is_empty()
                && !stop.load(Ordering::Acquire)
            {
                publish_simple(&shared, EventKind::Reconnecting);
                match serial::open(&config.serial) {
                    Ok(open) if !stop.load(Ordering::Acquire) => {
                        port = Some(open);
                        link_lost = false;
                        publish_connected(&shared, config.serial);
                    }
                    Ok(_) => {}
                    Err(error) if !stop.load(Ordering::Acquire) => {
                        publish_error_state(&shared, error.clone());
                        publish_simple(&shared, EventKind::Reconnecting);
                        reconnect_at = Some(Instant::now() + Duration::from_secs(1));
                    }
                    Err(_) => {}
                }
            }
        }
        if !stop.load(Ordering::Acquire) {
            auto_send(
                &shared,
                &data_directory,
                &mut port,
                &mut next_auto,
                &mut reconnect_at,
                &mut link_lost,
            );
        }
    }
}

fn handle_command(
    id: RequestId,
    command: Command,
    shared: &Arc<Shared>,
    dir: &Path,
    port: &mut Option<Box<dyn serialport::SerialPort>>,
    reconnect_at: &mut Option<Instant>,
    next_auto: &mut Instant,
    link_lost: &mut bool,
) {
    let mut send_final = false;
    let result = (|| -> Result<(), CoreError> {
        match command {
            Command::ListPorts => serial::ports().map(|ports| update_ports(shared, ports)),
            Command::SetConfig(config) => apply_config(
                shared,
                dir,
                config,
                None,
                port,
                reconnect_at,
                next_auto,
                link_lost,
            ),
            Command::UpdateConfig(patch) => {
                let mut config = snapshot_config(shared)?;
                if let Some(value) = patch.port_name {
                    config.serial.port_name = value;
                }
                if let Some(value) = patch.baud_rate {
                    config.serial.baud_rate = value;
                }
                if let Some(value) = patch.data_bits {
                    config.serial.data_bits = value;
                }
                if let Some(value) = patch.parity {
                    config.serial.parity = value;
                }
                if let Some(value) = patch.stop_bits {
                    config.serial.stop_bits = value;
                }
                if let Some(value) = patch.auto_reconnect {
                    config.serial.auto_reconnect = value;
                }
                if let Some(value) = patch.flow_control {
                    config.serial.flow_control = value;
                }
                if let Some(value) = patch.hex_send {
                    config.send.hex = value;
                }
                if let Some(value) = patch.newline {
                    config.send.newline = value;
                }
                if let Some(value) = patch.append_newline {
                    config.send.append_newline = value;
                }
                if let Some(value) = patch.auto_send_enabled {
                    config.send.auto_send_enabled = value;
                }
                if let Some(value) = patch.auto_send_interval_ms {
                    config.send.auto_send_interval_ms = value;
                }
                if let Some(value) = patch.log_capacity_bytes {
                    config.log_capacity_bytes = value;
                }
                apply_config(
                    shared,
                    dir,
                    config,
                    patch.auto_send_input,
                    port,
                    reconnect_at,
                    next_auto,
                    link_lost,
                )
            }
            Command::Connect => {
                if port.is_some() {
                    Ok(())
                } else {
                    let config = snapshot_config(shared)?;
                    let keep_reconnecting = *link_lost && config.serial.auto_reconnect;
                    publish_state(shared, ConnectionState::Connecting, None);
                    match serial::open(&config.serial) {
                        Ok(open) => {
                            *port = Some(open);
                            *link_lost = false;
                            *reconnect_at = None;
                            publish_connected(shared, config.serial);
                            Ok(())
                        }
                        Err(error) => {
                            let retry = keep_reconnecting && retryable_connection_error(&error);
                            publish_disconnected(shared, error.clone(), retry);
                            *reconnect_at = retry.then(|| Instant::now() + Duration::from_secs(1));
                            Err(error)
                        }
                    }
                }
            }
            Command::Disconnect => {
                mark_log_incomplete_if_pending(shared);
                publish_state(shared, ConnectionState::Disconnecting, None);
                *port = None;
                *reconnect_at = None;
                *link_lost = false;
                publish_state(shared, ConnectionState::Disconnected, None);
                Ok(())
            }
            Command::SendText { text, newline } => {
                send_final = true;
                send(
                    id,
                    serial::encode_text(&text, newline),
                    &text,
                    shared,
                    dir,
                    port,
                )
            }
            Command::SendHex { input } => {
                send_final = true;
                let bytes = serial::decode_hex(&input)?;
                send(id, bytes, &input, shared, dir, port)
            }
            Command::SendInput { input } => {
                send_final = true;
                let settings = shared
                    .state
                    .lock()
                    .map_err(lock_error)?
                    .snapshot
                    .config
                    .send
                    .clone();
                let prepared = if settings.hex {
                    serial::decode_hex(&input)
                } else if input
                    .len()
                    .saturating_add(newline_len(effective_newline(&settings)))
                    > 1_048_576
                {
                    Err(
                        CoreError::new(ErrorKind::InvalidArgument, "send exceeds 1 MiB")
                            .with_code(ErrorCode::SendTooLarge),
                    )
                } else {
                    Ok(serial::encode_text(&input, effective_newline(&settings)))
                };
                match prepared {
                    Ok(bytes) => send(id, bytes, &input, shared, dir, port),
                    Err(error) => {
                        publish_write_failed(shared, id, error.clone());
                        Err(error)
                    }
                }
            }
            Command::ClearLog => {
                if let Ok(mut state) = shared.state.lock() {
                    state.snapshot.rx_bytes = 0;
                    state.snapshot.tx_bytes = 0;
                    state.snapshot.last_rx_bytes = 0;
                    state.snapshot.rx_bytes_per_second = 0.0;
                    let delta = state.log.clear();
                    publish_simple_locked(&mut state, EventKind::LogChanged(delta));
                    publish_state_event_locked(&mut state);
                } else {
                    return Err(CoreError::new(
                        ErrorKind::Internal,
                        "core synchronization lock poisoned",
                    ));
                }
                Ok(())
            }
            Command::SetAutoReconnect(enabled) => {
                let mut config = snapshot_config(shared)?;
                config.serial.auto_reconnect = enabled;
                let retry =
                    enabled && port.is_none() && !config.serial.port_name.is_empty() && *link_lost;
                persist_update(shared, dir, config).map(|()| {
                    if !enabled {
                        *reconnect_at = None;
                        if let Ok(state) = shared.state.lock() {
                            if state.snapshot.connection == ConnectionState::Reconnecting {
                                let error = state.snapshot.error.clone();
                                drop(state);
                                publish_state(shared, ConnectionState::Disconnected, error);
                            }
                        }
                    } else if retry {
                        *reconnect_at = Some(Instant::now() + Duration::from_secs(1));
                        publish_state(shared, ConnectionState::Reconnecting, None);
                    }
                })
            }
            Command::SetAutoSend {
                enabled,
                interval_ms,
                input,
                hex,
                newline,
            } => {
                let mut config = snapshot_config(shared)?;
                config.send.auto_send_enabled = enabled;
                config.send.auto_send_interval_ms = interval_ms;
                config.send.hex = hex;
                config.send.append_newline = newline != Newline::None;
                if newline != Newline::None {
                    config.send.newline = newline;
                }
                config.validate()?;
                let auto_error = validate_auto_input(&config, &input);
                config.save(dir)?;
                update_config_with_input(shared, config, Some(input), auto_error.clone())?;
                *next_auto = Instant::now() + Duration::from_millis(interval_ms as u64);
                auto_error.map_or(Ok(()), Err)
            }
            Command::ExportLog { path, options } => {
                let bytes = match shared.state.lock().map_err(lock_error) {
                    Ok(state) => state.log.export(options),
                    Err(error) => return Err(error),
                };
                if bytes.is_empty() {
                    return Err(CoreError::new(
                        ErrorKind::InvalidArgument,
                        "no retained log records match the export options",
                    )
                    .with_code(ErrorCode::NoLogsToExport));
                }
                write_export_atomic(Path::new(&path), &bytes).map_err(|error| {
                    CoreError::new(ErrorKind::TaskFailed, format!("export log: {error}"))
                        .with_code(ErrorCode::ExportFailed)
                })
            }
        }
    })();
    match result {
        Ok(()) if !send_final => {
            publish_simple(shared, EventKind::CommandCompleted { request_id: id })
        }
        Ok(()) => {}
        Err(error) if send_final => {
            if error.kind == ErrorKind::Disconnected && port.is_some() {
                *port = None;
                *link_lost = true;
                let retry =
                    auto_reconnect_enabled(shared).expect("core worker state lock poisoned");
                publish_disconnected(shared, error.clone(), retry);
                *reconnect_at = retry.then(|| Instant::now() + Duration::from_secs(1));
            } else {
                publish_error_state(shared, error.clone());
            }
        }
        Err(error) => complete_failure(shared, id, error),
    }
}
fn apply_config(
    shared: &Shared,
    dir: &Path,
    config: AppConfig,
    auto_input: Option<String>,
    port: &mut Option<Box<dyn serialport::SerialPort>>,
    reconnect_at: &mut Option<Instant>,
    next_auto: &mut Instant,
    link_lost: &mut bool,
) -> Result<(), CoreError> {
    config.validate()?;
    let previous = snapshot_config(shared)?;
    let current_input = match auto_input.as_ref() {
        Some(input) => input.clone(),
        None => shared
            .state
            .lock()
            .map_err(lock_error)?
            .snapshot
            .auto_send_input
            .clone(),
    };
    let auto_error = validate_auto_input(&config, &current_input);
    if config != previous {
        config.save(dir)?;
    }
    update_config_with_input(shared, config.clone(), auto_input, auto_error.clone())?;
    if previous.send != config.send {
        *next_auto =
            Instant::now() + Duration::from_millis(config.send.auto_send_interval_ms as u64);
    }
    let transport_changed = previous.serial.port_name != config.serial.port_name
        || previous.serial.baud_rate != config.serial.baud_rate
        || previous.serial.data_bits != config.serial.data_bits
        || previous.serial.parity != config.serial.parity
        || previous.serial.stop_bits != config.serial.stop_bits
        || previous.serial.flow_control != config.serial.flow_control;
    if port.is_some() && transport_changed {
        publish_state(shared, ConnectionState::Reconfiguring, None);
        mark_log_incomplete_if_pending(shared);
        *port = None;
        *reconnect_at = None;
        if config.serial.port_name.is_empty() {
            *link_lost = false;
            publish_state(shared, ConnectionState::Disconnected, None);
            return auto_error.map_or(Ok(()), Err);
        }
        *link_lost = true;
        match serial::open(&config.serial) {
            Ok(open) => {
                *port = Some(open);
                *link_lost = false;
                publish_connected(shared, config.serial);
            }
            Err(error) => {
                let retry = config.serial.auto_reconnect && retryable_connection_error(&error);
                publish_disconnected(shared, error.clone(), retry);
                *reconnect_at = retry.then(|| Instant::now() + Duration::from_secs(1));
                return Err(error);
            }
        }
    } else if !config.serial.auto_reconnect || config.serial.port_name.is_empty() {
        *reconnect_at = None;
        if config.serial.port_name.is_empty() {
            *link_lost = false;
        }
        if let Ok(state) = shared.state.lock() {
            if state.snapshot.connection == ConnectionState::Reconnecting {
                let error = state.snapshot.error.clone();
                drop(state);
                publish_state(shared, ConnectionState::Disconnected, error);
            }
        }
    } else if *link_lost && port.is_none() && !config.serial.port_name.is_empty() {
        *reconnect_at = Some(Instant::now() + Duration::from_secs(1));
        publish_state(shared, ConnectionState::Reconnecting, None);
    }
    auto_error.map_or(Ok(()), Err)
}
fn validate_auto_input(config: &AppConfig, input: &str) -> Option<CoreError> {
    if config.send.hex {
        if input.len() > 2_097_152 {
            return Some(
                CoreError::new(ErrorKind::InvalidArgument, "send input exceeds 2 MiB")
                    .with_code(ErrorCode::SendInputTooLarge),
            );
        }
        serial::validate_hex(input).err()
    } else if input
        .len()
        .saturating_add(newline_len(effective_newline(&config.send)))
        > 1_048_576
    {
        Some(
            CoreError::new(ErrorKind::InvalidArgument, "auto-send input exceeds 1 MiB")
                .with_code(ErrorCode::AutoSendTooLarge),
        )
    } else {
        None
    }
}
fn newline_len(newline: Newline) -> usize {
    match newline {
        Newline::None => 0,
        Newline::Lf | Newline::Cr => 1,
        Newline::CrLf => 2,
    }
}
fn effective_newline(settings: &crate::SendSettings) -> Newline {
    if settings.append_newline {
        settings.newline
    } else {
        Newline::None
    }
}
fn validate_command(command: &Command) -> Result<(), CoreError> {
    match command {
        Command::SetConfig(c) => c.validate(),
        Command::SendText { text, newline }
            if text.len().saturating_add(newline_len(*newline)) > 1_048_576 =>
        {
            Err(
                CoreError::new(ErrorKind::InvalidArgument, "send exceeds 1 MiB")
                    .with_code(ErrorCode::SendTooLarge),
            )
        }
        Command::SendHex { input } | Command::SendInput { input } if input.len() > 2_097_152 => {
            Err(
                CoreError::new(ErrorKind::InvalidArgument, "send input exceeds 2 MiB")
                    .with_code(ErrorCode::SendInputTooLarge),
            )
        }
        Command::SendHex { input } => serial::validate_hex(input),
        Command::SetAutoSend { interval_ms, .. } if !(10..=60_000).contains(interval_ms) => {
            Err(CoreError::new(
                ErrorKind::InvalidArgument,
                "auto-send interval must be between 10 and 60000 milliseconds",
            )
            .with_code(ErrorCode::AutoSendIntervalInvalid))
        }
        Command::SetAutoSend {
            input, hex: true, ..
        } if input.len() > 2_097_152 => Err(CoreError::new(
            ErrorKind::InvalidArgument,
            "send input exceeds 2 MiB",
        )
        .with_code(ErrorCode::SendInputTooLarge)),
        Command::SetAutoSend {
            input,
            hex: false,
            newline,
            ..
        } if input.len().saturating_add(newline_len(*newline)) > 1_048_576 => Err(CoreError::new(
            ErrorKind::InvalidArgument,
            "auto-send input exceeds 1 MiB",
        )
        .with_code(ErrorCode::AutoSendTooLarge)),
        Command::SetAutoSend {
            input, hex: true, ..
        } => serial::validate_hex(input),
        Command::UpdateConfig(patch)
            if patch
                .auto_send_input
                .as_ref()
                .is_some_and(|input| input.len() > 2_097_152) =>
        {
            Err(
                CoreError::new(ErrorKind::InvalidArgument, "send input exceeds 2 MiB")
                    .with_code(ErrorCode::SendInputTooLarge),
            )
        }
        _ => Ok(()),
    }
}
fn send(
    id: RequestId,
    data: Vec<u8>,
    history: &str,
    shared: &Shared,
    dir: &Path,
    port: &mut Option<Box<dyn serialport::SerialPort>>,
) -> Result<(), CoreError> {
    if data.is_empty() {
        let error = CoreError::new(ErrorKind::InvalidArgument, "send data must not be empty")
            .with_code(ErrorCode::SendEmpty);
        publish_write_failed(shared, id, error.clone());
        return Err(error);
    }
    if data.len() > 1_048_576 {
        let e = CoreError::new(ErrorKind::InvalidArgument, "send exceeds 1 MiB")
            .with_code(ErrorCode::SendTooLarge);
        publish_write_failed(shared, id, e.clone());
        return Err(e);
    }
    let Some(open) = port.as_mut() else {
        let e = CoreError::new(ErrorKind::Disconnected, "serial port is not connected");
        publish_write_failed(shared, id, e.clone());
        return Err(e);
    };
    if let Err(error) = serial::write_all_accounted(open.as_mut(), &data) {
        if error.bytes_written > 0 {
            if let Err(logging_error) = record_tx(shared, &data[..error.bytes_written as usize]) {
                publish_simple(shared, EventKind::TaskFailed(logging_error));
            }
        }
        publish_write_failed(shared, id, error.clone());
        return Err(error);
    }
    let written = data.len();
    if let Err(error) = record_tx_with_total(shared, data, id) {
        let error = error.with_written(written as u64);
        publish_write_failed(shared, id, error.clone());
        return Err(error);
    }
    record_history(shared, dir, history);
    Ok(())
}
fn record_tx(shared: &Shared, data: &[u8]) -> Result<(), CoreError> {
    let mut state = shared.state.lock().map_err(lock_error)?;
    let delta = state.log.sent(data, timestamp_ms());
    state.snapshot.tx_bytes = state.snapshot.tx_bytes.saturating_add(data.len() as u64);
    publish_simple_locked(&mut state, EventKind::LogChanged(delta));
    Ok(())
}
fn record_tx_with_total(shared: &Shared, data: Vec<u8>, id: RequestId) -> Result<(), CoreError> {
    let mut state = shared.state.lock().map_err(lock_error)?;
    let delta = state.log.sent(&data, timestamp_ms());
    state.snapshot.tx_bytes = state.snapshot.tx_bytes.saturating_add(data.len() as u64);
    let tx_bytes = state.snapshot.tx_bytes;
    publish_simple_locked(
        &mut state,
        EventKind::DataSent {
            request_id: id,
            data,
            log: delta,
            tx_bytes,
        },
    );
    Ok(())
}
fn auto_send(
    shared: &Arc<Shared>,
    dir: &Path,
    port: &mut Option<Box<dyn serialport::SerialPort>>,
    next: &mut Instant,
    reconnect_at: &mut Option<Instant>,
    link_lost: &mut bool,
) {
    let (data, input, history_needed) = {
        let state = shared
            .state
            .lock()
            .expect("core worker state lock poisoned");
        if !state.snapshot.config.send.auto_send_enabled || Instant::now() < *next {
            return;
        }
        *next = Instant::now()
            + Duration::from_millis(state.snapshot.config.send.auto_send_interval_ms as u64);
        if port.is_none() {
            return;
        }
        let Some(payload) = &state.auto_payload else {
            return;
        };
        (
            payload.bytes.clone(),
            payload.input.clone(),
            !payload.history_attempted,
        )
    };
    let result = match port.as_mut() {
        Some(open) => serial::write_all_accounted(open.as_mut(), &data),
        None => return,
    };
    match result {
        Ok(()) => match record_tx_with_total(shared, data.to_vec(), 0) {
            Ok(()) => {
                if history_needed {
                    record_history(shared, dir, &input);
                    if let Some(payload) = shared
                        .state
                        .lock()
                        .expect("core worker state lock poisoned")
                        .auto_payload
                        .as_mut()
                    {
                        payload.history_attempted = true;
                    }
                }
            }
            Err(error) => publish_simple(shared, EventKind::TaskFailed(error)),
        },
        Err(error) => {
            if error.bytes_written > 0 {
                if let Err(logging_error) = record_tx(shared, &data[..error.bytes_written as usize])
                {
                    publish_simple(shared, EventKind::TaskFailed(logging_error));
                }
            }
            publish_simple(shared, EventKind::TaskFailed(error.clone()));
            if error.kind == ErrorKind::Disconnected {
                *port = None;
                *link_lost = true;
                let retry =
                    auto_reconnect_enabled(shared).expect("core worker state lock poisoned");
                publish_disconnected(shared, error, retry);
                *reconnect_at = retry.then(|| Instant::now() + Duration::from_secs(1));
            }
        }
    }
}
fn persist_update(shared: &Arc<Shared>, dir: &Path, cfg: AppConfig) -> Result<(), CoreError> {
    cfg.save(dir)?;
    update_config(shared, cfg)
}
fn snapshot_config(shared: &Shared) -> Result<AppConfig, CoreError> {
    shared
        .state
        .lock()
        .map(|s| s.snapshot.config.clone())
        .map_err(lock_error)
}
fn retryable_connection_error(error: &CoreError) -> bool {
    matches!(
        error.kind,
        ErrorKind::Disconnected
            | ErrorKind::ReadFailed
            | ErrorKind::PortNotFound
            | ErrorKind::OpenFailed
            | ErrorKind::PermissionDenied
    )
}
fn update_config(shared: &Shared, cfg: AppConfig) -> Result<(), CoreError> {
    let input = shared
        .state
        .lock()
        .map_err(lock_error)?
        .snapshot
        .auto_send_input
        .clone();
    let auto_error = validate_auto_input(&cfg, &input);
    update_config_with_input(shared, cfg, None, auto_error)
}
fn update_config_with_input(
    shared: &Shared,
    cfg: AppConfig,
    input: Option<String>,
    auto_error: Option<CoreError>,
) -> Result<(), CoreError> {
    let mut state = shared.state.lock().map_err(lock_error)?;
    let input_changed = input
        .as_ref()
        .is_some_and(|value| value != &state.snapshot.auto_send_input);
    let previous_auto_error = state.snapshot.auto_send_error.clone();
    let format_changed = cfg.send.hex != state.snapshot.config.send.hex
        || cfg.send.newline != state.snapshot.config.send.newline
        || cfg.send.append_newline != state.snapshot.config.send.append_newline;
    let history_changed = cfg.history != state.snapshot.config.history;
    let task_restarted = cfg.send.auto_send_enabled != state.snapshot.config.send.auto_send_enabled;
    let delta = state.log.set_capacity(cfg.log_capacity_bytes);
    state.snapshot.config = cfg;
    if let Some(input) = input {
        state.snapshot.auto_send_input = input;
    }
    state.snapshot.auto_send_error = auto_error.clone();
    if input_changed || format_changed || previous_auto_error != auto_error {
        state.auto_payload = if auto_error.is_none() && !state.snapshot.auto_send_input.is_empty() {
            let settings = &state.snapshot.config.send;
            let bytes = if settings.hex {
                serial::decode_hex(&state.snapshot.auto_send_input)
                    .expect("validated automatic input")
            } else {
                serial::encode_text(&state.snapshot.auto_send_input, effective_newline(settings))
            };
            if bytes.is_empty() {
                None
            } else {
                Some(AutoPayload {
                    bytes: bytes.into(),
                    input: Arc::from(state.snapshot.auto_send_input.as_str()),
                    history_attempted: false,
                })
            }
        } else {
            None
        };
    } else if history_changed || task_restarted {
        if let Some(payload) = state.auto_payload.as_mut() {
            payload.history_attempted = false;
        }
    }
    if !delta.removed_ids.is_empty() {
        publish_simple_locked(&mut state, EventKind::LogChanged(delta));
    }
    publish_state_event_locked(&mut state);
    if input_changed || previous_auto_error != auto_error {
        if let Some(error) = auto_error {
            publish_simple_locked(&mut state, EventKind::TaskFailed(error));
        }
    }
    Ok(())
}
fn update_ports(shared: &Shared, mut ports: Vec<String>) {
    ports.sort_unstable();
    ports.dedup();
    if let Ok(mut state) = shared.state.lock() {
        if state.snapshot.ports != ports {
            state.snapshot.ports = ports.clone();
            publish_simple_locked(&mut state, EventKind::PortsChanged(ports));
        }
    }
}
fn publish_state(shared: &Shared, connection: ConnectionState, error: Option<CoreError>) {
    if let Ok(mut s) = shared.state.lock() {
        if matches!(
            s.snapshot.connection,
            ConnectionState::Closing | ConnectionState::Closed
        ) && !matches!(
            connection,
            ConnectionState::Closing | ConnectionState::Closed
        ) {
            return;
        }
        s.snapshot.connection = connection;
        s.snapshot.error = error;
        if connection == ConnectionState::Connected {
            s.snapshot.connected_at_ms = Some(timestamp_ms());
            s.snapshot.applied_config = Some(s.snapshot.config.serial.clone());
        } else if connection == ConnectionState::Disconnected
            || connection == ConnectionState::Closed
        {
            s.snapshot.connected_at_ms = None;
            s.snapshot.applied_config = None;
        }
        publish_state_event_locked(&mut s);
    }
}
fn publish_connected(shared: &Shared, cfg: SerialConfig) {
    if let Ok(mut s) = shared.state.lock() {
        if s.snapshot.connection == ConnectionState::Closing
            || s.snapshot.connection == ConnectionState::Closed
        {
            return;
        }
        s.snapshot.connection = ConnectionState::Connected;
        s.snapshot.error = None;
        s.snapshot.connected_at_ms = Some(timestamp_ms());
        s.snapshot.applied_config = Some(cfg);
        publish_state_event_locked(&mut s);
    }
}
fn mark_log_incomplete_if_pending(shared: &Shared) {
    if let Ok(mut s) = shared.state.lock() {
        if let Some(delta) = s.log.mark_incomplete_if_pending() {
            publish_simple_locked(&mut s, EventKind::LogChanged(delta));
        }
    }
}
fn publish_disconnected(shared: &Shared, error: CoreError, reconnecting: bool) {
    if let Ok(mut s) = shared.state.lock() {
        if matches!(
            s.snapshot.connection,
            ConnectionState::Closing | ConnectionState::Closed
        ) {
            return;
        }
        let delta = if s.snapshot.applied_config.is_some() {
            Some(s.log.mark_incomplete())
        } else {
            s.log.mark_incomplete_if_pending()
        };
        if let Some(delta) = delta {
            publish_simple_locked(&mut s, EventKind::LogChanged(delta));
        }
        s.snapshot.connection = if reconnecting {
            ConnectionState::Reconnecting
        } else {
            ConnectionState::Disconnected
        };
        s.snapshot.error = Some(error.clone());
        s.snapshot.connected_at_ms = None;
        s.snapshot.applied_config = None;
        publish_state_event_locked(&mut s);
        publish_simple_locked(&mut s, EventKind::Disconnected(error));
    }
}
fn publish_received(shared: &Shared, data: &[u8]) {
    if let Ok(mut s) = shared.state.lock() {
        if s.snapshot.connection == ConnectionState::Closed {
            return;
        }
        let delta = s.log.receive(data, timestamp_ms());
        s.snapshot.rx_bytes = s.snapshot.rx_bytes.saturating_add(data.len() as u64);
        s.snapshot.last_rx_bytes = data.len() as u64;
        let rx = s.snapshot.rx_bytes;
        let last = s.snapshot.last_rx_bytes;
        publish_simple_locked(
            &mut s,
            EventKind::DataReceived {
                data: data.to_vec(),
                log: delta,
                rx_bytes: rx,
                last_rx_bytes: last,
            },
        );
    }
}
fn publish_write_failed(shared: &Shared, id: RequestId, error: CoreError) {
    publish_simple(
        shared,
        EventKind::WriteFailed {
            request_id: id,
            error,
        },
    );
}
fn publish_error_state(shared: &Shared, error: CoreError) {
    if let Ok(mut state) = shared.state.lock() {
        if matches!(
            state.snapshot.connection,
            ConnectionState::Closing | ConnectionState::Closed
        ) {
            return;
        }
        state.snapshot.error = Some(error);
        publish_state_event_locked(&mut state);
    }
}
fn app_state(snapshot: &AppSnapshot) -> AppState {
    AppState {
        sequence: snapshot.sequence,
        config: snapshot.config.clone(),
        connection: snapshot.connection,
        applied_config: snapshot.applied_config.clone(),
        connected_at_ms: snapshot.connected_at_ms,
        ports: snapshot.ports.clone(),
        rx_bytes: snapshot.rx_bytes,
        tx_bytes: snapshot.tx_bytes,
        last_rx_bytes: snapshot.last_rx_bytes,
        rx_bytes_per_second: snapshot.rx_bytes_per_second,
        error: snapshot.error.clone(),
        auto_send_error: snapshot.auto_send_error.clone(),
        auto_send_input: snapshot.auto_send_input.clone(),
    }
}
fn update_rx_rate(
    shared: &Shared,
    sampled_at: &mut Instant,
    sampled_bytes: &mut u64,
    sampled_connection: &mut ConnectionState,
) {
    let now = Instant::now();
    let Ok(mut state) = shared.state.lock() else {
        return;
    };
    let connection = state.snapshot.connection;
    let bytes = state.snapshot.rx_bytes;
    if connection != *sampled_connection || bytes < *sampled_bytes {
        *sampled_connection = connection;
        *sampled_bytes = bytes;
        *sampled_at = now;
        if state.snapshot.rx_bytes_per_second != 0.0 {
            state.snapshot.rx_bytes_per_second = 0.0;
            publish_state_event_locked(&mut state);
        }
        return;
    }
    let elapsed = now.duration_since(*sampled_at);
    if elapsed < Duration::from_secs(1) {
        return;
    }
    let rate = if connection == ConnectionState::Connected {
        bytes.saturating_sub(*sampled_bytes) as f64 / elapsed.as_secs_f64()
    } else {
        0.0
    };
    *sampled_at = now;
    *sampled_bytes = bytes;
    if state.snapshot.rx_bytes_per_second != rate {
        state.snapshot.rx_bytes_per_second = rate;
        publish_state_event_locked(&mut state);
    }
}
fn publish_state_event_locked(state: &mut State) {
    state.snapshot.sequence = state.snapshot.sequence.wrapping_add(1);
    let update = app_state(&state.snapshot);
    publish_to_subscribers_locked(
        state,
        Event {
            sequence: update.sequence,
            kind: EventKind::StateChanged(update),
        },
    );
}
fn publish_simple(shared: &Shared, kind: EventKind) {
    if let Ok(mut state) = shared.state.lock() {
        publish_simple_locked(&mut state, kind);
    }
}
fn publish_simple_locked(state: &mut State, kind: EventKind) {
    state.snapshot.sequence = state.snapshot.sequence.wrapping_add(1);
    publish_to_subscribers_locked(
        state,
        Event {
            sequence: state.snapshot.sequence,
            kind,
        },
    );
}
fn publish_to_subscribers_locked(state: &mut State, event: Event) {
    let weight = event_weight(&event);
    let mut remove = Vec::new();
    let mut event = Some(event);
    let mut subscribers = state.subscribers.iter().peekable();
    while let Some((id, sub)) = subscribers.next() {
        if sub.cancelled.load(Ordering::Acquire) {
            remove.push(*id);
            continue;
        }
        let reserved = sub
            .queued_bytes
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |used| {
                used.checked_add(weight)
                    .filter(|total| *total <= MAX_SUBSCRIBER_BYTES)
            });
        if reserved.is_err() {
            if let Ok(mut overflow) = sub.overflow.lock() {
                *overflow=Some(CoreError::new(ErrorKind::QueueOverflow,"event subscription exceeded its bounded queue; resubscribe to recover current state"));
            }
            sub.cancelled.store(true, Ordering::Release);
            remove.push(*id);
            continue;
        }
        let outgoing = if subscribers.peek().is_none() {
            event.take().expect("last subscriber owns the event")
        } else {
            event.as_ref().expect("event available for fanout").clone()
        };
        match sub.tx.try_send(outgoing) {
            Ok(()) => {}
            Err(TrySendError::Full(_)) => {
                sub.queued_bytes.fetch_sub(weight, Ordering::AcqRel);
                if let Ok(mut overflow) = sub.overflow.lock() {
                    *overflow = Some(CoreError::new(
                        ErrorKind::QueueOverflow,
                        "event subscription overflow; resubscribe to recover current state",
                    ));
                }
                sub.cancelled.store(true, Ordering::Release);
                remove.push(*id)
            }
            Err(TrySendError::Disconnected(_)) => {
                sub.queued_bytes.fetch_sub(weight, Ordering::AcqRel);
                remove.push(*id)
            }
        }
    }
    for id in remove {
        state.subscribers.remove(&id);
    }
}
fn auto_reconnect_enabled(shared: &Shared) -> Result<bool, CoreError> {
    shared
        .state
        .lock()
        .map(|state| state.snapshot.config.serial.auto_reconnect)
        .map_err(lock_error)
}
fn complete_failure(shared: &Shared, id: RequestId, error: CoreError) {
    if let Ok(mut state) = shared.state.lock() {
        state.snapshot.error = Some(error.clone());
        publish_state_event_locked(&mut state);
        publish_simple_locked(
            &mut state,
            EventKind::CommandFailed {
                request_id: id,
                error,
            },
        );
    }
}
fn record_history(shared: &Shared, dir: &Path, item: &str) {
    if item.is_empty() {
        return;
    }
    if item.len() > 1_048_576 {
        publish_simple(
            shared,
            EventKind::TaskFailed(
                CoreError::new(
                    ErrorKind::InvalidArgument,
                    "send history entry exceeds 1 MiB",
                )
                .with_code(ErrorCode::HistoryTooLarge),
            ),
        );
        return;
    }
    {
        let state = shared
            .state
            .lock()
            .expect("core worker state lock poisoned");
        if state
            .snapshot
            .config
            .history
            .last()
            .is_some_and(|last| last == item)
        {
            return;
        }
    }
    let mut config = match snapshot_config(shared) {
        Ok(config) => config,
        Err(error) => {
            publish_simple(shared, EventKind::TaskFailed(error));
            return;
        }
    };
    config.history.retain(|entry| entry != item);
    config.history.push(item.to_owned());
    while config.history.len() > 100
        || config.history.iter().map(String::len).sum::<usize>() > 1_048_576
    {
        config.history.remove(0);
    }
    match config.save(dir) {
        Ok(()) => {
            if let Err(error) = update_config(shared, config) {
                publish_simple(shared, EventKind::TaskFailed(error))
            }
        }
        Err(error) => publish_simple(shared, EventKind::TaskFailed(error)),
    }
}
static EXPORT_TEMP_ID: AtomicU64 = AtomicU64::new(0);

fn write_export_atomic(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let name = path.file_name().unwrap_or_default().to_string_lossy();
    let (temporary, mut file) = loop {
        let id = EXPORT_TEMP_ID.fetch_add(1, Ordering::Relaxed);
        let candidate = parent.join(format!(".{name}.{}.{}.tmp", std::process::id(), id));
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&candidate)
        {
            Ok(file) => break (candidate, file),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    };
    let result = file.write_all(bytes).and_then(|()| file.sync_all());
    drop(file);
    let result = result.and_then(|()| crate::config::replace_file(&temporary, path));
    if result.is_ok() {
        if let Ok(directory) = OpenOptions::new().read(true).open(parent) {
            let _ = directory.sync_all();
        }
    }
    if result.is_err() {
        let _ = fs::remove_file(temporary);
    }
    result
}

fn auto_wait(shared: &Shared, next: Instant, maximum: Duration) -> Duration {
    let state = shared
        .state
        .lock()
        .expect("core worker state lock poisoned");
    if state.snapshot.config.send.auto_send_enabled {
        maximum.min(next.saturating_duration_since(Instant::now()))
    } else {
        maximum
    }
}
