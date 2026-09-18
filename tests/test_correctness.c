#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <assert.h>
#include "l2hc_native.h"

int main() {
    printf("=== L2HC Native Correctness Test ===\n");
    l2hc_native_t enc = l2hc_native_create();
    assert(enc != NULL);

    L2hcEncParam param = {
        .sample_rate = 48000,
        .bps = 24,
        .channels = 2,
        .frame_samples = 480,
        .bitrate_kbps = 320
    };
    int r = l2hc_native_set_param(enc, &param);
    assert(r == 0);

    const int N = 480;
    const int pcm_len = N * 2 * 3; // 2880 bytes
    uint8_t *pcm = malloc(pcm_len);
    uint8_t out[1024];
    uint32_t out_len = 0;

    for (int f = 0; f < 50; f++) {
        for (int i = 0; i < N; i++) {
            double t = (double)(f * N + i) / 48000.0;
            double s_l = sin(2.0 * M_PI * 440.0 * t) * 0.5 + sin(2.0 * M_PI * 1200.0 * t) * 0.3;
            double s_r = cos(2.0 * M_PI * 440.0 * t) * 0.5 + cos(2.0 * M_PI * 800.0 * t) * 0.3;
            int32_t v_l = (int32_t)(s_l * 8388600.0);
            int32_t v_r = (int32_t)(s_r * 8388600.0);
            pcm[i * 6 + 0] = v_l & 0xff;
            pcm[i * 6 + 1] = (v_l >> 8) & 0xff;
            pcm[i * 6 + 2] = (v_l >> 16) & 0xff;
            pcm[i * 6 + 3] = v_r & 0xff;
            pcm[i * 6 + 4] = (v_r >> 8) & 0xff;
            pcm[i * 6 + 5] = (v_r >> 16) & 0xff;
        }

        out_len = 0;
        int res = l2hc_native_encode(enc, pcm, pcm_len, out, &out_len);
        assert(res == 0);
        assert(out_len == 400);
        assert(out[0] == 0x5c); // Sync byte
    }

    printf("All 50 frames verified: exactly 400 bytes, sync byte 0x5c, valid framing!\n");
    l2hc_native_destroy(enc);
    free(pcm);
    return 0;
}
