//! Android owns HTTP routing/DNS/proxy/TLS; Rust owns the existing signed wire
//! protocol. No credentials or responses are written to a bridge file/log.
//! The application class is captured on a Java-originating install call so a
//! Rust worker never relies on FindClass through the bootstrap class loader.

use jni::objects::{GlobalRef, JByteArray, JClass, JObject, JObjectArray, JString, JValue};
use jni::{JNIEnv, JavaVM};
use std::collections::HashMap;
use std::io::{self, Read};
use std::sync::OnceLock;

struct Context {
    vm: JavaVM,
    class: GlobalRef,
}
static CONTEXT: OnceLock<Context> = OnceLock::new();
fn bridge_error<T>(_: T) -> String {
    "connection".to_owned()
}

#[no_mangle]
pub extern "system" fn Java_com_mesting_music_MusicNativeTransport_nativeInstall(
    env: JNIEnv,
    class: JClass,
) -> jni::sys::jboolean {
    if CONTEXT.get().is_some() {
        return 1;
    }
    let result = (|| {
        let vm = env.get_java_vm()?;
        let class = env.new_global_ref(class)?;
        Ok::<_, jni::errors::Error>(Context { vm, class })
    })();
    match result {
        Ok(context) => {
            let _ = CONTEXT.set(context);
            1
        }
        Err(_) => 0,
    }
}

fn using<T>(run: impl FnOnce(&mut JNIEnv, &JClass) -> Result<T, String>) -> Result<T, String> {
    let context = CONTEXT
        .get()
        .ok_or_else(|| "system_transport_not_ready".to_owned())?;
    let mut env = context.vm.attach_current_thread().map_err(bridge_error)?;
    let class = JClass::from(
        env.new_local_ref(context.class.as_obj())
            .map_err(bridge_error)?,
    );
    let result = run(&mut env, &class);
    // A pending Java exception must never leak into a later unrelated request.
    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
    }
    result
}

fn string_field(env: &mut JNIEnv, object: &JObject, field: &str) -> Result<Option<String>, String> {
    let value = env
        .get_field(object, field, "Ljava/lang/String;")
        .map_err(bridge_error)?
        .l()
        .map_err(bridge_error)?;
    if value.is_null() {
        return Ok(None);
    }
    let string = JString::from(value);
    let result: String = env.get_string(&string).map_err(bridge_error)?.into();
    Ok(Some(result))
}

pub struct Reply {
    pub status: u16,
    pub body: Vec<u8>,
    pub cookies: Vec<String>,
    pub final_url: String,
    pub location: Option<String>,
    pub ssa_code: Option<String>,
}

pub fn exchange(
    method: &str,
    url: &str,
    headers: &HashMap<String, String>,
    body: &[u8],
    timeout_ms: u64,
    follow_redirects: bool,
) -> Result<Reply, String> {
    using(|env, class| {
        let method = JObject::from(env.new_string(method).map_err(bridge_error)?);
        let url = JObject::from(env.new_string(url).map_err(bridge_error)?);
        let json = serde_json::to_string(headers).map_err(bridge_error)?;
        let headers = JObject::from(env.new_string(json).map_err(bridge_error)?);
        let body = JObject::from(env.byte_array_from_slice(body).map_err(bridge_error)?);
        let reply = env.call_static_method(class, "exchange",
            "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;[BJZ)Lcom/mesting/music/MusicHttpReply;",
            &[JValue::Object(&method), JValue::Object(&url), JValue::Object(&headers),
              JValue::Object(&body), JValue::Long(timeout_ms.min(180000) as i64),
              JValue::Bool(follow_redirects as u8)]).map_err(bridge_error)?.l().map_err(bridge_error)?;
        if let Some(error) = string_field(env, &reply, "error")? {
            return Err(error);
        }
        let status = env
            .get_field(&reply, "status", "I")
            .map_err(bridge_error)?
            .i()
            .map_err(bridge_error)?;
        let bytes = JByteArray::from(
            env.get_field(&reply, "body", "[B")
                .map_err(bridge_error)?
                .l()
                .map_err(bridge_error)?,
        );
        let body = env.convert_byte_array(bytes).map_err(bridge_error)?;
        let array = JObjectArray::from(
            env.get_field(&reply, "cookies", "[Ljava/lang/String;")
                .map_err(bridge_error)?
                .l()
                .map_err(bridge_error)?,
        );
        let mut cookies = Vec::new();
        for index in 0..env.get_array_length(&array).map_err(bridge_error)? {
            let value = JString::from(
                env.get_object_array_element(&array, index)
                    .map_err(bridge_error)?,
            );
            cookies.push(env.get_string(&value).map_err(bridge_error)?.into());
        }
        Ok(Reply {
            status: status as u16,
            body,
            cookies,
            final_url: string_field(env, &reply, "finalUrl")?.unwrap_or_default(),
            location: string_field(env, &reply, "location")?,
            ssa_code: string_field(env, &reply, "ssaCode")?,
        })
    })
}

