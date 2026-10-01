/**************************************************************************/
/*  audio_effect_opus.cpp                                                 */
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
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED httpTO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "audio_stream_opus.h"

#include <algorithm>
#include <cmath>

#include <godot_cpp/classes/audio_server.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void AudioStreamOpus::_bind_methods() {
}

void AudioStreamPlaybackOpus::_bind_methods() {

    ClassDB::bind_method(D_METHOD("available_space_frames"), &AudioStreamPlaybackOpus::available_space_frames);
    ClassDB::bind_method(D_METHOD("queue_length_frames"), &AudioStreamPlaybackOpus::queue_length_frames);
    ClassDB::bind_method(D_METHOD("initialize", "opus_sample_rate", "opus_channels", "opus_frame_size", "buffer_length", "start_delay", "stale_timeout"), &AudioStreamPlaybackOpus::initialize, DEFVAL(2.0f), DEFVAL(0.0f), DEFVAL(2.0f));
    ClassDB::bind_method(D_METHOD("push_opus_packet", "opusbytepacket", "begin", "decode_fec"), &AudioStreamPlaybackOpus::push_opus_packet);
    ClassDB::bind_method(D_METHOD("finish_episode"), &AudioStreamPlaybackOpus::finish_episode);
    ClassDB::bind_method(D_METHOD("get_tail_max", "frame_count"), &AudioStreamPlaybackOpus::get_tail_max);
    ClassDB::bind_method(D_METHOD("get_frame_number_actually_in_speaker"), &AudioStreamPlaybackOpus::get_frame_number_actually_in_speaker);
    ClassDB::bind_method(D_METHOD("get_skips", "overflow"), &AudioStreamPlaybackOpus::get_skips);
    ClassDB::bind_method(D_METHOD("get_underflow_frames"), &AudioStreamPlaybackOpus::get_underflow_frames);
    ClassDB::bind_method(D_METHOD("get_overflow_frames"), &AudioStreamPlaybackOpus::get_overflow_frames);
    ClassDB::bind_method(D_METHOD("get_decode_errors"), &AudioStreamPlaybackOpus::get_decode_errors);
    ClassDB::bind_method(D_METHOD("get_last_decode_error"), &AudioStreamPlaybackOpus::get_last_decode_error);
    ClassDB::bind_method(D_METHOD("get_frame_hash", "first_frame", "frame_count"), &AudioStreamPlaybackOpus::get_frame_hash);
    ClassDB::bind_method(D_METHOD("set_sinewave_frames", "sinewaveframes", "volume"), &AudioStreamPlaybackOpus::set_sinewave_frames);
}

Ref<AudioStreamPlayback> AudioStreamOpus::_instantiate_playback() const {
    Ref<AudioStreamPlaybackOpus> playback;
    playback.instantiate();
    return playback;
}

AudioStreamPlaybackOpus::AudioStreamPlaybackOpus() {
    godot::UtilityFunctions::print_verbose("construct AudioStreamPlaybackOpus");
}

