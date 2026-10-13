$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

$main = [IO.File]::ReadAllText(
    (Join-Path $repo 'payload/game_pad_bridge_main.c'))
$bridge = [IO.File]::ReadAllText(
    (Join-Path $repo 'payload/wireless_ds4.c'))
$makefile = [IO.File]::ReadAllText(
    (Join-Path $repo 'payload/Makefile'))

Assert-True ($makefile.Contains('VERSION      := 1.1.0')) `
    'Makefile release version is not 1.1.0.'
Assert-True ($makefile.Contains('VERSION_CODE := 110')) `
    'Makefile release version code is not 110.'
Assert-True ($makefile.Contains('BUILD_VERSION := $(VERSION)-beta.$(BETA)')) `
    'Makefile lost the incremental beta artifact naming.'
Assert-True ($makefile.Contains('-DPOORDS4_VERSION_STR="$(BUILD_VERSION)"')) `
    'Bridge build does not pass the build version string.'
Assert-True (-not $makefile.Contains('-lScePad')) `
    'Build still links libScePad despite using runtime-resolved game exports.'
Assert-True (-not $makefile.Contains('-lpthread')) `
    'Build still links pthread despite using runtime-resolved game functions.'
Assert-True (-not $makefile.Contains('-ldl')) `
    'Build still links libdl without a direct import.'
Assert-True ($makefile.Contains(
    'RUNTIME_LIBS := -nodefaultlibs -lc -lkernel_web -lSceLibcInternal')) `
    'Build does not declare its minimal SDK runtime dependencies.'
Assert-True ($makefile.Contains(
    'BRIDGE_LIBS  := $(RUNTIME_LIBS) -lSceUserService')) `
    'Automatic payload is missing its direct user-service dependency.'
Assert-True ($makefile.Contains(
    '$(STRIP) --strip-debug $(TARGET) $(STATUS_TARGET) $(STOP_TARGET)')) `
    'Release target does not remove workstation paths from DWARF data.'
Assert-True (-not $makefile.Contains('-lSceNet')) `
    'Build still links the SDK networking library without a network import.'
Assert-True (-not $makefile.Contains('EXP_TARGET')) `
    'Build still produces the retired experimental artifact.'
Assert-True ($makefile.Contains('tests/static-audit.ps1')) `
    'The audit target does not run the static audit.'
Assert-True ($makefile.Contains('TARGET        := PoorDS4-v$(BUILD_VERSION).elf')) `
    'Automatic payload does not use the PoorDS4 release name.'
Assert-True ($makefile.Contains('STATUS_TARGET := PoorDS4-status.elf')) `
    'Status payload does not use the PoorDS4 release name.'
Assert-True ($makefile.Contains('STOP_TARGET   := PoorDS4-stop.elf')) `
    'Stop payload does not use the PoorDS4 release name.'
Assert-True ($main.Contains('#define POORDS4_DATA_DIR   "/data/poords4"')) `
    'Runtime data directory does not use the PoorDS4 name.'
Assert-True ($bridge.Contains(
    'define POORDS4_VERBOSE_FILE    POORDS4_DATA_DIR "/verbose"')) `
    'Verbose log switch file is not wired to the runtime data directory.'
Assert-True ($bridge.Contains('wireless_ds4_log_verbose_enabled(void)') `
    -and $bridge.Contains('wireless_ds4_log_enable_verbose(const char *reason)') `
    -and $bridge.Contains('wireless_ds4_log_verbose_poll(void)')) `
    'Runtime log verbosity helpers are missing.'
Assert-True ($main.Contains('#define POORDS4_LOG_DEBUG(...)')) `
    'Bridge is missing the verbose-only log macro.'
Assert-True ($bridge.Contains('POORDS4_LOG_DEBUG("[WirelessDS4] pt_call: fn=')) `
    'Per-call ptrace tracing is not gated behind verbose logging.'
Assert-True (-not $bridge.Contains('klog_printf("[PoorDS4] source candidate user=') `
    -and -not $bridge.Contains('klog_printf("[PoorDS4] pad alt-index user=') `
    -and -not $bridge.Contains('klog_printf("[PoorDS4] pad alt-type user=') `
    -and -not $bridge.Contains('klog_printf("[PoorDS4] pad controller-info user=') `
    -and -not $bridge.Contains('klog_printf("[PoorDS4] pad is-ds4-connected by_user=')) `
    'Per-candidate pad diagnostics are not gated behind verbose logging.'
