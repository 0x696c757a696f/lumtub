// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#ifndef ANGLE_SURFACE_MANAGER_H_
#define ANGLE_SURFACE_MANAGER_H_

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <EGL/eglplatform.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#include <Windows.h>

#include <d3d.h>
#include <d3d11.h>
#include <d3d11_4.h>
#include <wrl.h>

#include "frame_stats.h"
#include "utils.h"

#include <atomic>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>

// |ANGLESurfaceManager| provides an abstraction around ANGLE to easily draw
// OpenGL ES 2.0 content & read as D3D 11 texture using shared |HANDLE|.
// * |Draw|: Takes callback where OpenGL ES 2.0 calls can be made for rendering.
// * |Read|: Returns the shared |HANDLE| of the last frame drawn.
//
// Lumtub: frames are drawn straight into a ring of shared textures that
// Flutter samples, instead of into one texture copied into another for each
// frame Flutter shows. A frame is handed out only once the GPU has finished
// drawing it, and a texture is drawn into again only after Flutter has
// taken two newer ones, so Flutter never samples one being drawn.

// A large part of implementation is inspired from Flutter.
// https://github.com/flutter/engine/blob/master/shell/platform/windows/angle_surface_manager.h

class ANGLESurfaceManager {
 public:
  const int32_t width() const { return width_; }
  const int32_t height() const { return height_; }
  const HANDLE handle() const { return handles_[front_]; }

  ANGLESurfaceManager(int32_t width, int32_t height);

  ~ANGLESurfaceManager();

  void SetSize(int32_t width, int32_t height);

  void Draw(std::function<void()> callback);

  HANDLE Read();

  void MakeCurrent(bool value);

  // Lumtub: how long drawing and Flutter's reads take, lock waits included.
  FrameTiming draw_timing;
  FrameTiming read_timing;
  // Lumtub: "frames=drawn/shown", frames drawn and frames Flutter took,
  // then starts again. More drawn than shown is work nobody saw.
  std::string TakeFrameStats();

 private:
  void SwapBuffers();

  void Create();

  void CleanUp(bool release_context);

  bool CreateD3DTexture();

  bool CreateEGLDisplay();

  bool CreateAndBindEGLSurface();

  int PickTarget();

  int32_t width_ = 1;
  int32_t height_ = 1;
  // Lumtub: the ring. |front_| is the last frame drawn, |taken_| the frames
  // Flutter took last and the one before, |drawing_| the one being drawn.
  static constexpr int kBuffers = 4;
  HANDLE handles_[kBuffers] = {};
  Microsoft::WRL::ComPtr<ID3D11Texture2D> textures_[kBuffers];
  EGLSurface surfaces_[kBuffers] = {EGL_NO_SURFACE, EGL_NO_SURFACE,
                                    EGL_NO_SURFACE, EGL_NO_SURFACE};
  uint64_t used_[kBuffers] = {};
  uint64_t clock_ = 0;
  int front_ = 0;
  int taken_[2] = {-1, -1};
  int drawing_ = -1;
  std::mutex ring_mutex_;
  std::atomic<uint64_t> drawn_{0};
  std::atomic<uint64_t> shown_{0};

  // Sync |Draw| with |SetSize| and the context's other users.
  HANDLE mutex_ = nullptr;
  // D3D 11
  ID3D11Device* d3d_11_device_ = nullptr;
  ID3D11DeviceContext* d3d_11_device_context_ = nullptr;
  // ANGLE
  EGLDisplay display_ = EGL_NO_DISPLAY;
  EGLContext context_ = nullptr;
  EGLConfig config_ = nullptr;

  static constexpr EGLint kEGLConfigurationAttributes[] = {
      EGL_RED_SIZE,   8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE,    8,
      EGL_ALPHA_SIZE, 8, EGL_DEPTH_SIZE, 0, EGL_STENCIL_SIZE, 0,
      EGL_NONE,
  };
  static constexpr EGLint kEGLContextAttributes[] = {
      EGL_CONTEXT_CLIENT_VERSION,
      2,
      EGL_NONE,
  };
  static constexpr EGLint kD3D11DisplayAttributes[] = {
      EGL_PLATFORM_ANGLE_TYPE_ANGLE,
      EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE,
      EGL_PLATFORM_ANGLE_ENABLE_AUTOMATIC_TRIM_ANGLE,
      EGL_TRUE,
      EGL_NONE,
  };
  static constexpr EGLint kD3D11_9_3DisplayAttributes[] = {
      EGL_PLATFORM_ANGLE_TYPE_ANGLE,
      EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE,
      EGL_PLATFORM_ANGLE_MAX_VERSION_MAJOR_ANGLE,
      9,
      EGL_PLATFORM_ANGLE_MAX_VERSION_MINOR_ANGLE,
      3,
      EGL_PLATFORM_ANGLE_ENABLE_AUTOMATIC_TRIM_ANGLE,
      EGL_TRUE,
      EGL_NONE,
  };
  static constexpr EGLint kD3D9DisplayAttributes[] = {
      EGL_PLATFORM_ANGLE_TYPE_ANGLE,
      EGL_PLATFORM_ANGLE_TYPE_D3D9_ANGLE,
      EGL_PLATFORM_ANGLE_DEVICE_TYPE_ANGLE,
      EGL_PLATFORM_ANGLE_DEVICE_TYPE_HARDWARE_ANGLE,
      EGL_NONE,
  };
  static constexpr EGLint kWrapDisplayAttributes[] = {
      EGL_PLATFORM_ANGLE_TYPE_ANGLE,
      EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE,
      EGL_PLATFORM_ANGLE_ENABLE_AUTOMATIC_TRIM_ANGLE,
      EGL_TRUE,
      EGL_NONE,
  };

  // Number of active instances of ANGLESurfaceManager.
  static int32_t instance_count_;
};

#endif  // ANGLE_SURFACE_MANAGER_H_