Error AudioStreamPlaybackOpus::initialize(int p_opus_sample_rate, int p_opus_channels, int p_opus_frame_size, float p_buffer_length, float p_start_delay, float p_stale_timeout) {
    if (episode_state.load(std::memory_order_acquire) != EPISODE_UNINITIALIZED) {
        return ERR_ALREADY_IN_USE;
    }
    if (!((p_opus_sample_rate == 8000) || (p_opus_sample_rate == 12000) || (p_opus_sample_rate == 16000) || (p_opus_sample_rate == 24000) || (p_opus_sample_rate == 48000))) {
        UtilityFunctions::printerr("Opus sample rate must be one of 48000,24000,16000,12000,8000");
        return ERR_INVALID_PARAMETER;
    }
    if ((p_opus_channels != 1) && (p_opus_channels != 2)) {
        UtilityFunctions::printerr("Opus channels must be 1 or 2");
        return ERR_INVALID_PARAMETER;
    }
    if (!(p_opus_frame_size == p_opus_sample_rate / 400 ||
            p_opus_frame_size == p_opus_sample_rate / 200 ||
            p_opus_frame_size == p_opus_sample_rate / 100 ||
            p_opus_frame_size == p_opus_sample_rate / 50 ||
            p_opus_frame_size == p_opus_sample_rate / 25 ||
            p_opus_frame_size == p_opus_sample_rate * 3 / 50)) {
        UtilityFunctions::printerr("Opus frame size must represent 2.5, 5, 10, 20, 40 or 60 ms");
        return ERR_INVALID_PARAMETER;
    }
    if (p_buffer_length <= 0.0f || p_start_delay < 0.0f || p_stale_timeout <= 0.0f) {
        return ERR_INVALID_PARAMETER;
    }

    int opuserror = 0;
    OpusDecoder *new_decoder = opus_decoder_create(p_opus_sample_rate, p_opus_channels, &opuserror);
    if (new_decoder == NULL || opuserror != OPUS_OK) {
        UtilityFunctions::printerr("opus_decoder_create error ", opuserror);
        return ERR_CANT_CREATE;
    }

    AudioServer *audio_server = AudioServer::get_singleton();
    const int new_output_mix_rate = static_cast<int>(audio_server->get_mix_rate());
    int speexerror = RESAMPLER_ERR_SUCCESS;
    SpeexResamplerState *new_resampler = speex_resampler_init(2, p_opus_sample_rate, new_output_mix_rate, SPEEX_RESAMPLER_QUALITY_DEFAULT, &speexerror);
    if (new_resampler == NULL || speexerror != RESAMPLER_ERR_SUCCESS) {
        opus_decoder_destroy(new_decoder);
        UtilityFunctions::printerr("Speex output resampler init failed code ", speexerror);
        return ERR_CANT_CREATE;
    }
    speex_resampler_set_input_stride(new_resampler, 2);
    speex_resampler_set_output_stride(new_resampler, 2);

    opus_sample_rate = p_opus_sample_rate;
    opus_channels = p_opus_channels;
    opus_frame_size = p_opus_frame_size;
    output_mix_rate = new_output_mix_rate;
    output_latency_seconds = audio_server->get_output_latency();
    opusdecoder = new_decoder;
    output_resampler = new_resampler;
    audiounpackedbuffer.resize(opus_frame_size * opus_channels);
    audiosamplebuffer.resize(std::max(opus_sample_rate * 2, std::max(1, static_cast<int>(p_buffer_length * opus_sample_rate))));
    resampler_input_latency = speex_resampler_get_input_latency(output_resampler);
    resampler_output_latency = speex_resampler_get_output_latency(output_resampler);
    resampler_silence.resize(std::max(1, resampler_input_latency));
    for (uint32_t i = 0; i < resampler_silence.size(); i++) {
        resampler_silence[i] = { 0.0f, 0.0f };
    }
    flush_input_frames_remaining = resampler_input_latency;

    buffer_read_frame.store(0, std::memory_order_relaxed);
    buffer_write_frame.store(0, std::memory_order_relaxed);
    const int64_t current_output_frame = mixed_output_frames.load(std::memory_order_acquire);
    const int64_t audible_start_frame = current_output_frame + static_cast<int64_t>(std::ceil(p_start_delay * output_mix_rate));
    scheduled_feed_output_frame = std::max(current_output_frame, audible_start_frame - resampler_output_latency);
    last_packet_output_frame.store(current_output_frame, std::memory_order_relaxed);
    stale_timeout_frames = static_cast<int64_t>(std::ceil(p_stale_timeout * output_mix_rate));
    episode_state.store(EPISODE_RECEIVING, std::memory_order_release);
    return OK;
}

AudioStreamPlaybackOpus::~AudioStreamPlaybackOpus() {
    if (opusdecoder != NULL) {
        opus_decoder_destroy(opusdecoder);
        opusdecoder = NULL; 
    }
    if (output_resampler != NULL) {
        speex_resampler_destroy(output_resampler);
        output_resampler = NULL;
    }
}

