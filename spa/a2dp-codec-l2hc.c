/* Spa A2DP Huawei L2HC codec */
/* SPDX-FileCopyrightText: Copyright © 2026 darakcheeff */
/* SPDX-License-Identifier: MIT */

#include <unistd.h>
#include <stddef.h>
#include <errno.h>
#include <arpa/inet.h>

#include <spa/param/audio/format.h>
#include <spa/param/audio/format-utils.h>
#include <endian.h>
#include <spa/utils/string.h>
#include <spa/utils/dict.h>
#include <spa/pod/parser.h>
#include <spa/pod/builder.h>

#include "rtp.h"
#include "media-codecs.h"
#include "l2hc_bridge.h"

#ifndef SPA_BLUETOOTH_AUDIO_CODEC_L2HC
#define SPA_BLUETOOTH_AUDIO_CODEC_L2HC 0x70
#define SPA_BLUETOOTH_AUDIO_CODEC_L2HC_320 0x71
#define SPA_BLUETOOTH_AUDIO_CODEC_L2HC_480 0x72
#define SPA_BLUETOOTH_AUDIO_CODEC_L2HC_640 0x73
#define SPA_BLUETOOTH_AUDIO_CODEC_L2HC_960 0x74
#endif

#define L2HC_DEFAULT_BITRATE 960

struct props {
	int bitrate;
};

struct impl {
	l2hc_handle_t enc;

	struct rtp_header *header;
	uint8_t *payload;

	int mtu;
	int samplerate;
	int channels;
	int bps;
	int frame_samples;
	int bitrate;
	int base_bitrate;
	int block_size;

	/* Fragmentation */
	uint8_t enc_buffer[2048];
	size_t enc_total;
	size_t frag_offset;
	bool frag_in_progress;
};

static const struct media_codec_config l2hc_frequencies[] = {
	{ L2HC_SAMPLING_FREQ_96000, 96000, 4 },
	{ L2HC_SAMPLING_FREQ_88200, 88200, 3 },
	{ L2HC_SAMPLING_FREQ_48000, 48000, 2 },
	{ L2HC_SAMPLING_FREQ_44100, 44100, 1 },
	{ L2HC_SAMPLING_FREQ_32000, 32000, 0 },
};

static const struct media_codec_config l2hc_bit_depths[] = {
	{ L2HC_BIT_DEPTH_24, 24, 2 },
	{ L2HC_BIT_DEPTH_32, 32, 1 },
	{ L2HC_BIT_DEPTH_16, 16, 0 },
};

#if defined(SPA_VERSION_BLUEZ5_CODEC_MEDIA) && (SPA_VERSION_BLUEZ5_CODEC_MEDIA >= 12)
static int codec_fill_caps(const struct media_codec *codec, uint32_t flags,
		const struct spa_dict *settings, uint8_t caps[A2DP_MAX_CAPS_SIZE])
#else
static int codec_fill_caps(const struct media_codec *codec, uint32_t flags,
		uint8_t caps[A2DP_MAX_CAPS_SIZE])
#endif
{
	const a2dp_l2hc_t a2dp_l2hc = {
		.info = codec->vendor,
		.bits_per_sample = L2HC_BIT_DEPTH_16 | L2HC_BIT_DEPTH_24 | L2HC_BIT_DEPTH_32,
		.frequency = L2HC_SAMPLING_FREQ_44100 | L2HC_SAMPLING_FREQ_48000 |
		             L2HC_SAMPLING_FREQ_88200 | L2HC_SAMPLING_FREQ_96000,
		.bitrate_high = L2HC_BITRATE_320K | L2HC_BITRATE_480K |
		                L2HC_BITRATE_640K | L2HC_BITRATE_960K,
		.bitrate_low_frame_len = L2HC_FRAME_10MS | L2HC_BITRATE_96K |
		                         L2HC_BITRATE_128K | L2HC_BITRATE_192K | L2HC_BITRATE_256K
	};
	memcpy(caps, &a2dp_l2hc, sizeof(a2dp_l2hc));
	return sizeof(a2dp_l2hc);
}

