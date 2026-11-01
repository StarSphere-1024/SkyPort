use jni::{
    objects::{GlobalRef, JByteArray, JObject, JObjectArray, JString, JValue},
    sys::jint,
    JNIEnv, JavaVM,
};
use skyport_core::{CoreError, ErrorKind, PortInfo, SerialBackend, SerialConfig, TransportPort};
use std::{
    io::{self, Read, Write},
    sync::{Arc, Mutex},
    time::Duration,
};

static BACKEND: Mutex<Option<Arc<AndroidBackend>>> = Mutex::new(None);

#[derive(Clone)]
struct AndroidBackend {
    vm: Arc<JavaVM>,
    object: GlobalRef,
}

#[no_mangle]
pub extern "system" fn Java_dev_skyport_app_UsbSerialBackend_install(
    mut env: JNIEnv,
    object: JObject,
) {
    let result = (|| -> jni::errors::Result<()> {
        let backend = Arc::new(AndroidBackend {
            vm: Arc::new(env.get_java_vm()?),
            object: env.new_global_ref(object)?,
        });
        *BACKEND.lock().unwrap_or_else(|e| e.into_inner()) = Some(backend);
        Ok(())
    })();
    if let Err(error) = result {
        let _ = env.throw_new(
            "java/lang/IllegalStateException",
            format!("Install USB backend: {error}"),
        );
    }
}

pub(crate) fn backend() -> Result<Arc<dyn SerialBackend>, CoreError> {
    BACKEND
        .lock()
        .map_err(|_| internal("USB backend lock poisoned"))?
        .clone()
        .map(|value| value as Arc<dyn SerialBackend>)
        .ok_or_else(|| internal("Android USB backend was not installed by the host"))
}

fn internal(message: impl ToString) -> CoreError {
    CoreError::new(ErrorKind::Internal, message.to_string())
}

fn string_value(env: &mut JNIEnv, object: JObject) -> Result<String, CoreError> {
    if object.is_null() {
        return Ok(String::new());
    }
    let value = JString::from(object);
    let result = env.get_string(&value).map(Into::into);
    if result.is_err() {
        let _ = env.exception_clear();
    }
    env.delete_local_ref(value).map_err(internal)?;
    let result = result.map_err(internal);
    result
}

fn checked<T>(env: &mut JNIEnv, result: jni::errors::Result<T>) -> Result<T, CoreError> {
    match result {
        Ok(value) => Ok(value),
        Err(jni::errors::Error::JavaException) => {
            let exception = env.exception_occurred().map_err(internal)?;
            env.exception_clear().map_err(internal)?;
            let kind = match env.get_field(&exception, "kind", "Ljava/lang/String;") {
                Ok(value) => string_value(env, value.l().map_err(internal)?)?,
                Err(_) => {
                    let _ = env.exception_clear();
                    String::new()
                }
            };
            let written = match env.get_field(&exception, "bytesWritten", "J") {
                Ok(value) => value.j().unwrap_or(0).max(0) as u64,
                Err(_) => {
                    let _ = env.exception_clear();
                    0
                }
            };
            let message = env.call_method(&exception, "toString", "()Ljava/lang/String;", &[]);
            let message = match message {
                Ok(value) => string_value(env, value.l().map_err(internal)?)?,
                Err(_) => {
                    let _ = env.exception_clear();
                    "Android USB operation failed".into()
                }
            };
            let kind = match kind.as_str() {
                "permissionDenied" => ErrorKind::PermissionDenied,
                "portNotFound" => ErrorKind::PortNotFound,
                "unsupportedConfiguration" => ErrorKind::UnsupportedConfiguration,
                "disconnected" => ErrorKind::Disconnected,
                "timeout" => ErrorKind::Timeout,
                "writeFailed" => ErrorKind::WriteFailed,
                "readFailed" => ErrorKind::ReadFailed,
                "openFailed" => ErrorKind::OpenFailed,
                _ => ErrorKind::Internal,
            };
            Err(CoreError::new(kind, message).with_written(written))
        }
        Err(error) => Err(internal(error)),
    }
}

fn local<T>(
    env: &mut JNIEnv,
    capacity: i32,
    work: impl FnOnce(&mut JNIEnv) -> Result<T, CoreError>,
) -> Result<T, CoreError> {
    env.with_local_frame(capacity, |env| Ok::<_, jni::errors::Error>(work(env)))
        .map_err(internal)?
}

