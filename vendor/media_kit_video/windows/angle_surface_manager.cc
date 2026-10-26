// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.
#include "angle_surface_manager.h"

#include <iostream>

#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3d11.lib")

#define FAIL(message)                                                 \
  std::cout << "media_kit: ANGLESurfaceManager: Failure: " << message \
            << std::endl;                                             \
  return false

#define CHECK_HRESULT(message) \
  if (FAILED(hr)) {            \
    FAIL(message);             \
  }

int ANGLESurfaceManager::instance_count_ = 0;

ANGLESurfaceManager::ANGLESurfaceManager(int32_t width, int32_t height)
    : width_(width), height_(height) {
  mutex_ = ::CreateMutex(NULL, FALSE, NULL);
  instance_count_++;
  try {
    Create();
  } catch (...) {
    CleanUp(true);
    ::CloseHandle(mutex_);
    instance_count_--;
    throw;
  }
}

ANGLESurfaceManager::~ANGLESurfaceManager() {
  CleanUp(true);
  ::CloseHandle(mutex_);
  instance_count_--;
}

void ANGLESurfaceManager::SetSize(int32_t width, int32_t height) {
  if (width == width_ && height == height_) {
    return;
  }
  width_ = width;
  height_ = height;
  Create();
}

void ANGLESurfaceManager::Draw(std::function<void()> callback) {
  const auto start = std::chrono::steady_clock::now();
  ::WaitForSingleObject(mutex_, INFINITE);
  const auto target = PickTarget();
  eglMakeCurrent(display_, surfaces_[target], surfaces_[target], context_);
  callback();
  // Lumtub: the frame is handed to Flutter only once the GPU has drawn it.
  SwapBuffers();
  MakeCurrent(false);
  {
    std::lock_guard<std::mutex> lock(ring_mutex_);
    front_ = target;
  }
  drawn_++;
  ::ReleaseMutex(mutex_);
  draw_timing.Add(std::chrono::steady_clock::now() - start);
}

int ANGLESurfaceManager::PickTarget() {
  std::lock_guard<std::mutex> lock(ring_mutex_);
  // Neither the frame Flutter may take next nor the two it took last, which
  // its GPU may still be sampling; of the others, the longest unused.
  auto target = -1;
  for (auto i = 0; i < kBuffers; i++) {
    if (i == front_ || i == taken_[0] || i == taken_[1]) {
      continue;
    }
    if (target < 0 || used_[i] < used_[target]) {
      target = i;
    }
  }
  used_[target] = ++clock_;
  return target;
}

HANDLE ANGLESurfaceManager::Read() {
  const auto start = std::chrono::steady_clock::now();
  HANDLE handle;
  {
    std::lock_guard<std::mutex> lock(ring_mutex_);
    if (taken_[0] != front_) {
      taken_[1] = taken_[0];
      taken_[0] = front_;
      shown_++;
    }
    handle = handles_[front_];
  }
  read_timing.Add(std::chrono::steady_clock::now() - start);
  return handle;
}

std::string ANGLESurfaceManager::TakeFrameStats() {
  return "frames=" + std::to_string(drawn_.exchange(0)) + "/" +
         std::to_string(shown_.exchange(0));
}

void ANGLESurfaceManager::MakeCurrent(bool value) {
  if (value) {
    eglMakeCurrent(display_, surfaces_[0], surfaces_[0], context_);
  } else {
    eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  }
}

void ANGLESurfaceManager::SwapBuffers() {
  glFinish();
}

void ANGLESurfaceManager::Create() {
  CleanUp(false);
  if (!CreateD3DTexture()) {
    throw std::runtime_error("Unable to create Windows Direct3D device.");
    return;
  }
  if (!CreateEGLDisplay()) {
    throw std::runtime_error("Unable to create ANGLE EGL display.");
    return;
  }
  if (!CreateAndBindEGLSurface()) {
    throw std::runtime_error("Unable to create ANGLE EGL surface.");
    return;
  }
  for (auto handle : handles_) {
    if (handle == nullptr) {
      throw std::runtime_error("Unable to retrieve Direct3D shared HANDLE.");
    }
  }
  std::lock_guard<std::mutex> lock(ring_mutex_);
  front_ = 0;
  taken_[0] = taken_[1] = -1;
  for (auto& used : used_) {
    used = 0;
  }
}

