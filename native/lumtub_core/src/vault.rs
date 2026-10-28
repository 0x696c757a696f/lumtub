//! Keeping a secret, on every platform the app runs on.
//!
//! On disk it is sealed with AES-256-GCM under a key that the system keeps:
//! on Windows a TPM key, behind Windows Hello where the user has it, with
//! DPAPI for the Windows account on top; on macOS the keychain, behind
//! Touch ID or the password where it allows; on Linux the Secret Service
//! keyring. Where there is none, only the file's permissions keep it.
//!
//! In memory it stays encrypted for this process (by Windows itself, or
//! under a key of the process's own elsewhere), in pages of its own that
//! are kept out of swap and core dumps and wiped when dropped. AES runs on
//! the CPU's AES instructions wherever it has them.

use aes_gcm::aead::{AeadInOut, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use zeroize::Zeroize;

const PAGE: usize = 4096;

/// Bytes in whole pages of their own, locked in RAM and wiped when dropped.
pub struct Locked {
    ptr: *mut u8,
    len: usize,
    size: usize,
}

// SAFETY: [Locked] owns its pages alone.
unsafe impl Send for Locked {}
unsafe impl Sync for Locked {}

impl Locked {
    pub fn new(len: usize) -> Option<Locked> {
        let size = len.max(1).div_ceil(PAGE) * PAGE;
        let layout = std::alloc::Layout::from_size_align(size, PAGE).ok()?;
        // SAFETY: [layout] has a size above zero.
        let ptr = unsafe { std::alloc::alloc_zeroed(layout) };
        if ptr.is_null() {
            return None;
        }
        memory::lock(ptr, size);
        Some(Locked { ptr, len, size })
    }

    pub fn from(bytes: &[u8]) -> Option<Locked> {
        let mut locked = Locked::new(bytes.len())?;
        locked.copy_from_slice(bytes);
        Some(locked)
    }

    /// The first [len] bytes; the rest are wiped.
    pub fn truncate(&mut self, len: usize) {
        if len < self.len {
            self[len..].zeroize();
            self.len = len;
        }
    }
}

impl std::ops::Deref for Locked {
    type Target = [u8];
    fn deref(&self) -> &[u8] {
        // SAFETY: [ptr] holds [size] >= [len] bytes owned by this value.
        unsafe { std::slice::from_raw_parts(self.ptr, self.len) }
    }
}

impl std::ops::DerefMut for Locked {
    fn deref_mut(&mut self) -> &mut [u8] {
        // SAFETY: as in deref, and borrowed mutably once.
        unsafe { std::slice::from_raw_parts_mut(self.ptr, self.len) }
    }
}

impl Drop for Locked {
    fn drop(&mut self) {
        // SAFETY: [ptr] holds [size] bytes allocated with this layout.
        unsafe {
            std::slice::from_raw_parts_mut(self.ptr, self.size).zeroize();
            memory::unlock(self.ptr, self.size);
            std::alloc::dealloc(self.ptr, std::alloc::Layout::from_size_align_unchecked(self.size, PAGE));
        }
    }
}

/// [len] random bytes from the system, in locked memory.
pub fn random(len: usize) -> Option<Locked> {
    let mut out = Locked::new(len)?;
    getrandom::fill(&mut out).ok()?;
    Some(out)
}

const NONCE: usize = 12;
const TAG: usize = 16;

fn cipher(key: &[u8]) -> Option<Aes256Gcm> {
    Aes256Gcm::new_from_slice(key).ok()
}

/// [data] encrypted in place under [key]; the nonce and tag it took.
fn encrypt(key: &[u8], aad: &[u8], data: &mut [u8]) -> Option<([u8; NONCE], [u8; TAG])> {
    let mut nonce = [0u8; NONCE];
    getrandom::fill(&mut nonce).ok()?;
    let tag = cipher(key)?.encrypt_inout_detached(&Nonce::from(nonce), aad, data.into()).ok()?;
    Some((nonce, tag.into()))
}

/// [data] decrypted in place; false when it was changed.
fn decrypt(key: &[u8], aad: &[u8], nonce: &[u8], tag: &[u8], data: &mut [u8]) -> bool {
    let (Ok(nonce), Ok(tag)) = (<[u8; NONCE]>::try_from(nonce), <[u8; TAG]>::try_from(tag)) else { return false };
    cipher(key).is_some_and(|c| c.decrypt_inout_detached(&Nonce::from(nonce), aad, data.into(), &tag.into()).is_ok())
}

/// A secret held encrypted in memory: only this process can decrypt it,
/// and only for as long as [Secret::reveal] runs.
pub struct Secret {
    data: Locked,
    len: usize,
    nonce: [u8; NONCE],
    tag: [u8; TAG],
}

impl Secret {
    pub fn new(plain: &[u8]) -> Option<Secret> {
        let mut data = Locked::new(plain.len().max(1).div_ceil(16) * 16)?;
        data[..plain.len()].copy_from_slice(plain);
        let (nonce, tag) = memory::seal(&mut data)?;
        Some(Secret { data, len: plain.len(), nonce, tag })
    }

    /// Runs [f] on the secret, decrypted into a copy that is wiped after.
    pub fn reveal<R>(&self, f: impl FnOnce(&[u8]) -> R) -> Option<R> {
        let mut copy = Locked::from(&self.data)?;
        if !memory::open(&mut copy, &self.nonce, &self.tag) {
            return None;
        }
        Some(f(&copy[..self.len]))
    }
}

/// What keeps a sealed file shut.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Guard {
    /// A system-kept key the user must confirm with Windows Hello, Touch ID
    /// or their password.
    Presence,
    /// A key in this PC's TPM.
    Hardware,
    /// A key in the system keyring.
    Keyring,
    /// The system account's own encryption alone (DPAPI).
    Account,
    /// Only the file's permissions.
    File,
}