int64_t AudioStreamPlaybackOpus::finish_episode() {
    EpisodeState expected = EPISODE_RECEIVING;
    if (!episode_state.compare_exchange_strong(expected, EPISODE_FINISHED, std::memory_order_release, std::memory_order_acquire)) {
        return -1;
    }
    return buffer_write_frame.load(std::memory_order_acquire);
}

int64_t AudioStreamPlaybackOpus::get_skips(bool overflow) const {
    return overflow ? get_overflow_frames() : get_underflow_frames();
}

int64_t AudioStreamPlaybackOpus::get_underflow_frames() const {
    return static_cast<int64_t>(underflow_frames.load(std::memory_order_relaxed));
}

int64_t AudioStreamPlaybackOpus::get_overflow_frames() const {
    return static_cast<int64_t>(overflow_frames.load(std::memory_order_relaxed));
}

int64_t AudioStreamPlaybackOpus::get_decode_errors() const {
    return static_cast<int64_t>(decode_errors.load(std::memory_order_relaxed));
}

int AudioStreamPlaybackOpus::get_last_decode_error() const {
    return last_decode_error.load(std::memory_order_relaxed);
}

int AudioStreamPlaybackOpus::queue_length_frames() const {
    if (audiosamplebuffer.is_empty()) {
        return 0;
    }
    // Read the consumer-owned counter first so this concurrent snapshot can
    // overestimate the queue briefly, but cannot wrap below zero.
    const int64_t read_frame = buffer_read_frame.load(std::memory_order_acquire);
    const int64_t write_frame = buffer_write_frame.load(std::memory_order_acquire);
    return static_cast<int>(std::clamp<int64_t>(write_frame - read_frame, 0, audiosamplebuffer.size()));
}

int AudioStreamPlaybackOpus::available_space_frames() const {
    return static_cast<int>(audiosamplebuffer.size()) - queue_length_frames();
}

//  *  not be capable of decoding some packets. In the case of PLC (data==NULL) or FEC (decode_fec=1),
//  *  then frame_size needs to be exactly the duration of audio that is missing, otherwise the
//  *  decoder will not be in the optimal state to decode the next incoming packet. For the PLC and
//  *  FEC cases, frame_size <b>must</b> be a multiple of 2.5 ms.
int AudioStreamPlaybackOpus::push_opus_packet(const PackedByteArray& opusbytepacket, int begin, int decode_fec) {
    if (episode_state.load(std::memory_order_acquire) != EPISODE_RECEIVING || opusdecoder == nullptr || begin < 0 || begin >= opusbytepacket.size()) {
        last_decode_error.store(OPUS_BAD_ARG, std::memory_order_relaxed);
        decode_errors.fetch_add(1, std::memory_order_relaxed);
        return OPUS_BAD_ARG; // negative
    }

    const unsigned char *opus_data = opusbytepacket.ptr() + begin;
    const int opus_data_size = opusbytepacket.size() - begin;
    const int packet_frame_size = opus_decoder_get_nb_samples(opusdecoder, opus_data, opus_data_size);
    if (packet_frame_size != opus_frame_size) {
        last_decode_error.store(OPUS_INVALID_PACKET, std::memory_order_relaxed);
        decode_errors.fetch_add(1, std::memory_order_relaxed);
        return OPUS_INVALID_PACKET; // negative
    }

    int decodedsamples = opus_decode_float(opusdecoder, opus_data, opus_data_size,
                audiounpackedbuffer.ptrw(), opus_frame_size, decode_fec != 0);
    if (decodedsamples < 0) {
        last_decode_error.store(decodedsamples, std::memory_order_relaxed);
        decode_errors.fetch_add(1, std::memory_order_relaxed);
        return decodedsamples;
    }
    last_decode_error.store(OPUS_OK, std::memory_order_relaxed);
    if (decodedsamples != opus_frame_size) {
        last_decode_error.store(OPUS_INVALID_PACKET, std::memory_order_relaxed);
        decode_errors.fetch_add(1, std::memory_order_relaxed);
        return OPUS_INVALID_PACKET; // negative
    }

    // Replace decoded audio with a pure sine wave to listen for playback crackles.
    if (Dsinewaveframes > 0) {
        for (int i = 0; i < decodedsamples; i++) {
            float w = std::sin(Dsinewavephase * 2 * 3.14159265358979323846 / Dsinewaveframes) * Dsinewavevolume;
            if (opus_channels == 2) {
                audiounpackedbuffer[i * 2] = w;
                audiounpackedbuffer[i * 2 + 1] = w;
            } else {
                audiounpackedbuffer[i] = w;
            }
            Dsinewavephase++;
            if (Dsinewavephase == Dsinewaveframes) {
                Dsinewavephase = 0;
            }
        }
    }

    queue_decoded_frames(audiounpackedbuffer.ptr(), decodedsamples);
    last_packet_output_frame.store(mixed_output_frames.load(std::memory_order_acquire), std::memory_order_release);
    return decodedsamples;
}

