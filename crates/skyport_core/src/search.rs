use crate::{logging::StoredRecord, serial, CoreError, ErrorCode, ErrorKind};
use memchr::memmem::Finder;
use std::{
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Condvar, Mutex, Weak,
    },
    thread::{self, JoinHandle},
};

const VIEW_UNITS: u64 = 4096;
const SCAN_CHUNK: usize = 4096;
const MAX_QUERY_BYTES: usize = 64 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SearchOptions {
    pub hex: bool,
    pub case_sensitive: bool,
    pub show_sent: bool,
    pub strip_ansi: bool,
}
#[derive(Clone, Debug)]
pub struct SearchProgress {
    pub total_matches: u64,
    pub complete: bool,
    pub cancelled: bool,
    pub error: Option<CoreError>,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SearchHit {
    pub record_id: u64,
    pub timestamp_ms: i64,
    pub source_length: u64,
    pub index: u64,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SearchSnapshotInfo {
    pub sequence: u64,
    pub first_record_id: Option<u64>,
    pub last_record_id: Option<u64>,
    pub pending: Option<SearchHit>,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SearchRange {
    pub start: u32,
    pub end: u32,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SearchSeek {
    pub hit: Option<SearchHit>,
    pub pending: bool,
    pub wrapped: bool,
}
#[derive(Clone, Debug)]
pub struct SearchRecordView {
    pub record_id: u64,
    pub timestamp_ms: i64,
    pub source_length: u64,
    pub start_offset: u64,
    pub text: String,
    pub ranges: Vec<SearchRange>,
    pub focus_range: Option<SearchRange>,
    pub leading_clipped: bool,
    pub trailing_clipped: bool,
}

pub(crate) struct PreparedSearch {
    options: SearchOptions,
    pattern: Pattern,
}
enum Pattern {
    Hex {
        bytes: Vec<u8>,
        prefix: Vec<usize>,
    },
    Text {
        chars: Vec<char>,
        prefix: Vec<usize>,
        finder: Finder<'static>,
        units: u64,
        ascii: bool,
    },
}
impl PreparedSearch {
    pub(crate) fn new(query: String, options: SearchOptions) -> Result<Self, CoreError> {
        if query.len() > MAX_QUERY_BYTES {
            return Err(CoreError::new(
                ErrorKind::InvalidArgument,
                "search query exceeds 64 KiB of UTF-8",
            )
            .with_code(ErrorCode::SearchQueryTooLarge));
        }
        let pattern = if options.hex {
            let bytes = serial::decode_hex(&query)?;
            let prefix = prefix_table(&bytes);
            Pattern::Hex { bytes, prefix }
        } else {
            // Unicode scalar lowercase, deliberately not normalization or full casefold.
            let chars: Vec<char> = if options.case_sensitive {
                query.chars().collect()
            } else {
                query.chars().flat_map(char::to_lowercase).collect()
            };
            let prefix = prefix_table(&chars);
            let ascii = chars.iter().all(char::is_ascii);
            let finder = if options.case_sensitive {
                Finder::new(query.as_bytes()).into_owned()
            } else if ascii {
                let lower: Vec<u8> = chars.iter().map(|ch| *ch as u8).collect();
                Finder::new(&lower).into_owned()
            } else {
                Finder::new(b"").into_owned()
            };
            let units = chars.iter().map(|ch| ch.len_utf16() as u64).sum();
            Pattern::Text {
                chars,
                prefix,
                finder,
                units,
                ascii,
            }
        };
        Ok(Self { options, pattern })
    }
}
fn prefix_table<T: Eq>(pattern: &[T]) -> Vec<usize> {
    let mut table = vec![0; pattern.len()];
    let mut matched = 0;
    for index in 1..pattern.len() {
        while matched > 0 && pattern[index] != pattern[matched] {
            matched = table[matched - 1];
        }
        if pattern[index] == pattern[matched] {
            matched += 1;
        }
        table[index] = matched;
    }
    table
}

struct SessionData {
    records: Vec<StoredRecord>,
    prepared: PreparedSearch,
}
#[derive(Clone, Copy)]
struct RecordCount {
    record: usize,
    first: u64,
    count: u64,
}
#[derive(Default)]
struct Index {
    records: Vec<RecordCount>,
    total: u64,
    completed_records: usize,
    complete: bool,
    error: Option<CoreError>,
}
struct SessionInner {
    snapshot: SearchSnapshotInfo,
    cancelled: AtomicBool,
    data: Mutex<Option<Arc<SessionData>>>,
    index: Mutex<Index>,
    // On-demand scans never hold the application state or progress mutex. Serialize
    // them to bound query-sized scratch storage even with concurrent bridge calls.
    lookup: Mutex<()>,
}

/// An immutable retained-log snapshot. At most one session is retained by each core.
/// Cancellation drops its payload ownership; already running lookups stop cooperatively.
#[derive(Clone)]
pub struct SearchSession {
    inner: Arc<SessionInner>,
}
impl SearchSession {
    pub fn snapshot_info(&self) -> SearchSnapshotInfo {
        self.inner.snapshot
    }
    pub fn poll(&self) -> SearchProgress {
        let index = self.inner.index.lock().unwrap_or_else(|e| e.into_inner());
        let cancelled = self.inner.cancelled.load(Ordering::Acquire);
        SearchProgress {
            total_matches: index.total,
            complete: index.complete || cancelled,
            cancelled,
            error: index.error.clone(),
        }
    }
    pub fn cancel(&self) {
        cancel(&self.inner);
    }
    pub fn search_match(&self, rank: u64) -> Result<Option<SearchHit>, CoreError> {
        let Some(data) = self.data() else {
            return Ok(None);
        };
        let index = self.inner.index.lock().map_err(lock_error)?;
        let Some(count) = find_rank(&index, rank) else {
            return Ok(None);
        };
        let record = &data.records[count.record];
        let hit = SearchHit {
            record_id: record.id,
            timestamp_ms: record.timestamp_ms,
            source_length: record.data.len() as u64,
            index: rank,
        };
        if self.inner.cancelled.load(Ordering::Acquire) {
            return Ok(None);
        }
        Ok(Some(hit))
    }
    pub fn search_seek(
        &self,
        record_id: u64,
        offset: u64,
        backwards: bool,
    ) -> Result<SearchSeek, CoreError> {
        let _lookup = self.inner.lookup.lock().map_err(lock_error)?;
        let empty = SearchSeek {
            hit: None,
            pending: false,
            wrapped: false,
        };
        let Some(data) = self.data() else {
            return Ok(empty);
        };
        let anchor = data.records.partition_point(|record| record.id < record_id);
        let exact = data
            .records
            .get(anchor)
            .is_some_and(|record| record.id == record_id);
        let index = self.inner.index.lock().map_err(lock_error)?;
        if self.inner.cancelled.load(Ordering::Acquire) {
            return Ok(empty);
        }
        if anchor > index.completed_records || exact && anchor >= index.completed_records {
            return Ok(SearchSeek {
                pending: true,
                ..empty
            });
        }
        let first = index
            .records
            .get(anchor)
            .map_or(index.total, |count| count.first);
        let count = if exact {
            index.records[anchor].count
        } else {
            0
        };
        drop(index);
        let mut before = 0;
        if count > 0 {
            scan(
                &data.records[anchor],
                &data.prepared,
                &self.inner.cancelled,
                true,
                |span| {
                    if span.start >= offset {
                        return false;
                    }
                    before += 1;
                    true
                },
                |_| {},
            );
        }
        let insertion = first.saturating_add(before);
        let index = self.inner.index.lock().map_err(lock_error)?;
        if self.inner.cancelled.load(Ordering::Acquire) {
            return Ok(empty);
        }
        let candidate = if backwards {
            insertion.checked_sub(1)
        } else {
            (insertion < index.total).then_some(insertion)
        };
        let (rank, wrapped) = if let Some(rank) = candidate {
            (rank, false)
        } else if index.completed_records < data.records.len() {
            return Ok(SearchSeek {
                pending: true,
                ..empty
            });
        } else if index.total == 0 {
            return Ok(empty);
        } else {
            (if backwards { index.total - 1 } else { 0 }, true)
        };
        let Some(count) = find_rank(&index, rank) else {
            return Ok(empty);
        };
        let record = &data.records[count.record];
        Ok(SearchSeek {
            hit: Some(SearchHit {
                record_id: record.id,
                timestamp_ms: record.timestamp_ms,
                source_length: record.data.len() as u64,
                index: rank,
            }),
            pending: false,
            wrapped,
        })
    }
    pub fn search_record(
        &self,
        record_id: u64,
        focus_index: Option<u64>,
    ) -> Result<Option<SearchRecordView>, CoreError> {
        let _lookup = self.inner.lookup.lock().map_err(lock_error)?;
        let Some(data) = self.data() else {
            return Ok(None);
        };
        let Ok(record_index) = data.records.binary_search_by_key(&record_id, |r| r.id) else {
            return Ok(None);
        };
        let record = &data.records[record_index];
        let focus_rank = if let Some(rank) = focus_index {
            let index = self.inner.index.lock().map_err(lock_error)?;
            let Some(count) = find_rank(&index, rank).filter(|c| c.record == record_index) else {
                return Ok(None);
            };
            Some(rank - count.first)
        } else {
            None
        };
        let mut focus = None;
        if let Some(rank) = focus_rank {
            let mut local = 0;
            scan(
                record,
                &data.prepared,
                &self.inner.cancelled,
                true,
                |span| {
                    if local == rank {
                        focus = Some(span);
                        return false;
                    }
                    local += 1;
                    true
                },
                |_| {},
            );
        }
        if self.inner.cancelled.load(Ordering::Acquire) {
            return Ok(None);
        }
        let desired_start = focus.map_or(0, |s: Span| s.start.saturating_sub(VIEW_UNITS / 4));
        let (text, start, end, trailing_clipped) = snippet(
            record,
            data.prepared.options,
            desired_start,
            &self.inner.cancelled,
        );
        let mut ranges = Vec::new();
        let mut focus_range = None;
        let mut local = 0;
        scan(
            record,
            &data.prepared,
            &self.inner.cancelled,
            true,
            |span| {
                if span.start >= end {
                    return false;
                }
                if span.end > start {
                    let range = SearchRange {
                        start: span.start.saturating_sub(start) as u32,
                        end: (span.end.min(end) - start) as u32,
                    };
                    // Several lowercase expansion tokens can refer to one source scalar.
                    // The scanner consumes that scalar on a match, so ranges never overlap.
                    ranges.push(range);
                    if focus_rank == Some(local) {
                        focus_range = Some(range)
                    }
                }
                local += 1;
                true
            },
            |_| {},
        );
        if self.inner.cancelled.load(Ordering::Acquire) {
            return Ok(None);
        }
        Ok(Some(SearchRecordView {
            record_id: record.id,
            timestamp_ms: record.timestamp_ms,
            source_length: record.data.len() as u64,
            start_offset: start,
            text,
            ranges,
            focus_range,
            leading_clipped: start > 0,
            trailing_clipped,
        }))
    }
    fn data(&self) -> Option<Arc<SessionData>> {
        if self.inner.cancelled.load(Ordering::Acquire) {
            return None;
        }
        self.inner
            .data
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
    }
}
fn find_rank(index: &Index, rank: u64) -> Option<RecordCount> {
    if rank >= index.total {
        return None;
    }
    let position = index
        .records
        .partition_point(|c| c.first.saturating_add(c.count) <= rank);
    index.records.get(position).copied()
}
fn cancel(session: &SessionInner) {
    session.cancelled.store(true, Ordering::Release);
    session
        .data
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .take();
    let mut index = session.index.lock().unwrap_or_else(|e| e.into_inner());
    index.records = Vec::new();
    index.total = 0;
    index.completed_records = 0;
    index.complete = true;
}
fn lock_error<T>(_: T) -> CoreError {
    CoreError::new(ErrorKind::Internal, "search synchronization lock poisoned")
}
struct WorkerState {
    pending: Option<Arc<SessionInner>>,
    active: Weak<SessionInner>,
    closed: bool,
}
struct WorkerShared {
    state: Mutex<WorkerState>,
    wake: Condvar,
}
pub(crate) struct SearchWorker {
    shared: Arc<WorkerShared>,
    join: Mutex<Option<JoinHandle<()>>>,
}
impl SearchWorker {
    pub(crate) fn new() -> Result<Self, CoreError> {
        let shared = Arc::new(WorkerShared {
            state: Mutex::new(WorkerState {
                pending: None,
                active: Weak::new(),
                closed: false,
            }),
            wake: Condvar::new(),
        });
        let worker_shared = shared.clone();
        let join = thread::Builder::new()
            .name("skyport-search".into())
            .spawn(move || loop {
                let session = {
                    let mut state = worker_shared
                        .state
                        .lock()
                        .unwrap_or_else(|e| e.into_inner());
                    while state.pending.is_none() && !state.closed {
                        state = worker_shared
                            .wake
                            .wait(state)
                            .unwrap_or_else(|e| e.into_inner());
                    }
                    if state.closed {
                        break;
                    }
                    state.pending.take().expect("search work is pending")
                };
                let result =
                    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| run_scan(&session)));
                if result.is_err() && !session.cancelled.load(Ordering::Acquire) {
                    let mut index = session.index.lock().unwrap_or_else(|e| e.into_inner());
                    index.error = Some(CoreError::new(
                        ErrorKind::TaskFailed,
                        "search worker panicked",
                    ));
                    index.complete = true;
                    session
                        .data
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .take();
                }
            })
            .map_err(|e| {
                CoreError::new(ErrorKind::Internal, format!("start search worker: {e}"))
            })?;
        Ok(Self {
            shared,
            join: Mutex::new(Some(join)),
        })
    }
    pub(crate) fn submit(
        &self,
        records: Vec<StoredRecord>,
        prepared: PreparedSearch,
        sequence: u64,
    ) -> SearchSession {
        let pending = records.last().filter(|record| record.id == u64::MAX);
        let finalized_len = records.len() - usize::from(pending.is_some());
        let finalized = &records[..finalized_len];
        let snapshot = SearchSnapshotInfo {
            sequence,
            first_record_id: finalized.first().map(|record| record.id),
            last_record_id: finalized.last().map(|record| record.id),
            pending: pending.map(|record| SearchHit {
                record_id: record.id,
                timestamp_ms: record.timestamp_ms,
                source_length: record.data.len() as u64,
                index: 0,
            }),
        };
        let session = SearchSession {
            inner: Arc::new(SessionInner {
                snapshot,
                cancelled: AtomicBool::new(false),
                data: Mutex::new(Some(Arc::new(SessionData { records, prepared }))),
                index: Mutex::new(Index::default()),
                lookup: Mutex::new(()),
            }),
        };
        let mut state = self.shared.state.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(old) = state.active.upgrade() {
            cancel(&old)
        }
        if let Some(old) = state.pending.take() {
            cancel(&old)
        }
        if state.closed {
            cancel(&session.inner);
        } else {
            state.active = Arc::downgrade(&session.inner);
            state.pending = Some(session.inner.clone());
            self.shared.wake.notify_one();
        }
        session
    }
    pub(crate) fn close(&self) -> Result<(), CoreError> {
        {
            let mut state = self.shared.state.lock().map_err(lock_error)?;
            state.closed = true;
            if let Some(active) = state.active.upgrade() {
                cancel(&active)
            }
            if let Some(pending) = state.pending.take() {
                cancel(&pending)
            }
            self.shared.wake.notify_one();
        }
        if let Some(join) = self.join.lock().map_err(lock_error)?.take() {
            join.join()
                .map_err(|_| CoreError::new(ErrorKind::TaskFailed, "search worker panicked"))?;
        }
        Ok(())
    }
}
impl Drop for SearchWorker {
    fn drop(&mut self) {
        let _ = self.close();
    }
}
fn run_scan(session: &Arc<SessionInner>) {
    let Some(data) = session
        .data
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .clone()
    else {
        return;
    };
    for (record_index, record) in data.records.iter().enumerate() {
        if session.cancelled.load(Ordering::Acquire) {
            return;
        }
        let first = {
            let mut index = session.index.lock().unwrap_or_else(|e| e.into_inner());
            if session.cancelled.load(Ordering::Acquire) {
                return;
            }
            let first = index.total;
            index.records.push(RecordCount {
                record: record_index,
                first,
                count: 0,
            });
            first
        };
        let count = std::cell::Cell::new(0u64);
        let publish = |_: usize| {
            let mut index = session.index.lock().unwrap_or_else(|e| e.into_inner());
            if session.cancelled.load(Ordering::Acquire) {
                return;
            }
            let count = count.get();
            if let Some(last) = index.records.last_mut() {
                last.count = count
            }
            index.total = first.saturating_add(count);
        };
        scan(
            record,
            &data.prepared,
            &session.cancelled,
            false,
            |_| {
                count.set(count.get().saturating_add(1));
                true
            },
            publish,
        );
        publish(0);
        let mut index = session.index.lock().unwrap_or_else(|e| e.into_inner());
        index.completed_records = record_index + 1;
    }
    let mut index = session.index.lock().unwrap_or_else(|e| e.into_inner());
    index.complete = true;
}

#[derive(Clone, Copy, Debug)]
struct Span {
    start: u64,
    end: u64,
}
fn advance<T: Eq>(value: T, pattern: &[T], prefix: &[usize], matched: &mut usize) -> bool {
    while *matched > 0 && value != pattern[*matched] {
        *matched = prefix[*matched - 1]
    }
    if value == pattern[*matched] {
        *matched += 1
    }
    if *matched == pattern.len() {
        *matched = 0; // Literal, nonoverlapping matches.
        true
    } else {
        false
    }
}
fn scan(
    record: &StoredRecord,
    prepared: &PreparedSearch,
    cancelled: &AtomicBool,
    positions: bool,
    mut hit: impl FnMut(Span) -> bool,
    mut progress: impl FnMut(usize),
) {
    let mut matched = 0;
    match &prepared.pattern {
        Pattern::Hex {
            bytes: pattern,
            prefix,
        } => {
            if pattern.is_empty() {
                return;
            }
            for (index, byte) in record.data.iter().enumerate() {
                if index % SCAN_CHUNK == 0 {
                    if cancelled.load(Ordering::Acquire) {
                        return;
                    }
                    progress(index);
                }
                if advance(*byte, pattern, prefix, &mut matched) {
                    let start = index + 1 - pattern.len();
                    if !hit(Span {
                        start: start as u64 * 3,
                        end: (index as u64 + 1) * 3 - 1,
                    }) {
                        return;
                    }
                }
            }
        }
        Pattern::Text {
            chars: pattern,
            prefix,
            finder,
            units,
            ascii,
        } => {
            if pattern.is_empty() {
                return;
            }
            if finder.needle().len() <= SCAN_CHUNK && (prepared.options.case_sensitive || *ascii) {
                if let Some(text) = raw_text(
                    &record.data,
                    prepared.options.strip_ansi,
                    !prepared.options.case_sensitive,
                    cancelled,
                ) {
                    scan_fast(
                        text,
                        finder,
                        *units,
                        !prepared.options.case_sensitive,
                        positions,
                        cancelled,
                        hit,
                        progress,
                    );
                    return;
                }
                if cancelled.load(Ordering::Acquire) {
                    return;
                }
            }
            let mut starts = if positions {
                vec![0; pattern.len()]
            } else {
                Vec::new()
            };
            let mut token = 0usize;
            let mut last_progress = 0;
            let mut chars = Canonical::new(&record.data, prepared.options.strip_ansi, cancelled);
            while let Some((ch, span)) = chars.next() {
                if chars.offset.saturating_sub(last_progress) >= SCAN_CHUNK {
                    progress(chars.offset);
                    last_progress = chars.offset;
                }
                if prepared.options.case_sensitive {
                    if positions {
                        starts[token % pattern.len()] = span.start
                    }
                    token += 1;
                    if advance(ch, pattern, prefix, &mut matched) {
                        let start = if positions {
                            starts[(token - pattern.len()) % pattern.len()]
                        } else {
                            0
                        };
                        if !hit(Span {
                            start,
                            end: span.end,
                        }) {
                            return;
                        }
                    }
                } else {
                    for lower in ch.to_lowercase() {
                        if positions {
                            starts[token % pattern.len()] = span.start
                        }
                        token += 1;
                        if advance(lower, pattern, prefix, &mut matched) {
                            let start = if positions {
                                starts[(token - pattern.len()) % pattern.len()]
                            } else {
                                0
                            };
                            if !hit(Span {
                                start,
                                end: span.end,
                            }) {
                                return;
                            }
                            // Do not emit two overlapping source ranges for an expanded scalar.
                            break;
                        }
                    }
                }
            }
        }
    }
}

// Validate in bounded chunks so a very long row cannot defer cancellation.
// Borrow the original UTF8 when there is no transformation, rather than allocating
// a lowercase/ANSI-free row or a full UTF16 offset map.
fn raw_text<'a>(
    bytes: &'a [u8],
    strip_ansi: bool,
    ascii_only: bool,
    cancelled: &AtomicBool,
) -> Option<&'a str> {
    let mut offset = 0;
    while offset < bytes.len() {
        if cancelled.load(Ordering::Acquire) {
            return None;
        }
        let end = (offset + SCAN_CHUNK).min(bytes.len());
        let chunk = &bytes[offset..end];
        if strip_ansi && memchr::memchr(0x1b, chunk).is_some() {
            return None;
        }
        if ascii_only {
            if !chunk.is_ascii() {
                return None;
            }
            offset = end;
        } else {
            match std::str::from_utf8(chunk) {
                Ok(_) => offset = end,
                Err(error) if error.error_len().is_none() && end < bytes.len() => {
                    offset += error.valid_up_to();
                }
                Err(_) => return None,
            }
        }
    }
    // Every byte has been validated, including code points split by chunk edges.
    Some(unsafe { std::str::from_utf8_unchecked(bytes) })
}
fn scan_fast(
    text: &str,
    finder: &Finder<'_>,
    query_units: u64,
    lowercase_ascii: bool,
    positions: bool,
    cancelled: &AtomicBool,
    mut hit: impl FnMut(Span) -> bool,
    mut progress: impl FnMut(usize),
) {
    let bytes = text.as_bytes();
    let length = finder.needle().len();
    let mut cursor = 0;
    let mut mapped_byte = 0;
    let mut mapped_units = 0;
    // The lowercase fast path uses bounded stack scratch, never a row-sized copy.
    let mut scratch = if lowercase_ascii {
        Some([0u8; SCAN_CHUNK * 2])
    } else {
        None
    };
    while cursor < bytes.len() {
        if cancelled.load(Ordering::Acquire) {
            return;
        }
        let base = cursor;
        let limit = (base + SCAN_CHUNK).min(bytes.len());
        let end = (limit + length - 1).min(bytes.len());
        let window = if let Some(scratch) = scratch.as_mut() {
            for (out, byte) in scratch.iter_mut().zip(&bytes[base..end]) {
                *out = byte.to_ascii_lowercase();
            }
            &scratch[..end - base]
        } else {
            &bytes[base..end]
        };
        loop {
            let Some(found) = finder.find(&window[cursor - base..]) else {
                cursor = limit;
                break;
            };
            let start = cursor + found;
            if start >= limit {
                cursor = limit;
                break;
            }
            cursor = start + length;
            let span = if positions {
                let units = if lowercase_ascii {
                    start as u64
                } else {
                    mapped_units + text[mapped_byte..start].encode_utf16().count() as u64
                };
                mapped_byte = cursor;
                mapped_units = units + query_units;
                Span {
                    start: units,
                    end: units + query_units,
                }
            } else {
                Span { start: 0, end: 0 }
            };
            if !hit(span) {
                return;
            }
            if cursor >= limit {
                break;
            }
        }
        progress(cursor);
    }
}