impl Guard {
    pub fn name(self) -> &'static str {
        match self {
            Guard::Presence => "presence",
            Guard::Hardware => "hardware",
            Guard::Keyring => "keyring",
            Guard::Account => "account",
            Guard::File => "file",
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum Failure {
    /// The user closed the system's prompt.
    Cancelled,
    Broken(String),
}

const MAGIC: &[u8; 4] = b"LTV2";

/// Modes in the file: where the AES key is kept.
const WINDOWS_HELLO: u8 = b'H';
const TPM_OAEP: u8 = b'T';
const TPM_PKCS1: u8 = b'P';
const KEYCHAIN_PRESENCE: u8 = b'K';
const KEYCHAIN: u8 = b'k';
const SECRET_SERVICE: u8 = b'S';
const PLAIN: u8 = b'D';

fn guard_of(mode: u8) -> Guard {
    match mode {
        WINDOWS_HELLO | KEYCHAIN_PRESENCE => Guard::Presence,
        TPM_OAEP | TPM_PKCS1 => Guard::Hardware,
        KEYCHAIN | SECRET_SERVICE => Guard::Keyring,
        _ if cfg!(windows) => Guard::Account,
        _ => Guard::File,
    }
}

/// Seals data: an AES-256 key kept by the system, behind the user's
/// confirmation where asked for and available. The key is kept encrypted
/// in memory, so later data is sealed without asking the user again.
pub struct Sealer {
    key: Option<Secret>,
    mode: u8,
    wrapped: Vec<u8>,
}

impl Sealer {
    /// A new key; one behind the user's confirmation asks for it. [reason]
    /// is what the system's prompt says.
    pub fn new(presence: bool, reason: &str) -> Sealer {
        if let Some(key) = random(32) {
            for &mode in keys::modes(presence) {
                let Some(wrapped) = keys::wrap(mode, &key, reason) else { continue };
                // A key that does not come back is not used: the file would never open.
                if keys::unwrap(mode, &wrapped, reason).ok().is_some_and(|back| *back == *key)
                    && let Some(key) = Secret::new(&key)
                {
                    return Sealer { key: Some(key), mode, wrapped };
                }
            }
        }
        Sealer { key: None, mode: PLAIN, wrapped: Vec::new() }
    }

    pub fn guard(&self) -> Guard {
        guard_of(self.mode)
    }

    fn header(&self) -> Vec<u8> {
        let mut header = Vec::with_capacity(7 + self.wrapped.len());
        header.extend_from_slice(MAGIC);
        header.push(self.mode);
        if self.key.is_some() {
            header.extend_from_slice(&(self.wrapped.len() as u16).to_le_bytes());
            header.extend_from_slice(&self.wrapped);
        }
        header
    }

    /// [plain] sealed; asks the user nothing.
    pub fn seal(&self, plain: &[u8]) -> Option<Vec<u8>> {
        let mut inner = self.header();
        match &self.key {
            Some(key) => {
                let mut data = Locked::from(plain)?;
                let header = inner.clone();
                let (nonce, tag) = key.reveal(|key| encrypt(key, &header, &mut data))??;
                inner.extend_from_slice(&nonce);
                inner.extend_from_slice(&tag);
                inner.extend_from_slice(&data);
            }
            None => inner.extend_from_slice(plain),
        }
        let out = account::seal(&inner);
        inner.zeroize();
        out
    }
}

/// Which [Guard] keeps [sealed] shut, read without asking the user.
pub fn guard(sealed: &[u8]) -> Option<Guard> {
    let inner = account::open(sealed)?;
    (inner.len() > MAGIC.len() && inner[..4] == *MAGIC).then(|| guard_of(inner[4]))
}

/// What a [Sealer] sealed, and that sealer; the system asks the user first
/// where their confirmation guards it.
pub fn open(sealed: &[u8], reason: &str) -> Result<(Locked, Sealer), Failure> {
    let broken = |why: &str| Failure::Broken(why.to_owned());
    let inner = account::open(sealed).ok_or_else(|| broken("the system could not decrypt the data"))?;
    if inner.len() <= MAGIC.len() || inner[..4] != *MAGIC {
        return Err(broken("not a sealed file"));
    }
    let mode = inner[4];
    let rest = &inner[5..];
    if mode == PLAIN {
        let plain = Locked::from(rest).ok_or_else(|| broken("out of memory"))?;
        return Ok((plain, Sealer { key: None, mode, wrapped: Vec::new() }));
    }
    let length = u16::from_le_bytes([*rest.first().unwrap_or(&0), *rest.get(1).unwrap_or(&0)]) as usize;
    if rest.len() < 2 + length + NONCE + TAG {
        return Err(broken("the sealed file is cut short"));
    }
    let header = &inner[..5 + 2 + length];
    let (wrapped, rest) = rest[2..].split_at(length);
    let (nonce, rest) = rest.split_at(NONCE);
    let (tag, ciphertext) = rest.split_at(TAG);
    let key = keys::unwrap(mode, wrapped, reason)?;
    let mut plain = Locked::from(ciphertext).ok_or_else(|| broken("out of memory"))?;
    if !decrypt(&key, header, nonce, tag, &mut plain) {
        return Err(broken("the sealed file was changed"));
    }
    let key = Secret::new(&key).ok_or_else(|| broken("out of memory"))?;
    Ok((plain, Sealer { key: Some(key), mode, wrapped: wrapped.to_vec() }))
}

#[cfg(windows)]
mod memory {
    use windows_sys::Win32::Security::Cryptography::{CRYPTPROTECTMEMORY_SAME_PROCESS, CryptProtectMemory, CryptUnprotectMemory};
    use windows_sys::Win32::System::Memory::{VirtualLock, VirtualUnlock};

    use super::{NONCE, TAG};

    pub fn lock(ptr: *mut u8, size: usize) {
        // Fails only past the working set's limit; the bytes are still wiped.
        unsafe { VirtualLock(ptr as _, size) };
    }

    pub fn unlock(ptr: *mut u8, size: usize) {
        unsafe { VirtualUnlock(ptr as _, size) };
    }

    /// Encrypted in place by Windows, with a key it keeps for this process.
    pub fn seal(data: &mut [u8]) -> Option<([u8; NONCE], [u8; TAG])> {
        // SAFETY: [data] is a live buffer of a multiple of 16 bytes.
        let ok = unsafe { CryptProtectMemory(data.as_mut_ptr() as _, data.len() as u32, CRYPTPROTECTMEMORY_SAME_PROCESS) != 0 };
        ok.then_some(([0; NONCE], [0; TAG]))
    }

    pub fn open(data: &mut [u8], _: &[u8; NONCE], _: &[u8; TAG]) -> bool {
        // SAFETY: as in seal.
        unsafe { CryptUnprotectMemory(data.as_mut_ptr() as _, data.len() as u32, CRYPTPROTECTMEMORY_SAME_PROCESS) != 0 }
    }
}

#[cfg(not(windows))]
mod memory {
    use std::sync::LazyLock;

    use super::{Locked, NONCE, TAG, decrypt, encrypt, random};

    pub fn lock(ptr: *mut u8, size: usize) {
        // SAFETY: [ptr] is the start of [size] bytes of whole pages.
        unsafe {
            libc::mlock(ptr as _, size);
            #[cfg(any(target_os = "linux", target_os = "android"))]
            libc::madvise(ptr as _, size, libc::MADV_DONTDUMP);
        }
    }

    pub fn unlock(ptr: *mut u8, size: usize) {
        unsafe {
            #[cfg(any(target_os = "linux", target_os = "android"))]
            libc::madvise(ptr as _, size, libc::MADV_DODUMP);
            libc::munlock(ptr as _, size);
        }
    }

    /// The process's own key for secrets in memory, made at first use.
    static KEY: LazyLock<Option<Locked>> = LazyLock::new(|| random(32));

    pub fn seal(data: &mut [u8]) -> Option<([u8; NONCE], [u8; TAG])> {
        encrypt(KEY.as_ref()?, b"", data)
    }

    pub fn open(data: &mut [u8], nonce: &[u8; NONCE], tag: &[u8; TAG]) -> bool {
        KEY.as_ref().is_some_and(|key| decrypt(key, b"", nonce, tag, data))
    }
}

#[cfg(windows)]
mod account {
    use windows_sys::Win32::Foundation::{HLOCAL, LocalFree};
    use windows_sys::Win32::Security::Cryptography::{CRYPT_INTEGER_BLOB, CRYPTPROTECT_UI_FORBIDDEN, CryptProtectData, CryptUnprotectData};
    use zeroize::Zeroize;

    use super::Locked;

    const ENTROPY: &[u8] = b"Lumtub vault v2";

    fn run(data: &[u8], seal: bool) -> Option<Locked> {
        let input = CRYPT_INTEGER_BLOB { cbData: data.len() as u32, pbData: data.as_ptr() as *mut u8 };
        let entropy = CRYPT_INTEGER_BLOB { cbData: ENTROPY.len() as u32, pbData: ENTROPY.as_ptr() as *mut u8 };
        let mut output = CRYPT_INTEGER_BLOB { cbData: 0, pbData: std::ptr::null_mut() };
        // SAFETY: the blobs point to live buffers; the output is wiped and freed below.
        let ok = unsafe {
            if seal {
                CryptProtectData(&input, std::ptr::null(), &entropy, std::ptr::null(), std::ptr::null(), CRYPTPROTECT_UI_FORBIDDEN, &mut output)
            } else {
                CryptUnprotectData(&input, std::ptr::null_mut(), &entropy, std::ptr::null(), std::ptr::null(), CRYPTPROTECT_UI_FORBIDDEN, &mut output)
            }
        };
        if ok == 0 || output.pbData.is_null() {
            return None;
        }
        // SAFETY: Windows filled [output] with cbData bytes.
        let bytes = unsafe { std::slice::from_raw_parts_mut(output.pbData, output.cbData as usize) };
        let out = Locked::from(bytes);
        bytes.zeroize();
        unsafe { LocalFree(output.pbData as HLOCAL) };
        out
    }

    pub fn seal(data: &[u8]) -> Option<Vec<u8>> {
        run(data, true).map(|sealed| sealed.to_vec())
    }

    pub fn open(data: &[u8]) -> Option<Locked> {
        run(data, false)
    }
}

// Elsewhere the account has no encryption of its own: the file is written
// for its owner alone.
#[cfg(not(windows))]
mod account {
    use super::Locked;

    pub fn seal(data: &[u8]) -> Option<Vec<u8>> {
        Some(data.to_vec())
    }

    pub fn open(data: &[u8]) -> Option<Locked> {
        Locked::from(data)
    }
}

/// Writes [data] to [file] by way of a temporary file, readable by the
/// user alone.
pub fn write_private(file: &std::path::Path, data: &[u8]) -> std::io::Result<()> {
    let temporary = file.with_extension("tmp");
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);
    std::io::Write::write_all(&mut options.open(&temporary)?, data)?;
    std::fs::rename(&temporary, file)
}

#[cfg(windows)]
mod keys {
    use windows_sys::Win32::Foundation::{HWND, LPARAM, NTE_BAD_KEYSET, NTE_USER_CANCELLED, SCARD_W_CANCELLED_BY_USER};
    use windows_sys::Win32::Security::Cryptography::*;
    use windows_sys::core::{BOOL, HRESULT, PCWSTR};