impl SerialBackend for AndroidBackend {
    fn ports(&self) -> Result<Vec<PortInfo>, CoreError> {
        let mut env = self
            .vm
            .attach_current_thread_permanently()
            .map_err(internal)?;
        local(&mut env, 32, |env| {
            let result = env.call_method(
                self.object.as_obj(),
                "ports",
                "()[Ldev/skyport/app/UsbSerialBackend$PortInfo;",
                &[],
            );
            let items = JObjectArray::from(checked(env, result)?.l().map_err(internal)?);
            let count = env.get_array_length(&items).map_err(internal)?;
            let mut ports = Vec::with_capacity(count as usize);
            for i in 0..count {
                ports.push(local(env, 16, |env| {
                    let item = env.get_object_array_element(&items, i).map_err(internal)?;
                    let optional =
                        |env: &mut JNIEnv, name: &str| -> Result<Option<String>, CoreError> {
                            let value = env
                                .get_field(&item, name, "Ljava/lang/String;")
                                .map_err(internal)?
                                .l()
                                .map_err(internal)?;
                            if value.is_null() {
                                Ok(None)
                            } else {
                                string_value(env, value).map(Some)
                            }
                        };
                    let number = |env: &mut JNIEnv, name: &str| -> Result<u16, CoreError> {
                        env.get_field(&item, name, "I")
                            .map_err(internal)?
                            .i()
                            .map_err(internal)
                            .and_then(|value| u16::try_from(value).map_err(internal))
                    };
                    let port_name = optional(env, "portName")?
                        .ok_or_else(|| internal("missing USB port name"))?;
                    let product = optional(env, "product")?;
                    let manufacturer = optional(env, "manufacturer")?;
                    let serial_number = optional(env, "serialNumber")?;
                    let vid = number(env, "vid")?;
                    let pid = number(env, "pid")?;
                    Ok(PortInfo {
                        port_name,
                        product,
                        manufacturer,
                        serial_number,
                        vid: Some(vid),
                        pid: Some(pid),
                    })
                })?);
            }
            Ok(ports)
        })
    }
    fn open(&self, config: &SerialConfig) -> Result<Box<dyn TransportPort>, CoreError> {
        config.validate(true)?;
        let mut env = self
            .vm
            .attach_current_thread_permanently()
            .map_err(internal)?;
        local(&mut env, 16, |env| {
            let name = JObject::from(env.new_string(&config.port_name).map_err(internal)?);
            let parity = match config.parity {
                skyport_core::Parity::None => 0,
                skyport_core::Parity::Odd => 1,
                skyport_core::Parity::Even => 2,
            };
            let flow = match config.flow_control {
                skyport_core::FlowControl::None => 0,
                skyport_core::FlowControl::Hardware => 1,
                skyport_core::FlowControl::Software => 2,
            };
            // Allocate JNI buffers before opening the hardware, so allocation failure cannot leak a session.
            let read_buffer = env.new_byte_array(8192).map_err(internal)?;
            let read_buffer = env.new_global_ref(read_buffer).map_err(internal)?;
            let result = env.call_method(
                self.object.as_obj(),
                "open",
                "(Ljava/lang/String;IIIII)J",
                &[
                    JValue::Object(&name),
                    JValue::Int(config.baud_rate as jint),
                    JValue::Int(config.data_bits as jint),
                    JValue::Int(parity),
                    JValue::Int(config.stop_bits as jint),
                    JValue::Int(flow),
                ],
            );
            let handle = checked(env, result)?.j().map_err(internal)?;
            Ok(Box::new(AndroidPort {
                backend: self.clone(),
                handle,
                timeout: Duration::from_millis(5),
                read_buffer,
                write_buffer: None,
                write_capacity: 0,
                write_error: None,
            }) as Box<dyn TransportPort>)
        })
    }
}

struct AndroidPort {
    backend: AndroidBackend,
    handle: i64,
    timeout: Duration,
    read_buffer: GlobalRef,
    write_buffer: Option<GlobalRef>,
    write_capacity: usize,
    write_error: Option<CoreError>,
}

