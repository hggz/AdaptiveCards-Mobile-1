/*
 * main.c
 *
 * Minimal demonstration of hosting the AdaptiveCards C-ABI surface from
 * a non-Swift C program. Exercises every public function in
 * adaptive_cards.h end-to-end.
 *
 * Build & run:
 *
 *   See build.ps1 in this directory. tl;dr from inside a VS Dev Shell:
 *     1) `swift build --target AdaptiveCardsCABI` from <repo>/ios
 *     2) `lib.exe /out:AdaptiveCardsCABI.lib *.o`  (pack the deps)
 *     3) `cl.exe main.c swiftrt.obj AdaptiveCardsCABI.lib swiftCore.lib ...`
 *
 * Critical link input: `swiftrt.obj` MUST be the first input on the
 * link line. It contains the static initializer that walks the
 * `__swift5_proto*` COFF sections at startup and registers protocol
 * conformance descriptors with the Swift runtime. Without it, any
 * Swift Codable / JSONDecoder call from C crashes with an access
 * violation (the descriptors are present in the binary but the runtime
 * never learns about them). Swift's own executable startup links
 * `swiftrt.obj` automatically; C hosts must do so explicitly.
 */

#include <stdio.h>
#include <string.h>
#include "adaptive_cards.h"

static const char *kSampleCard =
    "{"
    "  \"type\": \"AdaptiveCard\","
    "  \"version\": \"1.6\","
    "  \"$schema\": \"http://adaptivecards.io/schemas/adaptive-card.json\","
    "  \"body\": ["
    "    { \"type\": \"TextBlock\", \"text\": \"Hello from C\", \"size\": \"Large\", \"weight\": \"Bolder\" }"
    "  ],"
    "  \"actions\": ["
    "    { \"type\": \"Action.Submit\", \"title\": \"Send\" }"
    "  ]"
    "}";

static void on_action(int kind, const char *payload, void *userdata) {
    const char *label = (const char *)userdata;
    printf("  [%s] action kind=%d payload=%s\n",
           label,
           kind,
           payload ? payload : "<null>");
}

int main(void) {
    /* 1. Create a host. */
    ACHost *host = ac_host_create(NULL);
    if (!host) {
        fprintf(stderr, "ac_host_create failed\n");
        return 1;
    }
    printf("ac_host_create:           OK\n");

    /* 2. Identify the rendering backend. */
    char *backend = ac_host_backend_identifier(host);
    printf("ac_host_backend_identifier: %s\n", backend ? backend : "<NULL>");
    ac_free(backend);

    /* 3. Parse + render the card JSON into the canonical RenderingNode
     *    plan. This is the path that crashes without swiftrt.obj on the
     *    link line; with it, JSONDecoder + Codable synthesis works
     *    correctly from a C-hosted Swift static library. */
    char *plan = ac_host_render_json(host, kSampleCard);
    if (!plan) {
        fprintf(stderr, "ac_host_render_json failed: %s\n", ac_last_error());
        ac_host_destroy(host);
        return 2;
    }
    printf("ac_host_render_json:      %lu chars\n",
           (unsigned long)strlen(plan));
    /* Uncomment to dump the full plan:
     *   printf("%s\n", plan); */
    ac_free(plan);

    /* 4. Wire up an action callback. */
    const char *label = "demo";
    ac_host_set_action_callback(host, on_action, (void *)label);
    printf("ac_host_set_action_callback: OK\n");

    /* 5. Synthesise a few actions to prove the callback round-trip. */
    printf("ac_host_fire_action:\n");
    ac_host_fire_action(host, AC_ACTION_SUBMIT, "{\"verb\":\"submit\"}");
    ac_host_fire_action(host, AC_ACTION_OPEN_URL, "https://example.com");
    ac_host_fire_action(host, AC_ACTION_SHOW_CARD, NULL);

    /* 6. Clean up. */
    ac_host_destroy(host);
    printf("ac_host_destroy:          OK\n");
    return 0;
}