    use super::{Failure, Locked, TPM_OAEP, TPM_PKCS1, WINDOWS_HELLO};

    const ALLOW_DECRYPT: u32 = 1;
    const ALLOW_SIGNING: u32 = 2;
    /// HRESULT_FROM_WIN32(ERROR_CANCELLED).
    const ERROR_CANCELLED: HRESULT = 0x800704C7_u32 as _;

    pub fn modes(presence: bool) -> &'static [u8] {
        if presence { &[WINDOWS_HELLO, TPM_OAEP, TPM_PKCS1] } else { &[TPM_OAEP, TPM_PKCS1] }
    }

    struct Handle(NCRYPT_HANDLE);

    impl Drop for Handle {
        fn drop(&mut self) {
            if self.0 != 0 {
                unsafe { NCryptFreeObject(self.0) };
            }
        }
    }

    fn wide(text: &str) -> Vec<u16> {
        text.encode_utf16().chain(Some(0)).collect()
    }

    fn set(handle: &Handle, name: PCWSTR, value: &[u8]) -> bool {
        // SAFETY: [value] is a live buffer.
        unsafe { NCryptSetProperty(handle.0, name, value.as_ptr(), value.len() as u32, 0) == 0 }
    }

    /// The Windows user's SID, for naming a Windows Hello key.
    fn user_sid() -> Option<String> {
        use windows_sys::Win32::Foundation::{CloseHandle, HANDLE, HLOCAL, LocalFree};
        use windows_sys::Win32::Security::Authorization::ConvertSidToStringSidW;
        use windows_sys::Win32::Security::{GetTokenInformation, TOKEN_QUERY, TOKEN_USER, TokenUser};
        use windows_sys::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};
        let mut token: HANDLE = std::ptr::null_mut();
        // SAFETY: plain Win32 calls on live buffers; handles are closed below.
        unsafe {
            if OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token) == 0 {
                return None;
            }
            let mut buffer = [0u64; 64];
            let mut length = 0u32;
            let ok = GetTokenInformation(token, TokenUser, buffer.as_mut_ptr() as _, std::mem::size_of_val(&buffer) as u32, &mut length);
            CloseHandle(token);
            if ok == 0 {
                return None;
            }
            let user = &*(buffer.as_ptr() as *const TOKEN_USER);
            let mut text = std::ptr::null_mut();
            if ConvertSidToStringSidW(user.User.Sid, &mut text) == 0 || text.is_null() {
                return None;
            }
            let length = (0..).take_while(|&i| *text.add(i) != 0).count();
            let sid = String::from_utf16_lossy(std::slice::from_raw_parts(text, length));
            LocalFree(text as HLOCAL);
            Some(sid)
        }
    }

    /// The app's main window, which the Windows Hello prompt is shown over.
    fn window() -> HWND {
        use windows_sys::Win32::System::Threading::GetCurrentProcessId;
        use windows_sys::Win32::UI::WindowsAndMessaging::{EnumWindows, GW_OWNER, GetWindow, GetWindowThreadProcessId, IsWindowVisible};
        unsafe extern "system" fn each(window: HWND, found: LPARAM) -> BOOL {
            let mut process = 0u32;
            // SAFETY: [found] points to the HWND below, alive during EnumWindows.
            unsafe {
                GetWindowThreadProcessId(window, &mut process);
                if process == GetCurrentProcessId() && IsWindowVisible(window) != 0 && GetWindow(window, GW_OWNER).is_null() {
                    *(found as *mut HWND) = window;
                    return 0;
                }
            }
            1
        }
        let mut found: HWND = std::ptr::null_mut();
        unsafe { EnumWindows(Some(each), &mut found as *mut HWND as LPARAM) };
        found
    }

    /// The key [mode] uses, made the first time when [create].
    fn key(mode: u8, create: bool) -> Result<Handle, HRESULT> {
        let (provider_name, name) = if mode == WINDOWS_HELLO {
            let sid = user_sid().ok_or(NTE_BAD_KEYSET)?;
            (MS_NGC_KEY_STORAGE_PROVIDER, wide(&format!("{sid}//Lumtub/Cookies/Vault")))
        } else {
            (MS_PLATFORM_CRYPTO_PROVIDER, wide("Lumtub vault key"))
        };
        let mut provider = Handle(0);
        // SAFETY: Win32 calls with live out pointers; handles are freed on drop.
        unsafe {
            let status = NCryptOpenStorageProvider(&mut provider.0, provider_name, 0);
            if status != 0 {
                return Err(status);
            }
            let mut key = Handle(0);
            let silent = if mode == WINDOWS_HELLO { 0 } else { NCRYPT_SILENT_FLAG };
            let status = NCryptOpenKey(provider.0, &mut key.0, name.as_ptr(), 0, silent);
            if status == 0 || !create {
                return if status == 0 { Ok(key) } else { Err(status) };
            }
            let status = NCryptCreatePersistedKey(provider.0, &mut key.0, NCRYPT_RSA_ALGORITHM, name.as_ptr(), 0, 0);
            if status != 0 {
                return Err(status);
            }
            set(&key, NCRYPT_LENGTH_PROPERTY, &2048u32.to_le_bytes());
            if mode == WINDOWS_HELLO {
                set(&key, NCRYPT_KEY_USAGE_PROPERTY, &(ALLOW_DECRYPT | ALLOW_SIGNING).to_le_bytes());
                set(&key, NCRYPT_WINDOW_HANDLE_PROPERTY, &(window() as usize).to_le_bytes());
            }
            let status = NCryptFinalizeKey(key.0, silent);
            if status != 0 {
                return Err(status);
            }
            Ok(key)
        }
    }

    /// The padding [mode] uses: OAEP with SHA-256 where the TPM takes it.
    fn padding(mode: u8) -> (NCRYPT_FLAGS, BCRYPT_OAEP_PADDING_INFO) {
        let info = BCRYPT_OAEP_PADDING_INFO { pszAlgId: BCRYPT_SHA256_ALGORITHM, pbLabel: std::ptr::null_mut(), cbLabel: 0 };
        if mode == TPM_OAEP { (NCRYPT_PAD_OAEP_FLAG, info) } else { (NCRYPT_PAD_PKCS1_FLAG, info) }
    }

    fn info_of(flags: NCRYPT_FLAGS, info: &BCRYPT_OAEP_PADDING_INFO) -> *const core::ffi::c_void {
        if flags == NCRYPT_PAD_OAEP_FLAG { info as *const _ as _ } else { std::ptr::null() }
    }

    pub fn wrap(mode: u8, data: &[u8], _reason: &str) -> Option<Vec<u8>> {
        debug_assert!([WINDOWS_HELLO, TPM_OAEP, TPM_PKCS1].contains(&mode));
        let key = key(mode, true).ok()?;
        let (flags, info) = padding(mode);
        let info = info_of(flags, &info);
        let mut length = 0u32;
        // SAFETY: sized first, then filled into a buffer of that size.
        unsafe {
            if NCryptEncrypt(key.0, data.as_ptr(), data.len() as u32, info, std::ptr::null_mut(), 0, &mut length, flags | NCRYPT_SILENT_FLAG) != 0 {
                return None;
            }
            let mut out = vec![0u8; length as usize];
            if NCryptEncrypt(key.0, data.as_ptr(), data.len() as u32, info, out.as_mut_ptr(), length, &mut length, flags | NCRYPT_SILENT_FLAG) != 0 {
                return None;
            }
            out.truncate(length as usize);
            Some(out)
        }
    }

    pub fn unwrap(mode: u8, data: &[u8], reason: &str) -> Result<Locked, Failure> {
        let failed = |status: HRESULT| match status {
            NTE_USER_CANCELLED | SCARD_W_CANCELLED_BY_USER | ERROR_CANCELLED => Failure::Cancelled,
            _ => Failure::Broken(format!("the key would not open: {status:#010x}")),
        };
        if ![WINDOWS_HELLO, TPM_OAEP, TPM_PKCS1].contains(&mode) {
            return Err(Failure::Broken("the file was sealed on another system".into()));
        }
        let key = key(mode, false).map_err(failed)?;
        let (mut flags, info) = padding(mode);
        let info_pointer = info_of(flags, &info);
        if mode == WINDOWS_HELLO {
            set(&key, NCRYPT_WINDOW_HANDLE_PROPERTY, &(window() as usize).to_le_bytes());
            let reason: Vec<u8> = wide(reason).iter().flat_map(|c| c.to_le_bytes()).collect();
            set(&key, NCRYPT_USE_CONTEXT_PROPERTY, &reason);
            set(&key, NCRYPT_PIN_CACHE_IS_GESTURE_REQUIRED_PROPERTY, &1u32.to_le_bytes());
        } else {
            flags |= NCRYPT_SILENT_FLAG;
        }
        let mut out = Locked::new(512).ok_or(Failure::Broken("out of memory".into()))?;
        let mut length = 0u32;
        // SAFETY: [out] holds 512 bytes, more than a 2048-bit key decrypts to.
        let status = unsafe { NCryptDecrypt(key.0, data.as_ptr(), data.len() as u32, info_pointer, out.as_mut_ptr(), 512, &mut length, flags) };
        if status != 0 {
            return Err(failed(status));
        }
        out.truncate(length as usize);
        Ok(out)
    }
}