// Streaming String::from_utf8_lossy semantics, without allocating canonical rows.
// ANSI controls are consumed before decoding; CSI, OSC, DCS/SOS/PM/APC strings,
// and ordinary ESC Fe/intermediate controls are hidden, including incomplete tails.
struct Canonical<'a> {
    bytes: &'a [u8],
    offset: usize,
    units: u64,
    strip_ansi: bool,
    cancelled: &'a AtomicBool,
}
impl<'a> Canonical<'a> {
    fn new(bytes: &'a [u8], strip_ansi: bool, cancelled: &'a AtomicBool) -> Self {
        Self {
            bytes,
            offset: 0,
            units: 0,
            strip_ansi,
            cancelled,
        }
    }
    fn next(&mut self) -> Option<(char, Span)> {
        loop {
            if self.offset >= self.bytes.len() || self.cancelled.load(Ordering::Acquire) {
                return None;
            }
            if self.strip_ansi && self.bytes[self.offset] == 0x1b {
                self.escape();
                continue;
            }
            let lead = self.bytes[self.offset];
            let width = match lead {
                0..=0x7f => 1,
                0xc2..=0xdf => 2,
                0xe0..=0xef => 3,
                0xf0..=0xf4 => 4,
                _ => 1,
            };
            let end = self.offset.saturating_add(width).min(self.bytes.len());
            let (ch, consumed) = match std::str::from_utf8(&self.bytes[self.offset..end]) {
                Ok(text) => (text.chars().next().expect("nonempty scalar"), width),
                Err(error) => ('\u{fffd}', error.error_len().unwrap_or(end - self.offset)),
            };
            self.offset += consumed;
            let start = self.units;
            self.units += ch.len_utf16() as u64;
            return Some((
                ch,
                Span {
                    start,
                    end: self.units,
                },
            ));
        }
    }
    fn escape(&mut self) {
        self.offset += 1;
        let Some(&kind) = self.bytes.get(self.offset) else {
            return;
        };
        self.offset += 1;
        match kind {
            b'[' => {
                while let Some(&byte) = self.bytes.get(self.offset) {
                    if self.cancelled.load(Ordering::Acquire) {
                        return;
                    }
                    self.offset += 1;
                    if (0x40..=0x7e).contains(&byte) {
                        break;
                    }
                }
            }
            b']' | b'P' | b'X' | b'^' | b'_' => {
                while let Some(&byte) = self.bytes.get(self.offset) {
                    if self.cancelled.load(Ordering::Acquire) {
                        return;
                    }
                    self.offset += 1;
                    if kind == b']' && byte == 7 {
                        break;
                    }
                    if byte == 0x1b && self.bytes.get(self.offset) == Some(&b'\\') {
                        self.offset += 1;
                        break;
                    }
                }
            }
            0x20..=0x2f => {
                while let Some(&byte) = self.bytes.get(self.offset) {
                    if self.cancelled.load(Ordering::Acquire) {
                        return;
                    }
                    self.offset += 1;
                    if !(0x20..=0x2f).contains(&byte) {
                        break;
                    }
                }
            }
            0x30..=0x7e => {}
            _ => {
                self.offset -= 1;
            }
        }
    }
}
fn snippet(
    record: &StoredRecord,
    options: SearchOptions,
    desired_start: u64,
    cancelled: &AtomicBool,
) -> (String, u64, u64, bool) {
    let mut text = String::with_capacity(VIEW_UNITS as usize);
    if options.hex {
        const HEX: &[u8] = b"0123456789ABCDEF";
        let first_byte = (desired_start / 3) as usize;
        let start = first_byte as u64 * 3;
        let mut end = start;
        for index in first_byte..record.data.len() {
            if cancelled.load(Ordering::Acquire) {
                break;
            }
            let needed = if index == first_byte { 2 } else { 3 };
            if end - start + needed > VIEW_UNITS {
                break;
            }
            if index > first_byte {
                text.push(if index % 32 == 0 { '\n' } else { ' ' })
            }
            let byte = record.data[index];
            text.push(HEX[(byte >> 4) as usize] as char);
            text.push(HEX[(byte & 15) as usize] as char);
            end += needed;
        }
        let total = (record.data.len() as u64)
            .saturating_mul(3)
            .saturating_sub(1);
        return (text, start, end, end < total);
    }
    let mut chars = Canonical::new(&record.data, options.strip_ansi, cancelled);
    let mut start = 0;
    let mut end = 0;
    let mut began = false;
    while let Some((ch, span)) = chars.next() {
        if span.end <= desired_start {
            continue;
        }
        if !began {
            start = span.start;
            end = start;
            began = true
        }
        if span.end - start > VIEW_UNITS {
            return (text, start, end, true);
        }
        text.push(ch);
        end = span.end;
    }
    (text, start, end, false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{AppCore, AppOptions, ErrorCode, LogStore};
    use std::time::{Duration, Instant};

    fn options() -> SearchOptions {
        SearchOptions {
            hex: false,
            case_sensitive: true,
            show_sent: true,
            strip_ansi: false,
        }
    }
    fn wait_until(mut condition: impl FnMut() -> bool) {
        let deadline = Instant::now() + Duration::from_secs(5);
        while !condition() {
            assert!(Instant::now() < deadline, "search did not settle");
            thread::sleep(Duration::from_millis(1));
        }
    }
    fn start(
        store: &LogStore,
        query: &str,
        options: SearchOptions,
    ) -> (SearchWorker, SearchSession) {
        let worker = SearchWorker::new().unwrap();
        let session = worker.submit(
            store.search_snapshot(options.show_sent),
            PreparedSearch::new(query.into(), options).unwrap(),
            0,
        );
        wait_until(|| session.poll().complete);
        assert!(session.poll().error.is_none());
        (worker, session)
    }
    fn first_view(session: &SearchSession) -> SearchRecordView {
        let hit = session.search_match(0).unwrap().unwrap();
        session
            .search_record(hit.record_id, Some(0))
            .unwrap()
            .unwrap()
    }
    #[test]
    fn seek_uses_canonical_offsets_and_wraps_within_records() {
        let mut store = LogStore::new(1024);
        store.sent("a😀x😀z\nplain".as_bytes(), 1);
        let (_worker, session) = start(&store, "😀", options());
        let record_id = session.search_match(0).unwrap().unwrap().record_id;
        assert_eq!(
            session
                .search_seek(record_id, 1, false)
                .unwrap()
                .hit
                .unwrap()
                .index,
            0
        );
        assert_eq!(
            session
                .search_seek(record_id, 2, false)
                .unwrap()
                .hit
                .unwrap()
                .index,
            1
        );
        assert_eq!(
            session
                .search_seek(record_id, 4, true)
                .unwrap()
                .hit
                .unwrap()
                .index,
            0
        );
        let wrapped = session.search_seek(record_id, 5, false).unwrap();
        assert!(wrapped.wrapped);
        assert_eq!(wrapped.hit.unwrap().index, 0);
        let wrapped_back = session.search_seek(record_id, 1, true).unwrap();
        assert!(wrapped_back.wrapped);
        assert_eq!(wrapped_back.hit.unwrap().index, 1);
    }

    #[test]
    fn seek_respects_hex_and_stripped_ansi_canonical_positions() {
        let mut store = LogStore::new(1024);
        store.sent(&[0xab, 0xcd], 1);
        let hex = SearchOptions {
            hex: true,
            ..options()
        };
        let (_worker, session) = start(&store, "CD", hex);
        let record_id = session.search_match(0).unwrap().unwrap().record_id;
        assert_eq!(
            session
                .search_seek(record_id, 3, false)
                .unwrap()
                .hit
                .unwrap()
                .index,
            0
        );

        store.sent(b"a\x1b[31mx", 2);
        let ansi = SearchOptions {
            strip_ansi: true,
            ..options()
        };
        let (_worker, session) = start(&store, "x", ansi);
        let record_id = session.search_match(0).unwrap().unwrap().record_id;
        let view = session.search_record(record_id, Some(0)).unwrap().unwrap();
        assert_eq!(view.start_offset + view.ranges[0].start as u64, 1);
        assert_eq!(
            session
                .search_seek(record_id, 1, false)
                .unwrap()
                .hit
                .unwrap()
                .index,
            0
        );
    }

    #[test]
    fn seek_locates_neighbors_when_the_reading_record_is_filtered_or_outside_snapshot() {
        let mut store = LogStore::new(1024);
        store.receive(b"hit\n", 1);
        store.sent(b"hidden", 2);
        store.receive(b"hit\n", 3);
        let hidden = store.search_snapshot(true)[1].id;
        let (_worker, session) = start(
            &store,
            "hit",
            SearchOptions {
                show_sent: false,
                ..options()
            },
        );
        assert_eq!(
            session
                .search_seek(hidden, 0, false)
                .unwrap()
                .hit
                .unwrap()
                .index,
            1
        );
        assert_eq!(
            session
                .search_seek(hidden, 0, true)
                .unwrap()
                .hit
                .unwrap()
                .index,
            0
        );
        let from_start = session.search_seek(0, 0, false).unwrap();
        assert_eq!(from_start.hit.unwrap().index, 0);
        assert!(!from_start.wrapped);
        let from_end = session.search_seek(u64::MAX, u64::MAX, true).unwrap();
        assert_eq!(from_end.hit.unwrap().index, 1);
        assert!(!from_end.wrapped);
    }

    #[test]
    fn seek_waits_for_unindexed_frontier_and_stops_after_cancel() {
        let mut store = LogStore::new(1024);
        store.sent(b"hit", 1);
        store.sent(b"hit", 2);
        let records = store.search_snapshot(true);
        let session = SearchSession {
            inner: Arc::new(SessionInner {
                snapshot: SearchSnapshotInfo {
                    sequence: 0,
                    first_record_id: Some(records[0].id),
                    last_record_id: Some(records[0].id),
                    pending: None,
                },
                cancelled: AtomicBool::new(false),
                data: Mutex::new(Some(Arc::new(SessionData {
                    records,
                    prepared: PreparedSearch::new("hit".into(), options()).unwrap(),
                }))),
                index: Mutex::new(Index::default()),
                lookup: Mutex::new(()),
            }),
        };
        assert_eq!(
            session.search_seek(1, 0, false).unwrap(),
            SearchSeek {
                hit: None,
                pending: true,
                wrapped: false
            }
        );
        {
            let mut index = session.inner.index.lock().unwrap();
            index.records.push(RecordCount {
                record: 0,
                first: 0,
                count: 1,
            });
            index.total = 1;
            index.completed_records = 1;
        }
        assert!(session.search_seek(2, 0, true).unwrap().pending);
        assert!(session.search_seek(1, 0, true).unwrap().pending);
        assert_eq!(
            session.search_seek(0, 0, false).unwrap().hit.unwrap().index,
            0
        );
        session.cancel();
        assert_eq!(
            session.search_seek(1, 0, false).unwrap(),
            SearchSeek {
                hit: None,
                pending: false,
                wrapped: false
            }
        );
    }

    #[test]
    fn literals_are_nonoverlapping_case_sensitive_and_record_local() {
        let mut store = LogStore::new(1024);
        store.receive(b"aaaa\n aa\nAaaa\na\na\n", 7);
        let (_worker, session) = start(&store, "aa", options());
        assert_eq!(session.poll().total_matches, 4);
        let hit0 = session.search_match(0).unwrap().unwrap();
        let hit1 = session.search_match(1).unwrap().unwrap();
        let hit2 = session.search_match(2).unwrap().unwrap();
        assert_eq!(hit0.record_id, hit1.record_id);
        assert_ne!(hit0.record_id, hit2.record_id);
        assert_eq!(
            first_view(&session).ranges,
            vec![
                SearchRange { start: 0, end: 2 },
                SearchRange { start: 2, end: 4 },
            ]
        );
        assert!(session.search_match(4).unwrap().is_none());
        assert!(session
            .search_record(hit2.record_id, Some(0))
            .unwrap()
            .is_none());
        let (_worker, spaces) = start(&store, " ", options());
        assert_eq!(spaces.poll().total_matches, 1);
    }

    #[test]
    fn sent_filter_and_snapshot_ignore_later_appends_and_mutation() {
        let mut store = LogStore::new(1024);
        store.receive(b"same\npending", 10);
        store.sent(b"same", 11);
        let opts = SearchOptions {
            show_sent: false,
            ..options()
        };
        let (_worker, session) = start(&store, "same", opts);
        assert_eq!(session.poll().total_matches, 1);
        store.receive(b"same\nsame\n", 12);
        assert_eq!(session.poll().total_matches, 1);
        let view = first_view(&session);
        assert_eq!(view.text, "same");
        let (_worker, all) = start(&store, "same", options());
        assert_eq!(all.poll().total_matches, 4);
    }

    #[test]
    fn snapshots_share_history_and_pending_is_copy_on_write() {
        let mut store = LogStore::new(1024);
        store.receive(b"closed\npending", 100);
        let first = store.search_snapshot(true);
        let second = store.search_snapshot(true);
        assert!(Arc::ptr_eq(&first[0].data, &second[0].data));
        assert!(Arc::ptr_eq(&first[1].data, &second[1].data));
        assert_eq!(first[1].id, u64::MAX);
        store.receive(b"more", 101);
        let third = store.search_snapshot(true);
        assert!(Arc::ptr_eq(&first[0].data, &third[0].data));
        assert!(!Arc::ptr_eq(&first[1].data, &third[1].data));
        assert_eq!(first[1].data.as_slice(), b"pending");
        assert_eq!(third[1].data.as_slice(), b"pendingmore");
        assert_eq!(first[1].timestamp_ms, third[1].timestamp_ms);
    }

    #[test]
    fn snapshot_metadata_uses_filtered_finalized_boundaries_and_original_pending() {
        let mut store = LogStore::new(1024);
        store.sent(b"leading", 1);
        store.receive(b"line\npending", 2);
        store.sent(b"trailing", 3);
        let worker = SearchWorker::new().unwrap();
        let all = worker.submit(
            store.search_snapshot(true),
            PreparedSearch::new("absent".into(), options()).unwrap(),
            41,
        );
        let pending = Some(SearchHit {
            record_id: u64::MAX,
            timestamp_ms: 2,
            source_length: 7,
            index: 0,
        });
        assert_eq!(
            all.snapshot_info(),
            SearchSnapshotInfo {
                sequence: 41,
                first_record_id: Some(1),
                last_record_id: Some(3),
                pending,
            }
        );
        let received_only = SearchOptions {
            show_sent: false,
            ..options()
        };
        let filtered = worker.submit(
            store.search_snapshot(false),
            PreparedSearch::new("absent".into(), received_only).unwrap(),
            42,
        );
        let captured = SearchSnapshotInfo {
            sequence: 42,
            first_record_id: Some(2),
            last_record_id: Some(2),
            pending,
        };
        assert_eq!(filtered.snapshot_info(), captured);
        assert!(all.poll().cancelled);
        assert_eq!(all.snapshot_info().sequence, 41);
        store.receive(b" extended\nnew", 4);
        store.clear();
        filtered.cancel();
        assert!(filtered.inner.data.lock().unwrap().is_none());
        assert_eq!(filtered.snapshot_info(), captured);
        worker.close().unwrap();
        assert_eq!(filtered.snapshot_info(), captured);
    }

    #[test]
    fn empty_and_pending_only_snapshots_have_no_finalized_boundaries() {
        let mut store = LogStore::new(1024);
        let received_only = SearchOptions {
            show_sent: false,
            ..options()
        };
        for sent in [false, true] {
            if sent {
                store.sent(b"excluded", 1);
            }
            let (_worker, session) = start(&store, "absent", received_only);
            assert_eq!(
                session.snapshot_info(),
                SearchSnapshotInfo {
                    sequence: 0,
                    first_record_id: None,
                    last_record_id: None,
                    pending: None,
                }
            );
        }
        store.receive(b"pending", 2);
        let (_worker, session) = start(&store, "absent", received_only);
        assert_eq!(
            session.snapshot_info(),
            SearchSnapshotInfo {
                sequence: 0,
                first_record_id: None,
                last_record_id: None,
                pending: Some(SearchHit {
                    record_id: u64::MAX,
                    timestamp_ms: 2,
                    source_length: 7,
                    index: 0,
                }),
            }
        );
        assert_eq!(session.poll().total_matches, 0);
    }

    #[test]
    fn pending_identity_carries_timestamp_and_source_length() {
        let mut store = LogStore::new(1024);
        store.receive(b"find", 100);
        let (_worker, session) = start(&store, "find", options());
        let hit = session.search_match(0).unwrap().unwrap();
        assert_eq!(
            (hit.record_id, hit.timestamp_ms, hit.source_length),
            (u64::MAX, 100, 4)
        );
        store.receive(b"later", 101);
        assert_eq!(first_view(&session).source_length, 4);
        store.clear();
        store.receive(b"find", 102);
        let current = store.snapshot().records.pop().unwrap();
        assert_eq!(current.id, hit.record_id);
        assert_ne!(current.timestamp_ms, hit.timestamp_ms);
    }

    #[test]
    fn unicode_lossy_text_ranges_are_utf16_not_bytes_or_scalars() {
        let mut store = LogStore::new(1024);
        store.sent("😀汉İx😀".as_bytes(), 1);
        let (_worker, session) = start(&store, "😀", options());
        let view = first_view(&session);
        assert_eq!(
            view.ranges,
            vec![
                SearchRange { start: 0, end: 2 },
                SearchRange { start: 5, end: 7 },
            ]
        );
        let opts = SearchOptions {
            case_sensitive: false,
            ..options()
        };
        let (_worker, lower) = start(&store, "i\u{307}X", opts);
        assert_eq!(
            first_view(&lower).ranges,
            vec![SearchRange { start: 3, end: 5 }]
        );
        let mut broken = LogStore::new(1024);
        broken.sent(b"a\xe2\x82z\xff", 2);
        let (_worker, invalid) = start(&broken, "\u{fffd}", options());
        let view = first_view(&invalid);
        assert_eq!(view.text, String::from_utf8_lossy(b"a\xe2\x82z\xff"));
        assert_eq!(
            view.ranges,
            vec![
                SearchRange { start: 1, end: 2 },
                SearchRange { start: 3, end: 4 },
            ]
        );
    }

    #[test]
    fn lowercase_expansion_does_not_emit_overlapping_source_ranges() {
        let mut store = LogStore::new(1024);
        store.sent("İİß".as_bytes(), 1);
        let opts = SearchOptions {
            case_sensitive: false,
            ..options()
        };
        let (_worker, session) = start(&store, "i", opts);
        assert_eq!(session.poll().total_matches, 2);
        assert_eq!(
            first_view(&session).ranges,
            vec![
                SearchRange { start: 0, end: 1 },
                SearchRange { start: 1, end: 2 },
            ]
        );
        let (_worker, not_casefold) = start(&store, "ss", opts);
        assert_eq!(not_casefold.poll().total_matches, 0);
    }

    #[test]
    fn ansi_controls_are_hidden_but_visible_text_can_match_across_them() {
        let mut store = LogStore::new(4096);
        store.sent(b"a\x1b[31mb\x1b[0mc\x1b]hidden\x07d\x1b]also hidden\x1b\\e\x1bPsecret\x1b\\f\x1b(Bg\x1b[31", 1);
        let opts = SearchOptions {
            strip_ansi: true,
            ..options()
        };
        let (_worker, session) = start(&store, "abcdefg", opts);
        let view = first_view(&session);
        assert_eq!(view.text, "abcdefg");
        assert_eq!(view.ranges, vec![SearchRange { start: 0, end: 7 }]);
        let (_worker, hidden) = start(&store, "hidden", opts);
        assert_eq!(hidden.poll().total_matches, 0);
        let (_worker, raw) = start(&store, "hidden", options());
        assert_eq!(raw.poll().total_matches, 2);
    }

    #[test]
    fn hex_matches_original_bytes_across_soft_line_breaks() {
        let mut store = LogStore::new(1024);
        store.sent(&(0u8..70).collect::<Vec<_>>(), 9);
        let opts = SearchOptions {
            hex: true,
            strip_ansi: true,
            ..options()
        };
        let (_worker, session) = start(&store, "1f \n20", opts);
        let view = first_view(&session);
        assert_eq!(session.poll().total_matches, 1);
        assert_eq!(&view.text[93..98], "1F\n20");
        assert_eq!(view.focus_range, Some(SearchRange { start: 93, end: 98 }));
        assert!(view.text.starts_with("00 01 02"));
    }

    #[test]
    fn strict_hex_errors_preserve_the_previous_core_session() {
        let dir = tempfile::tempdir().unwrap();
        let core = AppCore::create(AppOptions {
            data_directory: dir.path().into(),
            ..AppOptions::default()
        })
        .unwrap();
        let existing = core.start_search("x".into(), options()).unwrap();
        let hex = SearchOptions {
            hex: true,
            ..options()
        };
        for (query, code) in [
            ("0", ErrorCode::IncompleteHexByte),
            ("0x00", ErrorCode::InvalidHexCharacter),
            ("00,01", ErrorCode::InvalidHexCharacter),
            ("00\u{a0}01", ErrorCode::InvalidHexCharacter),
        ] {
            let error = core.start_search(query.into(), hex).err().unwrap();
            assert_eq!(error.code, Some(code));
            assert!(!existing.poll().cancelled);
        }
        core.close().unwrap();
        assert!(existing.poll().cancelled);
        assert_eq!(
            core.start_search("x".into(), options()).err().unwrap().kind,
            ErrorKind::Closed
        );
    }

    #[test]
    fn query_limit_counts_utf8_bytes_before_hex_decoding_or_pattern_preparation() {
        for opts in [
            options(),
            SearchOptions {
                case_sensitive: false,
                ..options()
            },
            SearchOptions {
                hex: true,
                ..options()
            },
        ] {
            assert!(PreparedSearch::new("a".repeat(MAX_QUERY_BYTES), opts).is_ok());
            let error = PreparedSearch::new("z".repeat(MAX_QUERY_BYTES + 1), opts)
                .err()
                .unwrap();
            assert_eq!(error.kind, ErrorKind::InvalidArgument);
            assert_eq!(error.code, Some(ErrorCode::SearchQueryTooLarge));
        }
        let unicode = "😀".repeat(MAX_QUERY_BYTES / 4);
        assert!(PreparedSearch::new(unicode.clone(), options()).is_ok());
        let error = PreparedSearch::new(format!("{unicode}x"), options())
            .err()
            .unwrap();
        assert_eq!(error.code, Some(ErrorCode::SearchQueryTooLarge));
        // Lowercase expansion happens only after the original UTF-8 input bound.
        assert!(PreparedSearch::new(
            "İ".repeat(MAX_QUERY_BYTES / 2),
            SearchOptions {
                case_sensitive: false,
                ..options()
            },
        )
        .is_ok());
    }

    #[test]
    fn oversized_queries_leave_the_previous_core_session_active() {
        let dir = tempfile::tempdir().unwrap();
        let core = AppCore::create(AppOptions {
            data_directory: dir.path().into(),
            ..AppOptions::default()
        })
        .unwrap();
        let existing = core.start_search("valid".into(), options()).unwrap();
        for opts in [
            options(),
            SearchOptions {
                hex: true,
                ..options()
            },
        ] {
            let error = core
                .start_search("z".repeat(MAX_QUERY_BYTES + 1), opts)
                .err()
                .unwrap();
            assert_eq!(error.code, Some(ErrorCode::SearchQueryTooLarge));
            assert!(!existing.poll().cancelled);
        }
        core.close().unwrap();
    }

    #[test]
    fn distant_focus_is_centered_and_all_visible_ranges_are_bounded() {
        let mut store = LogStore::new(100_000);
        let text = format!("{}NEEDLE{}", "😀".repeat(6000), "x".repeat(6000));
        store.sent(text.as_bytes(), 3);
        let (_worker, session) = start(&store, "NEEDLE", options());
        let hit = session.search_match(0).unwrap().unwrap();
        let preview = session.search_record(hit.record_id, None).unwrap().unwrap();
        assert_eq!(preview.text.encode_utf16().count(), 4096);
        assert!(preview.ranges.is_empty());
        assert!(!preview.leading_clipped);
        assert!(preview.trailing_clipped);
        let focused = first_view(&session);
        assert!(focused.leading_clipped && focused.trailing_clipped);
        assert!(focused.text.contains("NEEDLE"));
        assert!(focused.text.encode_utf16().count() <= 4096);
        let focus = focused.focus_range.unwrap();
        assert_eq!(focus.end - focus.start, 6);
        assert_eq!(focused.start_offset + u64::from(focus.start), 12_000);
        assert!(focused
            .ranges
            .iter()
            .all(|r| r.start < r.end && r.end <= 4096));
    }

    #[test]
    fn huge_queries_clip_ranges_without_copying_the_match_into_the_view() {
        let mut store = LogStore::new(100_000);
        store.sent(&vec![b'x'; 20_000], 4);
        let (_worker, session) = start(&store, &"x".repeat(10_000), options());
        assert_eq!(session.poll().total_matches, 2);
        let hit = session.search_match(1).unwrap().unwrap();
        let view = session
            .search_record(hit.record_id, Some(1))
            .unwrap()
            .unwrap();
        assert_eq!(view.text.encode_utf16().count(), 4096);
        assert_eq!(
            view.focus_range,
            Some(SearchRange {
                start: 1024,
                end: 4096
            })
        );
        assert!(view.ranges.len() <= 4096);
    }

    #[test]
    fn match_index_retains_one_count_per_record_not_one_entry_per_match() {
        let mut store = LogStore::new(100_000);
        store.sent(&vec![b'x'; 50_000], 4);
        let (_worker, session) = start(&store, "x", options());
        assert_eq!(session.poll().total_matches, 50_000);
        assert_eq!(session.inner.index.lock().unwrap().records.len(), 1);
        assert_eq!(session.search_match(49_999).unwrap().unwrap().index, 49_999);
        let view = first_view(&session);
        assert_eq!(view.ranges.len(), 4096);
        assert!(view.text.encode_utf16().count() <= 4096);
    }

    #[test]
    fn replacement_cancels_long_hidden_rows_and_releases_payload_ownership() {
        let mut store = LogStore::new(32 * 1024 * 1024);
        let mut bytes = vec![b'x'; 16 * 1024 * 1024];
        bytes[..2].copy_from_slice(b"\x1b]");
        store.sent(&bytes, 1);
        let records = store.search_snapshot(true);
        let weak = Arc::downgrade(&records[0].data);
        let worker = SearchWorker::new().unwrap();
        let old = worker.submit(
            records,
            PreparedSearch::new(
                "x".into(),
                SearchOptions {
                    strip_ansi: true,
                    ..options()
                },
            )
            .unwrap(),
            0,
        );
        store.clear();
        let fresh = worker.submit(
            Vec::new(),
            PreparedSearch::new("new".into(), options()).unwrap(),
            1,
        );
        assert!(old.poll().cancelled);
        assert!(old.inner.data.lock().unwrap().is_none());
        assert!(old.search_match(0).unwrap().is_none());
        assert!(old.search_record(1, None).unwrap().is_none());
        wait_until(|| fresh.poll().complete && weak.upgrade().is_none());
        worker.close().unwrap();
        assert!(fresh.poll().cancelled);
        assert!(worker.join.lock().unwrap().is_none());
    }

    #[test]
    fn core_replacement_and_awaited_close_cancel_all_handles() {
        let dir = tempfile::tempdir().unwrap();
        let core = AppCore::create(AppOptions {
            data_directory: dir.path().into(),
            ..AppOptions::default()
        })
        .unwrap();
        let first = core.start_search("one".into(), options()).unwrap();
        let second = core.start_search("two".into(), options()).unwrap();
        assert!(first.poll().cancelled);
        core.close().unwrap();
        assert!(second.poll().cancelled);
        assert!(second.inner.data.lock().unwrap().is_none());
        core.close().unwrap();
    }

    #[test]
    fn utf8_and_ascii_lowercase_fast_paths_match_across_chunk_edges() {
        let mut store = LogStore::new(100_000);
        store.sent(
            format!("{}😀Z{}", "x".repeat(4094), "x".repeat(4096)).as_bytes(),
            1,
        );
        let (_worker, session) = start(&store, "😀Z", options());
        assert_eq!(session.poll().total_matches, 1);
        assert_eq!(
            first_view(&session).focus_range,
            Some(SearchRange {
                start: 1024,
                end: 1027
            })
        );
        store.clear();
        store.sent(
            format!("{}AbCdEF{}", "x".repeat(4094), "x".repeat(4096)).as_bytes(),
            2,
        );
        let opts = SearchOptions {
            case_sensitive: false,
            ..options()
        };
        let (_worker, lower) = start(&store, "abcdef", opts);
        assert_eq!(lower.poll().total_matches, 1);
        let view = first_view(&lower);
        assert!(view.text.contains("AbCdEF"));
        assert_eq!(
            view.focus_range,
            Some(SearchRange {
                start: 1024,
                end: 1030
            })
        );
    }

    #[test]
    fn ansi_stripping_preserves_lossy_scalars_and_repeated_escape_boundaries() {
        let mut store = LogStore::new(1024);
        store.sent("a\u{1b}😀\u{1b}\u{1b}[31mb".as_bytes(), 1);
        let opts = SearchOptions {
            strip_ansi: true,
            ..options()
        };
        let (_worker, session) = start(&store, "a😀b", opts);
        let view = first_view(&session);
        assert_eq!(view.text, "a😀b");
        assert_eq!(view.ranges, vec![SearchRange { start: 0, end: 4 }]);
    }

    #[test]
    fn hex_focus_past_the_preview_is_bounded_and_byte_aligned() {
        let mut store = LogStore::new(100_000);
        let mut bytes = vec![0xaa; 10_000];
        bytes[8000] = 0xff;
        store.sent(&bytes, 1);
        let opts = SearchOptions {
            hex: true,
            ..options()
        };
        let (_worker, session) = start(&store, "ff", opts);
        let hit = session.search_match(0).unwrap().unwrap();
        let preview = session.search_record(hit.record_id, None).unwrap().unwrap();
        assert!(preview.ranges.is_empty() && preview.trailing_clipped);
        let view = first_view(&session);
        assert!(view.leading_clipped && view.trailing_clipped);
        assert!(view.text.encode_utf16().count() <= 4096);
        let range = view.focus_range.unwrap();
        assert_eq!(&view.text[range.start as usize..range.end as usize], "FF");
    }

    #[test]
    fn empty_queries_have_no_matches_and_empty_rows_remain_safe() {
        let mut store = LogStore::new(1024);
        store.receive(b"\n", 1);
        for opts in [
            options(),
            SearchOptions {
                hex: true,
                ..options()
            },
        ] {
            let (_worker, session) = start(&store, "", opts);
            assert_eq!(session.poll().total_matches, 0);
            assert!(session.search_match(0).unwrap().is_none());
            let id = store.snapshot().records[0].id;
            let view = session.search_record(id, None).unwrap().unwrap();
            assert!(view.text.is_empty() && view.ranges.is_empty());
        }
    }
}
