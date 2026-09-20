#ifndef L2HC_BRIDGE_H
#define L2HC_BRIDGE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct l2hc_encoder_s *l2hc_handle_t;

typedef struct {
    uint32_t sample_rate;   /* 44100, 48000, 88200, 96000 */
    int16_t  bps;           /* 16, 24, 32 */
    int16_t  channels;      /* 1, 2 */
    int16_t  frame_samples; /* 960, 480 */
    int16_t  bitrate_kbps;  /* 64..960 */
} __attribute__((packed)) l2hc_param_t;

l2hc_handle_t l2hc_encoder_create(void);
int l2hc_encoder_set_params(l2hc_handle_t h, const l2hc_param_t *param);
int l2hc_encoder_encode(l2hc_handle_t h, const void *pcm_in, uint32_t pcm_bytes, void *out_buf, uint32_t *out_bytes);
void l2hc_encoder_destroy(l2hc_handle_t h);

#ifdef __cplusplus
}
#endif

#endif /* L2HC_BRIDGE_H */
