use skyport_core::{AppConfig, Direction, ErrorKind, ExportOptions, LegacyConfig, LogStore};
use std::fs;
use tempfile::tempdir;

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
