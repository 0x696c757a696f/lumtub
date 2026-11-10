//! What the GPU can decode, asked of its driver through Direct3D 11 video
//! decoding, the interface libmpv's d3d11va uses: per codec, the tallest
//! 16:9 picture it decodes, 0 for none. With the graphics adapter and its
//! driver version, so the answer can be kept until either changes.

use serde::Serialize;
use std::os::raw::c_char;

#[derive(Serialize, Debug, PartialEq, Default)]
pub struct Decoders {
    /// The graphics adapter, its PCI ids and driver version.
    pub adapter: String,
    pub h264: u32,
    pub vp9: u32,
    pub av1: u32,
}

/// The heights tried, tallest last.
pub const HEIGHTS: [u32; 4] = [1080, 1440, 2160, 4320];

/// The tallest of [HEIGHTS] that [decodes] accepts, 0 for none.
pub fn tallest(decodes: impl Fn(u32, u32) -> bool) -> u32 {
    HEIGHTS
        .into_iter()
        .filter(|&h| decodes(h * 16 / 9, h))
        .max()
        .unwrap_or(0)
}

#[cfg(windows)]
pub fn probe() -> Option<Decoders> {
    use windows::Win32::Foundation::HMODULE;
    use windows::Win32::Graphics::Direct3D::D3D_DRIVER_TYPE_HARDWARE;
    use windows::Win32::Graphics::Direct3D11::*;
    use windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT_NV12;
    use windows::Win32::Graphics::Dxgi::IDXGIDevice;
    use windows::core::{GUID, Interface};

    unsafe {
        let mut device = None;
        D3D11CreateDevice(
            None,
            D3D_DRIVER_TYPE_HARDWARE,
            HMODULE::default(),
            D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
            None,
            D3D11_SDK_VERSION,
            Some(&mut device),
            None,
            None,
        )
        .ok()?;
        let device = device?;
        let adapter = device.cast::<IDXGIDevice>().ok()?.GetAdapter().ok()?;
        let desc = adapter.GetDesc().ok()?;
        let name = String::from_utf16_lossy(&desc.Description);
        let driver = adapter.CheckInterfaceSupport(&IDXGIDevice::IID).map(|v| {
            let v = v as u64;
            format!(
                "{}.{}.{}.{}",
                v >> 48,
                (v >> 32) & 0xffff,
                (v >> 16) & 0xffff,
                v & 0xffff
            )
        });
        let adapter = format!(
            "{} ({:04x}:{:04x}) {}",
            name.trim_end_matches('\0').trim(),
            desc.VendorId,
            desc.DeviceId,
            driver.unwrap_or_default()
        );
        let video = device.cast::<ID3D11VideoDevice>().ok()?;
        let profiles: Vec<GUID> = (0..video.GetVideoDecoderProfileCount())
            .filter_map(|i| video.GetVideoDecoderProfile(i).ok())
            .collect();
        let height = |profile: GUID| {
            if !profiles.contains(&profile)
                || !video
                    .CheckVideoDecoderFormat(&profile, DXGI_FORMAT_NV12)
                    .is_ok_and(|ok| ok.as_bool())
            {
                return 0;
            }
            tallest(|width, height| {
                let desc = D3D11_VIDEO_DECODER_DESC {
                    Guid: profile,
                    SampleWidth: width,
                    SampleHeight: height,
                    OutputFormat: DXGI_FORMAT_NV12,
                };
                video.GetVideoDecoderConfigCount(&desc).is_ok_and(|n| n > 0)
            })
        };
        Some(Decoders {
            adapter,
            h264: height(D3D11_DECODER_PROFILE_H264_VLD_NOFGT),
            vp9: height(D3D11_DECODER_PROFILE_VP9_VLD_PROFILE0),
            av1: height(D3D11_DECODER_PROFILE_AV1_VLD_PROFILE0),
        })
    }
}