#[cfg(target_os = "macos")]
mod keys {
    use security_framework::passwords::{delete_generic_password_options, generic_password, set_generic_password_options};
    use security_framework::passwords_options::{AccessControlOptions, PasswordOptions};

    use super::{Failure, KEYCHAIN, KEYCHAIN_PRESENCE, Locked};

    const SERVICE: &str = "Lumtub";
    const ACCOUNT: &str = "vault key";
    /// errSecUserCanceled.
    const CANCELLED: i32 = -128;

    pub fn modes(presence: bool) -> &'static [u8] {
        if presence { &[KEYCHAIN_PRESENCE, KEYCHAIN] } else { &[KEYCHAIN] }
    }

    /// The item's options: in the data protection keychain behind Touch ID
    /// or the password for [KEYCHAIN_PRESENCE], which takes a signed app;
    /// else in the login keychain, which only this app reads unasked.
    fn options(mode: u8, access: bool) -> PasswordOptions {
        let mut options = PasswordOptions::new_generic_password(SERVICE, ACCOUNT);
        if mode == KEYCHAIN_PRESENCE {
            options.use_protected_keychain();
            if access {
                options.set_access_control_options(AccessControlOptions::USER_PRESENCE);
            }
        }
        options
    }

    /// Keeps [data] in the keychain; the item stands for the wrapped key.
    pub fn wrap(mode: u8, data: &[u8], _reason: &str) -> Option<Vec<u8>> {
        let _ = delete_generic_password_options(options(mode, false));
        set_generic_password_options(data, options(mode, true)).ok()?;
        Some(vec![mode])
    }

    pub fn unwrap(mode: u8, _wrapped: &[u8], _reason: &str) -> Result<Locked, Failure> {
        if ![KEYCHAIN_PRESENCE, KEYCHAIN].contains(&mode) {
            return Err(Failure::Broken("the file was sealed on another system".into()));
        }
        match generic_password(options(mode, false)) {
            Ok(mut key) => {
                let out = Locked::from(&key);
                zeroize::Zeroize::zeroize(&mut key);
                out.ok_or(Failure::Broken("out of memory".into()))
            }
            Err(e) if e.code() == CANCELLED => Err(Failure::Cancelled),
            Err(e) => Err(Failure::Broken(format!("the keychain would not give the key: {}", e.code()))),
        }
    }
}

