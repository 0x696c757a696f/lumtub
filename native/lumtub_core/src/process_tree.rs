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

#[cfg(not(windows))]
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