static int codec_select_config(const struct media_codec *codec, uint32_t flags,
		const void *caps, size_t caps_size,
		const struct media_codec_audio_info *info,
		const struct spa_dict *global_settings, uint8_t config[A2DP_MAX_CAPS_SIZE])
{
	const a2dp_l2hc_t *c = caps;
	a2dp_l2hc_t conf;
	int res;

	if (caps_size < sizeof(conf))
		return -EINVAL;

	if (c->info.vendor_id != codec->vendor.vendor_id ||
	    c->info.codec_id != codec->vendor.codec_id)
		return -ENOTSUP;

	memset(&conf, 0, sizeof(conf));
	conf.info = codec->vendor;

	/* Select frequency */
	res = media_codec_select_config(l2hc_frequencies, SPA_N_ELEMENTS(l2hc_frequencies),
			c->frequency, info ? info->rate : A2DP_CODEC_DEFAULT_RATE);
	if (res < 0)
		return -ENOTSUP;
	conf.frequency = l2hc_frequencies[res].config;

	/* Select bit depth: prefer 24-bit */
	res = media_codec_select_config(l2hc_bit_depths, SPA_N_ELEMENTS(l2hc_bit_depths),
			c->bits_per_sample, 24);
	if (res < 0)
		return -ENOTSUP;
	conf.bits_per_sample = l2hc_bit_depths[res].config;

	/* Select bitrate based on codec profile */
	uint32_t target_bitrate = 0;
	if (codec->id == SPA_BLUETOOTH_AUDIO_CODEC_L2HC_320) target_bitrate = 320;
	else if (codec->id == SPA_BLUETOOTH_AUDIO_CODEC_L2HC_480) target_bitrate = 480;
	else if (codec->id == SPA_BLUETOOTH_AUDIO_CODEC_L2HC_640) target_bitrate = 640;
	else if (codec->id == SPA_BLUETOOTH_AUDIO_CODEC_L2HC_960) target_bitrate = 960;

	if (target_bitrate == 320) {
		if (!(c->bitrate_high & L2HC_BITRATE_320K)) return -ENOTSUP;
		conf.bitrate_high = L2HC_BITRATE_320K;
	} else if (target_bitrate == 480) {
		if (!(c->bitrate_high & L2HC_BITRATE_480K)) return -ENOTSUP;
		conf.bitrate_high = L2HC_BITRATE_480K;
	} else if (target_bitrate == 640) {
		if (!(c->bitrate_high & L2HC_BITRATE_640K)) return -ENOTSUP;
		conf.bitrate_high = L2HC_BITRATE_640K;
	} else if (target_bitrate == 960) {
		if (!(c->bitrate_high & L2HC_BITRATE_960K)) return -ENOTSUP;
		conf.bitrate_high = L2HC_BITRATE_960K;
	} else {
		/* Auto: pick best supported */
		if (c->bitrate_high & L2HC_BITRATE_960K)
			conf.bitrate_high = L2HC_BITRATE_960K;
		else if (c->bitrate_high & L2HC_BITRATE_640K)
			conf.bitrate_high = L2HC_BITRATE_640K;
		else if (c->bitrate_high & L2HC_BITRATE_480K)
			conf.bitrate_high = L2HC_BITRATE_480K;
		else if (c->bitrate_high & L2HC_BITRATE_320K)
			conf.bitrate_high = L2HC_BITRATE_320K;
		else
			conf.bitrate_high = 0;
	}

	/* Select 10ms frame duration */
	conf.bitrate_low_frame_len = L2HC_FRAME_10MS;
	if (conf.bitrate_high == 0) {
		if (c->bitrate_low_frame_len & L2HC_BITRATE_256K)
			conf.bitrate_low_frame_len |= L2HC_BITRATE_256K;
		else if (c->bitrate_low_frame_len & L2HC_BITRATE_192K)
			conf.bitrate_low_frame_len |= L2HC_BITRATE_192K;
		else if (c->bitrate_low_frame_len & L2HC_BITRATE_128K)
			conf.bitrate_low_frame_len |= L2HC_BITRATE_128K;
		else
			conf.bitrate_low_frame_len |= L2HC_BITRATE_96K;
	}

	memcpy(config, &conf, sizeof(conf));
	return sizeof(conf);
}

