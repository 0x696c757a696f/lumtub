# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.14)

# This option is read by the other packages which are part of package:media_kit.
option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_video")
project(${PROJECT_NAME} LANGUAGES CXX)

# Deal with MSVC incompatiblity
add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

# ------------------------------------------------------------------------------
# Lumtub: checked by SHA-256 instead of MD5.
function(download_and_verify url sha256 locationForArchive)
  # Check if the archive exists.
  if(EXISTS "${locationForArchive}")
    file(SHA256 "${locationForArchive}" ARCHIVE_SHA256)

    # If SHA-256 doesn't match, delete the archive to download again.
    if(NOT sha256 STREQUAL ARCHIVE_SHA256)
      file(REMOVE "${locationForArchive}")
      message(STATUS "SHA-256 mismatch. File deleted.")
    endif()
  endif()

  # Download the archive if it doesn't exist.
  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "Downloading archive from ${url}...")
    file(DOWNLOAD "${url}" "${locationForArchive}")
    message(STATUS "Downloaded archive to ${locationForArchive}.")

    # Verify SHA-256 of the newly downloaded file.
    file(SHA256 "${locationForArchive}" ARCHIVE_SHA256)

    if(sha256 STREQUAL ARCHIVE_SHA256)
      message(STATUS "${locationForArchive} Verification successful.")
    else()
      message(FATAL_ERROR "${locationForArchive} Integrity check failed, please try to re-build project again.")
    endif()
  endif()
endfunction()

function(check_directory_exists_and_not_empty dir result_var)
  # Check if the directory exists
  if(EXISTS "${dir}")
    # Check if the directory is not empty
    file(GLOB dir_contents "${dir}/*")

    if(dir_contents)
      set(${result_var} TRUE PARENT_SCOPE)
    else()
      set(${result_var} FALSE PARENT_SCOPE)
      message(STATUS "Directory ${dir} exists but is empty!")
    endif()
  else()
    set(${result_var} FALSE PARENT_SCOPE)
    message(STATUS "Directory ${dir} does not exist!")
  endif()
endfunction()

# Lumtub: media_kit only publishes x64 libmpv and ANGLE. An ARM64 build
# expects both already unpacked by the build workflow (libmpv from
# zhongfly/mpv-winbuild aarch64, ANGLE built from source for arm64) in the
# same folders the x64 archives would be extracted to.
if(CMAKE_GENERATOR_PLATFORM MATCHES "^[Aa][Rr][Mm]64$" OR CMAKE_VS_PLATFORM_NAME MATCHES "^[Aa][Rr][Mm]64$")
  set(LUMTUB_ARM64 TRUE)
else()
  set(LUMTUB_ARM64 FALSE)
endif()

if(LUMTUB_ARM64)
  set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")
  set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE")
  foreach(required
      "${LIBMPV_SRC}/libmpv-2.dll" "${LIBMPV_SRC}/libmpv.dll.a" "${LIBMPV_SRC}/include/client.h"
      "${ANGLE_SRC}/libEGL.dll" "${ANGLE_SRC}/libGLESv2.dll" "${ANGLE_SRC}/d3dcompiler_47.dll"
      "${ANGLE_SRC}/lib/libEGL.dll.lib" "${ANGLE_SRC}/lib/libGLESv2.dll.lib" "${ANGLE_SRC}/include/EGL/egl.h")
    if(NOT EXISTS "${required}")
      message(FATAL_ERROR "media_kit: ARM64 build needs ${required}; the build workflow prepares it.")
    endif()
  endforeach()