Assert-True ($main.Contains("wireless_ds4_log_enable_verbose(`"reader start failed`");")) `
    'Failures do not switch the detailed log on for post-mortem analysis.'
$hexGuards = ([regex]::Matches($bridge,
    [regex]::Escape('if (wireless_ds4_log_verbose_enabled()) {'))).Count
Assert-True ($hexGuards -ge 3) `
    'Hex dumps still run without verbose logging.'
$verbosePolls = ([regex]::Matches($main,
    [regex]::Escape('wireless_ds4_log_verbose_poll();'))).Count
Assert-True ($verbosePolls -ge 3) `
    'Verbose log switch is not polled from the supervisor loops.'

Assert-True ($main.Contains('game_bridge_notify(const char *message)') `
    -and $main.Contains('sceKernelSendNotificationRequest(')) `
    'The debug notification popup is not sent through the kernel request.'
Assert-True ($main.Contains('"PoorDS4: %d controller active - %s%s"')) `
    'Controller count notification does not carry count and event on one line.'
Assert-True (-not $main.Contains('sceNotificationSend') `
    -and -not $main.Contains('POORDS4_NOTIFY_TEMPLATE') `
    -and -not $main.Contains('game_bridge_icon')) `
    'Native system toast or toast-icon code is still present.'
Assert-True ($main.Contains('game bridge start version=%s')) `
    'Startup banner does not log the release version.'
Assert-True ($main.Contains('install_result == 0 ? 5u : 15u')) `
    'Bounded retry for a transient fail-closed game snapshot is missing.'
Assert-True ($main.Contains(
    'restoring wireless reader before game scan')) `
    'Missing reader-before-game-install lifecycle gate.'
Assert-True ($main.Contains(
    'wireless_ds4_remote_reader_status(')) `
    'Pre-game reader gate does not validate the live reader snapshot.'
Assert-True ($main.Contains(
    'reader_preflight.connected != 0')) `
    'Pre-game reader gate does not require a connected source.'
Assert-True ($main.Contains('int reader_healthy =') `
    -and $main.Contains('reader_restart_required || !reader_healthy ||')) `
    'Reader restart gate does not distinguish health from a connected pad.'
Assert-True ($main.Contains('g_reader_foreground_user') `
    -and $main.Contains('foreground_changed')) `
    'Reader candidate list is not refreshed when the foreground user changes.'
Assert-True ($main.Contains('controller appeared while waiting')) `
    'Controller arrival while waiting does not refresh the source discovery.'
Assert-True ($main.Contains(
    '"waiting_reader_stop"')) `
    'Failed reader stop is not retained for retry.'
Assert-True ($main.Contains(
    'reader unavailable after clean bridge removal')) `
    'Clean reader-failure recovery still exits instead of rediscovering.'
Assert-True ($main.Contains(
    'game exited before bridge-ready;')) `
    'Game-exit race before bridge readiness still terminates auto-watch.'
Assert-True ($main.Contains(
    'game_session_end_reason_name(end_reason)')) `
    'Session diagnostics do not include a named termination reason.'
Assert-True ($main.Contains(
    'g_pad_source = (PoorDS4PadSource){-1, -1, -1, 0, 0};')) `
    'Reader-loss gate does not invalidate the stale source identity.'

$readerGate = $main.IndexOf(
    'restoring wireless reader before game scan',
    [StringComparison]::Ordinal)
$gameInstall = $main.IndexOf(
    'int install_result = wireless_ds4_game_bridge_install(',
    [StringComparison]::Ordinal)
Assert-True ($readerGate -ge 0 -and $gameInstall -gt $readerGate) `
    'Game installation is not ordered after the reader validation gate.'
Assert-True ($bridge.Contains('source_runtime_abi_match')) `
    'Runtime controller-information ABI evidence is missing.'
Assert-True ($bridge.Contains('POORDS4_GAME_BRIDGE_FW_0860')) `
    'Firmware 8.60 exact-manifest support is missing.'
Assert-True ($bridge.Contains('source-user-index-inactive')) `
    'Multi-slot game routing lacks the source user/index fallback.'
Assert-True ($bridge.Contains(
    'user_id == source_user_id &&')) `
    'Multi-slot routing does not bind the candidate to the DS4 user.'
Assert-True ($bridge.Contains(
    'ds4_count == 0u && identity_count == 1u &&')) `
    'Ambiguous duplicate user/index identities do not fail closed.'
Assert-True ($bridge.Contains(
    'active_count == 1u && identity_count == 1u')) `
    'Sole active fallback is not bound to the source controller identity.'
Assert-True ($bridge.Contains('source-user-inactive-first')) `
    'Multi-slot game routing lacks the source-user-inactive-first fallback for P2.'
Assert-True ($bridge.Contains('global-inactive-first')) `
    'Multi-slot game routing lacks the global-inactive-first fallback for P2.'
Assert-True ($main.Contains('SESSION_END_RESET_REQUESTED')) `
    'Supervisor is missing the controller reset shortcut lifecycle state.'
Assert-True ($bridge.Contains('reset_combo_ticks')) `
    'Bridge and reader are missing the reset combo tick tracking.'
Assert-True ($bridge.Contains('poords4_rc=%d\nreport_schema=8')) `
    'Firmware reports do not identify their RC and schema.'
Assert-True ($bridge.Contains('client_locator_summary')) `
    'Cross-firmware client-table locator diagnostics are missing.'
Assert-True ($bridge.Contains('client_user_scan')) `
    'Rejected table layouts do not report bounded source-user evidence.'
Assert-True ($bridge.Contains('target_protection state=')) `
    'Rejected executable mappings do not report raw protections.'
Assert-True ($bridge.Contains('waiting_for_executable_mapping')) `
    'Exact-manifest executable mapping races are still permanent skips.'
Assert-True ($bridge.Contains('libpad_section index=')) `
    'Firmware reports do not include bounded libScePad section mappings.'
Assert-True ($bridge.Contains(
    'stale_recovery_error=import_scan')) `
    'Incomplete import discovery does not fail closed before installation.'
Assert-True ($bridge.Contains(
    'import_scan_error=no_supported_hooks')) `
    'Games without supported pad imports are not diagnosed fail closed.'
Assert-True ($bridge.Contains('reason=known-module-target')) `
    'Unreadable import names are not bounded by loaded-module ownership.'
Assert-True ($bridge.Contains('source_library_match')) `
    'Same-firmware source/game libScePad comparison is missing.'
Assert-True ($bridge.Contains('scePadSetLoginUserNumber')) `
    'RemotePlay login-user context setup is missing.'
Assert-True ($bridge.Contains('scePadSetProcessFocus')) `
    'RemotePlay focus setup is missing.'
Assert-True ($bridge.Contains('queued_result = read_events(')) `
    'Adaptive queued source read is missing.'
Assert-True ($bridge.Contains('state_fallback_frames')) `
    'Queued/state source path diagnostics are missing.'
Assert-True (-not $bridge.Contains('scePadSetUserNumber')) `
    'Rejected, profile-sensitive user-number setup is still present.'
Assert-True ($bridge.Contains('native_passthrough_frames')) `
    'Native connected-frame preservation is missing.'
Assert-True ($bridge.Contains('direct_fallback_frames')) `
    'Disconnected native-path fallback diagnostics are missing.'
Assert-True ($bridge.Contains('native_input_activity_frames')) `
    'Pre-translation native input diagnostics are missing.'
Assert-True ($bridge.Contains('touch_x == 0 || touch_x > 8192u')) `
    'Controller metadata no longer preserves plausible firmware geometry.'
Assert-True (-not $bridge.Contains('game_pad_bridge_receiver_stub')) `
    'Retired injected game receiver is present.'
Assert-True (-not $bridge.Contains('wireless_ds4_game_bridge_run(')) `
    'Retired game-ptrace installer is present.'

$installerStart = $bridge.IndexOf(
    'wireless_ds4_game_bridge_run_passive(',
    [StringComparison]::Ordinal)
$installerEnd = $bridge.IndexOf(
    'wireless_ds4_game_bridge_install(', $installerStart,
    [StringComparison]::Ordinal)
Assert-True ($installerStart -ge 0 -and $installerEnd -gt $installerStart) `
    'Could not isolate the active game installer.'
$installer = $bridge.Substring(
    $installerStart, $installerEnd - $installerStart)
Assert-True (-not $installer.Contains('sys_ptrace(')) `
    'Active game installer contains ptrace.'
Assert-True (-not $installer.Contains('pt_call(')) `
    'Active game installer contains a borrowed game call.'
Assert-True (-not $installer.Contains('PT_ATTACH')) `
    'Active game installer contains a game attach operation.'

$tracked = & git -C $repo ls-files
if ($LASTEXITCODE -ne 0) {
    throw 'git ls-files failed.'
}
$expectedTracked = @(
    '.gitattributes',
    '.github/workflows/build-and-release.yml',
    '.gitignore',
    '.gitmodules',
    'CHANGELOG.md',
    'LICENSE',
    'NOTICE.md',
    'README.md',
    'docs/ARCHITECTURE.md',
    'docs/FIRMWARE_SUPPORT.md',
    'payload/Makefile',
    'payload/game_pad_bridge_main.c',
    'payload/game_pad_bridge_status_main.c',
    'payload/pad_types.h',
    'payload/stop_game_pad_bridge_main.c',
    'payload/wireless_ds4.c',
    'payload/wireless_ds4.h',
    'tests/static-audit.ps1'
)
Assert-True ($tracked.Count -eq $expectedTracked.Count) `
    'Tracked file count does not match the focused public tree.'
foreach ($path in $expectedTracked) {
    Assert-True ($tracked -contains $path) `
        "Required public-tree file is missing: $path"
}

Write-Output 'PoorDS4 static audit passed.'
