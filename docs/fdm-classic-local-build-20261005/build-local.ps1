param([ValidateSet('classic','ul','libtorrent','torrent','ie-midl','bho-midl','boost-bootstrap','boost','probe')][string]$Target = 'classic')
$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot
$taskVcVersion = if ($Target -eq 'ul') { '14.51.36231' } else { '14.16.27023' }
$taskVcRoot = Join-Path $taskRoot "toolchain/VC/Tools/MSVC/$taskVcVersion/"
$taskSdkRoot = Join-Path $taskRoot 'toolchain/sdk/c/'
$taskSolution = switch ($Target) {
    'ul' { 'ul-source/FDM-UL.sln' }
    'libtorrent' { 'source/trunc/Bittorrent/libtorrent/libtorrent.vcxproj' }
    'torrent' { 'source/trunc/Bittorrent/fdmbtsupp/fdmbtsupp.vcxproj' }
    'classic' { 'source/trunc/FDM.sln' }
    'ie-midl' { 'source/trunc/iefdm/iefdmdm/iefdmdm.vcxproj' }
    'bho-midl' { 'source/trunc/iefdm/FdmIeBho/FdmIeBho.vcxproj' }
}
$taskStart = [System.Diagnostics.ProcessStartInfo]::new()
$taskStart.FileName = 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe'
$taskStart.WorkingDirectory = $taskRoot
$taskStart.UseShellExecute = $false
$taskStart.RedirectStandardOutput = $true
$taskStart.RedirectStandardError = $true
# MSBuild's .NET Framework child-process setup fails with PATH and Path aliases.
$taskPath = $taskStart.Environment['PATH']
$taskStart.Environment.Remove('PATH') | Out-Null
$taskStart.Environment['Path'] = "$taskVcRoot/bin/Hostx64/x86;$taskVcRoot/bin/Hostx64/x64;$taskSdkRoot/bin/10.0.26100.0/x64;$taskPath"
$taskStart.Environment['INCLUDE'] = "$taskVcRoot/include;$taskVcRoot/atlmfc/include;$taskSdkRoot/Include/10.0.26100.0/ucrt;$taskSdkRoot/Include/10.0.26100.0/shared;$taskSdkRoot/Include/10.0.26100.0/um;$taskSdkRoot/Include/10.0.26100.0/winrt"
$taskStart.Environment['LIB'] = "$taskVcRoot/lib/x86;$taskVcRoot/atlmfc/lib/x86;$taskSdkRoot/Lib/10.0.26100.0/ucrt/x86;$taskSdkRoot/Lib/10.0.26100.0/um/x86"
$taskStart.ArgumentList.Add('/p:UseEnv=true')
$taskStart.ArgumentList.Add('/p:CheckMSVCComponents=false')
$taskStart.Environment['VSINSTALLDIR'] = Join-Path $taskRoot 'toolchain/'
$taskStart.Environment['VCINSTALLDIR'] = $taskVcRoot
$taskBuildTarget = if ($Target -eq 'classic') { '/t:FDM' } elseif ($Target -match 'midl$') { '/t:Midl' } else { '/t:Build' }
foreach ($taskArg in @($taskSolution, $taskBuildTarget, '/p:Configuration=Release', '/p:Platform=Win32', '/p:PlatformToolset=v145', "/p:VCToolsVersion=$taskVcVersion", "/p:VCToolsInstallDir=$taskVcRoot", "/p:WindowsSdkDir=$taskSdkRoot", "/p:UniversalCRTSdkDir=$taskSdkRoot", '/p:WindowsTargetPlatformVersion=10.0.26100.0', '/p:PostBuildEventUseInBuild=false', '/p:PreBuildEventUseInBuild=false', "/p:BOOST_ROOT=$taskRoot/dependencies/boost_1_65_1", '/m', '/nologo', "/flp:logfile=$taskRoot/build-$Target.log;verbosity=normal", '/verbosity:minimal')) {
    $taskStart.ArgumentList.Add($taskArg)
}
if ($Target -in @('classic','torrent')) { $taskStart.Environment['LINK'] = "$taskRoot/legacy-msvcrt.lib" }
if ($Target -eq 'boost-bootstrap') {
    $taskStart.ArgumentList.Clear()
    $taskStart.FileName = Join-Path $taskVcRoot 'bin/Hostx64/x86/cl.exe'
    $taskStart.WorkingDirectory = Join-Path $taskRoot 'dependencies/boost_1_65_1/tools/build/src/engine'
    $taskBuildBat = Get-Content -Raw (Join-Path $taskStart.WorkingDirectory 'build.bat')
    $taskSources = @([regex]::Matches($taskBuildBat, '(?m)^set BJAM_SOURCES=%BJAM_SOURCES% (.*)') | ForEach-Object { $_.Groups[1].Value.Trim() -split ' ' })
    $taskSources += @('debugger.c','hcache.c','mem.c')
    $taskDefs = @('NDEBUG','OPT_HEADER_CACHE_EXT','OPT_GRAPH_DEBUG_EXT','OPT_SEMAPHORE','OPT_AT_FILES','OPT_DEBUG_PROFILE','JAM_DEBUGGER','OPT_FIX_TARGET_VARIABLES_EXT','OPT_IMPROVED_PATIENCE_EXT','YYSTACKSIZE=5000') | ForEach-Object { '/D' + $_ }
    foreach ($taskArg in @('/nologo','/MT','/O2','/DNT','/DYYDEBUG','/wd4996',"/Fe$taskRoot/dependencies/boost_1_65_1/b2.exe") + $taskDefs + $taskSources + @('kernel32.lib','advapi32.lib','user32.lib')) { $taskStart.ArgumentList.Add($taskArg) }
}
if ($Target -eq 'probe') {
    $taskStart.ArgumentList.Clear()
    $taskStart.FileName = Join-Path $taskVcRoot 'bin/Hostx64/x86/cl.exe'
    foreach ($taskArg in @('/nologo','/MD','/EHsc','/DUNICODE','/D_UNICODE','/std:c++14','torrent-probe.cpp',"/Fetorrent-probe.exe")) { $taskStart.ArgumentList.Add($taskArg) }
}
if ($Target -eq 'boost') {
    $taskStart.ArgumentList.Clear()
    $taskStart.FileName = Join-Path $taskRoot 'dependencies/boost_1_65_1/b2.exe'
    $taskStart.WorkingDirectory = Join-Path $taskRoot 'dependencies/boost_1_65_1'
    $taskConfig = Join-Path $taskRoot 'boost-project-config.jam'
    $taskCompiler = ($taskVcRoot + 'bin/Hostx64/x86/cl.exe').Replace('\','/')
    'using msvc : 14.1 : "' + $taskCompiler + '" : <setup>"" ;' | Set-Content $taskConfig
    foreach ($taskArg in @('--ignore-site-config',"--project-config=$taskConfig",'toolset=msvc-14.1','address-model=32','architecture=x86','variant=release','link=static','runtime-link=shared','threading=multi','--with-system','--with-thread','--with-date_time','--with-filesystem','--with-regex','--with-chrono','--with-atomic','-j4','stage')) { $taskStart.ArgumentList.Add($taskArg) }
}
$taskProcess = [System.Diagnostics.Process]::Start($taskStart)
$taskOutput = $taskProcess.StandardOutput.ReadToEndAsync()
$taskError = $taskProcess.StandardError.ReadToEndAsync()
$taskProcess.WaitForExit()
($taskOutput.Result + $taskError.Result) | Set-Content (Join-Path $taskRoot "$Target-console.log")
Write-Output "Build $Target exit code: $($taskProcess.ExitCode)"
if ($taskProcess.ExitCode -ne 0) {
    ($taskOutput.Result + $taskError.Result) -split '\r?\n' | Where-Object { $_ -match 'error [A-Z]+[0-9]+' } | Select-Object -First 12 | Write-Output
}
exit $taskProcess.ExitCode
