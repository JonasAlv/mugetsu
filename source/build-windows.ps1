# Builds Mugetsu.exe from Ruffle's source and the patches in this folder.
#
#   powershell -ExecutionPolicy Bypass -File build-windows.ps1            (with the speed profile)
#   powershell -ExecutionPolicy Bypass -File build-windows.ps1 -NoPgo     (without it)
#   powershell -ExecutionPolicy Bypass -File build-windows.ps1 -PrepareOnly   (patched source only, no build)
#
# Needs: Rust (the version in RUST_VERSION), Java 17+ (Ruffle compiles its Flash classes
# with it) and git. The result is build\out\Mugetsu.exe.
#
# Optional, for building without downloads: MUGETSU_RUFFLE_REMOTE (a local clone of Ruffle
# to fetch the commit from) and MUGETSU_CRATES_DIR (a folder with the unpacked crates, e.g.
# Cargo's registry/src/index.crates.io-*).
#
# For CPUs without AVX2 (they stop at once with an illegal-instruction crash):
#   $env:MUGETSU_TARGET_CPU = 'x86-64-v2'; $env:MUGETSU_TARGET_FEATURES = '+avx,+fma,+f16c'
# These keep the speed profile and the shortened paths.
param([switch]$NoPgo, [switch]$PrepareOnly)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$work = Join-Path $root 'build'
$ruffle = Join-Path $work 'ruffle'
$out = Join-Path $work 'out'

function Run($exe, [string[]]$arguments) {
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "$exe $($arguments -join ' ') failed ($LASTEXITCODE)" }
}

$commit = (Get-Content (Join-Path $root 'RUFFLE_COMMIT') -Raw).Trim()
$remote = if ($env:MUGETSU_RUFFLE_REMOTE) { $env:MUGETSU_RUFFLE_REMOTE } else { 'https://github.com/ruffle-rs/ruffle.git' }

# 1. Ruffle at the commit Mugetsu is based on (only that commit is downloaded).
if (Test-Path $ruffle) { Remove-Item -Recurse -Force $ruffle }
New-Item -ItemType Directory -Force $ruffle | Out-Null
Run git @('-C', $ruffle, 'init', '-q')
# Ruffle's tests have paths longer than Windows' old 260-character limit.
Run git @('-C', $ruffle, 'config', 'core.longpaths', 'true')
Run git @('-C', $ruffle, 'fetch', '-q', '--depth', '1', $remote, $commit)
Run git @('-C', $ruffle, '-c', 'advice.detachedHead=false', 'checkout', '-q', 'FETCH_HEAD')

# 2. Mugetsu's changes to Ruffle.
Run git @('-C', $ruffle, 'apply', '--whitespace=nowarn', (Join-Path $root 'patches\ruffle.patch'))
# Skua build: the bridge to VibeSkua and drawing inside its window (desktop\src\skua.rs).
Run git @('-C', $ruffle, 'apply', '--whitespace=nowarn', (Join-Path $root 'patches\skua.patch'))

# 3. The libraries Mugetsu changes, from crates.io, patched into ruffle\patches\.
$crates = @(
    @{ Name = 'wgpu-core'; Version = '30.0.1' },
    @{ Name = 'wgpu-hal'; Version = '30.0.1' },
    @{ Name = 'gc-arena'; Version = '0.7.0' },
    @{ Name = 'lyon_path'; Version = '1.0.7' },
    @{ Name = 'lyon_algorithms'; Version = '1.0.5' }
)
New-Item -ItemType Directory -Force (Join-Path $ruffle 'patches') | Out-Null
foreach ($crate in $crates) {
    $name = $crate.Name
    $full = "$name-$($crate.Version)"
    $dest = Join-Path $ruffle "patches\$name"
    if ($env:MUGETSU_CRATES_DIR) {
        Copy-Item -Recurse (Join-Path $env:MUGETSU_CRATES_DIR $full) $dest
    } else {
        $archive = Join-Path $work "$full.crate"
        Invoke-WebRequest -UseBasicParsing "https://static.crates.io/crates/$name/$full.crate" -OutFile $archive
        $unpack = Join-Path $work 'crates'
        New-Item -ItemType Directory -Force $unpack | Out-Null
        # Windows' own tar (another tar on PATH, e.g. Git's, reads 'C:' as a remote host).
        Run (Join-Path $env:SystemRoot 'System32\tar.exe') @('-xzf', $archive, '-C', $unpack)
        Move-Item (Join-Path $unpack $full) $dest
    }
    Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $dest '.cargo_vcs_info.json')
    # From Ruffle's folder: inside a repository, git apply skips paths outside the current folder.
    Run git @('-C', $ruffle, 'apply', '--whitespace=nowarn', '-p1', "--directory=patches/$name",
        (Join-Path $root "patches\$name.patch"))
}

if ($PrepareOnly) {
    Write-Host "Patched source ready in $ruffle"
    return
}

# 4. Build. x86-64-v3 (AVX2) like the released builds unless MUGETSU_TARGET_CPU says otherwise;
# paths in the program are shortened.
$targetCpu = if ($env:MUGETSU_TARGET_CPU) { $env:MUGETSU_TARGET_CPU } else { 'x86-64-v3' }
$features = '+crt-static'
if ($env:MUGETSU_TARGET_FEATURES) { $features += ",$env:MUGETSU_TARGET_FEATURES" }
$flags = @("-Ctarget-feature=$features", "-Ctarget-cpu=$targetCpu",
    "--remap-path-prefix=$ruffle=ruffle", "--remap-path-prefix=$env:USERPROFILE=home")
if ($env:CARGO_HOME) { $flags += "--remap-path-prefix=$env:CARGO_HOME=cargo" }
if (-not $NoPgo) {
    # The speed profile (PGO), recorded while playing AQW.
    $pgo = Join-Path $work 'pgo'
    Expand-Archive -Force (Join-Path $root 'pgo\aqw.profdata.zip') $pgo
    $flags += "-Cprofile-use=$(Join-Path $pgo 'aqw.profdata')"
}
$env:RUSTFLAGS = $flags -join ' '
$env:CARGO_TARGET_DIR = Join-Path $work 'target'
Push-Location $ruffle
try { Run cargo @('build', '--locked', '--package', 'ruffle_desktop', '--profile', 'dist') } finally { Pop-Location }

New-Item -ItemType Directory -Force $out | Out-Null
Copy-Item -Force (Join-Path $env:CARGO_TARGET_DIR 'dist\ruffle_desktop.exe') (Join-Path $out 'Mugetsu.exe')
Write-Host "Built $(Join-Path $out 'Mugetsu.exe')"