/// Linux: asked of VA-API (libva, loaded when the system has it), the
/// interface libmpv's vaapi uses, on the first render node that answers.
/// NVIDIA's own driver has no VA-API and is not measured.
#[cfg(target_os = "linux")]
pub fn probe() -> Option<Decoders> {
    use std::ffi::{CStr, c_int, c_void};
    use std::os::fd::AsRawFd;

    type Display = *mut c_void;
    #[repr(C)]
    struct Attrib {
        kind: c_int,
        value: u32,
    }
    const VLD: c_int = 1;
    const MAX_WIDTH: c_int = 18;
    const MAX_HEIGHT: c_int = 19;
    const NOT_SUPPORTED: u32 = 0x8000_0000;
    const H264_HIGH: c_int = 7;
    const VP9_PROFILE0: c_int = 19;
    const AV1_PROFILE0: c_int = 32;

    /// A dlopen handle, closed when dropped.
    struct Library(*mut c_void);
    impl Drop for Library {
        fn drop(&mut self) {
            // SAFETY: [self.0] came from dlopen and is closed only here.
            unsafe { libc::dlclose(self.0) };
        }
    }
    unsafe fn open(name: &CStr) -> Option<Library> {
        let library = unsafe { libc::dlopen(name.as_ptr(), libc::RTLD_NOW | libc::RTLD_LOCAL) };
        (!library.is_null()).then_some(Library(library))
    }
    unsafe fn symbol<T>(library: &Library, name: &CStr) -> Option<T> {
        let found = unsafe { libc::dlsym(library.0, name.as_ptr()) };
        // SAFETY: T is the function pointer type of [name].
        (!found.is_null()).then(|| unsafe { std::mem::transmute_copy::<*mut c_void, T>(&found) })
    }

    // SAFETY: libva's documented C functions, called with the types va.h gives.
    unsafe {
        let va = open(c"libva.so.2")?;
        let drm = open(c"libva-drm.so.2")?;
        let get_display: unsafe extern "C" fn(c_int) -> Display = symbol(&drm, c"vaGetDisplayDRM")?;
        let initialize: unsafe extern "C" fn(Display, *mut c_int, *mut c_int) -> c_int =
            symbol(&va, c"vaInitialize")?;
        let terminate: unsafe extern "C" fn(Display) -> c_int = symbol(&va, c"vaTerminate")?;
        let vendor: unsafe extern "C" fn(Display) -> *const std::ffi::c_char =
            symbol(&va, c"vaQueryVendorString")?;
        let max_profiles: unsafe extern "C" fn(Display) -> c_int =
            symbol(&va, c"vaMaxNumProfiles")?;
        let query_profiles: unsafe extern "C" fn(Display, *mut c_int, *mut c_int) -> c_int =
            symbol(&va, c"vaQueryConfigProfiles")?;
        let max_entrypoints: unsafe extern "C" fn(Display) -> c_int =
            symbol(&va, c"vaMaxNumEntrypoints")?;
        let query_entrypoints: unsafe extern "C" fn(
            Display,
            c_int,
            *mut c_int,
            *mut c_int,
        ) -> c_int = symbol(&va, c"vaQueryConfigEntrypoints")?;
        let get_attributes: unsafe extern "C" fn(
            Display,
            c_int,
            c_int,
            *mut Attrib,
            c_int,
        ) -> c_int = symbol(&va, c"vaGetConfigAttributes")?;

        let mut nodes: Vec<_> = std::fs::read_dir("/dev/dri")
            .ok()?
            .flatten()
            .map(|e| e.path())
            .filter(|p| {
                p.file_name()
                    .is_some_and(|n| n.to_string_lossy().starts_with("renderD"))
            })
            .collect();
        nodes.sort();
        for node in nodes {
            let Ok(file) = std::fs::OpenOptions::new()
                .read(true)
                .write(true)
                .open(&node)
            else {
                continue;
            };
            let display = get_display(file.as_raw_fd());
            if display.is_null() {
                continue;
            }
            let (mut major, mut minor) = (0, 0);
            if initialize(display, &mut major, &mut minor) != 0 {
                terminate(display);
                continue;
            }
            let name = vendor(display);
            let name = if name.is_null() {
                String::new()
            } else {
                CStr::from_ptr(name).to_string_lossy().into_owned()
            };
            let mut profiles = vec![0; max_profiles(display).max(0) as usize];
            let mut count = 0;
            if query_profiles(display, profiles.as_mut_ptr(), &mut count) != 0 {
                count = 0;
            }
            profiles.truncate(count.max(0) as usize);
            let height = |profile: c_int| -> u32 {
                if !profiles.contains(&profile) {
                    return 0;
                }
                let mut entrypoints = vec![0; max_entrypoints(display).max(0) as usize];
                let mut count = 0;
                if query_entrypoints(display, profile, entrypoints.as_mut_ptr(), &mut count) != 0
                    || !entrypoints[..count.max(0) as usize].contains(&VLD)
                {
                    return 0;
                }
                let mut attributes = [
                    Attrib {
                        kind: MAX_WIDTH,
                        value: 0,
                    },
                    Attrib {
                        kind: MAX_HEIGHT,
                        value: 0,
                    },
                ];
                let known = get_attributes(display, profile, VLD, attributes.as_mut_ptr(), 2) == 0;
                let (width, tall) = (attributes[0].value, attributes[1].value);
                // Drivers that do not say decode at least 4K.
                let (width, tall) = if !known
                    || width == NOT_SUPPORTED
                    || tall == NOT_SUPPORTED
                    || width == 0
                    || tall == 0
                {
                    (3840, 2160)
                } else {
                    (width, tall)
                };
                tallest(|w, h| w <= width && h <= tall)
            };
            let decoders = Decoders {
                adapter: format!("{name} ({}) VA-API {major}.{minor}", node.display()),
                h264: height(H264_HIGH),
                vp9: height(VP9_PROFILE0),
                av1: height(AV1_PROFILE0),
            };
            terminate(display);
            return Some(decoders);
        }
        None
    }
}

