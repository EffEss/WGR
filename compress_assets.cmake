# compress_assets.cmake — compress HTML/JSON with PowerShell using Windows Compression API
execute_process(
  COMMAND powershell -NoProfile -ExecutionPolicy Bypass -Command "
    Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class XComp{[DllImport(\"cabinet.dll\")]public static extern bool CreateCompressor(int a,IntPtr b,out IntPtr h);[DllImport(\"cabinet.dll\")]public static extern bool Compress(IntPtr h,byte[] s,int sl,byte[] d,int dl,out int sz);[DllImport(\"cabinet.dll\")]public static extern bool CloseCompressor(IntPtr h);}' -EA SilentlyContinue
    foreach ($asset in @('radar-map.html','us-states.geo.json')) {
      $raw = [IO.File]::ReadAllBytes(\"Assets/$asset\")
      $ptr = [IntPtr]::Zero
      [XComp]::CreateCompressor(4,[IntPtr]::Zero,[ref]$ptr) | Out-Null
      $buf = New-Object byte[] ($raw.Length)
      $sz = 0
      [XComp]::Compress($ptr,$raw,$raw.Length,$buf,$buf.Length,[ref]$sz) | Out-Null
      [XComp]::CloseCompressor($ptr) | Out-Null
      $hdr = [BitConverter]::GetBytes([uint32]$raw.Length)
      $out = New-Object byte[] (4+$sz)
      [Array]::Copy($hdr,0,$out,0,4)
      [Array]::Copy($buf,0,$out,4,$sz)
      [IO.File]::WriteAllBytes(\"Assets/$asset.compressed\",$out)
    }
  "
  WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
  RESULT_VARIABLE result
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Asset compression failed")
endif()
