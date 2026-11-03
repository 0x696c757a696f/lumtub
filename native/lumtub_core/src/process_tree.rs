//! Keeps each yt-dlp (and the ffmpeg and Deno it starts) in a Windows job
//! object, so stopping it stops all of them, and so none outlives Lumtub:
//! the job is created with "kill on close", and Windows closes its handle
//! when Lumtub exits or crashes.
//!
//! A process is added to its job right after it starts. yt-dlp starts its
//! own children only later, and they join the job with it.

#[cfg(windows)]
mod imp {
    use std::mem::{size_of, zeroed};
    use std::ptr::null;
    use windows_sys::Win32::Foundation::{CloseHandle, HANDLE};
    use windows_sys::Win32::System::JobObjects::{
        AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
        SetInformationJobObject, TerminateJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
    };
    use windows_sys::Win32::System::Threading::{
        GetCurrentProcess, OpenProcess, ProcessPowerThrottling, SetProcessInformation, BELOW_NORMAL_PRIORITY_CLASS,
        PROCESS_POWER_THROTTLING_CURRENT_VERSION, PROCESS_POWER_THROTTLING_EXECUTION_SPEED, PROCESS_POWER_THROTTLING_STATE,
        PROCESS_SET_INFORMATION, PROCESS_SET_QUOTA, PROCESS_TERMINATE,
    };
    use windows_sys::Win32::System::JobObjects::JOB_OBJECT_LIMIT_PRIORITY_CLASS;

    pub fn adopt(pid: u32) -> isize {
        unsafe {
            let job = CreateJobObjectW(null(), null());
            if job.is_null() {
                return 0;
            }
            let mut limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = zeroed();
            limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            let process = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, 0, pid);
            let ok = !process.is_null()
                && SetInformationJobObject(
                    job,
                    JobObjectExtendedLimitInformation,
                    &limits as *const _ as *const _,
                    size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
                ) != 0
                && AssignProcessToJobObject(job, process) != 0;
            if !process.is_null() {
                CloseHandle(process);
            }
            if !ok {
                CloseHandle(job);
                return 0;
            }
            job as isize
        }
    }

    pub fn kill(job: isize, code: u32) -> bool {
        unsafe { TerminateJobObject(job as HANDLE, code) != 0 }
    }

    pub fn close(job: isize) {
        unsafe {
            CloseHandle(job as HANDLE);
        }
    }

    /// Windows' efficiency mode (EcoQoS) for [process]: it runs on
    /// efficient cores at lower clocks, for work nobody waits on.
    fn efficiency(process: HANDLE, on: bool) -> bool {
        let state = PROCESS_POWER_THROTTLING_STATE {
            Version: PROCESS_POWER_THROTTLING_CURRENT_VERSION,
            ControlMask: PROCESS_POWER_THROTTLING_EXECUTION_SPEED,
            StateMask: if on { PROCESS_POWER_THROTTLING_EXECUTION_SPEED } else { 0 },
        };
        unsafe { SetProcessInformation(process, ProcessPowerThrottling, &state as *const _ as *const _, size_of::<PROCESS_POWER_THROTTLING_STATE>() as u32) != 0 }
    }

    pub fn background(job: isize, pid: u32) -> bool {
        unsafe {
            // Everything in the job, ffmpeg included, below normal priority.
            let mut limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = zeroed();
            limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_PRIORITY_CLASS;
            limits.BasicLimitInformation.PriorityClass = BELOW_NORMAL_PRIORITY_CLASS;
            let prioritised = SetInformationJobObject(
                job as HANDLE,
                JobObjectExtendedLimitInformation,
                &limits as *const _ as *const _,
                size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            ) != 0;
            let process = OpenProcess(PROCESS_SET_INFORMATION, 0, pid);
            if process.is_null() {
                return prioritised;
            }
            let efficient = efficiency(process, true);
            CloseHandle(process);
            prioritised && efficient
        }
    }

    pub fn efficient_self(on: bool) -> bool {
        unsafe { efficiency(GetCurrentProcess(), on) }
    }
}