static int codec_enum_config(const struct media_codec *codec, uint32_t flags,
		const void *caps, size_t caps_size, uint32_t id, uint32_t idx,
		struct spa_pod_builder *b, struct spa_pod **param)
{
	uint8_t cbuf[A2DP_MAX_CAPS_SIZE];
	const a2dp_l2hc_t *conf = (const a2dp_l2hc_t *)cbuf;
	struct spa_pod_frame f[2];
	uint32_t rate;
	enum spa_audio_format format;

	if (codec_select_config(codec, flags, caps, caps_size, NULL, NULL, cbuf) < 0)
		return -ENOTSUP;

	switch (conf->frequency) {
	case L2HC_SAMPLING_FREQ_96000: rate = 96000; break;
	case L2HC_SAMPLING_FREQ_88200: rate = 88200; break;
	case L2HC_SAMPLING_FREQ_48000: rate = 48000; break;
	case L2HC_SAMPLING_FREQ_44100: rate = 44100; break;
	case L2HC_SAMPLING_FREQ_32000: rate = 32000; break;
	default: return -EINVAL;
	}

	switch (conf->bits_per_sample) {
	case L2HC_BIT_DEPTH_24: format = SPA_AUDIO_FORMAT_S24_LE; break;
	case L2HC_BIT_DEPTH_32: format = SPA_AUDIO_FORMAT_S32_LE; break;
	case L2HC_BIT_DEPTH_16: format = SPA_AUDIO_FORMAT_S16_LE; break;
	default: return -EINVAL;
	}

	if (idx > 0)
		return 0;

	spa_pod_builder_push_object(b, &f[0], SPA_TYPE_OBJECT_Format, id);
	spa_pod_builder_add(b,
		SPA_FORMAT_mediaType,      SPA_POD_Id(SPA_MEDIA_TYPE_audio),
		SPA_FORMAT_mediaSubtype,   SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
		SPA_FORMAT_AUDIO_format,   SPA_POD_Id(format),
		SPA_FORMAT_AUDIO_channels, SPA_POD_Int(2),
		SPA_FORMAT_AUDIO_rate,     SPA_POD_Int(rate),
		0);

	spa_pod_builder_prop(b, SPA_FORMAT_AUDIO_position, 0);
	spa_pod_builder_push_array(b, &f[1]);
	spa_pod_builder_id(b, SPA_AUDIO_CHANNEL_FL);
	spa_pod_builder_id(b, SPA_AUDIO_CHANNEL_FR);
	spa_pod_builder_pop(b, &f[1]);

	*param = spa_pod_builder_pop(b, &f[0]);
	return 1;
}

static int codec_validate_config(const struct media_codec *codec, uint32_t flags,
		const void *caps, size_t caps_size,
		struct spa_audio_info *info)
{
	const a2dp_l2hc_t *conf = caps;

	if (caps_size < sizeof(*conf))
		return -EINVAL;

	if (conf->info.vendor_id != codec->vendor.vendor_id ||
	    conf->info.codec_id != codec->vendor.codec_id)
		return -EINVAL;

	info->media_type = SPA_MEDIA_TYPE_audio;
	info->media_subtype = SPA_MEDIA_SUBTYPE_raw;

	switch (conf->bits_per_sample) {
	case L2HC_BIT_DEPTH_24: info->info.raw.format = SPA_AUDIO_FORMAT_S24_LE; break;
	case L2HC_BIT_DEPTH_32: info->info.raw.format = SPA_AUDIO_FORMAT_S32_LE; break;
	case L2HC_BIT_DEPTH_16: info->info.raw.format = SPA_AUDIO_FORMAT_S16_LE; break;
	default: return -EINVAL;
	}

	switch (conf->frequency) {
	case L2HC_SAMPLING_FREQ_96000: info->info.raw.rate = 96000; break;
	case L2HC_SAMPLING_FREQ_88200: info->info.raw.rate = 88200; break;
	case L2HC_SAMPLING_FREQ_48000: info->info.raw.rate = 48000; break;
	case L2HC_SAMPLING_FREQ_44100: info->info.raw.rate = 44100; break;
	case L2HC_SAMPLING_FREQ_32000: info->info.raw.rate = 32000; break;
	default: return -EINVAL;
	}

