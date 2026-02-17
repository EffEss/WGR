cmake_minimum_required(VERSION 3.20)
project(WeatherGlance-Lite LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)

# ── WebView2 NuGet package ──────────────────────────────────────
# Expect WebView2 SDK to be extracted to deps/
# Run: nuget install Microsoft.Web.WebView2 -Version 1.0.3179.45 -OutputDirectory deps
# Or use build.ps1 which downloads it automatically.
set(WV2_DIR "${CMAKE_SOURCE_DIR}/deps/Microsoft.Web.WebView2.1.0.3179.45")
set(WV2_INCLUDE "${WV2_DIR}/build/native/include")
set(WV2_LIB_DIR "${WV2_DIR}/build/native/x64")
set(WV2_LOADER "${WV2_DIR}/build/native/x64/WebView2LoaderStatic.lib")

add_executable(WRG WIN32
  main.cpp
  WeatherGlance.rc
)

# Embed our app manifest via CMake's native manifest support
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} /MANIFEST:NO")
target_sources(WRG PRIVATE app.manifest)

target_include_directories(WRG PRIVATE "${WV2_INCLUDE}")
target_link_libraries(WRG PRIVATE "${WV2_LOADER}" user32 ole32 oleaut32 gdi32 shell32 shlwapi advapi32 urlmon)

# Minimize exe size (Release only — these conflict with Debug /RTC1)
target_compile_options(WRG PRIVATE
  $<$<CONFIG:Release>:/O1 /GS- /GL>
  $<$<CONFIG:MinSizeRel>:/O1 /GS- /GL>
)
target_link_options(WRG PRIVATE
  $<$<OR:$<CONFIG:Release>,$<CONFIG:MinSizeRel>>:/LTCG /OPT:REF /OPT:ICF>
)

# ── Install target: produces a clean shippable folder ────────────
# Usage: cmake --install out/build/x64-Release --prefix dist
install(TARGETS WRG RUNTIME DESTINATION .)