/// The video/media proxy remains streaming. Reads cross JNI in bounded chunks;
/// a full recording is never buffered into one platform message or byte array.
pub struct NativeStream {
    id: i64,
}
impl Read for NativeStream {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        if buffer.is_empty() || self.id == 0 {
            return Ok(0);
        }
        let count = using(|env, class| {
            let bytes = env
                .call_static_method(
                    class,
                    "readStream",
                    "(JI)[B",
                    &[
                        JValue::Long(self.id),
                        JValue::Int(buffer.len().min(65536) as i32),
                    ],
                )
                .map_err(bridge_error)?
                .l()
                .map_err(bridge_error)?;
            let bytes = env
                .convert_byte_array(JByteArray::from(bytes))
                .map_err(bridge_error)?;
            buffer[..bytes.len()].copy_from_slice(&bytes);
            Ok(bytes.len())
        })
        .map_err(|_| {
            io::Error::new(io::ErrorKind::ConnectionAborted, "Music stream interrupted")
        })?;
        // Java closes an exhausted stream. Remember EOF locally so subsequent
        // Read calls remain Ok(0) instead of addressing a removed native handle.
        if count == 0 {
            self.id = 0;
        }
        Ok(count)
    }
}
impl Drop for NativeStream {
    fn drop(&mut self) {
        if self.id == 0 {
            return;
        }
        let _ = using(|env, class| {
            env.call_static_method(class, "closeStream", "(J)V", &[JValue::Long(self.id)])
                .map_err(bridge_error)?;
            Ok(())
        });
    }
}
pub fn open_stream(
    url: &str,
) -> Result<(u16, Option<u64>, String, Box<dyn Read + Send + Sync>), String> {
    using(|env, class| {
        let url = JObject::from(env.new_string(url).map_err(bridge_error)?);
        let reply = env
            .call_static_method(
                class,
                "openStream",
                "(Ljava/lang/String;)Lcom/mesting/music/MusicStreamReply;",
                &[JValue::Object(&url)],
            )
            .map_err(bridge_error)?
            .l()
            .map_err(bridge_error)?;
        if let Some(error) = string_field(env, &reply, "error")? {
            return Err(error);
        }
        let id = env
            .get_field(&reply, "id", "J")
            .map_err(bridge_error)?
            .j()
            .map_err(bridge_error)?;
        let status = env
            .get_field(&reply, "status", "I")
            .map_err(bridge_error)?
            .i()
            .map_err(bridge_error)?;
        let length = env
            .get_field(&reply, "length", "J")
            .map_err(bridge_error)?
            .j()
            .map_err(bridge_error)?;
        let content_type =
            string_field(env, &reply, "contentType")?.unwrap_or_else(|| "video/mp4".to_owned());
        let reader = Box::new(NativeStream { id }) as Box<dyn Read + Send + Sync>;
        if !(200..300).contains(&status) {
            return Err(format!("status {status}"));
        }
        Ok((
            status as u16,
            (length >= 0).then_some(length as u64),
            content_type,
            reader,
        ))
    })
}