#[cfg(unix)]
mod imp {
    //! Without job objects the tree is found when it is needed: [kill]
    //! walks the processes whose parent is in the tree. A child that
    //! outlived its parent has been handed to init by then and is missed,
    //! which yt-dlp's ffmpeg and Deno, ended with yt-dlp, do not do.

    /// The "job" is the first process's id.
    pub fn adopt(pid: u32) -> isize {
        pid as isize
    }

    pub fn kill(job: isize, _code: u32) -> bool {
        let Ok(root) = libc::pid_t::try_from(job) else { return false };
        if root <= 1 {
            return false;
        }
        // Stopped first, so none starts another while the tree is read.
        let mut tree = vec![root];
        unsafe { libc::kill(root, libc::SIGSTOP) };
        let mut i = 0;
        while i < tree.len() {
            for child in children(tree[i]) {
                if !tree.contains(&child) {
                    unsafe { libc::kill(child, libc::SIGSTOP) };
                    tree.push(child);
                }
            }
            i += 1;
        }
        let mut any = false;
        for pid in tree.iter().rev() {
            any |= unsafe { libc::kill(*pid, libc::SIGKILL) } == 0;
        }
        any
    }

    pub fn close(_job: isize) {}

    /// Below normal priority, which the processes it starts inherit.
    pub fn background(_job: isize, pid: u32) -> bool {
        unsafe { libc::setpriority(libc::PRIO_PROCESS, pid as libc::id_t, 10) == 0 }
    }

    pub fn efficient_self(_on: bool) -> bool {
        false
    }

    #[cfg(target_os = "linux")]
    pub fn children(parent: libc::pid_t) -> Vec<libc::pid_t> {
        let Ok(entries) = std::fs::read_dir("/proc") else { return Vec::new() };
        entries
            .flatten()
            .filter_map(|entry| entry.file_name().to_str()?.parse::<libc::pid_t>().ok())
            .filter(|pid| parent_of(*pid) == Some(parent))
            .collect()
    }

    /// The parent in /proc/<pid>/stat: the field after the command name,
    /// which is in parentheses and may itself hold spaces and ')'.
    #[cfg(target_os = "linux")]
    fn parent_of(pid: libc::pid_t) -> Option<libc::pid_t> {
        let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
        let rest = &stat[stat.rfind(')')? + 1..];
        rest.split_whitespace().nth(1)?.parse().ok()
    }

    #[cfg(target_os = "macos")]
    pub fn children(parent: libc::pid_t) -> Vec<libc::pid_t> {
        const PROC_PPID_ONLY: u32 = 6;
        unsafe extern "C" {
            fn proc_listpids(kind: u32, info: u32, buffer: *mut libc::c_void, size: libc::c_int) -> libc::c_int;
        }
        let mut pids = vec![0 as libc::pid_t; 4096];
        let size = (pids.len() * std::mem::size_of::<libc::pid_t>()) as libc::c_int;
        // The answer is in bytes.
        let bytes = unsafe { proc_listpids(PROC_PPID_ONLY, parent as u32, pids.as_mut_ptr().cast(), size) };
        if bytes <= 0 {
            return Vec::new();
        }
        pids.truncate(bytes as usize / std::mem::size_of::<libc::pid_t>());
        pids.retain(|pid| *pid > 0);
        pids
    }

    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    pub fn children(_parent: libc::pid_t) -> Vec<libc::pid_t> {
        Vec::new()
    }
}

#[cfg(not(any(windows, unix)))]
mod imp {
    pub fn adopt(_pid: u32) -> isize {
        0
    }
    pub fn kill(_job: isize, _code: u32) -> bool {
        false
    }
    pub fn close(_job: isize) {}

    pub fn background(_job: isize, _pid: u32) -> bool {
        false
    }

    pub fn efficient_self(_on: bool) -> bool {
        false
    }
}

/// Puts process [pid] in a new job of its own. Returns the job handle, or 0
/// when it could not (the process already exited, or no permission).
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_tree_adopt(pid: u32) -> isize {
    imp::adopt(pid)
}

