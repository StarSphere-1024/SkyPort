use serde::{Deserialize, Serialize};
use std::borrow::Cow;
use std::{collections::VecDeque, fmt::Write};

const MAX_PENDING_BYTES: usize = 256 * 1024;
const MAX_RECORDS: usize = 65_536;
const EXPORT_PREVIEW_BYTES: usize = 4096;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum Direction {
    Received,
    Sent,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct LogRecord {
    pub id: u64,
    pub timestamp_ms: i64,
    pub direction: Direction,
    pub data: Vec<u8>,
    pub pending: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct LogSnapshot {
    pub records: Vec<LogRecord>,
    pub total_bytes: u64,
    pub trimmed_bytes: u64,
    pub trimmed_records: u64,
    pub incomplete: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct LogDelta {
    pub upsert: Vec<LogRecord>,
    pub removed_ids: Vec<u64>,
    pub earliest_id: u64,
    pub total_bytes: u64,
    pub trimmed_bytes: u64,
    pub trimmed_records: u64,
    pub incomplete: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ExportOptions {
    pub show_sent: bool,
    pub hex: bool,
    pub timestamps: bool,
    pub strip_ansi: bool,
}

pub struct LogStore {
    records: VecDeque<LogRecord>,
    capacity: u64,
    total_bytes: u64,
    trimmed_bytes: u64,
    trimmed_records: u64,
    incomplete: bool,
    next_id: u64,
    pending_id: Option<u64>,
    pending_timestamp_ms: Option<i64>,
}

impl LogStore {
    pub fn new(capacity: u64) -> Self {
        Self {
            records: VecDeque::new(),
            capacity,
            total_bytes: 0,
            trimmed_bytes: 0,
            trimmed_records: 0,
            incomplete: false,
            next_id: 1,
            pending_id: None,
            pending_timestamp_ms: None,
        }
    }

    pub fn snapshot(&self) -> LogSnapshot {
        LogSnapshot {
            records: self.records.iter().cloned().collect(),
            total_bytes: self.total_bytes,
            trimmed_bytes: self.trimmed_bytes,
            trimmed_records: self.trimmed_records,
            incomplete: self.incomplete,
        }
    }

    pub fn receive(&mut self, data: &[u8], timestamp_ms: i64) -> LogDelta {
        let mut changed = Vec::new();
        let mut removed = Vec::new();
        let mut start = 0;
        for (index, byte) in data.iter().enumerate() {
            if *byte != b'\n' {
                continue;
            }
            self.append_pending(&data[start..index], timestamp_ms);
            // CRLF is one delimiter even when its bytes arrive in separate reads.
            if self.pending_last_byte() == Some(b'\r') {
                self.pop_pending_byte();
            }
            if let Some(id) = self.pending_id {
                removed.push(id);
            }
            changed.push(self.finish_pending(timestamp_ms));
            start = index + 1;
        }
        if start < data.len() {
            self.append_pending(&data[start..], timestamp_ms);
            if self.pending_len() > MAX_PENDING_BYTES {
                if let Some(id) = self.pending_id {
                    removed.push(id);
                }
                changed.push(self.finish_pending(timestamp_ms));
            } else if let Some(record) = self.pending_record() {
                changed.push(record);
            }
        }
        removed.extend(self.trim());
        self.delta(changed, removed)
    }

    pub fn sent(&mut self, data: &[u8], timestamp_ms: i64) -> LogDelta {
        let record = LogRecord {
            id: self.allocate_id(),
            timestamp_ms,
            direction: Direction::Sent,
            data: data.to_vec(),
            pending: false,
        };
        self.total_bytes = self.total_bytes.saturating_add(record.data.len() as u64);
        if self.pending_id.is_some() {
            let pending = self.records.pop_back().expect("pending record exists");
            self.records.push_back(record.clone());
            self.records.push_back(pending);
        } else {
            self.records.push_back(record.clone());
        }
        let removed = self.trim();
        self.delta(vec![record], removed)
    }

    pub fn clear(&mut self) -> LogDelta {
        let removed = self.records.iter().map(|record| record.id).collect();
        self.records.clear();
        self.total_bytes = 0;
        self.trimmed_bytes = 0;
        self.trimmed_records = 0;
        self.incomplete = false;
        self.pending_id = None;
        self.pending_timestamp_ms = None;
        self.delta(Vec::new(), removed)
    }

    pub fn set_capacity(&mut self, capacity: u64) -> LogDelta {
        self.capacity = capacity;
        let removed = self.trim();
        self.delta(Vec::new(), removed)
    }

    pub fn mark_incomplete(&mut self) -> LogDelta {
        self.incomplete = true;
        self.delta(Vec::new(), Vec::new())
    }
    pub(crate) fn mark_incomplete_if_pending(&mut self) -> Option<LogDelta> {
        self.pending_id.map(|_| self.mark_incomplete())
    }

    pub fn export(&self, options: ExportOptions) -> Vec<u8> {
        let mut output = Vec::new();
        for record in &self.records {
            if record.direction == Direction::Sent && !options.show_sent {
                continue;
            }
            let truncated = record.data.len() > EXPORT_PREVIEW_BYTES;
            let data = &record.data[..record.data.len().min(EXPORT_PREVIEW_BYTES)];
            let content = if options.hex {
                let mut value = String::with_capacity(data.len().saturating_mul(3));
                for (i, byte) in data.iter().enumerate() {
                    if i > 0 {
                        value.push(' ');
                    }
                    let _ = write!(value, "{byte:02X}");
                }
                Cow::Owned(value)
            } else {
                let value = String::from_utf8_lossy(data);
                if options.strip_ansi {
                    Cow::Owned(strip_ansi(&value))
                } else {
                    value
                }
            };
            let timestamp = if options.timestamps {
                format!("{} ", local_timestamp(record.timestamp_ms))
            } else {
                String::new()
            };
            let mut lines = content.split('\n').peekable();
            let mut first = true;
            while let Some(line) = lines.next() {
                if first {
                    first = false;
                    output.extend_from_slice(timestamp.as_bytes());
                    if options.show_sent {
                        let marker = match record.direction {
                            Direction::Sent => "TX > ",
                            Direction::Received => "RX < ",
                        };
                        output.extend_from_slice(marker.as_bytes());
                    }
                }
                output.extend_from_slice(line.as_bytes());
                if truncated && lines.peek().is_none() {
                    output.extend_from_slice(b" ... [TRUNCATED]");
                }
                output.push(b'\n');
            }
        }
        output
    }

    fn append_pending(&mut self, bytes: &[u8], timestamp_ms: i64) {
        if bytes.is_empty() {
            return;
        }
        let id = *self.pending_id.get_or_insert(u64::MAX);
        let timestamp = *self.pending_timestamp_ms.get_or_insert(timestamp_ms);
        if let Some(record) = self.records.back_mut().filter(|r| r.id == id) {
            record.data.extend_from_slice(bytes);
        } else {
            self.records.push_back(LogRecord {
                id,
                timestamp_ms: timestamp,
                direction: Direction::Received,
                data: bytes.to_vec(),
                pending: true,
            });
        }
        self.total_bytes = self.total_bytes.saturating_add(bytes.len() as u64);
    }
    fn pending_last_byte(&self) -> Option<u8> {
        self.records
            .back()
            .filter(|r| r.pending)
            .and_then(|r| r.data.last().copied())
    }
    fn pending_len(&self) -> usize {
        self.records
            .back()
            .filter(|r| r.pending)
            .map_or(0, |r| r.data.len())
    }
    fn pop_pending_byte(&mut self) {
        if let Some(record) = self.records.back_mut().filter(|r| r.pending) {
            if record.data.pop().is_some() {
                self.total_bytes = self.total_bytes.saturating_sub(1);
            }
        }
    }
    fn pending_record(&self) -> Option<LogRecord> {
        self.records.back().filter(|r| r.pending).cloned()
    }
    fn finish_pending(&mut self, timestamp_ms: i64) -> LogRecord {
        if let Some(id) = self.pending_id.take() {
            let mut record = self.records.pop_back().expect("pending record exists");
            debug_assert_eq!(record.id, id);
            record.id = self.allocate_id();
            record.pending = false;
            self.pending_timestamp_ms = None;
            self.records.push_back(record.clone());
            record
        } else {
            let record = LogRecord {
                id: self.allocate_id(),
                timestamp_ms,
                direction: Direction::Received,
                data: Vec::new(),
                pending: false,
            };
            self.records.push_back(record.clone());
            record
        }
    }
    fn allocate_id(&mut self) -> u64 {
        let id = self.next_id;
        self.next_id = self.next_id.saturating_add(1);
        id
    }

    fn trim(&mut self) -> Vec<u64> {
        let mut removed = Vec::new();
        while !self.records.is_empty()
            && (self.total_bytes > self.capacity || self.records.len() > MAX_RECORDS)
        {
            let record = self.records.pop_front().unwrap();
            self.total_bytes = self.total_bytes.saturating_sub(record.data.len() as u64);
            self.trimmed_bytes = self.trimmed_bytes.saturating_add(record.data.len() as u64);
            self.trimmed_records = self.trimmed_records.saturating_add(1);
            removed.push(record.id);
            if self.pending_id == Some(record.id) {
                self.pending_id = None;
                self.pending_timestamp_ms = None;
            }
        }
        removed
    }
    fn delta(&self, mut upsert: Vec<LogRecord>, mut removed_ids: Vec<u64>) -> LogDelta {
        if !removed_ids.is_empty() {
            removed_ids.sort_unstable();
            upsert.retain(|record| {
                (record.id == u64::MAX && self.pending_id == Some(u64::MAX))
                    || removed_ids.binary_search(&record.id).is_err()
            });
        }
        let earliest_id = self
            .records
            .front()
            .filter(|r| !r.pending)
            .map_or(self.next_id, |r| r.id);
        LogDelta {
            upsert,
            removed_ids,
            earliest_id,
            total_bytes: self.total_bytes,
            trimmed_bytes: self.trimmed_bytes,
            trimmed_records: self.trimmed_records,
            incomplete: self.incomplete,
        }
    }
}

fn local_timestamp(timestamp_ms: i64) -> String {
    let seconds = timestamp_ms.div_euclid(1000) as libc::time_t;
    let millis = timestamp_ms.rem_euclid(1000);
    let Some(local) = local_time(&seconds) else {
        return format!("00:00:00.{millis:03}");
    };
    format!(
        "{:02}:{:02}:{:02}.{millis:03}",
        local.tm_hour, local.tm_min, local.tm_sec
    )
}

#[cfg(unix)]
fn local_time(seconds: &libc::time_t) -> Option<libc::tm> {
    let mut local = std::mem::MaybeUninit::<libc::tm>::uninit();
    let result = unsafe { libc::localtime_r(seconds, local.as_mut_ptr()) };
    if result.is_null() {
        None
    } else {
        Some(unsafe { local.assume_init() })
    }
}

#[cfg(windows)]
fn local_time(seconds: &libc::time_t) -> Option<libc::tm> {
    let mut local = std::mem::MaybeUninit::<libc::tm>::uninit();
    if unsafe { libc::localtime_s(local.as_mut_ptr(), seconds) } != 0 {
        return None;
    }
    Some(unsafe { local.assume_init() })
}

fn strip_ansi(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut output = String::with_capacity(text.len());
    let mut start = 0;
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] != 0x1b {
            i += 1;
            continue;
        }
        output.push_str(&text[start..i]);
        i += 1;
        if i == bytes.len() {
            start = i;
            break;
        }
        match bytes[i] {
            b'[' => {
                i += 1;
                while i < bytes.len() {
                    let byte = bytes[i];
                    i += 1;
                    if (0x40..=0x7e).contains(&byte) {
                        break;
                    }
                }
            }
            b']' => {
                i += 1;
                while i < bytes.len() {
                    if bytes[i] == 0x07 {
                        i += 1;
                        break;
                    }
                    if bytes[i] == 0x1b && bytes.get(i + 1) == Some(&b'\\') {
                        i += 2;
                        break;
                    }
                    i += 1;
                }
            }
            _ => {}
        }
        start = i;
    }
    output.push_str(&text[start..]);
    output
}
