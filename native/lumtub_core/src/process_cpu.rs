//! How much processor time this process has used, for the playback test:
//! libmpv decodes on threads of this process, so its work is counted too.

/// User plus kernel time of every thread of this process, in milliseconds.
pub fn used_ms() -> u64 {
    imp::used_ms()
}

#[cfg(unix)]
mod imp {
    pub fn used_ms() -> u64 {
        let mut usage = std::mem::MaybeUninit::<libc::rusage>::zeroed();
        // SAFETY: getrusage fills the struct it is given.
        if unsafe { libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()) } != 0 {
            return 0;
        }
        // SAFETY: filled by the successful call above.
        let usage = unsafe { usage.assume_init() };
        let ms = |t: libc::timeval| t.tv_sec as u64 * 1000 + t.tv_usec as u64 / 1000;
        ms(usage.ru_utime) + ms(usage.ru_stime)
    }
}

#[cfg(windows)]
mod imp {
    use windows_sys::Win32::Foundation::FILETIME;
    use windows_sys::Win32::System::Threading::{GetCurrentProcess, GetProcessTimes};

    pub fn used_ms() -> u64 {
        let zero = FILETIME { dwLowDateTime: 0, dwHighDateTime: 0 };
        let (mut created, mut exited, mut kernel, mut user) = (zero, zero, zero, zero);
        // SAFETY: the pseudo handle of this process and four FILETIMEs to fill.
        if unsafe { GetProcessTimes(GetCurrentProcess(), &mut created, &mut exited, &mut kernel, &mut user) } == 0 {
            return 0;
        }
        let hundreds = |t: FILETIME| (t.dwHighDateTime as u64) << 32 | t.dwLowDateTime as u64;
        (hundreds(kernel) + hundreds(user)) / 10_000
    }
}

#[cfg(not(any(unix, windows)))]
mod imp {
    pub fn used_ms() -> u64 {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn lumtub_process_cpu_ms() -> u64 {
    used_ms()
}

#[cfg(test)]
mod tests {
    #[test]
    fn counts_work() {
        let before = super::used_ms();
        let start = std::time::Instant::now();
        let mut x = 0u64;
        while start.elapsed().as_millis() < 300 {
            x = x.wrapping_mul(6364136223846793005).wrapping_add(1);
        }
        std::hint::black_box(x);
        assert!(super::used_ms() >= before + 200);
    }
}