int AudioStreamPlaybackOpus::queue_decoded_frames(const float *decoded_samples, int frame_count) {
    std::lock_guard<std::mutex> buffer_lock(buffer_mutex);
    const int64_t write_frame = buffer_write_frame.load(std::memory_order_relaxed);
    const int64_t read_frame = buffer_read_frame.load(std::memory_order_acquire);
    const int64_t queued = std::clamp<int64_t>(write_frame - read_frame, 0, audiosamplebuffer.size());
    const int64_t overflow = std::max<int64_t>(0, frame_count - (audiosamplebuffer.size() - queued));
    if (overflow > 0) {
        overflow_frames.fetch_add(overflow, std::memory_order_relaxed);
    }

    for (int i = 0; i < frame_count; i++) {
        AudioFrame &output = audiosamplebuffer[(write_frame + i) % audiosamplebuffer.size()];
        if (opus_channels == 2) {
            output = { decoded_samples[i * 2], decoded_samples[i * 2 + 1] };
        } else {
            output = { decoded_samples[i], decoded_samples[i] };
        }
    }

    // Publishing the write position after all sample writes makes them visible to the
    // audio-thread acquire load before it reads those slots.
    buffer_write_frame.store(write_frame + frame_count, std::memory_order_release);
    return frame_count;
}

int64_t AudioStreamPlaybackOpus::get_frame_hash(int64_t first_frame, int frame_count) const {
    const int64_t write_frame = buffer_write_frame.load(std::memory_order_acquire);
    if (first_frame < std::max<int64_t>(0, write_frame - audiosamplebuffer.size()) ||
            frame_count <= 0 || frame_count > audiosamplebuffer.size() ||
            first_frame > write_frame - frame_count) {
        return -1;
    }

    uint32_t hash = 2166136261u;
    for (int64_t frame = first_frame; frame < first_frame + frame_count; frame++) {
        const AudioFrame &sample_frame = audiosamplebuffer[frame % audiosamplebuffer.size()];
        for (float sample : { sample_frame.left, sample_frame.right }) {
            const int16_t quantized = static_cast<int16_t>(std::lround(std::clamp(sample, -1.0f, 1.0f) * 32767.0f));
            const uint16_t bits = static_cast<uint16_t>(quantized);
            hash ^= bits & 0xff;
            hash *= 16777619u;
            hash ^= bits >> 8;
            hash *= 16777619u;
        }
    }
    return hash;
}

float AudioStreamPlaybackOpus::get_tail_max(int frame_count) const {
    const int64_t write_frame = buffer_write_frame.load(std::memory_order_acquire);
    if (frame_count <= 0 || frame_count > audiosamplebuffer.size() || frame_count > write_frame) {
        return 0.0f;
    }

    float chunk_max = 0.0f;
    for (int64_t frame = write_frame - frame_count; frame < write_frame; frame++) {
        const AudioFrame &sample_frame = audiosamplebuffer[frame % audiosamplebuffer.size()];
        chunk_max = std::max(chunk_max, std::max(std::abs(sample_frame.left), std::abs(sample_frame.right)));
    }
    return chunk_max;
}