	info->info.raw.channels = 2;
	info->info.raw.position[0] = SPA_AUDIO_CHANNEL_FL;
	info->info.raw.position[1] = SPA_AUDIO_CHANNEL_FR;
	return 0;
}

static int codec_caps_preference_cmp(const struct media_codec *codec, uint32_t flags,
		const void *caps1, size_t caps1_size,
		const void *caps2, size_t caps2_size,
		const struct media_codec_audio_info *info,
		const struct spa_dict *global_settings)
{
	return 0;
}

static void *codec_init(const struct media_codec *codec, uint32_t flags,
		void *config, size_t config_len, const struct spa_audio_info *info,
		void *props, size_t mtu)
{
	struct impl *this;
	const a2dp_l2hc_t *conf = config;
	l2hc_param_t p;

	if (config_len < sizeof(*conf))
		return NULL;

	this = calloc(1, sizeof(*this));
	if (!this)
		return NULL;

	this->mtu = mtu;
	this->channels = 2;

	switch (conf->frequency) {
	case L2HC_SAMPLING_FREQ_96000: this->samplerate = 96000; break;
	case L2HC_SAMPLING_FREQ_88200: this->samplerate = 88200; break;
	case L2HC_SAMPLING_FREQ_48000: this->samplerate = 48000; break;
	case L2HC_SAMPLING_FREQ_44100: this->samplerate = 44100; break;
	case L2HC_SAMPLING_FREQ_32000: this->samplerate = 32000; break;
	default: this->samplerate = 96000; break;
	}

	switch (conf->bits_per_sample) {
	case L2HC_BIT_DEPTH_24: this->bps = 24; break;
	case L2HC_BIT_DEPTH_32: this->bps = 32; break;
	case L2HC_BIT_DEPTH_16: this->bps = 16; break;
	default: this->bps = 24; break;
	}

	/* Samples per 10ms frame */
	this->frame_samples = this->samplerate / 100;
	this->block_size = this->frame_samples * this->channels * (this->bps / 8);

	if (conf->bitrate_high & L2HC_BITRATE_960K)
		this->bitrate = 960;
	else if (conf->bitrate_high & L2HC_BITRATE_640K)
		this->bitrate = 640;
	else if (conf->bitrate_high & L2HC_BITRATE_480K)
		this->bitrate = 480;
	else if (conf->bitrate_high & L2HC_BITRATE_320K)
		this->bitrate = 320;
	else if (conf->bitrate_low_frame_len & L2HC_BITRATE_256K)
		this->bitrate = 256;
	else
		this->bitrate = 192;

	this->base_bitrate = this->bitrate;

	fprintf(stderr, "l2hc: codec_init: rate=%u bps=%u ch=%u block_size=%d bitrate=%d (base=%d) mtu=%zu\n",
		this->samplerate, this->bps, this->channels, this->block_size, this->bitrate, this->base_bitrate, mtu);
	this->enc = l2hc_encoder_create();
	if (!this->enc) {
		fprintf(stderr, "l2hc: codec_init: FAILED to connect to encoder!\n");
		free(this);
		return NULL;
	}
	fprintf(stderr, "l2hc: codec_init: connected to encoder successfully\n");

	p.sample_rate = this->samplerate;
	p.bps = this->bps;
	p.channels = this->channels;
	p.frame_samples = this->frame_samples;
	p.bitrate_kbps = this->bitrate;

	if (l2hc_encoder_set_params(this->enc, &p) != 0) {
		l2hc_encoder_destroy(this->enc);
		free(this);
		return NULL;
	}

	return this;
}

static void codec_deinit(void *data)
{
	struct impl *this = data;
	if (this) {
		if (this->enc)
			l2hc_encoder_destroy(this->enc);
		free(this);
	}
}

static int codec_get_block_size(void *data)
{
	struct impl *this = data;
	return this->block_size;
}

