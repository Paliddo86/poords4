# PoorDS4

> PoorDS4 would not have been possible without the excellent work behind
> [Ghostcontrol](https://github.com/StonedModder/Ghostcontrol-PS5-USB-Controller-Patcher)
> by StonedModder. Its controller research and PS5 payload foundation made this
> project possible, this project will eventually be merged to it later on if stoned Modder agrees even though its different now.
> I'm only using this for testing and gathering logs from testers until its fully stable and make this implementation much cleaner.
> PoorDS4 also relies on the
> [PS5 Payload SDK](https://github.com/ps5-payload-dev/sdk) and the remote-syscall
> interface documented by [kstuff-lite](https://github.com/EchoStretch/kstuff-lite).

PoorDS4 lets a wireless DualShock 4 paired with a jailbroken PS5
control native PS5 games. It does not require USB, a DualSense, a second user,
or a profile-selection prompt. Native DualSense controllers remain on Sony's
original input path and can be used independently for local multiplayer.

This is experimental homebrew that modifies a running game's pad imports.
Compatibility checks fail closed, but untested firmware and games can still
crash. Save your gamesave before testing (it broke the save file of a game during very early builds testings, never happened again but there is stil the risk so this is your disclaimer to save your work).

## What's new in 1.1.0

1.1.0 is the multi-controller release. Changes since 1.0.0:

- **Controllers are routed per user, not per slot.** A title assigns its
  per-user pad entries in its own order, which is not the order RemotePlay
  enumerates the same controllers. When the two orders differed, one DS4 was fed
  into another player's slot (two controllers for the same person in game) while
  a third controller was never fed. Every controller now reaches its own player
  slot, and a reader slot is never used twice.
- **The native DualSense slot is protected for the whole session.** The slot that
  holds a natively connected DualSense is re-derived from the live bridge status
  (every ~250 ms) instead of being frozen to the install-time scan, and it is
  never deactivated, so a momentarily disconnected DualSense cannot leave that
  slot exposed to the DS4 feed.
- **The in-game discovery polling is paused.** Once a title is bridged the
  candidate users are no longer re-probed every ~3 s: the recurring
  `scePadOpen()`/`scePadClose()` on those users had no benefit left and is what
  the native DualSense path had to share the pad client with. A controller
  switched on while a title runs is picked up at the next launch, or immediately
  by holding the reset combo.
- **Stable controller-count popups.** One popup per real change: the duplicated
  "now bridged" announcement is gone, the fed-slot mask is reset at session
  start, and a single dropped read no longer flaps it (a slot is released only
  after 30 consecutive missed frames).
- **New diagnostics** for firmware/game reports: `native DualSense disconnect
  episode: episodes=N frames=M state=S dualsense_slot=..`, `slot routing:
  game_user=0x...,... reader_user=0x...,...`, the automatic-discovery counters in
  the status payload and the `DualSense Disconnects` / `Automatic Discovery`
  blocks in the session summary. The report field `poords4_rc` is `110`.

Every change in detail is in [CHANGELOG.md](CHANGELOG.md).

## Requirements

- A jailbroken PS5 with a compatible HEN/kstuff environment and ELF loader.
- A wireless DualShock 4 paired with the PS5 and connected to a logged-in user.
- Firmware 11.60 for the currently live-tested configuration. See
  [firmware support](docs/FIRMWARE_SUPPORT.md) before testing another version.

## Quick start

1. **Bluetooth Pairing**: Put your DualShock 4 into pairing mode by holding `SHARE` + `PS Button` together until the lightbar starts double-blinking rapidly. On the PS5, go to `Settings > Accessories > Bluetooth Accessories` and select **DUALSHOCK 4**.
2. **Controller Profile**: Connect the DS4 to whichever user profile should play (Player 1 or Player 2). If Player 1 is already using a native DualSense, connect the DS4 under Player 2's profile.
3. **Deploy Payload**: Send `PoorDS4-v1.1.0.elf` to the console's ELF loader (port 9021). The game may already be running or launched afterward.
4. **Play**: Wait for the `wireless DS4 active` notification, then play normally.

Only run one automatic instance. PoorDS4 follows later game launches without reinjection. It performs safe cleanup before rest mode; reinject after waking. Use `PoorDS4-stop.elf` before replacing a running build.

## In-Game Hotkeys & Reset Combo

- **Universal Reset Shortcut (`L1 + R1 + L2 + R2` held for ~400ms)**:
  Holding `L1 + R1 + L2 + R2` simultaneously on **any connected controller** (DS4 or DualSense) triggers an instant in-game re-synchronization. PoorDS4 will quiesce active hooks, re-evaluate all game pad slots, re-bind the controller to the correct profile, and re-attach seamlessly without needing to reinject the payload.
  Use this shortcut if:
  - You switched user profiles in the middle of a game session.
  - Player 2 joined late after the title screen.
  - You want to force a clean re-detection of the controller table.

## Controller Compatibility & Multiplayer

- **Supported Controllers**: Sony DualShock 4 v1 (`054c:05c4`), DS4 v2 (`054c:09cc`), and official Sony wireless USB adapters (`054c:0ba0`).
- **Multi-Controller & Player 2**: Fully supported. DualSense controllers remain strictly on their original Sony hardware input path and are never clobbered or stolen. PoorDS4 detects open/waiting player slots and binds cleanly to Player 2 alongside a Player 1 DualSense.
- **Native DualSense Touchpad Emulation**: Touchpad geometry is spoofed at native `1920x1080` resolution matching DualSense hardware, ensuring full compatibility with Unreal Engine 4/5 titles, Stellar Blade, and EA Sports FC 26.

## How it works

1. Enumerate the logged-in and Invite users' pad slots.
2. Identify a live DS4 through public device metadata and Sony's DS4 API.
3. Read its 120-byte `ScePadData` state at 120 Hz in `SceRemotePlay`.
4. Wait for one fully initialized native game process.
5. Validate the game's pad ABI, client table, player slot, import owners, and
   target mappings before changing anything.
6. Redirect only validated pad imports to a game-owned anonymous mapping and
   publish translated frames through a double buffer.
7. Record the game-side user id of every pad-client entry and route each reader
   slot to the game slot that holds that user, so a title that registers its
   users in a different order still receives every controller on its own player
   slot, never twice and never on another player's.
8. Pause the in-target discovery polling as soon as the title is bridged and
   resume it when the session ends.

The game is never ptraced, stopped, or used to run a borrowed thread. No eboot
or `libScePad` code page is patched, and no game heap, socket, or thread is
created. See the [architecture document](docs/ARCHITECTURE.md) for the exact
safety and cleanup invariants.

## Firmware compatibility

| Firmware | Status |
| --- | --- |
| 6.02 (`0x06020004`) | Exact manifest and dynamic table stride (`0x548`) verified from memory dumps |
| 8.60 (`0x08600004`) | RC39 installed cleanly; RC42/RC43 includes queued/state source reader, source-context setup, and native-frame preservation |
| 10.01 (`0x10010000`) | Exact manifest and stride (`0x5c8`) verified from memory dumps |
| 11.60 (`0x11600005`) | Live-tested across multiple games (Greak, Pragmata, JoJo, FC 26), multiple connection orders, reconnects, and rest cleanup |
| 12.40 (`0x12400009`) | Exact manifest verified from supplied reports and memory dumps |
| Other | Dynamic table stride discovery (`0x548`/`0x5c8`) and structural verification allow execution if ABI matches; fails closed safely |

Compatibility is based on proven ABI structure, not a broad `11.xx` or `12.xx`
version assumption. Unknown layouts fail closed and produce a report instead
of installing hooks. See [docs/FIRMWARE_SUPPORT.md](docs/FIRMWARE_SUPPORT.md).

## Build

Install the official [ps5-payload-sdk](https://github.com/ps5-payload-dev/sdk),
set `PS5_PAYLOAD_SDK`, then build from the repository root:

```sh
make -C payload clean
make -C payload release
```

`VERSION` and `VERSION_CODE` in `payload/Makefile` are the released version and
its numeric code (startup banner `version=...`, report field `poords4_rc`). To
build an incremental prerelease of the same version, pass a beta number: `make
-C payload BETA=1 release` produces `PoorDS4-v1.1.0-beta.1.elf` (a `*-beta*` tag
is published by CI as a prerelease and never as "latest").

### Local build on macOS

The SDK binary distribution is POSIX and CPU-architecture independent, so a
local macOS build only needs the SDK plus LLVM 18 from Homebrew:

```sh
# LLVM 18 provides llvm-config and llvm-strip, used by prospero.mk
brew install llvm@18 wget

# PS5 payload SDK binary distribution
curl -L -o /tmp/ps5-payload-sdk.zip \
  https://github.com/ps5-payload-dev/sdk/releases/latest/download/ps5-payload-sdk.zip
sudo unzip -q -d /opt /tmp/ps5-payload-sdk.zip

# Environment (append to ~/.zshrc to persist)
export PS5_PAYLOAD_SDK=/opt/ps5-payload-sdk
export LLVM_CONFIG="$(brew --prefix llvm@18)/bin/llvm-config"
export PATH="$PS5_PAYLOAD_SDK/bin:$(brew --prefix llvm@18)/bin:$PATH"

# Build, audit, deploy
make -C payload clean
make -C payload release
pwsh -File tests/static-audit.ps1
make -C payload deploy PS5_HOST=<console-ip>
```

Notes for the local loop: `pwsh` comes from `brew install --cask powershell`;
`make -C payload audit` is only a stub that prints a notice, so the audit must
be run with `pwsh` directly; `make -C payload release` needs `llvm-strip` on
`PATH`; `make -C payload deploy` streams the ELF to the console's loader with
`nc` (override with `PORT=`). The `ps5-sdk` submodule is a source checkout
rather than an installed SDK, so using it directly requires
`make DESTDIR=... install` with clang-18/lld-18; the released zip is simply
unpacked and used through `PS5_PAYLOAD_SDK`.

On the Windows PS5 development workspace used for release builds, load the
environment and select its target wrapper explicitly:

```powershell
. .\ps5dev-env.ps1
make -C payload CC=ps5-clang.cmd clean
make -C payload CC=ps5-clang.cmd release audit
```

Release assets are produced by the GitHub workflow with the latest
ps5-payload-sdk release (v0.43 at the time of writing; earlier builds such as
rc64 used v0.42). The 1.1.0 assets are `PoorDS4-v1.1.0.elf`,
`PoorDS4-status.elf`, and `PoorDS4-stop.elf`:

| Output | Purpose |
| --- | --- |
| `PoorDS4-v1.1.0.elf` | Automatic wireless DS4 bridge (release 1.1.0) |
| `PoorDS4-status.elf` | Read-only bridge status snapshot |
| `PoorDS4-stop.elf` | Cooperative stop request |

## Logs and compatibility reports

Diagnostics are stored under `/data/poords4/`:

- `game-pad-bridge.log` and `game-pad-bridge.log.1`
- `game-pad-bridge-supervisor.txt`
- `game-pad-bridge-last.txt`
- `game-pad-bridge-status.txt` after running the status ELF
- `reports/source-fw-XXXXXXXX-pid-N.txt`
- `reports/fw-XXXXXXXX-pid-N.txt`

For a firmware or game incompatibility, copy the complete `/data/poords4/`
directory and include the steps that reproduced the failure. Source and game
reports identify `poords4_rc` and `report_schema`. Review reports before posting
them publicly because they contain runtime process addresses and controller
diagnostics.

Release builds keep the log quiet: they write errors and the essential
lifecycle information (version, reader start/stop, game detected, install
result, controller count changes, session end) and nothing else. Create
`/data/poords4/verbose` to switch the detailed diagnostics on at runtime; the
file is picked up within a few seconds and the payload also turns verbose mode
on by itself as soon as something fails, so a session that breaks is captured
automatically. `game-pad-bridge-last.txt` and `reports/` keep the full
telemetry in every case.

Notifications are the kernel "debug" popups
(`sceKernelSendNotificationRequest`): a single line of text and no icon. The
controller-count popup reads `PoorDS4: N controller active - <event>`, where
`<event>` is what triggered it (wireless DS4 ready / active in the PS5 game /
now bridged); every other popup is the same sentence the log carries
(`PoorDS4: wireless DS4 bridge stopped`, ...).

## Multi-Controller Support (Experimental)

PoorDS4 supports streaming multiple wireless DS4 controllers concurrently (up to 4 controllers as Player 1..Player 4), along with simulated controller channels and native DualSense passthrough. Every controller is fed to the game slot whose owning user matches it, so a title that registers its users in a different order still gets one controller per player - the configuration validated in the field with one native DualSense plus three wireless DS4s on four different profiles. Please note that multi-controller support is currently **experimental**: if you have multiple DS4 controllers, test them and open an issue with the whole `/data/poords4/` folder zipped. `game-pad-bridge-summary.txt` and `game-pad-bridge-status.txt` contain the routing table (`game_user` per slot, `reader_user` per reader slot) needed to diagnose a mismatch.

## Testers Needed

I need testers especially for firmwares **13.40**, **13.20**, **13.00**, **12.60**, and **9.60**. If you encounter any bugs, crashes, or want to contribute test logs, please zip the entire `/data/poords4/` folder on your PS5 and send it over in GitHub issues or reach out to me directly on Discord (`blurf.`).

## Special Thanks & Shoutout

A huge shoutout to [reyzinhoplayoliver-design](https://github.com/reyzinhoplayoliver-design) / `ElCauaRey` on Discord for helping with a lot of testing and finding bugs!

## Donations & Support

If you find PoorDS4 helpful and would like to support faster future development, hardware acquisition (like additional controllers and testing gear), and maintenance, please consider donating:

- **PayPal**: [paypal.me/nblurf](https://paypal.me/nblurf)
- **Bitcoin (BTC Network)**: `1CW8JWSnWc5w7yKhYk7ixAFG487nU5Jrzc`
- **USDT (Tron / TRC20)**: `TRcrCeonXzgyxjR4LGzo4JdfEHYGGqD3gX`

## Attribution and license

PoorDS4 is a focused wireless-DS4 derivative of Ghostcontrol. The original USB
implementations and binaries are intentionally not distributed in this tree.
See [NOTICE.md](NOTICE.md) for detailed credits and [LICENSE](LICENSE) for the
GPL-3.0-or-later terms.