int64_t AudioStreamPlaybackOpus::get_frame_number_actually_in_speaker() const {
    if (opus_sample_rate == 0) {
        return -1;
    }
    const EpisodeState state = episode_state.load(std::memory_order_acquire);
    if (state == EPISODE_DRAINING) {
        const double audible_output_frame = mixed_output_frames.load(std::memory_order_acquire) +
                AudioServer::get_singleton()->get_time_since_last_mix() * output_mix_rate -
                output_latency_seconds * output_mix_rate;
        const double output_frames_before_end = std::max(0.0, episode_end_output_frame - audible_output_frame);
        return static_cast<int64_t>(std::floor(buffer_write_frame.load(std::memory_order_acquire) -
                output_frames_before_end * opus_sample_rate / output_mix_rate));
    }
    const int64_t read_frame = buffer_read_frame.load(std::memory_order_acquire);
    const double audible_frame = read_frame - resampler_input_latency +
            (AudioServer::get_singleton()->get_time_since_last_mix() - output_latency_seconds) * opus_sample_rate;
    return static_cast<int64_t>(std::floor(audible_frame));
}

void AudioStreamPlaybackOpus::set_sinewave_frames(int sinewaveframes, float volume) {
    Dsinewaveframes = sinewaveframes;
    Dsinewavephase = 0;
    Dsinewavevolume = volume;
    godot::UtilityFunctions::print_verbose("Sinewave frames set to ", Dsinewaveframes, " volume ", Dsinewavevolume);
}

int AudioStreamPlaybackOpus::resample_frames(const AudioFrame *input, int input_frames, AudioFrame *output, int output_frames, int &consumed_frames) {
    consumed_frames = 0;
    if (output_resampler == NULL || input_frames <= 0 || output_frames <= 0) {
        return 0;
    }

    spx_uint32_t left_input = input_frames;
    spx_uint32_t left_output = output_frames;
    const int left_error = speex_resampler_process_float(output_resampler, 0,
            &input[0].left, &left_input, &output[0].left, &left_output);
    spx_uint32_t right_input = input_frames;
    spx_uint32_t right_output = output_frames;
    const int right_error = speex_resampler_process_float(output_resampler, 1,
            &input[0].right, &right_input, &output[0].right, &right_output);
    if (left_error != RESAMPLER_ERR_SUCCESS || right_error != RESAMPLER_ERR_SUCCESS ||
            left_input != right_input || left_output != right_output) {
        return -1;
    }

    consumed_frames = static_cast<int>(left_input);
    return static_cast<int>(left_output);
}