else()
  # libmpv archive containing the pre-built shared libraries & headers.
  set(LIBMPV "mpv-dev-x86_64-20230924-git-652a1dd.7z")

  # Download URL & SHA-256 hash of the libmpv archive.
  set(LIBMPV_URL "https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/${LIBMPV}")
  set(LIBMPV_SHA256 "dce982222d7a23e4a1c6f0fb6cc39f6e899a6714624b95ea49cff6558ee97572")

  # Download location of the libmpv archive.
  set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
  set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")

  download_and_verify(
    ${LIBMPV_URL}
    ${LIBMPV_SHA256}
    ${LIBMPV_ARCHIVE}
  )

  check_directory_exists_and_not_empty(${LIBMPV_SRC} LIBMPV_SRC_VALID)

  # Extract the libmpv archive.
  if(NOT LIBMPV_SRC_VALID)
    message(STATUS "Extracting ${LIBMPV}...")
    make_directory("${LIBMPV_SRC}")
    add_custom_target("${PROJECT_NAME}_LIBMPV_EXTRACT" ALL)
    add_custom_command(
      TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT"
      COMMAND "${CMAKE_COMMAND}" -E tar xzf "\"${LIBMPV_ARCHIVE}\""
      COMMAND xcopy "\"${LIBMPV_SRC}/include/mpv\"" "\"${LIBMPV_SRC}/mpv\"" /E /H /C /I
      COMMAND rmdir "\"${LIBMPV_SRC}/include\"" /S /Q
      COMMAND ren "\"${LIBMPV_SRC}/mpv\"" "\"include\""
      WORKING_DIRECTORY "${LIBMPV_SRC}"
    )
  endif()

  # ------------------------------------------------------------------------------

  # ANGLE archive containing the pre-built shared libraries & headers.
  set(ANGLE "ANGLE.7z")

  # Download URL & SHA-256 hash of the ANGLE archive.
  set(ANGLE_URL "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z")
  set(ANGLE_SHA256 "cc5911bb15d596fd5a2b362613ad35b7093b427117269a7359054a65746a5f9a")

  # Download location of the ANGLE archive.
  set(ANGLE_ARCHIVE "${CMAKE_BINARY_DIR}/${ANGLE}")
  set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE")

  download_and_verify(
    ${ANGLE_URL}
    ${ANGLE_SHA256}
    ${ANGLE_ARCHIVE}
  )

  check_directory_exists_and_not_empty(${ANGLE_SRC} ANGLE_SRC_VALID)

  # Extract the ANGLE archive.
  if(NOT ANGLE_SRC_VALID)
    message(STATUS "Extracting ${ANGLE}...")
    make_directory("${ANGLE_SRC}")
    add_custom_target("${PROJECT_NAME}_ANGLE_EXTRACT" ALL)
    add_custom_command(
      TARGET "${PROJECT_NAME}_ANGLE_EXTRACT"
      COMMAND "${CMAKE_COMMAND}" -E tar xzf "\"${ANGLE_ARCHIVE}\""
      WORKING_DIRECTORY "${ANGLE_SRC}"
    )
  endif()
endif()

# ------------------------------------------------------------------------------
set(PLUGIN_NAME "media_kit_libs_windows_video_plugin")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h"
  "media_kit_libs_windows_video_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(
  ${PLUGIN_NAME}
  PROPERTIES
  CXX_VISIBILITY_PRESET
  hidden
)
target_compile_definitions(
  ${PLUGIN_NAME}
  PRIVATE
  FLUTTER_PLUGIN_IMPL
)

target_include_directories(
  ${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(
  ${PLUGIN_NAME}
  PRIVATE
  flutter
  flutter_wrapper_plugin
)

if(LUMTUB_ARM64)
  # Only what an arm64 ANGLE D3D11 build needs, plus any DLL it depends on.
  file(GLOB lumtub_angle_dlls "${ANGLE_SRC}/*.dll")
  set(
    media_kit_libs_windows_video_bundled_libraries
    "${LIBMPV_SRC}/libmpv-2.dll"
    ${lumtub_angle_dlls}
    PARENT_SCOPE
  )
  return()
endif()

# Lumtub: the archive's zlib.dll is a debug build (it needs VCRUNTIME140D.dll,
# which no user has) and nothing in it imports zlib.dll, so it is left out.
set(
  media_kit_libs_windows_video_bundled_libraries
  "${LIBMPV_SRC}/libmpv-2.dll"
  "${ANGLE_SRC}/d3dcompiler_47.dll"
  "${ANGLE_SRC}/libEGL.dll"
  "${ANGLE_SRC}/libGLESv2.dll"
  "${ANGLE_SRC}/vk_swiftshader.dll"
  "${ANGLE_SRC}/vulkan-1.dll"
  PARENT_SCOPE
)