static int codec_start_encode(void *data,
		void *dst, size_t dst_size, uint16_t seqnum, uint32_t timestamp)
{
	struct impl *this = data;

	if (dst_size < sizeof(struct rtp_header) + 1)
		return -EINVAL;

	this->header = (struct rtp_header *)dst;
	this->payload = (uint8_t *)dst + sizeof(struct rtp_header);

	memset(this->header, 0, sizeof(struct rtp_header) + 1);

	this->header->v = 2;
	this->header->pt = 96;
	this->header->sequence_number = htons(seqnum);
	this->header->timestamp = htonl(timestamp);
	this->header->ssrc = htonl(1);

	/* 1 byte L2HC payload header: written in codec_encode */
	*this->payload = 0;

	return sizeof(struct rtp_header) + 1;
}

static int codec_encode(void *data,
		const void *src, size_t src_size,
		void *dst, size_t dst_size,
		size_t *dst_out, int *need_flush)
{
	struct impl *this = data;
	uint32_t encoded_bytes = 0;
	size_t max_payload;
	int res;

	max_payload = (this->mtu > 13) ? (this->mtu - 13) : 800;

	/* Continuation of fragmented frame */
	if (this->frag_in_progress) {
		size_t remaining = this->enc_total - this->frag_offset;
		size_t chunk = SPA_MIN(remaining, max_payload);

		memcpy(dst, this->enc_buffer + this->frag_offset, chunk);
		*dst_out = chunk;
		this->frag_offset += chunk;

		if (this->frag_offset < this->enc_total) {
			*this->payload = 0xcc; /* Middle fragment */
			*need_flush = NEED_FLUSH_FRAGMENT;
		} else {
			*this->payload = 0xdd; /* Final fragment */
			*need_flush = NEED_FLUSH_ALL;
			this->frag_in_progress = false;
			this->frag_offset = 0;
			this->enc_total = 0;
		}
		return 0;
	}

	if (src == NULL || src_size < (size_t)this->block_size) {
		*dst_out = 0;
		*need_flush = NEED_FLUSH_NO;
		return 0;
	}

	static uint32_t enc_cnt = 0;
	res = l2hc_encoder_encode(this->enc, src, this->block_size, this->enc_buffer, &encoded_bytes);
	if (res != 0 || encoded_bytes == 0) {
		fprintf(stderr, "l2hc: codec_encode: FAILED res=%d encoded_bytes=%u\n", res, encoded_bytes);
		return -EINVAL;
	}
	if (++enc_cnt % 100 == 1) {
		fprintf(stderr, "l2hc: codec_encode #%u: %d pcm bytes -> %u encoded bytes (bitrate=%d)\n",
			enc_cnt, this->block_size, encoded_bytes, this->bitrate);
	}

	this->enc_total = encoded_bytes;

	if (this->enc_total <= max_payload) {
		/* Fits in single packet */
		memcpy(dst, this->enc_buffer, this->enc_total);
		*dst_out = this->enc_total;
		*this->payload = 0x01; /* 1 frame */
		*need_flush = NEED_FLUSH_ALL;
		this->frag_in_progress = false;
	} else {
		/* Exceeds MTU: split into fragments */
		size_t chunk = max_payload;
		if (this->enc_total == 1200) {
			chunk = 600; /* Balanced 600 + 600 bytes for 960 kbps */
		}

		memcpy(dst, this->enc_buffer, chunk);
		*dst_out = chunk;
		this->frag_offset = chunk;
		this->frag_in_progress = true;

		*this->payload = 0xee; /* First fragment */
		*need_flush = NEED_FLUSH_FRAGMENT;
	}

	return this->block_size;
}

static int codec_reduce_bitpool(void *data)
{
	struct impl *this = data;
	int prev = this->bitrate;

	if (this->bitrate == 960) this->bitrate = 640;
	else if (this->bitrate == 640) this->bitrate = 480;
	else if (this->bitrate == 480) this->bitrate = 320;
	else return this->bitrate;

	l2hc_param_t p = {
		.sample_rate = this->samplerate,
		.bps = this->bps,
		.channels = this->channels,
		.frame_samples = this->frame_samples,
		.bitrate_kbps = this->bitrate
	};
	l2hc_encoder_set_params(this->enc, &p);
	fprintf(stderr, "l2hc: ABR reduce bitrate: %d -> %d kbps\n", prev, this->bitrate);
	return this->bitrate;
}