void ANGLESurfaceManager::CleanUp(bool release_context) {
  if (display_ != EGL_NO_DISPLAY) {
    MakeCurrent(false);
  }
  for (auto& surface : surfaces_) {
    if (surface != EGL_NO_SURFACE) {
      eglDestroySurface(display_, surface);
      surface = EGL_NO_SURFACE;
    }
  }
  if (release_context) {
    if (display_ != EGL_NO_DISPLAY && context_ != EGL_NO_CONTEXT) {
      eglDestroyContext(display_, context_);
      context_ = EGL_NO_CONTEXT;
    }
    if (instance_count_ == 1 && display_ != EGL_NO_DISPLAY) {
      eglTerminate(display_);
    }
    display_ = EGL_NO_DISPLAY;
    // Release D3D device & context if the instance is being destroyed.
    if (d3d_11_device_context_) {
      d3d_11_device_context_->Release();
      d3d_11_device_context_ = nullptr;
    }
    if (d3d_11_device_) {
      d3d_11_device_->Release();
      d3d_11_device_ = nullptr;
    }
  }
  // Release D3D 11 texture(s).
  for (auto i = 0; i < kBuffers; i++) {
    textures_[i].Reset();
    handles_[i] = nullptr;
  }
}

bool ANGLESurfaceManager::CreateD3DTexture() {
  if (d3d_11_device_ == nullptr) {
    // NOTE: Not enabling Feature Level 12. It crashes directly on Windows 7.
    const auto feature_levels = {
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0,
        D3D_FEATURE_LEVEL_9_3,
    };

    IDXGIAdapter* adapter = nullptr;
    D3D_DRIVER_TYPE driver_type = D3D_DRIVER_TYPE_UNKNOWN;

    // NOTE: Automatically selecting adapter on Windows 10 RTM or greater.
    if (Utils::IsWindows10RTMOrGreater()) {
      adapter = NULL;
      driver_type = D3D_DRIVER_TYPE_HARDWARE;
    } else {
      IDXGIFactory* dxgi = nullptr;
      ::CreateDXGIFactory(__uuidof(IDXGIFactory), (void**)&dxgi);
      // As far as my experience goes, this is the safest approach. Passing NULL
      // (so-called default) seems to cause issues on Windows 7 or maybe some
      // older graphics drivers. First adapter is the default.
      // D3D_DRIVER_TYPE_UNKNOWN| must be passed with manual adapter selection.
      dxgi->EnumAdapters(0, &adapter);
      dxgi->Release();
    }

    auto hr = ::D3D11CreateDevice(
        adapter, driver_type, 0, 0, feature_levels.begin(),
        static_cast<UINT>(feature_levels.size()), D3D11_SDK_VERSION,
        &d3d_11_device_, 0, &d3d_11_device_context_);
    if (adapter) {
      adapter->Release();
    }
    CHECK_HRESULT("D3D11CreateDevice");
  }

  Microsoft::WRL::ComPtr<IDXGIDevice> dxgi_device = nullptr;
  auto dxgi_device_success = d3d_11_device_->QueryInterface(
      __uuidof(IDXGIDevice), (void**)&dxgi_device);
  if (SUCCEEDED(dxgi_device_success) && dxgi_device != nullptr) {
    dxgi_device->SetGPUThreadPriority(5);  // Must be in interval [-7, 7].
  }

  auto level = d3d_11_device_->GetFeatureLevel();
  std::cout << "media_kit: ANGLESurfaceManager: Direct3D Feature Level: "
            << (((unsigned)level) >> 12) << "_"
            << ((((unsigned)level) >> 8) & 0xf) << std::endl;
  auto d3d11_texture2D_desc = D3D11_TEXTURE2D_DESC{0};
  d3d11_texture2D_desc.Width = width_;
  d3d11_texture2D_desc.Height = height_;
  d3d11_texture2D_desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  d3d11_texture2D_desc.MipLevels = 1;
  d3d11_texture2D_desc.ArraySize = 1;
  d3d11_texture2D_desc.SampleDesc.Count = 1;
  d3d11_texture2D_desc.SampleDesc.Quality = 0;
  d3d11_texture2D_desc.Usage = D3D11_USAGE_DEFAULT;
  d3d11_texture2D_desc.BindFlags =
      D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  d3d11_texture2D_desc.CPUAccessFlags = 0;
  d3d11_texture2D_desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

  // Lumtub: the ring of textures ANGLE draws into and Flutter samples
  // through their shared |HANDLE|s.
  for (auto i = 0; i < kBuffers; i++) {
    auto hr = d3d_11_device_->CreateTexture2D(&d3d11_texture2D_desc, nullptr,
                                              &textures_[i]);
    CHECK_HRESULT("ID3D11Device::CreateTexture2D");
    auto resource = Microsoft::WRL::ComPtr<IDXGIResource>{};
    hr = textures_[i].As(&resource);
    CHECK_HRESULT("ID3D11Texture2D::As");
    // Retrieve the shared |HANDLE| for interop.
    hr = resource->GetSharedHandle(&handles_[i]);
    CHECK_HRESULT("IDXGIResource::GetSharedHandle");
  }

  return true;
}

