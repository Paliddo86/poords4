# Architecture

## Source side

PoorDS4 attaches only to the system `SceRemotePlay` process during source
discovery. It resolves public `libScePad` functions, identifies a connected
DS4, validates one controller-information result, then starts a small reader
thread owned by RemotePlay. The reader publishes 120-byte `ScePadData`
snapshots and exits if its owning payload disappears.

The reader prefers the public queued `scePadRead(handle, frame, 1)` path and
uses `scePadReadState` only when the queue is empty or unavailable. This keeps
the verified later-firmware state path while avoiding an idle secondary-thread
state cache on older libScePad revisions. Both raw results and path counters
are included in the normal health log and status report.

Before opening the pad, the stopped RemotePlay main thread receives process
privilege, login-user count, and focus setup through resolved public exports.
Their addresses and return values are recorded; the injected reader thread
does not perform setup IPC concurrently with RemotePlay.

Controller discovery scans all candidate users and pad indices. A live state
sample alone is never treated as proof of DS4 identity: public VID/PID data,
`scePadIsDS4Connected`, or the exact 11.60 identity table must confirm it.

## Game admission

The supervisor accepts exactly one `eboot.bin` process whose `libScePad`, libc,
and libkernel modules are ready. Two or more `eboot.bin` processes fail closed.

Some titles start a launcher `eboot.bin` that exits after spawning the game
from a nested executable; the kernel names that process after its
app0-relative path (Metal Gear Solid Master Collection Vol. 2 uses
`mgs4/mgs4.elf` and `mgspw/mgspw.elf`). Only when no `eboot.bin` exists, the
same shared selector, used by both the supervisor and the installer, accepts
exactly one process that satisfies all of:

- its kernel name contains `/` (no system service or ELF-loader payload is
  named that way, so nothing else is inspected);
- the kernel's dynlib list records its main executable (handle 0) at a path
  ending in `/app0/<name>` and `.elf`; kernel names are truncated to 19
  bytes, so a name that fills the field only has to be a prefix of that path;
- its `libScePad`, libc, and libkernel modules are ready.

Two or more verified candidates, or a malformed process list, fail closed. A
candidate whose path or modules are not readable yet is reported as waiting
and is never selected. A selection that disappears between discovery and
installation returns the installer to waiting instead of reporting an error.
Every check below applies unchanged to a nested executable. Before inspecting that process, it snapshots
the RemotePlay reader and requires a ready, healthy, connected DS4. Reader
loss blocks admission, cooperatively stops the old reader, invalidates its
source identity, and completes rediscovery before the launch grace restarts.
It then applies a 1.5-second launch grace and validates:

- six required pad exports and bounded 256-byte fingerprints;
- wrapper shapes, common internal targets, and executable mappings;
- controller-information ABI evidence from the live source process;
- the dynamically discovered client-table address and entry invariants;
- one unambiguous global player handle;
- each caller-owned PLT relocation and its current original destination;
- a runtime-proven virtual-to-physical mapping path before direct writes.

Exact 8.60, 11.60, and 12.40 manifests provide additional evidence but do not supply
the addresses used by the bridge. Unknown versions must pass the same
structural checks.

## Game-side bridge

The installer uses the existing kstuff remote-syscall facility to allocate and
lock two 16 KiB pages in the game: one RX page for small pad gateways and one
RW page for state. Only validated pad import slots are redirected. No game
code page, Sony library code, heap allocation, thread, or socket is modified.

The supervisor writes the inactive 120-byte frame, then atomically publishes
its sequence, finite lease, active flag, and packet count. Each gateway either
preserves a connected frame returned by the saved Sony function or uses a
stable RemotePlay snapshot when the native backing path is disconnected or
fails. Non-selected handles always use the original path. Controller metadata
keeps plausible native geometry and deadzones; only missing values and the
connected standard-controller compatibility fields are repaired.

## Player selection

Pad indices are local to a PS5 user and cannot identify global P1/P2 ordering.
PoorDS4 therefore inspects the game's global table. It prefers one exact DS4
entry, then one disconnected entry matching both the source user and local pad
index, otherwise one unique disconnected entry, and finally one sole entry.
The user/index pair disambiguates titles that preallocate multiple inactive
slots without treating a local index as global. Multiple remaining candidates
fail closed; a sole connected entry must also match the source identity so a
native DualSense is never silently taken over.

## Cleanup and recovery

Normal cleanup first disables publication, proves every import still points to
either PoorDS4's gateway or its saved Sony function, restores imports in
reverse order, waits for in-flight calls, and unmaps the anonymous allocation.

Suspend cleanup restores imports without ptrace, target syscalls, or unmapping.
The game discards the unreachable allocation when it exits. If the supervisor
is terminated abruptly, the next injection accepts a stale bridge only after
all gateways resolve to one valid bridge ABI v1 argument block with matching owners.

The product contains no game-ptrace fallback. Unknown layouts are abandoned
rather than attached to, because live testing proved that even a brief
write-free game attach can poison some titles' startup state.

## Logging, notifications and diagnostics

Release builds write only errors and the essential lifecycle information to
`/data/poords4/game-pad-bridge.log`; the diagnostics in between (one line per
game-side remote call, per-candidate pad probes, periodic health, hex dumps)
are wrapped in `POORDS4_LOG_DEBUG()` and emitted only when verbose logging is
on. Verbose logging is enabled at runtime by creating
`/data/poords4/verbose` (polled every 5 s from the supervisor loops) or
automatically by `wireless_ds4_log_enable_verbose()` as soon as a session
fails, so a failing run captures its own context. The per-session report under
`reports/` always keeps the full telemetry.

Notifications are the kernel "debug" popups sent through
`sceKernelSendNotificationRequest` (libkernel): a single line of text and no
icon. The controller-count popup reads `PoorDS4: N controller active - <event>`,
where `<event>` is the event that changed the count (wireless DS4 ready / active
in the PS5 game / now bridged); every other popup reuses the log sentence
verbatim. Both the notification and the line the bridge writes to its own log
are emitted from `game_bridge_notify()` and `notify_with_ds4_count()`.

