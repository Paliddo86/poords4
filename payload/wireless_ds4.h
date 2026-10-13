/* SPDX-License-Identifier: GPL-3.0-or-later */
#pragma once

#include <stdint.h>
#include <sys/types.h>

#define POORDS4_MAX_USER_CANDIDATES 8u
#define POORDS4_MAX_SLOTS 4u

typedef struct {
    int32_t user_id;
    int32_t pad_index;
    int32_t pad_handle;
    int32_t ds4_connected;
    /* Number of DS4 pads the reader detected and associated with a slot. */
    int32_t ds4_count;
} PoorDS4PadSource;

int wireless_ds4_remote_reader_start(
    const int32_t *user_ids, const int32_t *user_numbers,
    uint32_t user_count,
    PoorDS4PadSource *out_source, pid_t *out_pid,
    intptr_t *out_args_address);
int wireless_ds4_remote_reader_read(pid_t pid, intptr_t args_address,
                                   void *pad_data, uint32_t pad_data_len,
                                   uint32_t *out_seq);
int wireless_ds4_remote_reader_read_slot(pid_t pid, intptr_t args_address,
                                        unsigned slot,
                                        void *pad_data, uint32_t pad_data_len,
                                        uint32_t *out_seq);
int wireless_ds4_remote_reader_stop(pid_t pid, intptr_t args_address);
/* Pauses or resumes the in-target automatic discovery. The supervisor pauses it
 * while a game session is bridged: once the title has its controllers the
 * rescan has nothing left to find and would only keep opening and closing pads
 * on users that can never take a reader slot. */
int wireless_ds4_remote_reader_pause_rescan(pid_t pid, intptr_t args_address,
                                            int paused);

/* Selects the currently active (foreground) user whose DS4 should become the
 * primary bridged controller. Pass -1 when there is no active user. */
void wireless_ds4_set_foreground_user(int32_t user_id);

/* Resolves the kernel's native log sink (sceKernelDebugOutText) inside the
 * calling process, or 0 when this firmware does not export it. Resolved at
 * runtime so no symbol is imported at load time. */
intptr_t wireless_ds4_native_log_resolve(void);

/* Runtime log verbosity. Release builds write only errors and the essential
 * lifecycle information; the detailed diagnostics are written only when the
 * user creates /data/poords4/verbose, or automatically after a failure so that
 * the log already carries the context needed to diagnose it. */
int wireless_ds4_log_verbose_enabled(void);
void wireless_ds4_log_set_verbose(int enabled);
void wireless_ds4_log_enable_verbose(const char *reason);
void wireless_ds4_log_verbose_poll(void);

typedef struct {
    int32_t ready;
    int32_t stop;
    int32_t last_result;
    uint32_t seq;
    int32_t pad_handle;
    int32_t owner_pid;
    uint32_t owner_check_interval;
    uint32_t owner_miss_count;
    uint32_t owner_watchdog_exits;
    int32_t close_pad_on_exit;
    uint8_t connected;
    int32_t last_read_result;
    uint32_t read_success_frames;
    uint32_t read_empty_frames;
    uint32_t read_error_frames;
    uint32_t state_fallback_frames;
    uint32_t reader_mode;
    uint32_t buttons;
    uint8_t left_x;
    uint8_t left_y;
    uint8_t right_x;
    uint8_t right_y;
    uint8_t left_trigger;
    uint8_t right_trigger;
    uint8_t count;
    uint8_t reserved0;
    uint64_t timestamp;
    uint32_t reset_combo_ticks;
    uint32_t reset_requested;
    /* Consecutive rescans that saw a connected DS4 the reader cannot read. The
     * supervisor rebuilds the reader when this reaches 2. */
    uint32_t rescan_stuck;
    /* Probe telemetry of the last automatic-discovery round: candidate users a
     * pad was opened for, how many of those carried no DS4 identity, and which
     * user that was. */
    uint32_t rescan_probes;
    uint32_t rescan_non_ds4;
    int32_t  rescan_last_non_ds4_user;
    uint32_t rescan_count;
    /* Non-zero while the supervisor keeps the in-target automatic discovery
     * paused (a game session is bridged). */
    uint32_t rescan_paused;
    /* User id bound to each reader slot (0xffffffff when the slot is free). The
     * supervisor matches these against the game client-table user ids to route
     * every controller to its own game slot. */
    int32_t  slot_users[POORDS4_MAX_SLOTS];
} PoorDS4RemoteReaderStatus;

int wireless_ds4_remote_reader_status(
    pid_t pid, intptr_t args_address,
    PoorDS4RemoteReaderStatus *out_status);

int wireless_ds4_game_bridge_install(
    const PoorDS4PadSource *source, pid_t *out_game_pid,
    intptr_t *out_args_address);
int wireless_ds4_game_bridge_find_target(pid_t *out_game_pid);
int wireless_ds4_game_bridge_update(pid_t game_pid, intptr_t args_address,
                                   const void *pad_data,
                                   uint32_t pad_data_len);
int wireless_ds4_game_bridge_update_slot(pid_t game_pid, intptr_t args_address,
                                        uint32_t slot_idx,
                                        const void *pad_data,
                                        uint32_t pad_data_len,
                                        int is_simulated,
                                        int is_dualsense);
int wireless_ds4_game_bridge_deactivate_slot(pid_t game_pid, intptr_t args_address,
                                            uint32_t slot_idx);