bool ANGLESurfaceManager::CreateEGLDisplay() {
  if (display_ == EGL_NO_DISPLAY) {
    auto eglGetPlatformDisplayEXT =
        reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(
            eglGetProcAddress("eglGetPlatformDisplayEXT"));
    if (eglGetPlatformDisplayEXT) {
      display_ = eglGetPlatformDisplayEXT(EGL_PLATFORM_ANGLE_ANGLE,
                                          EGL_DEFAULT_DISPLAY,
                                          kD3D11DisplayAttributes);
      if (eglInitialize(display_, 0, 0) == EGL_FALSE) {
        display_ = eglGetPlatformDisplayEXT(EGL_PLATFORM_ANGLE_ANGLE,
                                            EGL_DEFAULT_DISPLAY,
                                            kD3D11_9_3DisplayAttributes);
        if (eglInitialize(display_, 0, 0) == EGL_FALSE) {
          display_ = eglGetPlatformDisplayEXT(EGL_PLATFORM_ANGLE_ANGLE,
                                              EGL_DEFAULT_DISPLAY,
                                              kD3D9DisplayAttributes);
          if (eglInitialize(display_, 0, 0) == EGL_FALSE) {
            display_ = eglGetPlatformDisplayEXT(EGL_PLATFORM_ANGLE_ANGLE,
                                                EGL_DEFAULT_DISPLAY,
                                                kWrapDisplayAttributes);
            if (eglInitialize(display_, 0, 0) == EGL_FALSE) {
              FAIL("eglGetPlatformDisplayEXT");
            }
          }
        }
      }
    } else {
      FAIL("eglGetProcAddress");
    }
  }
  return true;
}

bool ANGLESurfaceManager::CreateAndBindEGLSurface() {
  // Do not create |context_| again, likely due to |Resize|.
  if (context_ == EGL_NO_CONTEXT) {
    // First time from the constructor itself.
    auto count = 0;
    auto result = eglChooseConfig(display_, kEGLConfigurationAttributes,
                                  &config_, 1, &count);
    if (result == EGL_FALSE || count == 0) {
      FAIL("eglChooseConfig");
    }
    context_ = eglCreateContext(display_, config_, EGL_NO_CONTEXT,
                                kEGLContextAttributes);
    if (context_ == EGL_NO_CONTEXT) {
      FAIL("eglCreateContext");
    }
  }
  EGLint buffer_attributes[] = {
      EGL_WIDTH,          width_,         EGL_HEIGHT,         height_,
      EGL_TEXTURE_TARGET, EGL_TEXTURE_2D, EGL_TEXTURE_FORMAT, EGL_TEXTURE_RGBA,
      EGL_NONE,
  };
  for (auto i = 0; i < kBuffers; i++) {
    surfaces_[i] = eglCreatePbufferFromClientBuffer(
        display_, EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE, handles_[i], config_,
        buffer_attributes);
    if (surfaces_[i] == EGL_NO_SURFACE) {
      FAIL("eglCreatePbufferFromClientBuffer");
    }
  }
  // libmpv renders to the pbuffer directly; no GL sampling texture is needed.
  return true;
}
