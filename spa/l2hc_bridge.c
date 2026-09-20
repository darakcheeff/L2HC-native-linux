/*
 * L2HC Native Bridge implementation
 * Direct in-process encoding without emulation or IPC socket.
 *
 * SPDX-License-Identifier: MIT
 */

#include "l2hc_bridge.h"
#include "l2hc_native.h"

#include <stdlib.h>
#include <string.h>
#include <errno.h>

struct l2hc_encoder_s {
    l2hc_native_t enc;
    l2hc_param_t params;
};

l2hc_handle_t l2hc_encoder_create(void) {
    l2hc_native_t enc = l2hc_native_create();
    if (!enc) return NULL;

    struct l2hc_encoder_s *h = (struct l2hc_encoder_s *)calloc(1, sizeof(*h));
    if (!h) {
        l2hc_native_destroy(enc);
        return NULL;
    }
    h->enc = enc;
    return h;
}

int l2hc_encoder_set_params(l2hc_handle_t h, const l2hc_param_t *param) {
    if (!h || !param) return -EINVAL;
    h->params = *param;

    L2hcEncParam np = {
        .sample_rate = param->sample_rate,
        .bps = param->bps,
        .channels = param->channels,
        .frame_samples = param->frame_samples,
        .bitrate_kbps = param->bitrate_kbps
    };
    return l2hc_native_set_param(h->enc, &np);
}

int l2hc_encoder_encode(l2hc_handle_t h, const void *pcm_in, uint32_t pcm_bytes,
                        void *out_buf, uint32_t *out_bytes) {
    if (!h || !pcm_in || !out_buf || !out_bytes) return -EINVAL;
    return l2hc_native_encode(h->enc, (const uint8_t *)pcm_in, pcm_bytes,
                              (uint8_t *)out_buf, out_bytes);
}

void l2hc_encoder_destroy(l2hc_handle_t h) {
    if (!h) return;
    if (h->enc) {
        l2hc_native_destroy(h->enc);
    }
    free(h);
}
