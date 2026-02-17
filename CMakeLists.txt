cmake_minimum_required(VERSION 3.20)
project(WeatherGlance-Lite LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)

# ── WebView2 NuGet package ──────────────────────────────────────
# Download the WebView2 SDK header + loader from NuGet
include(FetchContent)
FetchContent_Declare(webview2
  URL https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.3179.45
  URL_HASH SHA256=0
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
# We'll handle this manually below since NuGet packages aren't CMake-native

# For now, expect WebView2 SDK to be extracted to deps/webview2/
# Run: nuget install Microsoft.Web.WebView2 -Version 1.0.3179.45 -OutputDirectory deps
set(WV2_DIR "${CMAKE_SOURCE_DIR}/deps/Microsoft.Web.WebView2.1.0.3179.45")
set(WV2_INCLUDE "${WV2_DIR}/build/native/include")
set(WV2_LIB_DIR "${WV2_DIR}/build/native/x64")
set(WV2_LOADER "${WV2_DIR}/build/native/x64/WebView2LoaderStatic.lib")

add_executable(WeatherGlance WIN32
  main.cpp
  WeatherGlance.rc
)

target_include_directories(WeatherGlance PRIVATE "${WV2_INCLUDE}")
target_link_libraries(WeatherGlance PRIVATE "${WV2_LOADER}" shlwapi ole32 shell32)
target_link_options(WeatherGlance PRIVATE /MANIFEST:EMBED /MANIFESTINPUT:${CMAKE_SOURCE_DIR}/app.manifest)

# Minimize exe size
target_compile_options(WeatherGlance PRIVATE /O1 /GS- /GL)
target_link_options(WeatherGlance PRIVATE /LTCG /OPT:REF /OPT:ICF)
