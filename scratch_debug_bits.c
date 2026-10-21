#include <stdio.h>
#include <stdint.h>
#include <math.h>
#include "l2hc_native.h"

int main() {
    l2hc_native_t enc640 = l2hc_native_create();
    l2hc_native_t enc960 = l2hc_native_create();

    L2hcEncParam p640 = { .sample_rate = 48000, .bps = 24, .channels = 2, .frame_samples = 480, .bitrate_kbps = 640 };
    L2hcEncParam p960 = { .sample_rate = 48000, .bps = 24, .channels = 2, .frame_samples = 480, .bitrate_kbps = 960 };

    l2hc_native_set_param(enc640, &p640);
    l2hc_native_set_param(enc960, &p960);

    uint8_t pcm[2880];
    for (int f = 0; f < 5; f++) {
        for (int i = 0; i < 480; i++) {
            double t = (double)(f * 480 + i) / 48000.0;
            // Rich multi-tone signal
            double s1 = 0.4 * sin(2*M_PI*220*t) + 0.3 * sin(2*M_PI*880*t) + 0.2 * sin(2*M_PI*3520*t);
            double s2 = 0.4 * cos(2*M_PI*440*t) + 0.3 * cos(2*M_PI*1760*t) + 0.2 * cos(2*M_PI*7040*t);
            int32_t v1 = (int32_t)(s1 * 8388607.0);
            int32_t v2 = (int32_t)(s2 * 8388607.0);
            pcm[i*6+0] = v1 & 0xff;
            pcm[i*6+1] = (v1 >> 8) & 0xff;
            pcm[i*6+2] = (v1 >> 16) & 0xff;
            pcm[i*6+3] = v2 & 0xff;
            pcm[i*6+4] = (v2 >> 8) & 0xff;
            pcm[i*6+5] = (v2 >> 16) & 0xff;
        }
        uint8_t out640[2048];
        uint32_t len640 = 0;
        l2hc_native_encode(enc640, pcm, sizeof(pcm), out640, &len640);

        uint8_t out960[2048];
        uint32_t len960 = 0;
        l2hc_native_encode(enc960, pcm, sizeof(pcm), out960, &len960);

        printf("Frame %d: 640k len=%u (sync=0x%02x, byte1=0x%02x) | 960k len=%u (sync=0x%02x, byte1=0x%02x)\n",
               f, len640, out640[0], out640[1], len960, out960[0], out960[1]);
    }

    l2hc_native_destroy(enc640);
    l2hc_native_destroy(enc960);
    return 0;
}
