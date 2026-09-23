/**************************************************************************/
/*  audio_effect_opus_chunked.h                                                */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#ifndef AUDIO_STREAM_OPUS_H
#define AUDIO_STREAM_OPUS_H

#include <atomic>
#include <cstdint>

#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include "opus.h"
#include "speex/speex_resampler.h"

namespace godot {

class AudioStreamOpus : public AudioStream {
    GDCLASS(AudioStreamOpus, AudioStream)

protected:
    static void _bind_methods();

public:
    virtual Ref<AudioStreamPlayback> _instantiate_playback() const override;
    virtual String _get_stream_name() const override { return "Opus Peer"; }
    virtual double _get_length() const override { return 0; }
    virtual bool _is_monophonic() const override { return false; }
    virtual double _get_bpm() const override { return 0.0; }
    virtual int32_t _get_beat_count() const override { return 0; }
};

class AudioStreamPlaybackOpus : public AudioStreamPlayback {
    GDCLASS(AudioStreamPlaybackOpus, AudioStreamPlayback)

    enum EpisodeState {
        EPISODE_UNINITIALIZED,
        EPISODE_RECEIVING,
        EPISODE_FINISHED,
        EPISODE_STOPPED,
    };

    std::atomic<bool> active{ false };
    std::atomic<EpisodeState> episode_state{ EPISODE_UNINITIALIZED };

    OpusDecoder* opusdecoder = NULL;
    SpeexResamplerState* output_resampler = NULL;
    int opus_sample_rate = 0;
    int opus_channels = 0;
    int output_mix_rate = 0;
    int max_decoded_frames = 0;
    int resampler_input_latency = 0;
    int resampler_output_latency = 0;
    int flush_input_frames_remaining = 0;

    PackedFloat32Array audiounpackedbuffer;
    LocalVector<AudioFrame> resampler_silence;

    // Single-producer/single-consumer decoded PCM ring. The packet receiver is
    // the producer and Godot's audio mixing thread is the consumer.
    LocalVector<AudioFrame> audiosamplebuffer;
    std::atomic<int64_t> bufferbegin{ 0 };
    std::atomic<int64_t> buffertail{ 0 };

    std::atomic<int64_t> mixed_output_frames{ 0 };
    std::atomic<int64_t> last_packet_output_frame{ 0 };
    int64_t scheduled_feed_output_frame = 0;
    int64_t stale_timeout_frames = 0;

    std::atomic<int64_t> underflow_frames{ 0 };
    std::atomic<int64_t> overflow_frames{ 0 };
    std::atomic<int64_t> decode_errors{ 0 };
    std::atomic<int> last_decode_error{ OPUS_OK };
    
    int lastpacketsizeforfec = 960;
    std::atomic<float> chunkmax{ 0.0f };
    int queue_decoded_frames(const float *decoded_samples, int frame_count);
    int resample_frames(const AudioFrame *input, int input_frames, AudioFrame *output, int output_frames, int &consumed_frames);
    void update_chunk_max(float magnitude);

    // Used to maps a pure sound wave in place of incoming audio data to check if problems are in playback or the data
    int Dsinewaveframes = 0;
    int Dsinewavephase = 0;
    float Dsinewavevolume = 1.0;

protected:
    static void _bind_methods();

public:
    virtual int32_t _mix(AudioFrame *dst_buffer, float rate_scale, int32_t frame_count) override;

    virtual void _start(double p_from_pos = 0.0) override;
    virtual void _stop() override;
    virtual bool _is_playing() const override;
    virtual int _get_loop_count() const override; 
    virtual double _get_playback_position() const override;
    virtual void _seek(double p_time) override;
    virtual void _tag_used_streams() override;

    Error initialize(int p_opus_sample_rate, int p_opus_channels, float p_buffer_length = 2.0f, float p_start_delay = 0.0f, float p_stale_timeout = 2.0f);
    int available_space_frames() const;
    int queue_length_frames() const;
    int push_opus_packet(const PackedByteArray& opusbytepacket, int begin, int decode_fec);
    float get_chunk_max();
    int64_t get_skips(bool overflow) const;
    int64_t get_underflow_frames() const;
    int64_t get_overflow_frames() const;
    int64_t get_decode_errors() const;
    int get_last_decode_error() const;
    int64_t finish_episode();
    void set_sinewave_frames(int sinewaveframes, float volume);
    AudioStreamPlaybackOpus();
    ~AudioStreamPlaybackOpus();
};


}

#endif // AUDIO_STREAM_OPUS_CHUNKED_H
