use super::{complete_failure, publish_simple, Shared};
use crate::{
    logging::StoredRecord, CoreError, ErrorCode, ErrorKind, EventKind, ExportOptions, RequestId,
};
use std::{
    fs::{self, OpenOptions},
    io::{self, BufWriter, Write},
    path::Path,
    sync::{
        atomic::{AtomicU64, Ordering},
        mpsc::{self, SyncSender, TrySendError},
        Arc,
    },
    thread::{self, JoinHandle},
};

static EXPORT_TEMP_ID: AtomicU64 = AtomicU64::new(0);

struct Job {
    id: RequestId,
    path: String,
    options: ExportOptions,
    records: Vec<StoredRecord>,
}

pub(super) struct ExportWorker {
    tx: Option<SyncSender<Job>>,
    thread: Option<JoinHandle<()>>,
    shared: Arc<Shared>,
}

impl ExportWorker {
    pub(super) fn new(shared: Arc<Shared>) -> Result<Self, CoreError> {
        let (tx, rx) = mpsc::sync_channel::<Job>(1);
        let worker_shared = shared.clone();
        let thread = thread::Builder::new()
            .name("skyport-export".into())
            .spawn(move || {
                while let Ok(job) = rx.recv() {
                    let id = job.id;
                    let result =
                        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| write_job(job)));
                    match result {
                        Ok(Ok(())) => publish_simple(
                            &worker_shared,
                            EventKind::CommandCompleted { request_id: id },
                        ),
                        Ok(Err(error)) => complete_failure(&worker_shared, id, error),
                        Err(_) => complete_failure(
                            &worker_shared,
                            id,
                            CoreError::new(ErrorKind::TaskFailed, "export worker panicked")
                                .with_code(ErrorCode::ExportFailed),
                        ),
                    }
                }
            })
            .map_err(|error| {
                CoreError::new(ErrorKind::Internal, format!("start export worker: {error}"))
            })?;
        Ok(Self {
            tx: Some(tx),
            thread: Some(thread),
            shared,
        })
    }

    pub(super) fn submit(
        &self,
        id: RequestId,
        path: String,
        options: ExportOptions,
    ) -> Result<(), CoreError> {
        let records = self
            .shared
            .state
            .lock()
            .map_err(|_| CoreError::new(ErrorKind::Internal, "application state lock poisoned"))?
            .log
            .search_snapshot(options.show_sent);
        if records.is_empty() {
            return Err(CoreError::new(
                ErrorKind::InvalidArgument,
                "no retained log records match the export options",
            )
            .with_code(ErrorCode::NoLogsToExport));
        }
        let job = Job {
            id,
            path,
            options,
            records,
        };
        match self
            .tx
            .as_ref()
            .expect("export worker is closed")
            .try_send(job)
        {
            Ok(()) => Ok(()),
            Err(TrySendError::Full(_)) => Err(CoreError::new(
                ErrorKind::QueueOverflow,
                "export queue is full",
            )),
            Err(TrySendError::Disconnected(_)) => {
                Err(CoreError::new(ErrorKind::Closed, "export worker is closed"))
            }
        }
    }

    pub(super) fn close(&mut self) {
        self.tx.take();
        if let Some(thread) = self.thread.take() {
            if thread.join().is_err() {
                let error = CoreError::new(ErrorKind::TaskFailed, "export worker panicked");
                if let Ok(mut worker_error) = self.shared.worker_error.lock() {
                    *worker_error = Some(error.clone());
                }
                publish_simple(&self.shared, EventKind::TaskFailed(error));
            }
        }
    }
}

impl Drop for ExportWorker {
    fn drop(&mut self) {
        self.close();
    }
}

fn write_job(job: Job) -> Result<(), CoreError> {
    write_export_atomic(Path::new(&job.path), |writer| {
        crate::logging::write_export(&job.records, job.options, writer)
    })
    .map_err(|error| {
        CoreError::new(ErrorKind::TaskFailed, format!("export log: {error}"))
            .with_code(ErrorCode::ExportFailed)
    })
}

fn write_export_atomic(
    path: &Path,
    write: impl FnOnce(&mut BufWriter<std::fs::File>) -> io::Result<()>,
) -> io::Result<()> {
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let name = path.file_name().unwrap_or_default().to_string_lossy();
    let (temporary, file) = loop {
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
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut writer = BufWriter::new(file);
        write(&mut writer)?;
        writer.flush()?;
        writer.get_ref().sync_all()
    }));
    let result = match result {
        Ok(result) => result.and_then(|()| crate::config::replace_file(&temporary, path)),
        Err(payload) => {
            let _ = fs::remove_file(temporary);
            std::panic::resume_unwind(payload);
        }
    };
    if result.is_ok() {
        if let Ok(directory) = OpenOptions::new().read(true).open(parent) {
            let _ = directory.sync_all();
        }
    } else {
        let _ = fs::remove_file(temporary);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn atomic_export_removes_temporary_file_after_write_error() {
        let directory = tempfile::tempdir().unwrap();
        let target = directory.path().join("export.txt");
        fs::write(&target, b"keep existing export").unwrap();
        let result = write_export_atomic(&target, |writer| {
            writer.write_all(b"partial replacement")?;
            Err(io::Error::other("write failed"))
        });
        assert!(result.is_err());
        assert_eq!(fs::read(&target).unwrap(), b"keep existing export");
        assert_eq!(fs::read_dir(directory.path()).unwrap().count(), 1);
    }
}
