/*
 * adaptive_cards.h
 *
 * C-callable surface for hosting Adaptive Cards from non-Swift apps.
 * Pairs with the static library produced by SwiftPM's
 * `AdaptiveCardsCABI` target (windows-port branch of the SwiftUI fork).
 *
 * Build & link example (Windows / MSVC):
 *
 *     # First build the static library from the repository root:
 *     cd ios
 *     swift build --target AdaptiveCardsCABI
 *
 *     # Then compile your host with cl.exe, linking the .lib plus the
 *     # Swift runtime libraries. swiftrt.obj MUST be the first link
 *     # input — it registers Swift's protocol conformance descriptors
 *     # at startup. Without it, JSONDecoder / Codable from C-hosted
 *     # Swift crashes with an access violation.
 *     cl /Fe:host.exe main.c ^
 *        %SWIFT_SDK%\usr\lib\swift\windows\x86_64\swiftrt.obj ^
 *        ios\.build\x86_64-unknown-windows-msvc\debug\libAdaptiveCardsCABI.lib ^
 *        # ... plus Swift runtime .libs from
 *        # %SWIFT_SDK%\usr\lib\swift\windows\x86_64
 *
 * Memory contract:
 *   - `ac_host_create` returns an opaque pointer; release with
 *     `ac_host_destroy`.
 *   - Functions returning `char *` allocate (`strdup`-style); release
 *     with `ac_free`.
 *   - All strings are UTF-8.
 *   - Action callbacks fire on the calling thread of whatever Swift
 *     code invoked `onAction`. Marshal to your UI thread as needed.
 *
 * Threading: the host object itself is not thread-safe. Callers must
 * serialise access if used from multiple threads.
 */

#ifndef ADAPTIVE_CARDS_H
#define ADAPTIVE_CARDS_H

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque handle. Always treated as `void *` by C/C++ hosts. */
typedef struct ACHost ACHost;

/* Action-kind tags. Keep in lock-step with Sources/AdaptiveCardsCABI/CABI.swift. */
typedef enum {
    AC_ACTION_SUBMIT             = 0,
    AC_ACTION_OPEN_URL           = 1,
    AC_ACTION_SHOW_CARD          = 2,
    AC_ACTION_EXECUTE            = 3,
    AC_ACTION_TOGGLE_VISIBILITY  = 4,
    AC_ACTION_POPOVER            = 5,
    AC_ACTION_RUN_COMMANDS       = 6,
    AC_ACTION_OPEN_URL_DIALOG    = 7,
    AC_ACTION_UNKNOWN            = 99
} ACActionKind;

/* Callback fired on each Adaptive Cards action.
 *   kind:    one of ACActionKind.
 *   payload: UTF-8 string. For AC_ACTION_SUBMIT this is the serialised
 *            form-state JSON; for AC_ACTION_OPEN_URL it is the URL.
 *            Other kinds pass NULL. Pointer is valid only for the
 *            duration of the call.
 *   userdata: opaque pointer passed to `ac_host_set_action_callback`. */
typedef void (*ACActionCallback)(int kind,
                                 const char *payload,
                                 void *userdata);

/* Create a host. `host_config_json` is the Adaptive Cards HostConfig
 * JSON; pass NULL to use defaults. Returns NULL only on out-of-memory. */
ACHost *ac_host_create(const char *host_config_json);

/* Release a host previously returned by ac_host_create. */
void    ac_host_destroy(ACHost *host);

/* Parse + render an Adaptive Card JSON document and return the
 * canonical RenderingNode JSON (the same shape `AdaptiveCardsValidate`
 * snapshots). Returns NULL on error; check `ac_last_error()`.
 * The returned pointer must be released with `ac_free`. */
char   *ac_host_render_json(ACHost *host, const char *card_json);

/* Returns a freshly-allocated string naming the active rendering
 * backend: "winui", "appkit", "uikit", "gtk", or "unknown". Caller
 * frees with `ac_free`. */
char   *ac_host_backend_identifier(ACHost *host);

/* Register a callback for Action.* events emitted by the rendered
 * card. Pass NULL to clear. `userdata` is opaque and round-tripped to
 * the callback. */
void    ac_host_set_action_callback(ACHost *host,
                                    ACActionCallback callback,
                                    void *userdata);

/* Synthesise an action firing from the host side. Useful when the host
 * draws its own Submit / OpenUrl chrome and wants to notify the
 * registered callback as if the card had fired the action. */
void    ac_host_fire_action(ACHost *host,
                            int kind,
                            const char *payload);

/* Release a string returned by any of the `ac_host_*` functions above. */
void    ac_free(char *ptr);

/* Returns a pointer to a static (per-thread) UTF-8 string describing
 * the most recent error, or NULL if the last call succeeded. The
 * pointer is invalidated by the next API call. */
const char *ac_last_error(void);

#ifdef __cplusplus
}
#endif

#endif /* ADAPTIVE_CARDS_H */
