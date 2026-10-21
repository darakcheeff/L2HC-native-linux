#include <stdio.h>
#include <stdint.h>
#include <math.h>
#include "l2hc_native.h"

int main() {
    l2hc_native_t enc = l2hc_native_create();
    for (int br = 640; br <= 960; br += 320) {
        L2hcEncParam p = {
            .sample_rate = 48000,
            .bps = 24,
            .channels = 2,
            .frame_samples = 480,
            .bitrate_kbps = br
        };
        l2hc_native_set_param(enc, &p);

        // generate complex stereo signal
        uint8_t pcm[2880];
        int32_t *samples = (int32_t*)pcm;
        for (int i = 0; i < 480; i++) {
            float s1 = sinf(2.0f * M_PI * 440.0f * i / 48000.0f) * 0.8f;
            float s2 = cosf(2.0f * M_PI * 1000.0f * i / 48000.0f) * 0.6f;
            int32_t v1 = (int32_t)(s1 * 8388607.0f) << 8;
            int32_t v2 = (int32_t)(s2 * 8388607.0f) << 8;
            // 24-bit packed in 3 bytes
            uint8_t *p1 = &pcm[i * 6];
            p1[0] = (v1 >> 8) & 0xff;
            p1[1] = (v1 >> 16) & 0xff;
            p1[2] = (v1 >> 24) & 0xff;
            p1[3] = (v2 >> 8) & 0xff;
            p1[4] = (v2 >> 16) & 0xff;
            p1[5] = (v2 >> 24) & 0xff;
        }

        uint8_t out[2048];
        uint32_t out_bytes = 0;
        l2hc_native_encode(enc, pcm, sizeof(pcm), out, &out_bytes);
        printf("Bitrate %d kbps: out_bytes = %u (target = %d)\n", br, out_bytes, (br * 10)/8);
    }
    l2hc_native_destroy(enc);
    return 0;
}