int wireless_ds4_game_bridge_abandon(void);

#define POORDS4_GAME_BRIDGE_EVENT_RING_SIZE 64u

#define POORDS4_EVT_KIND_READ_STATE      0u
#define POORDS4_EVT_KIND_READ_STATE_EXT  1u
#define POORDS4_EVT_KIND_READ            2u
#define POORDS4_EVT_KIND_READ_EXT        3u
#define POORDS4_EVT_KIND_DATA_INTERNAL   4u
#define POORDS4_EVT_KIND_CONTROLLER_INFO 5u
#define POORDS4_EVT_KIND_EXT_CONTROLLER_INFO 6u

#define POORDS4_EVT_FLAG_DIRECT   0x01u
#define POORDS4_EVT_FLAG_NATIVE   0x02u
#define POORDS4_EVT_FLAG_CHANGED  0x04u
#define POORDS4_EVT_FLAG_MISMATCH 0x08u

typedef struct {
    uint32_t seq;
    uint32_t timestamp_ms;
    int32_t handle;
    uint32_t buttons;
    uint8_t lx;
    uint8_t ly;
    uint8_t rx;
    uint8_t ry;
    uint8_t l2;
    uint8_t r2;
    uint8_t stub_kind;
    uint8_t flags;
} PoorDS4InputEvent;

typedef struct {
    int32_t  pad_handle;
    int32_t  pad_index;
    uint32_t active;
    uint32_t is_dualsense;
    uint32_t is_simulated;
    uint32_t seq;
    uint32_t packets;
    uint64_t read_state_calls;
    uint64_t read_calls;
    uint64_t direct_fallback_frames;
    uint64_t native_passthrough_frames;
    uint32_t buttons;
    uint8_t  lx;
    uint8_t  ly;
    uint8_t  rx;
    uint8_t  ry;
    uint8_t  l2;
    uint8_t  r2;
    uint8_t  connected;
    uint8_t  user_matches;
    uint8_t  reserved[2];
    /* Game-side user id of this client-table entry, captured from the pad
     * client table at install time (0xffffffff when unknown). The supervisor
     * routes the reader data by this id instead of by slot position, because
     * the order in which a title creates its per-user pad entries is not the
     * order in which RemotePlay enumerates the same controllers. */
    int32_t  game_user_id;
} PoorDS4SlotStatus;

typedef struct {
    uint32_t layout_marker;
    uint32_t active;
    uint32_t seq;
    int32_t pad_handle;
    int32_t bridge_ready;
    uint64_t published_packets;
    uint64_t lease_expirations;
    uint64_t read_state_calls;
    uint64_t read_state_ext_calls;
    uint64_t read_calls;
    uint64_t read_ext_calls;
    uint64_t data_internal_calls;
    uint64_t controller_info_calls;
    uint64_t controller_info_spoofs;
    uint64_t snapshot_contention_fallbacks;
    uint64_t controller_info_result_overrides;
    uint64_t native_backing_calls;
    uint64_t native_backing_errors;
    uint64_t native_passthrough_frames;
    uint64_t native_connected_frames;
    uint64_t direct_fallback_frames;
    uint64_t direct_active_fallbacks;
    int32_t last_native_result;
    uint64_t native_success_frames;
    uint64_t native_input_activity_frames;
    uint64_t last_native_timestamp;
    uint32_t last_native_buttons;
    uint8_t last_native_lx;
    uint8_t last_native_ly;
    uint8_t last_native_rx;
    uint8_t last_native_ry;
    uint8_t last_native_l2;
    uint8_t last_native_r2;
    uint8_t last_native_connected;
    uint8_t last_native_count;
    /* DualSense native-path continuity: frames the system reported the native
     * DualSense as disconnected, and how many of those were a new
     * connected->disconnected transition. */
    uint64_t native_disconnect_frames;
    uint64_t native_disconnect_events;
    uint8_t native_disconnect_state;
    uint8_t reserved_native[7];
    uint32_t import_hook_count;
    int32_t game_pad_index;
    uint32_t buttons;
    uint8_t connected;
    uint32_t reset_combo_ticks;
    uint32_t reset_requested;
    int32_t last_caller_handle;
    int32_t last_mismatched_handle;
    uint64_t handle_match_calls;
    uint64_t handle_mismatch_calls;
    uint64_t read_zero_returns;
    uint64_t read_nonzero_returns;
    uint32_t max_read_streak;
    int32_t observed_handles[4];
    uint64_t observed_handle_calls[4];
    uint32_t event_ring_head;
    PoorDS4InputEvent event_ring[POORDS4_GAME_BRIDGE_EVENT_RING_SIZE];
    PoorDS4SlotStatus slots[POORDS4_MAX_SLOTS];
} PoorDS4GameBridgeStatus;

int wireless_ds4_game_bridge_status(pid_t game_pid, intptr_t args_address,
                                   PoorDS4GameBridgeStatus *out_status);
int wireless_ds4_game_bridge_check_reset(pid_t game_pid,
                                        intptr_t args_address);
int wireless_ds4_game_bridge_remove(pid_t game_pid,
                                   intptr_t args_address);
/* Suspend-safe teardown: restore game imports without target syscalls,
 * ptrace, or unmapping memory that an in-flight pad call may still use. */
int wireless_ds4_game_bridge_quiesce(pid_t game_pid,
                                    intptr_t args_address);
