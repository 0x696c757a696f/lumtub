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
    HEIGHTS.into_iter().filter(|&h| decodes(h * 16 / 9, h)).max().unwrap_or(0)
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
        D3D11CreateDevice(None, D3D_DRIVER_TYPE_HARDWARE, HMODULE::default(), D3D11_CREATE_DEVICE_VIDEO_SUPPORT, None, D3D11_SDK_VERSION, Some(&mut device), None, None).ok()?;
        let device = device?;
        let adapter = device.cast::<IDXGIDevice>().ok()?.GetAdapter().ok()?;
        let desc = adapter.GetDesc().ok()?;
        let name = String::from_utf16_lossy(&desc.Description);
        let driver = adapter.CheckInterfaceSupport(&IDXGIDevice::IID).map(|v| {
            let v = v as u64;
            format!("{}.{}.{}.{}", v >> 48, (v >> 32) & 0xffff, (v >> 16) & 0xffff, v & 0xffff)
        });
        let adapter = format!("{} ({:04x}:{:04x}) {}", name.trim_end_matches('\0').trim(), desc.VendorId, desc.DeviceId, driver.unwrap_or_default());
        let video = device.cast::<ID3D11VideoDevice>().ok()?;
        let profiles: Vec<GUID> = (0..video.GetVideoDecoderProfileCount()).filter_map(|i| video.GetVideoDecoderProfile(i).ok()).collect();
        let height = |profile: GUID| {
            if !profiles.contains(&profile) || !video.CheckVideoDecoderFormat(&profile, DXGI_FORMAT_NV12).is_ok_and(|ok| ok.as_bool()) {
                return 0;
            }
            tallest(|width, height| {
                let desc = D3D11_VIDEO_DECODER_DESC { Guid: profile, SampleWidth: width, SampleHeight: height, OutputFormat: DXGI_FORMAT_NV12 };
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

#[cfg(not(windows))]
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
