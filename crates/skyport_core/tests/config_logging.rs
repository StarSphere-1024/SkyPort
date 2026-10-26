use skyport_core::{
    AppConfig, AppCore, AppOptions, Command, ConfigPatch, Direction, ErrorKind, EventKind,
    ExportOptions, FlowControl, LegacyConfig, LogStore,
};
use std::{fs, time::Duration};
use tempfile::tempdir;

#[test]
fn input_capacity_errors_are_distinct_from_payload_capacity_errors() {
    use skyport_core::{ErrorCode, Newline};

    let dir = tempdir().unwrap();
    let core = AppCore::create(AppOptions {
        data_directory: dir.path().into(),
        ..AppOptions::default()
    })
    .unwrap();
    // 700,000 decoded bytes fit the payload limit; spaces exceed the input limit.
    let input = "AA ".repeat(700_000);
    for command in [
        Command::SendHex {
            input: input.clone(),
        },
        Command::SendInput {
            input: input.clone(),
        },
        Command::SetAutoSend {
            enabled: true,
            interval_ms: 100,
            input: input.clone(),
            hex: true,
            newline: Newline::None,
        },
        Command::UpdateConfig(ConfigPatch {
            hex_send: Some(true),
            auto_send_input: Some(input),
            ..ConfigPatch::default()
        }),
    ] {
        let error = core.dispatch(command).unwrap_err();
        assert_eq!(error.kind, ErrorKind::InvalidArgument);
        assert_eq!(error.code, Some(ErrorCode::SendInputTooLarge));
    }
    let text = "a".repeat(1_048_577);
    for (command, expected) in [
        (
            Command::SendText {
                text: text.clone(),
                newline: Newline::None,
            },
            ErrorCode::SendTooLarge,
        ),
        (
            Command::SetAutoSend {
                enabled: true,
                interval_ms: 100,
                input: text,
                hex: false,
                newline: Newline::None,
            },
            ErrorCode::AutoSendTooLarge,
        ),
    ] {
        assert_eq!(core.dispatch(command).unwrap_err().code, Some(expected));
    }
    core.close().unwrap();
}

#[test]
fn legacy_config_is_saved_before_load_acknowledges_it() {
    let dir = tempdir().unwrap();
    let legacy = LegacyConfig {
        port_name: Some("/dev/ttyUSB0".into()),
        history: Some(vec!["hello".into()]),
        ..LegacyConfig::default()
    };
    let mut expected = AppConfig::default();
    expected.serial.port_name = "/dev/ttyUSB0".into();
    expected.history = vec!["hello".into()];

    let loaded = AppConfig::load(dir.path(), Some(legacy)).unwrap();
    assert_eq!(loaded, expected);
    assert_eq!(
        serde_json::from_slice::<AppConfig>(&fs::read(dir.path().join("config.json")).unwrap())
            .unwrap(),
        expected
    );
}
#[test]
fn config_save_atomically_replaces_an_existing_file() {
    let dir = tempdir().unwrap();
    let mut config = AppConfig::default();
    config.save(dir.path()).unwrap();
    config.serial.baud_rate = 115_200;
    config.save(dir.path()).unwrap();
    assert_eq!(AppConfig::load(dir.path(), None).unwrap(), config);
    assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
}

