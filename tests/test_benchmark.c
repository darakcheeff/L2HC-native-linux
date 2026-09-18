#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <math.h>

#include "l2hc_native.h"

int main() {
    printf("Testing Native L2HC Encoder on x86_64...\n");

    l2hc_native_t enc = l2hc_native_create();
    if (!enc) {
        printf("Failed to create native encoder!\n");
        return 1;
    }

    L2hcEncParam param = {
        .sample_rate = 48000,
        .bps = 16,
        .channels = 2,
        .frame_samples = 480,
        .bitrate_kbps = 320
    };

    l2hc_native_set_param(enc, &param);

    uint32_t in_pcm_bytes = 480 * 2 * sizeof(int16_t);
    uint8_t *in_pcm = malloc(in_pcm_bytes);
    int16_t *samples = (int16_t*)in_pcm;
    for (int i = 0; i < 480; i++) {
        int16_t s = (int16_t)(10000.0 * sin(2.0 * 3.1415926535 * 440.0 * i / 48000.0));
        samples[i * 2] = s;
        samples[i * 2 + 1] = s;
    }

    uint8_t out_frame[4096];
    uint32_t out_len = 0;

    /* Warm-up */
    l2hc_native_encode(enc, in_pcm, in_pcm_bytes, out_frame, &out_len);
    printf("Initial frame output size: %u bytes, Header: 0x%02x\n", out_len, out_frame[0]);

    struct timespec t1, t2;
    clock_gettime(CLOCK_MONOTONIC, &t1);

    int num_frames = 1000; /* 10 seconds of audio */
    for (int i = 0; i < num_frames; i++) {
        int ret = l2hc_native_encode(enc, in_pcm, in_pcm_bytes, out_frame, &out_len);
        if (ret != 0) {
            printf("Error at frame %d: %d\n", i, ret);
            break;
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &t2);

    double elapsed_ms = (t2.tv_sec - t1.tv_sec) * 1000.0 + (t2.tv_nsec - t1.tv_nsec) / 1000000.0;
    double per_frame_ms = elapsed_ms / (double)num_frames;
    printf("Successfully encoded %d frames (10.0 seconds of audio) in %.2f ms!\n", num_frames, elapsed_ms);
    printf("Performance: %.3f ms per 10ms frame (%.1fx REALTIME speed!)\n", per_frame_ms, 10.0 / per_frame_ms);

    printf("Frame sync byte: 0x%02x (expected 0x5c)\n", out_frame[0]);

    l2hc_native_destroy(enc);
    free(in_pcm);
    return 0;
}