int32_t AudioStreamPlaybackOpus::_mix(AudioFrame *buffer, float rate_scale, int32_t frames) {
    (void)rate_scale; // Network playback owns its timing and does not support pitch scaling.
    if (frames <= 0) {
        return 0;
    }

    for (int i = 0; i < frames; i++) {
        buffer[i] = { 0.0f, 0.0f };
    }
    if (!active.load(std::memory_order_acquire)) {
        return 0;
    }

    const int64_t output_begin = mixed_output_frames.load(std::memory_order_relaxed);
    const int64_t output_end = output_begin + frames;
    EpisodeState state = episode_state.load(std::memory_order_acquire);
    if (state == EPISODE_UNINITIALIZED) {
        mixed_output_frames.store(output_end, std::memory_order_release);
        return frames;
    }
    if (state == EPISODE_STOPPED) {
        active.store(false, std::memory_order_release);
        return 0;
    }
    if (state == EPISODE_DRAINING) {
        mixed_output_frames.store(output_end, std::memory_order_release);
        if (output_end - output_latency_seconds * output_mix_rate >= episode_end_output_frame) {
            episode_state.store(EPISODE_STOPPED, std::memory_order_release);
            active.store(false, std::memory_order_release);
        }
        return frames;
    }

    int output_offset = static_cast<int>(std::clamp<int64_t>(scheduled_feed_output_frame - output_begin, 0, frames));
    int produced_total = 0;
    std::lock_guard<std::mutex> buffer_lock(buffer_mutex);
    int64_t read_frame = buffer_read_frame.load(std::memory_order_relaxed);
    const int64_t write_frame = buffer_write_frame.load(std::memory_order_acquire);

    while (output_offset + produced_total < frames) {
        int consumed = 0;
        int produced = 0;
        if (read_frame < write_frame) {
            const int ring_index = static_cast<int>(read_frame % audiosamplebuffer.size());
            const int input_frames = static_cast<int>(std::min<int64_t>(write_frame - read_frame, audiosamplebuffer.size() - ring_index));
            produced = resample_frames(&audiosamplebuffer[ring_index], input_frames,
                    buffer + output_offset + produced_total, frames - output_offset - produced_total, consumed);
            read_frame += consumed;
        } else if (state == EPISODE_FINISHED && flush_input_frames_remaining > 0) {
            const int input_frames = std::min(flush_input_frames_remaining, static_cast<int>(resampler_silence.size()));
            produced = resample_frames(resampler_silence.ptr(), input_frames,
                    buffer + output_offset + produced_total, frames - output_offset - produced_total, consumed);
            flush_input_frames_remaining -= consumed;
        } else {
            break;
        }

        if (produced < 0) {
            episode_state.store(EPISODE_STOPPED, std::memory_order_release);
            active.store(false, std::memory_order_release);
            break;
        }
        produced_total += produced;
        if (produced == 0 && consumed == 0) {
            break;
        }
        state = episode_state.load(std::memory_order_acquire);
    }

    if (read_frame != buffer_read_frame.load(std::memory_order_relaxed)) {
        buffer_read_frame.store(read_frame, std::memory_order_release);
    }

    state = episode_state.load(std::memory_order_acquire);
    if (state == EPISODE_RECEIVING && read_frame == write_frame && output_end >= scheduled_feed_output_frame) {
        const int64_t idle_start = std::max(last_packet_output_frame.load(std::memory_order_acquire), scheduled_feed_output_frame);
        if (output_end - idle_start >= stale_timeout_frames) {
            EpisodeState expected = EPISODE_RECEIVING;
            episode_state.compare_exchange_strong(expected, EPISODE_FINISHED, std::memory_order_release, std::memory_order_acquire);
            state = episode_state.load(std::memory_order_acquire);
        }
    }

    const int unfilled_frames = frames - output_offset - produced_total;
    if (state == EPISODE_RECEIVING && unfilled_frames > 0 && output_end > scheduled_feed_output_frame) {
        underflow_frames.fetch_add(unfilled_frames, std::memory_order_relaxed);
    }

    mixed_output_frames.store(output_end, std::memory_order_release);

    if (state == EPISODE_FINISHED && read_frame == write_frame && flush_input_frames_remaining == 0 && output_end >= scheduled_feed_output_frame) {
        episode_end_output_frame = output_begin + output_offset + produced_total;
        episode_state.store(EPISODE_DRAINING, std::memory_order_release);
    }
    return frames;
}

void AudioStreamPlaybackOpus::_start(double p_from_pos) {
    (void)p_from_pos;
    underflow_frames.store(0, std::memory_order_relaxed);
    overflow_frames.store(0, std::memory_order_relaxed);
    decode_errors.store(0, std::memory_order_relaxed);
    last_decode_error.store(OPUS_OK, std::memory_order_relaxed);
    mixed_output_frames.store(0, std::memory_order_relaxed);
    last_packet_output_frame.store(0, std::memory_order_relaxed);
    active.store(true, std::memory_order_release);
}

void AudioStreamPlaybackOpus::_stop() {
    episode_state.store(EPISODE_STOPPED, std::memory_order_release);
    active.store(false, std::memory_order_release);
}

bool AudioStreamPlaybackOpus::_is_playing() const {
    return active.load(std::memory_order_acquire);
}

int AudioStreamPlaybackOpus::_get_loop_count() const {
    return 0;
}

double AudioStreamPlaybackOpus::_get_playback_position() const {
    return output_mix_rate > 0 ? mixed_output_frames.load(std::memory_order_relaxed) / static_cast<double>(output_mix_rate) : 0.0;
}

void AudioStreamPlaybackOpus::_seek(double p_time) {
    //no seek possible
}

void AudioStreamPlaybackOpus::_tag_used_streams() {
    //base->_tag_used(0);
}