#[test]
fn invalid_legacy_and_persisted_configs_are_errors_not_defaults() {
    let dir = tempdir().unwrap();
    let invalid = LegacyConfig {
        baud_rate: Some(0),
        ..LegacyConfig::default()
    };
    assert_eq!(
        AppConfig::load(dir.path(), Some(invalid)).unwrap_err().kind,
        ErrorKind::InvalidArgument
    );
    assert!(!dir.path().join("config.json").exists());

    fs::write(dir.path().join("config.json"), br#"{"version":2}"#).unwrap();
    assert_eq!(
        AppConfig::load(dir.path(), Some(LegacyConfig::default()))
            .unwrap_err()
            .kind,
        ErrorKind::InvalidArgument
    );
    assert_eq!(
        fs::read(dir.path().join("config.json")).unwrap(),
        br#"{"version":2}"#
    );
    let malformed = b"{not valid json";
    fs::write(dir.path().join("config.json"), malformed).unwrap();
    assert_eq!(
        AppConfig::load(dir.path(), Some(LegacyConfig::default()))
            .unwrap_err()
            .kind,
        ErrorKind::InvalidArgument
    );
    assert_eq!(fs::read(dir.path().join("config.json")).unwrap(), malformed);

    fs::write(
        dir.path().join("config.json"),
        vec![b' '; 8 * 1024 * 1024 + 1],
    )
    .unwrap();
    assert_eq!(
        AppConfig::load(dir.path(), None).unwrap_err().kind,
        ErrorKind::InvalidArgument
    );

    let mut oversized_history = AppConfig::default();
    oversized_history.history.push("x".repeat(1024 * 1024 + 1));
    assert_eq!(
        oversized_history.validate().unwrap_err().kind,
        ErrorKind::InvalidArgument
    );
    let mut invalid_interval = AppConfig::default();
    invalid_interval.send.auto_send_interval_ms = 9;
    assert_eq!(
        invalid_interval.validate().unwrap_err().kind,
        ErrorKind::InvalidArgument
    );
    let mut invalid_port = AppConfig::default();
    invalid_port.serial.port_name = "tty\nport".into();
    assert_eq!(
        invalid_port.validate().unwrap_err().kind,
        ErrorKind::InvalidArgument
    );
}
#[test]
fn persisted_config_wins_over_invalid_legacy_and_raw_enums_are_rejected() {
    let dir = tempdir().unwrap();
    let mut persisted = AppConfig::default();
    persisted.serial.port_name = "saved".into();
    persisted.save(dir.path()).unwrap();
    let invalid = LegacyConfig {
        parity: Some(99),
        ..LegacyConfig::default()
    };
    assert_eq!(
        AppConfig::load(dir.path(), Some(invalid)).unwrap(),
        persisted
    );

    let dir = tempdir().unwrap();
    let invalid = LegacyConfig {
        parity: Some(99),
        ..LegacyConfig::default()
    };
    assert_eq!(
        AppConfig::load(dir.path(), Some(invalid)).unwrap_err().kind,
        ErrorKind::InvalidArgument
    );
    let invalid = LegacyConfig {
        append_newline: Some(true),
        newline_mode: Some(99),
        ..LegacyConfig::default()
    };
    assert_eq!(
        AppConfig::load(dir.path(), Some(invalid)).unwrap_err().kind,
        ErrorKind::InvalidArgument
    );
    assert!(!dir.path().join("config.json").exists());
}

#[test]
fn flow_control_updates_persist_through_appcore_restart() {
    let dir = tempdir().unwrap();
    let mut core = AppCore::create(AppOptions {
        data_directory: dir.path().into(),
        ..AppOptions::default()
    })
    .unwrap();

    for mode in [
        FlowControl::Hardware,
        FlowControl::Software,
        FlowControl::None,
    ] {
        let (_, events) = core.subscribe().unwrap();
        let request_id = core
            .dispatch(Command::UpdateConfig(ConfigPatch {
                flow_control: Some(mode),
                baud_rate: (mode == FlowControl::Hardware).then_some(115_200),
                hex_send: (mode == FlowControl::Hardware).then_some(true),
                ..ConfigPatch::default()
            }))
            .unwrap();
        loop {
            match events.recv_timeout(Duration::from_secs(3)).unwrap() {
                Some(event) => match event.kind {
                    EventKind::CommandCompleted {
                        request_id: completed,
                    } if completed == request_id => {
                        break;
                    }
                    EventKind::CommandFailed {
                        request_id: failed,
                        error,
                    } if failed == request_id => panic!("config update failed: {error:?}"),
                    _ => {}
                },
                None => panic!("config update did not complete"),
            }
        }

        let expected = core.snapshot().unwrap().config;
        assert_eq!(expected.serial.flow_control, mode);
        assert_eq!(expected.serial.baud_rate, 115_200);
        assert!(expected.send.hex);
        let saved: serde_json::Value =
            serde_json::from_slice(&fs::read(dir.path().join("config.json")).unwrap()).unwrap();
        assert_eq!(saved["serial"]["flow_control"], format!("{mode:?}"));
        assert!(saved["serial"].get("hardware_flow_control").is_none());
        assert_eq!(
            serde_json::from_value::<AppConfig>(saved).unwrap(),
            expected
        );

        core.close().unwrap();
        core = AppCore::create(AppOptions {
            data_directory: dir.path().into(),
            ..AppOptions::default()
        })
        .unwrap();
        assert_eq!(core.snapshot().unwrap().config, expected);
        assert_eq!(core.snapshot().unwrap().config.serial.flow_control, mode);
    }
    core.close().unwrap();
}

#[test]
fn flow_control_update_is_not_applied_when_atomic_save_fails() {
    let dir = tempdir().unwrap();
    let core = AppCore::create(AppOptions {
        data_directory: dir.path().into(),
        ..AppOptions::default()
    })
    .unwrap();
    fs::remove_file(dir.path().join("config.json")).unwrap();
    fs::create_dir(dir.path().join("config.json")).unwrap();
    let (_, events) = core.subscribe().unwrap();
    let request_id = core
        .dispatch(Command::UpdateConfig(ConfigPatch {
            flow_control: Some(FlowControl::Hardware),
            ..ConfigPatch::default()
        }))
        .unwrap();

    loop {
        match events.recv_timeout(Duration::from_secs(3)).unwrap() {
            Some(event) => match event.kind {
                EventKind::CommandFailed {
                    request_id: failed,
                    error,
                } if failed == request_id => {
                    assert_eq!(error.code, Some(skyport_core::ErrorCode::ConfigIo));
                    break;
                }
                EventKind::CommandCompleted {
                    request_id: completed,
                } if completed == request_id => {
                    panic!("failed config save was applied")
                }
                _ => {}
            },
            None => panic!("config update did not fail"),
        }
    }

    assert_eq!(
        core.snapshot().unwrap().config.serial.flow_control,
        FlowControl::None
    );
    core.close().unwrap();
}

#[test]
fn receive_rows_keep_completion_order_across_send_and_split_crlf() {
    let mut log = LogStore::new(1024);
    let pending = log.receive(b"part", 10);
    assert_eq!(pending.upsert[0].timestamp_ms, 10);
    assert!(pending.upsert[0].pending);
    let sent = log.sent(b"tx", 20);
    assert_eq!(sent.upsert[0].direction, Direction::Sent);
    assert_eq!(sent.upsert[0].id, log.snapshot().records[0].id);
    assert_eq!(
        log.snapshot()
            .records
            .iter()
            .map(|r| r.direction)
            .collect::<Vec<_>>(),
        vec![Direction::Sent, Direction::Received]
    );

    log.receive(b"\r", 30);
    let completed = log.receive(b"\n", 40);
    assert_eq!(completed.removed_ids, vec![u64::MAX]);
    assert_eq!(completed.upsert[0].data, b"part");
    assert_eq!(completed.upsert[0].timestamp_ms, 10);
    assert!(completed.upsert[0].id > sent.upsert[0].id);
    assert_eq!(
        log.snapshot()
            .records
            .iter()
            .map(|r| (r.direction, r.data.as_slice()))
            .collect::<Vec<_>>(),
        vec![
            (Direction::Sent, b"tx".as_slice()),
            (Direction::Received, b"part".as_slice())
        ]
    );
    assert_eq!(completed.upsert[0], log.snapshot().records[1]);

    let empty_rows = log.receive(b"\n\n", 50);
    assert_eq!(empty_rows.upsert.len(), 2);
    assert!(empty_rows
        .upsert
        .iter()
        .all(|row| row.data.is_empty() && !row.pending));
}
#[test]
fn delta_replaces_pending_after_completion_while_tx_precedes_it() {
    let mut log = LogStore::new(1024);
    log.receive(b"old", 10);
    log.sent(b"tx", 20);
    let mut cache = log.snapshot().records;
    let delta = log.receive(b"\npart", 30);
    assert_eq!(delta.removed_ids, vec![u64::MAX]);
    assert!(delta
        .upsert
        .iter()
        .any(|record| record.id == u64::MAX && record.pending));
    cache.retain(|record| !delta.removed_ids.contains(&record.id));
    cache.retain(|record| record.id == u64::MAX || record.id >= delta.earliest_id);
    for record in delta.upsert {
        if let Some(existing) = cache.iter_mut().find(|existing| existing.id == record.id) {
            *existing = record;
        } else {
            cache.push(record);
        }
    }
    cache.sort_by_key(|record| record.id);
    assert_eq!(cache, log.snapshot().records);
}

#[test]
fn empty_rows_are_record_bounded_and_byte_trimming_is_visible() {
    let mut log = LogStore::new(0);
    let delta = log.receive(&vec![b'\n'; 65_537], 1);
    let snapshot = log.snapshot();
    assert_eq!(snapshot.records.len(), 65_536);
    assert_eq!(snapshot.total_bytes, 0);
    assert_eq!(snapshot.trimmed_records, 1);
    assert_eq!(delta.earliest_id, 2);

    let mut log = LogStore::new(8);
    log.sent(b"abcd", 1);
    let trimmed = log.set_capacity(2);
    assert_eq!(trimmed.removed_ids.len(), 1);
    assert_eq!(trimmed.trimmed_bytes, 4);
    assert_eq!(trimmed.trimmed_records, 1);
    let incomplete = log.mark_incomplete();
    assert!(incomplete.incomplete);
    assert!(log.snapshot().incomplete);
    let cleared = log.clear();
    assert!(cleared.upsert.is_empty());
    assert_eq!(cleared.total_bytes, 0);
    assert_eq!(cleared.trimmed_bytes, 0);
    assert_eq!(cleared.trimmed_records, 0);
    assert!(!cleared.incomplete);
}

#[test]
fn export_replaces_invalid_utf8_strips_ansi_and_formats_hex() {
    let mut log = LogStore::new(1024);
    log.sent(b"\xff\x1b[31mred\x1b[0m", 0);
    let text = String::from_utf8(log.export(ExportOptions {
        show_sent: true,
        hex: false,
        timestamps: false,
        strip_ansi: true,
    }))
    .unwrap();
    assert_eq!(text, "TX > �red\n");
    let hex = String::from_utf8(log.export(ExportOptions {
        show_sent: true,
        hex: true,
        timestamps: false,
        strip_ansi: true,
    }))
    .unwrap();
    assert_eq!(hex, "TX > FF 1B 5B 33 31 6D 72 65 64 1B 5B 30 6D\n");
}
#[test]
fn export_without_sent_markers_preserves_utf8_after_unknown_escape() {
    let mut log = LogStore::new(1024);
    log.receive("\u{1b}汉\n".as_bytes(), 0);
    let exported = log.export(ExportOptions {
        show_sent: false,
        hex: false,
        timestamps: false,
        strip_ansi: true,
    });
    assert_eq!(String::from_utf8(exported).unwrap(), "汉\n");
}