static int codec_increase_bitpool(void *data)
{
	struct impl *this = data;
	int prev = this->bitrate;

	if (this->bitrate >= this->base_bitrate)
		return this->bitrate;

	if (this->bitrate == 320) this->bitrate = (this->base_bitrate >= 480) ? 480 : 320;
	else if (this->bitrate == 480) this->bitrate = (this->base_bitrate >= 640) ? 640 : 480;
	else if (this->bitrate == 640) this->bitrate = (this->base_bitrate >= 960) ? 960 : 640;
	else return this->bitrate;

	if (this->bitrate != prev) {
		l2hc_param_t p = {
			.sample_rate = this->samplerate,
			.bps = this->bps,
			.channels = this->channels,
			.frame_samples = this->frame_samples,
			.bitrate_kbps = this->bitrate
		};
		l2hc_encoder_set_params(this->enc, &p);
		fprintf(stderr, "l2hc: ABR increase bitrate: %d -> %d kbps\n", prev, this->bitrate);
	}
	return this->bitrate;
}

static int codec_abr_process(void *data, size_t unsent)
{
	struct impl *this = data;
	if (unsent > 32768 && this->bitrate > 320) {
		return codec_reduce_bitpool(this);
	}
	return 0;
}

#define L2HC_COMMON_DEFS \
	.codec_id = A2DP_CODEC_VENDOR, \
	.send_buf_size = 524288, \
	.vendor = { \
		.vendor_id = L2HC_VENDOR_ID, \
		.codec_id = L2HC_CODEC_ID \
	}, \
	.fill_caps = codec_fill_caps, \
	.select_config = codec_select_config, \
	.enum_config = codec_enum_config, \
	.validate_config = codec_validate_config, \
	.caps_preference_cmp = codec_caps_preference_cmp, \
	.init = codec_init, \
	.deinit = codec_deinit, \
	.get_block_size = codec_get_block_size, \
	.start_encode = codec_start_encode, \
	.encode = codec_encode, \
	.abr_process = codec_abr_process, \
	.reduce_bitpool = codec_reduce_bitpool, \
	.increase_bitpool = codec_increase_bitpool

static const struct media_codec spa_l2hc_auto = {
	L2HC_COMMON_DEFS,
	.id = SPA_BLUETOOTH_AUDIO_CODEC_L2HC,
	.name = "l2hc",
	.description = "L2HC (Auto)",
	.endpoint_name = "l2hc_auto",
};

static const struct media_codec spa_l2hc_320 = {
	L2HC_COMMON_DEFS,
	.id = SPA_BLUETOOTH_AUDIO_CODEC_L2HC_320,
	.name = "l2hc_320",
	.description = "L2HC (320 kbps)",
	.endpoint_name = "l2hc_320",
};

static const struct media_codec spa_l2hc_480 = {
	L2HC_COMMON_DEFS,
	.id = SPA_BLUETOOTH_AUDIO_CODEC_L2HC_480,
	.name = "l2hc_480",
	.description = "L2HC (480 kbps)",
	.endpoint_name = "l2hc_480",
};

static const struct media_codec spa_l2hc_640 = {
	L2HC_COMMON_DEFS,
	.id = SPA_BLUETOOTH_AUDIO_CODEC_L2HC_640,
	.name = "l2hc_640",
	.description = "L2HC (640 kbps)",
	.endpoint_name = "l2hc_640",
};

static const struct media_codec spa_l2hc_960 = {
	L2HC_COMMON_DEFS,
	.id = SPA_BLUETOOTH_AUDIO_CODEC_L2HC_960,
	.name = "l2hc_960",
	.description = "L2HC (960 kbps)",
	.endpoint_name = "l2hc_960",
};

MEDIA_CODEC_EXPORT_DEF("l2hc",
	&spa_l2hc_auto,
	&spa_l2hc_320,
	&spa_l2hc_480,
	&spa_l2hc_640,
	&spa_l2hc_960
);