#[cfg(target_os = "linux")]
mod keys {
    use std::time::Duration;

    use super::{Failure, Locked, SECRET_SERVICE};

    const ATTRIBUTES: [(&str, &str); 2] = [("application", "lumtub"), ("purpose", "vault key")];

    pub fn modes(_presence: bool) -> &'static [u8] {
        &[SECRET_SERVICE]
    }

    /// Runs [work] on the Secret Service, here on this thread.
    fn run<T>(work: impl AsyncFnOnce(oo7::Keyring) -> Result<T, String>) -> Result<T, String> {
        let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().map_err(|e| e.to_string())?;
        runtime.block_on(async {
            let keyring = tokio::time::timeout(Duration::from_secs(10), oo7::Keyring::new()).await.map_err(|_| "no keyring answered".to_owned())?.map_err(|e| e.to_string())?;
            work(keyring).await
        })
    }

    pub fn wrap(_mode: u8, data: &[u8], _reason: &str) -> Option<Vec<u8>> {
        run(async |keyring| {
            keyring.unlock().await.map_err(|e| e.to_string())?;
            keyring.create_item("Lumtub", &ATTRIBUTES, oo7::Secret::blob(data), true).await.map_err(|e| e.to_string())
        })
        .ok()?;
        Some(vec![SECRET_SERVICE])
    }

    pub fn unwrap(mode: u8, _wrapped: &[u8], _reason: &str) -> Result<Locked, Failure> {
        if mode != SECRET_SERVICE {
            return Err(Failure::Broken("the file was sealed on another system".into()));
        }
        let key = run(async |keyring| {
            let items = keyring.search_items(&ATTRIBUTES).await.map_err(|e| e.to_string())?;
            let item = items.first().ok_or("the keyring has no key")?;
            if item.is_locked().await.unwrap_or(false) {
                item.unlock().await.map_err(|e| e.to_string())?;
            }
            let secret = item.secret().await.map_err(|e| e.to_string())?;
            Locked::from(&secret).ok_or_else(|| "out of memory".to_owned())
        });
        // A keyring whose unlocking prompt was dismissed answers with an error too.
        key.map_err(|why| if why.contains("ismissed") { Failure::Cancelled } else { Failure::Broken(why) })
    }
}