/// Runs the processes of [job] as background work: below normal priority,
/// and [pid] (the one started) in Windows' efficiency mode. For downloads.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_tree_background(job: isize, pid: u32) -> bool {
    imp::background(job, pid)
}

/// Turns Windows' efficiency mode for Lumtub itself on or off.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_efficiency_mode(on: bool) -> bool {
    imp::efficient_self(on)
}

/// Ends every process in [job] with exit [code].
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_tree_kill(job: isize, code: u32) -> bool {
    job != 0 && imp::kill(job, code)
}

/// Closes [job]: whatever is still running in it ends too.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_tree_close(job: isize) {
    if job != 0 {
        imp::close(job);
    }
}

#[cfg(all(test, windows))]
mod tests {
    use super::*;
    use std::io::{BufRead, BufReader};
    use std::process::{Command, Stdio};
    use std::thread::sleep;
    use std::time::{Duration, Instant};

    fn alive(pid: u32) -> bool {
        let out = Command::new("tasklist").args(["/FI", &format!("PID eq {pid}"), "/NH"]).output().unwrap();
        String::from_utf8_lossy(&out.stdout).contains(&pid.to_string())
    }

    /// A child that starts a grandchild and prints its pid, as yt-dlp does
    /// with ffmpeg, put in a job: (child, its job, grandchild pid).
    fn start_tree() -> (std::process::Child, isize, u32) {
        let mut child = Command::new("powershell.exe")
            .args([
                "-NoProfile",
                "-Command",
                "$p = Start-Process -PassThru -WindowStyle Hidden ping -ArgumentList '-n','60','127.0.0.1'; Write-Output $p.Id; Start-Sleep 60",
            ])
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let job = lumtub_tree_adopt(child.id());
        assert_ne!(job, 0);
        let mut line = String::new();
        BufReader::new(child.stdout.as_mut().unwrap()).read_line(&mut line).unwrap();
        let grandchild: u32 = line.trim().parse().unwrap();
        assert!(alive(grandchild));
        (child, job, grandchild)
    }

    fn gone_soon(pid: u32) -> bool {
        let start = Instant::now();
        while start.elapsed() < Duration::from_secs(10) {
            if !alive(pid) {
                return true;
            }
            sleep(Duration::from_millis(100));
        }
        false
    }

    #[test]
    fn kill_ends_the_grandchildren_too() {
        let (mut child, job, grandchild) = start_tree();
        assert!(lumtub_tree_kill(job, 1));
        child.wait().unwrap();
        assert!(gone_soon(grandchild));
        lumtub_tree_close(job);
    }

    #[test]
    fn closing_the_job_ends_what_is_left() {
        let (mut child, job, grandchild) = start_tree();
        lumtub_tree_close(job);
        child.wait().unwrap();
        assert!(gone_soon(grandchild));
    }

    #[test]
    fn nothing_to_kill_without_a_job() {
        assert!(!lumtub_tree_kill(0, 1));
        lumtub_tree_close(0);
    }
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use std::process::Command;
    use std::time::{Duration, Instant};

    #[test]
    fn killing_a_tree_ends_the_processes_it_started() {
        let mut shell = Command::new("sh").args(["-c", "sleep 30 & sleep 30 & wait"]).spawn().unwrap();
        let root = shell.id();
        let deadline = Instant::now() + Duration::from_secs(5);
        while super::imp::children(root as libc::pid_t).len() < 2 && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(20));
        }
        let sleepers = super::imp::children(root as libc::pid_t);
        assert_eq!(sleepers.len(), 2);
        let job = super::lumtub_tree_adopt(root);
        assert!(super::lumtub_tree_kill(job, 1));
        shell.wait().unwrap();
        std::thread::sleep(Duration::from_millis(100));
        for pid in sleepers {
            let state = std::fs::read_to_string(format!("/proc/{pid}/stat")).unwrap_or_default();
            assert!(state.is_empty() || state.contains(") Z"), "{pid} still runs: {state}");
        }
    }
}

