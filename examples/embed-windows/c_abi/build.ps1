<#
.SYNOPSIS
    Build and run the example C host against AdaptiveCardsCABI on Windows.

.DESCRIPTION
    Demonstrates the full link recipe for consuming
    AdaptiveCardsCABI.lib + the Swift runtime from a non-Swift host.
    Requires a Visual Studio Dev Shell (cl.exe / lib.exe on PATH) and
    a Swift toolchain installed under %LOCALAPPDATA%\Programs\Swift.

.NOTES
    * SwiftPM doesn't itself emit a `.lib` for static-library targets,
      so we pack the produced `.o` files (AdaptiveCardsCABI + its
      transitive deps) into a single `.lib` via `lib.exe`.
    * The Swift runtime `.lib` set is sensitive to the toolchain
      version. The list below matches Swift 6.3.x; adjust for newer
      releases.
    * `swiftrt.obj` MUST be the first link input. It registers Swift's
      protocol-conformance descriptors with the runtime at startup.
      Without it, any JSONDecoder / Codable call from C-hosted Swift
      crashes with an access violation. Swift's own executable startup
      links it automatically; C hosts must do so explicitly.
    * `host-demo.exe` exercises every public C-ABI function:
      ac_host_create, ac_host_backend_identifier, ac_host_render_json
      (parses + renders an Adaptive Card JSON to canonical
      RenderingNode JSON), ac_host_set_action_callback, ac_host_fire_action
      (Submit/OpenUrl/ShowCard), ac_host_destroy.
#>

[CmdletBinding()]
param(
    [string]$Configuration = 'debug',
    [string]$Triple = 'x86_64-unknown-windows-msvc',
    [switch]$Run
)

$ErrorActionPreference = 'Stop'

$repo = Resolve-Path "$PSScriptRoot\..\..\.." | Select-Object -ExpandProperty Path
$ios  = Join-Path $repo 'ios'
$buildDir = Join-Path $ios ".build\$Triple\$Configuration"

if (-not $env:VSINSTALLDIR) {
    throw "Visual Studio Dev Shell is not active. Launch via Launch-VsDevShell.ps1 first."
}

# Locate Swift toolchain (used by `swift build` and to find runtime libs).
$swiftRoot = if (Test-Path "$env:LOCALAPPDATA\Programs\Swift") {
    "$env:LOCALAPPDATA\Programs\Swift"
} elseif (Test-Path "$env:ProgramFiles\Swift") {
    "$env:ProgramFiles\Swift"
} else {
    throw "Swift install not found in %LOCALAPPDATA%\Programs\Swift or %ProgramFiles%\Swift"
}
$toolchain = (Get-ChildItem "$swiftRoot\Toolchains" | Select-Object -First 1).FullName
$runtime   = (Get-ChildItem "$swiftRoot\Runtimes"   | Select-Object -First 1).FullName
$platform  = (Get-ChildItem "$swiftRoot\Platforms"  | Select-Object -First 1).FullName
$swiftLibs = "$platform\Windows.platform\Developer\SDKs\Windows.sdk\usr\lib\swift\windows\x86_64"
$env:Path = "$toolchain\usr\bin;$runtime\usr\bin;$env:Path"
$env:SDKROOT = "$platform\Windows.platform\Developer\SDKs\Windows.sdk"
$env:DEVELOPER_DIR = "$platform\Windows.platform\Developer"

# 1) Build the Swift static target.
Push-Location $ios
try {
    Write-Host "==> swift build --target AdaptiveCardsCABI"
    & swift build --target AdaptiveCardsCABI -c $Configuration
    if ($LASTEXITCODE -ne 0) { throw "swift build failed" }
} finally { Pop-Location }

# 2) Pack the produced .o files (CABI + transitive deps) into a static .lib.
$needed = @('AdaptiveCardsCABI','AdaptiveCardsWindowsEmbedded','AdaptiveCardsCrossUI','ACCore')
$objs = @()
foreach ($t in $needed) {
    $found = Get-ChildItem (Join-Path $buildDir "$t.build") -Recurse -Filter '*.o' -ErrorAction SilentlyContinue
    if (-not $found) { throw "No .o files found for target $t under $buildDir" }
    $objs += $found.FullName
}
Write-Host "==> lib.exe /out:AdaptiveCardsCABI.lib  ($($objs.Count) objs)"
$objsFile = New-TemporaryFile
Set-Content -Path $objsFile -Value ($objs -join "`n")
$libOut = Join-Path $PSScriptRoot 'AdaptiveCardsCABI.lib'
& lib /nologo /out:"$libOut" "@$objsFile" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "lib.exe failed" }
Remove-Item $objsFile

# 3) Compile + link the C host.
Push-Location $PSScriptRoot
try {
    Write-Host "==> cl /Fe:host-demo.exe main.c"
    # CRITICAL: swiftrt.obj MUST be the first link input. It contains
    # the static initializer that walks the __swift5_proto* COFF
    # sections and registers protocol conformance descriptors with the
    # Swift runtime. Without it, any JSONDecoder / Codable call from a
    # C-hosted Swift static library crashes with E_ACCESSVIOLATION.
    # Swift's own executable startup links swiftrt.obj automatically;
    # C hosts must do so explicitly.
    & cl /nologo /Fe:host-demo.exe main.c /I . `
        /link `
        "$swiftLibs\swiftrt.obj" `
        AdaptiveCardsCABI.lib `
        "/LIBPATH:$swiftLibs" `
        swiftCore.lib swiftCRT.lib swiftDispatch.lib `
        swift_Concurrency.lib swiftSwiftOnoneSupport.lib swiftWinSDK.lib `
        Foundation.lib FoundationEssentials.lib FoundationInternationalization.lib `
        _FoundationICU.lib BlocksRuntime.lib dispatch.lib `
        swift_StringProcessing.lib swift_RegexParser.lib
    if ($LASTEXITCODE -ne 0) { throw "cl.exe failed" }
} finally { Pop-Location }

Write-Host ""
Write-Host "Built: $PSScriptRoot\host-demo.exe"

if ($Run) {
    Write-Host "==> host-demo.exe"
    & "$PSScriptRoot\host-demo.exe"
    Write-Host "Exit: $LASTEXITCODE"
}