/// macOS: asked of VideoToolbox, the interface libmpv's videotoolbox uses.
/// VP9 and AV1 are supplemental decoders that are registered first, as
/// FFmpeg does. VideoToolbox gives no size limit, so the usual ones of
/// Apple's media engines are assumed.
#[cfg(target_os = "macos")]
pub fn probe() -> Option<Decoders> {
    #[link(name = "VideoToolbox", kind = "framework")]
    unsafe extern "C" {
        fn VTIsHardwareDecodeSupported(codec: u32) -> u8;
        fn VTRegisterSupplementalVideoDecoderIfAvailable(codec: u32);
    }
    const H264: u32 = u32::from_be_bytes(*b"avc1");
    const VP9: u32 = u32::from_be_bytes(*b"vp09");
    const AV1: u32 = u32::from_be_bytes(*b"av01");

    // SAFETY: VideoToolbox functions taking a four-character codec code.
    let supported = |codec: u32, height: u32| -> u32 {
        unsafe {
            if codec != H264 {
                VTRegisterSupplementalVideoDecoderIfAvailable(codec);
            }
            if VTIsHardwareDecodeSupported(codec) != 0 {
                height
            } else {
                0
            }
        }
    };
    Some(Decoders {
        adapter: format!("{} VideoToolbox", model()),
        h264: supported(H264, 2160),
        vp9: supported(VP9, 4320),
        av1: supported(AV1, 4320),
    })
}

#[cfg(target_os = "macos")]
fn model() -> String {
    let mut buffer = [0u8; 128];
    let mut size = buffer.len();
    // SAFETY: sysctlbyname writes at most [size] bytes into [buffer].
    let found = unsafe {
        libc::sysctlbyname(
            c"hw.model".as_ptr(),
            buffer.as_mut_ptr().cast(),
            &mut size,
            std::ptr::null_mut(),
            0,
        )
    } == 0;
    if !found {
        return "Mac".into();
    }
    String::from_utf8_lossy(&buffer[..size])
        .trim_end_matches('\0')
        .to_string()
}

#[cfg(not(any(windows, target_os = "linux", target_os = "macos")))]
pub fn probe() -> Option<Decoders> {
    None
}

/// [probe] as JSON, or null where it cannot ask the GPU.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_hw_decoders() -> *mut c_char {
    probe().map_or(std::ptr::null_mut(), |d| crate::taste::give_json(&d))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_the_tallest_height() {
        assert_eq!(tallest(|_, h| h <= 2160), 2160);
        assert_eq!(tallest(|w, _| w <= 1920), 1080);
        assert_eq!(tallest(|_, _| false), 0);
    }
}