// Elsewhere there is no keeper of keys yet: files are kept by their
// permissions alone.
#[cfg(not(any(windows, target_os = "macos", target_os = "linux")))]
mod keys {
    use super::{Failure, Locked};

    pub fn modes(_presence: bool) -> &'static [u8] {
        &[]
    }
    pub fn wrap(_: u8, _: &[u8], _: &str) -> Option<Vec<u8>> {
        None
    }
    pub fn unwrap(_: u8, _: &[u8], _: &str) -> Result<Locked, Failure> {
        Err(Failure::Broken("the file was sealed on another system".into()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn locked_bytes_are_their_own_pages() {
        let mut locked = Locked::from(b"secret").unwrap();
        assert_eq!(&*locked, b"secret");
        assert_eq!(locked.ptr as usize % PAGE, 0);
        locked.truncate(3);
        assert_eq!(&*locked, b"sec");
        assert!(Locked::new(0).is_some());
        assert_eq!(random(32).unwrap().len(), 32);
    }

    #[test]
    fn secrets_come_back_only_inside_reveal() {
        let secret = Secret::new(b"SAPISID=abc").unwrap();
        assert_ne!(&secret.data[..11], b"SAPISID=abc");
        assert_eq!(secret.reveal(|bytes| bytes.to_vec()).unwrap(), b"SAPISID=abc");
        assert_eq!(Secret::new(b"").unwrap().reveal(<[u8]>::len), Some(0));
    }

    #[test]
    fn aes_gcm_finds_changes() {
        let key = random(32).unwrap();
        let mut data = *b"cookies";
        let (nonce, tag) = encrypt(&key, b"head", &mut data).unwrap();
        assert_ne!(&data, b"cookies");
        let mut copy = data;
        assert!(!decrypt(&key, b"other", &nonce, &tag, &mut copy));
        assert!(decrypt(&key, b"head", &nonce, &tag, &mut data));
        assert_eq!(&data, b"cookies");
    }

    #[test]
    fn sealed_files_open_again() {
        let sealed = Sealer { key: Some(Secret::new(&[7; 32]).unwrap()), mode: b'X', wrapped: vec![1, 2] }.seal(b"cookies").unwrap();
        assert!(matches!(open(&sealed, "why"), Err(Failure::Broken(_))));

        let sealer = Sealer { key: None, mode: PLAIN, wrapped: Vec::new() };
        let sealed = sealer.seal(b"cookies").unwrap();
        let plain_guard = if cfg!(windows) { Guard::Account } else { Guard::File };
        assert_eq!(guard(&sealed), Some(plain_guard));
        let (plain, again) = open(&sealed, "why").unwrap();
        assert_eq!(&*plain, b"cookies");
        assert_eq!(&*open(&again.seal(b"more").unwrap(), "why").unwrap().0, b"more");
        assert!(matches!(open(b"junk", "why"), Err(Failure::Broken(_))));
    }

    #[test]
    fn writes_files_for_their_owner() {
        let file = std::env::temp_dir().join(format!("lumtub-vault-{}.bin", std::process::id()));
        write_private(&file, b"x").unwrap();
        assert_eq!(std::fs::read(&file).unwrap(), b"x");
        #[cfg(unix)]
        assert_eq!(std::os::unix::fs::PermissionsExt::mode(&std::fs::metadata(&file).unwrap().permissions()) & 0o777, 0o600);
        std::fs::remove_file(&file).unwrap();
    }
}
