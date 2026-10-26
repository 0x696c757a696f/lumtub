//! The proxy Windows is set to, read from the registry as the browsers read
//! it, without starting `reg.exe` twice on every check.

use serde::Serialize;
use std::os::raw::c_char;

#[derive(Serialize, Debug, PartialEq)]
pub struct SystemProxy {
    pub enabled: bool,
    pub server: String,
}

#[cfg(windows)]
pub fn read() -> Option<SystemProxy> {
    use windows_sys::Win32::System::Registry::{HKEY_CURRENT_USER, RRF_RT_REG_DWORD, RRF_RT_REG_SZ, RegGetValueW};

    fn wide(text: &str) -> Vec<u16> {
        text.encode_utf16().chain(Some(0)).collect()
    }
    let key = wide(r"Software\Microsoft\Windows\CurrentVersion\Internet Settings");
    let mut enabled = 0u32;
    let mut size = std::mem::size_of::<u32>() as u32;
    let status = unsafe {
        RegGetValueW(HKEY_CURRENT_USER, key.as_ptr(), wide("ProxyEnable").as_ptr(), RRF_RT_REG_DWORD, std::ptr::null_mut(), (&raw mut enabled).cast(), &mut size)
    };
    if status != 0 {
        return Some(SystemProxy { enabled: false, server: String::new() });
    }
    let name = wide("ProxyServer");
    let mut size = 0u32;
    let status = unsafe { RegGetValueW(HKEY_CURRENT_USER, key.as_ptr(), name.as_ptr(), RRF_RT_REG_SZ, std::ptr::null_mut(), std::ptr::null_mut(), &mut size) };
    let mut server = String::new();
    if status == 0 && size > 0 {
        let mut buffer = vec![0u16; (size as usize).div_ceil(2)];
        let status = unsafe {
            RegGetValueW(HKEY_CURRENT_USER, key.as_ptr(), name.as_ptr(), RRF_RT_REG_SZ, std::ptr::null_mut(), buffer.as_mut_ptr().cast(), &mut size)
        };
        if status == 0 {
            let end = buffer.iter().position(|&c| c == 0).unwrap_or(buffer.len());
            server = String::from_utf16_lossy(&buffer[..end]).trim().to_owned();
        }
    }
    Some(SystemProxy { enabled: enabled != 0, server })
}

#[cfg(not(windows))]
pub fn read() -> Option<SystemProxy> {
    None
}

/// [read] as JSON `{enabled, server}`, or null off Windows.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_system_proxy() -> *mut c_char {
    read().map_or(std::ptr::null_mut(), |proxy| crate::taste::give_json(&proxy))
}
