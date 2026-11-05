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
    //! Without job objects the tree is followed as it grows: every second
    //! the processes whose parent is in a tree join it, remembered with
    //! their start time. A child that outlives its parent is handed to
    //! init and no longer looks related, but it was seen before then, so
    //! [kill] and [close] still end it, as Windows ends what is left in a
    //! job when it closes; so does Lumtub quitting. The start time keeps a
    //! reused pid from being mistaken for one seen earlier.

    use std::collections::HashMap;
    use std::sync::{Mutex, Once};
    use std::time::Duration;

    type Member = (libc::pid_t, u64);

    /// Each tree by its first process: the processes seen in it.
    static TREES: Mutex<Option<HashMap<libc::pid_t, Vec<Member>>>> = Mutex::new(None);
    static WATCH: Once = Once::new();

    fn trees() -> std::sync::MutexGuard<'static, Option<HashMap<libc::pid_t, Vec<Member>>>> {
        TREES.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// The "job" is the first process's id.
    pub fn adopt(pid: u32) -> isize {
        let Ok(root) = libc::pid_t::try_from(pid) else { return 0 };
        let Some(started) = started(root) else { return 0 };
        trees().get_or_insert_with(HashMap::new).insert(root, vec![(root, started)]);
        WATCH.call_once(|| {
            // Lumtub quitting ends the trees, as closing its job objects does
            // on Windows.
            unsafe { libc::atexit(end_all) };
            let _ = std::thread::Builder::new().name("lumtub-tree".into()).spawn(|| loop {
                std::thread::sleep(Duration::from_secs(1));
                let roots: Vec<_> = trees().as_ref().map(|t| t.keys().copied().collect()).unwrap_or_default();
                for root in roots {
                    grow(root);
                }
            });
        });
        pid as isize
    }

    extern "C" fn end_all() {
        // Never waits at exit for a lock some thread may keep.
        let Ok(held) = TREES.try_lock() else { return };
        let roots: Vec<_> = held.as_ref().map(|t| t.keys().copied().collect()).unwrap_or_default();
        drop(held);
        for root in roots {
            close(root as isize);
        }
    }

    /// Adds the processes started since by the tree's members.
    fn grow(root: libc::pid_t) {
        let Some(mut members) = trees().as_ref().and_then(|t| t.get(&root).cloned()) else { return };
        let mut i = 0;
        while i < members.len() {
            let (pid, start) = members[i];
            if started(pid) == Some(start) {
                for child in children(pid) {
                    if !members.iter().any(|m| m.0 == child)
                        && let Some(at) = started(child)
                    {
                        members.push((child, at));
                    }
                }
            }
            i += 1;
        }
        if let Some(tree) = trees().as_mut().and_then(|t| t.get_mut(&root)) {
            for member in members {
                if !tree.contains(&member) {
                    tree.push(member);
                }
            }
        }
    }

    /// The members of the tree still running: those seen before and their
    /// descendants now, each stopped so none starts another meanwhile.
    fn stop_all(root: libc::pid_t) -> Vec<libc::pid_t> {
        let known = trees().as_ref().and_then(|t| t.get(&root).cloned()).unwrap_or_else(|| started(root).map(|s| vec![(root, s)]).unwrap_or_default());
        let mut tree: Vec<libc::pid_t> = known.iter().filter(|(pid, start)| started(*pid) == Some(*start)).map(|m| m.0).collect();
        for pid in &tree {
            unsafe { libc::kill(*pid, libc::SIGSTOP) };
        }
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
        tree
    }

    pub fn kill(job: isize, _code: u32) -> bool {
        let Ok(root) = libc::pid_t::try_from(job) else { return false };
        if root <= 1 {
            return false;
        }
        let mut any = false;
        for pid in stop_all(root).iter().rev() {
            any |= unsafe { libc::kill(*pid, libc::SIGKILL) } == 0;
        }
        any
    }

    /// The first process has ended: what it left running is ended too.
    pub fn close(job: isize) {
        let Ok(root) = libc::pid_t::try_from(job) else { return };
        if root <= 1 {
            return;
        }
        for pid in stop_all(root).iter().rev() {
            unsafe { libc::kill(*pid, libc::SIGKILL) };
        }
        if let Some(trees) = trees().as_mut() {
            trees.remove(&root);
        }
    }

    /// When [pid] started, in the system's own units; None once it is gone.
    #[cfg(target_os = "linux")]
    pub fn started(pid: libc::pid_t) -> Option<u64> {
        let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
        let rest = &stat[stat.rfind(')')? + 1..];
        let mut fields = rest.split_whitespace();
        // A zombie has ended; only its parent's wait is left.
        if fields.next()? == "Z" {
            return None;
        }
        // Field 22, counted from the state, field 3.
        fields.nth(18)?.parse().ok()
    }

    #[cfg(target_os = "macos")]
    pub fn started(pid: libc::pid_t) -> Option<u64> {
        let mut info: libc::proc_bsdinfo = unsafe { std::mem::zeroed() };
        let size = std::mem::size_of::<libc::proc_bsdinfo>() as libc::c_int;
        // SAFETY: [info] is a proc_bsdinfo of the size given.
        let got = unsafe { libc::proc_pidinfo(pid, libc::PROC_PIDTBSDINFO, 0, (&mut info as *mut libc::proc_bsdinfo).cast(), size) };
        // SZOMB is 5.
        (got == size && info.pbi_status != 5).then(|| info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
    }

    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    pub fn started(pid: libc::pid_t) -> Option<u64> {
        (unsafe { libc::kill(pid, 0) } == 0).then_some(0)
    }

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

    #[test]
    fn closing_a_tree_ends_what_its_first_process_left_running() {
        let mut shell = Command::new("sh").args(["-c", "sleep 30 & echo $!; sleep 2.5"]).stdout(std::process::Stdio::piped()).spawn().unwrap();
        let job = super::lumtub_tree_adopt(shell.id());
        let mut line = String::new();
        std::io::BufRead::read_line(&mut std::io::BufReader::new(shell.stdout.take().unwrap()), &mut line).unwrap();
        let orphan: libc::pid_t = line.trim().parse().unwrap();
        shell.wait().unwrap();
        // Handed to init now, no longer a child of the tree.
        assert!(super::imp::started(orphan).is_some());
        super::lumtub_tree_close(job);
        std::thread::sleep(Duration::from_millis(200));
        assert!(super::imp::started(orphan).is_none(), "{orphan} still runs");
    }
}