fn io_error(error: &CoreError) -> io::Error {
    let kind = match error.kind {
        ErrorKind::Timeout => io::ErrorKind::TimedOut,
        ErrorKind::Disconnected | ErrorKind::PortNotFound => io::ErrorKind::NotConnected,
        ErrorKind::PermissionDenied => io::ErrorKind::PermissionDenied,
        _ => io::ErrorKind::Other,
    };
    io::Error::new(kind, error.message.clone())
}

impl Read for AndroidPort {
    fn read(&mut self, output: &mut [u8]) -> io::Result<usize> {
        let result = (|| -> Result<usize, CoreError> {
            if output.is_empty() {
                return Ok(0);
            }
            let mut env = self
                .backend
                .vm
                .attach_current_thread_permanently()
                .map_err(internal)?;
            local(&mut env, 8, |env| {
                let array: &JByteArray = self.read_buffer.as_obj().into();
                let result = env.call_method(
                    self.backend.object.as_obj(),
                    "read",
                    "(J[BII)I",
                    &[
                        JValue::Long(self.handle),
                        JValue::Object(array.as_ref()),
                        JValue::Int(output.len().min(8192) as jint),
                        JValue::Int(self.timeout.as_millis().clamp(1, i32::MAX as u128) as jint),
                    ],
                );
                let count = checked(env, result)?.i().map_err(internal)?;
                if count < 0 || count as usize > output.len().min(8192) {
                    return Err(internal("Invalid USB read byte count"));
                }
                // JNI jbyte and u8 have identical representation; copy only the received prefix.
                let signed = unsafe {
                    std::slice::from_raw_parts_mut(output.as_mut_ptr().cast::<i8>(), count as usize)
                };
                env.get_byte_array_region(array, 0, signed)
                    .map_err(internal)?;
                Ok(count as usize)
            })
        })();
        result.map_err(|error| io_error(&error))
    }
}

impl Write for AndroidPort {
    fn write(&mut self, input: &[u8]) -> io::Result<usize> {
        self.write_error = None;
        let result = (|| -> Result<usize, CoreError> {
            if input.is_empty() {
                return Ok(0);
            }
            let mut env = self
                .backend
                .vm
                .attach_current_thread_permanently()
                .map_err(internal)?;
            local(&mut env, 8, |env| {
                let length = input.len().min(16384);
                if self.write_capacity < length {
                    let capacity = length.next_power_of_two();
                    let buffer = env.new_byte_array(capacity as jint).map_err(internal)?;
                    self.write_buffer = Some(env.new_global_ref(&buffer).map_err(internal)?);
                    env.delete_local_ref(buffer).map_err(internal)?;
                    self.write_capacity = capacity;
                }
                let array: &JByteArray = self.write_buffer.as_ref().unwrap().as_obj().into();
                let signed =
                    unsafe { std::slice::from_raw_parts(input.as_ptr().cast::<i8>(), length) };
                env.set_byte_array_region(array, 0, signed)
                    .map_err(internal)?;
                let result = env.call_method(
                    self.backend.object.as_obj(),
                    "write",
                    "(J[BII)I",
                    &[
                        JValue::Long(self.handle),
                        JValue::Object(array.as_ref()),
                        JValue::Int(length as jint),
                        JValue::Int(self.timeout.as_millis().clamp(1, i32::MAX as u128) as jint),
                    ],
                );
                let count = checked(env, result)?.i().map_err(internal)?;
                if count < 0 || count as usize > length {
                    return Err(internal("Invalid USB write byte count"));
                }
                Ok(count as usize)
            })
        })();
        result.map_err(|error| {
            let io = io_error(&error);
            self.write_error = Some(error);
            io
        })
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

impl TransportPort for AndroidPort {
    fn timeout(&self) -> Duration {
        self.timeout
    }
    fn set_timeout(&mut self, timeout: Duration) -> Result<(), CoreError> {
        self.timeout = timeout;
        Ok(())
    }
    fn take_write_error(&mut self) -> Option<CoreError> {
        self.write_error.take()
    }
}

impl Drop for AndroidPort {
    fn drop(&mut self) {
        if let Ok(mut env) = self.backend.vm.attach_current_thread_permanently() {
            let result = env.call_method(
                self.backend.object.as_obj(),
                "close",
                "(J)V",
                &[JValue::Long(self.handle)],
            );
            let _ = checked(&mut env, result);
        }
    }
}
