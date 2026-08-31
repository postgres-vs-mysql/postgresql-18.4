// src/trace.rs
use std::ffi::{CString, c_int};

// Declare external C functions
//#[pg_guard]
unsafe extern "C" {
    // Function enter/exit - simple pointer + length
    pub fn rust_trace_function_enter(function: *const u8, len: usize);
    pub fn rust_trace_function_exit(function: *const u8, len: usize);

    pub fn rust_trace_print(fmt: *const std::os::raw::c_char, ...);

    pub fn rust_trace_instant_print(fmt: *const std::os::raw::c_char, ...);

    pub fn is_trace_enabled() -> bool;
    pub fn set_trace_enabled();
    pub fn set_trace_disabled();
    pub fn set_trace_thread_mode();
    pub fn set_trace_process_mode();
    pub fn retrieve_max_trace_iterations() -> c_int;
    pub fn retrieve_min_trace_iterations() -> c_int;
    pub fn test_for_rust() -> c_int;
    pub fn test_for_rust2() -> c_int;
}

#[inline(always)]
pub fn trace_enabled() -> bool {
    unsafe { is_trace_enabled() }
}

#[inline(always)]
pub fn enable_trace_thread_mode() {
    unsafe {
        set_trace_thread_mode();
    }
}

#[inline(always)]
pub fn disable_trace_thread_mode() {
    unsafe {
        set_trace_process_mode();
    }
}

#[inline(always)]
pub fn enable_trace() {
    unsafe {
        set_trace_enabled();
    }
}

#[inline(always)]
pub fn disable_trace() {
    unsafe {
        set_trace_disabled();
    }
}

#[inline(always)]
pub fn max_trace_iterations() -> i32 {
    unsafe { retrieve_max_trace_iterations() }
}

pub fn test_vchord() -> i32 {
    unsafe { test_for_rust() }
}

pub fn test_vchord2() -> i32 {
    unsafe { test_for_rust2() }
}

#[inline(always)]
pub fn min_trace_iterations() -> i32 {
    unsafe { retrieve_min_trace_iterations() }
}

#[inline(always)]
pub fn trace_print(fmt: &str) {
    if let Ok(msg) = CString::new(fmt) {
        unsafe { rust_trace_print(msg.as_ptr()) };
    }
}

#[inline(always)]
pub fn trace_instant_print(fmt: &str) {
    if let Ok(msg) = CString::new(fmt) {
        unsafe { rust_trace_instant_print(msg.as_ptr()) };
    }
}

pub struct TraceGuard {
    name: &'static str,
}

impl TraceGuard {
    #[inline(always)]
    pub fn new(name: &'static str) -> Self {
        unsafe {
            rust_trace_function_enter(name.as_ptr(), name.len());
        }
        TraceGuard { name }
    }
}

impl Drop for TraceGuard {
    #[inline(always)]
    fn drop(&mut self) {
        unsafe {
            rust_trace_function_exit(self.name.as_ptr(), self.name.len());
        }
    }
}
// ============================================================================
// Macros - Support User-Specified Function Name
// ============================================================================

#[macro_export]
macro_rules! trace_guard {
    // User specifies function name - direct pass, zero cost
    ($func_name:expr) => {{
        if $crate::trace::trace_enabled() {
            Some($crate::trace::TraceGuard::new($func_name))
        } else {
            None
        }
    }};
}

#[macro_export]
macro_rules! trace_vchord_print {
    ($msg:literal) => {{
      if $crate::trace::trace_enabled() {
        let _ = $crate::trace::trace_print($msg);
      }
    }};
    ($fmt:literal, $($arg:tt)*) => {{
      if $crate::trace::trace_enabled() {
        let _ = $crate::trace::trace_print(&format!($fmt, $($arg)*));
      }
    }};
}

#[macro_export]
macro_rules! trace_vchord_instant_print {
    ($msg:literal) => {{
      if $crate::trace::trace_enabled() {
        let _ = $crate::trace::trace_instant_print($msg);
      }
    }};
    ($fmt:literal, $($arg:tt)*) => {{
      if $crate::trace::trace_enabled() {
        let _ = $crate::trace::trace_instant_print(&format!($fmt, $($arg)*));
      }
    }};
}
