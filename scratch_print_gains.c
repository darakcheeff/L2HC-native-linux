#include <stdio.h>
#include <stdint.h>
#include <math.h>

#define private public
#include "l2hc_native.c"

int main() {
    L2hcEncoderState *st = (L2hcEncoderState*)l2hc_native_create();
    for (int br = 320; br <= 960; br += 160) {
        L2hcEncParam p = { .sample_rate = 48000, .bps = 24, .channels = 2, .frame_samples = 480, .bitrate_kbps = br };
        AudioL2hcEncSetParam(st, &p);

        uint8_t pcm[2880];
        for (int i = 0; i < 480; i++) {
            double t = (double)i / 48000.0;
            double s1 = 0.4 * sin(2*M_PI*220*t) + 0.3 * sin(2*M_PI*880*t);
            double s2 = 0.4 * cos(2*M_PI*440*t) + 0.3 * cos(2*M_PI*1760*t);
            int32_t v1 = (int32_t)(s1 * 8388607.0);
            int32_t v2 = (int32_t)(s2 * 8388607.0);
            pcm[i*6+0] = v1 & 0xff;
            pcm[i*6+1] = (v1 >> 8) & 0xff;
            pcm[i*6+2] = (v1 >> 16) & 0xff;
            pcm[i*6+3] = v2 & 0xff;
            pcm[i*6+4] = (v2 >> 8) & 0xff;
            pcm[i*6+5] = (v2 >> 16) & 0xff;
        }

        uint8_t out[2048];
        uint32_t out_len = 0;
        l2hc_native_encode((l2hc_native_t)st, pcm, sizeof(pcm), out, &out_len);
        int exact_bits = count_frame_exact_bits(st);
        printf("BR=%d kbps | target_bits=%d | exact_bits=%d | global_gain=%d | frac_gain=%d | ms_flag=%d | diff_sf=%d\n",
               br, st->target_frame_bits, exact_bits, st->global_gain, st->frac_gain, st->ms_flag, st->diff_sf_flag);
    }
    l2hc_native_destroy((l2hc_native_t)st);
    return 0;
}
