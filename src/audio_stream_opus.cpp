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

#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void AudioStreamOpus::_bind_methods() {

    ClassDB::bind_method(D_METHOD("set_opus_sample_rate", "opus_sample_rate"), &AudioStreamOpus::set_opus_sample_rate);
    ClassDB::bind_method(D_METHOD("get_opus_sample_rate"), &AudioStreamOpus::get_opus_sample_rate);
    ClassDB::bind_method(D_METHOD("set_opus_channels", "opus_sample_rate"), &AudioStreamOpus::set_opus_channels);
    ClassDB::bind_method(D_METHOD("get_opus_channels"), &AudioStreamOpus::get_opus_channels);
    ClassDB::bind_method(D_METHOD("set_buffer_length", "seconds"), &AudioStreamOpus::set_buffer_length);
    ClassDB::bind_method(D_METHOD("get_buffer_length"), &AudioStreamOpus::get_buffer_length);


    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "buffer_length", PROPERTY_HINT_RANGE, "0.1,10.0,0.1,suffix:s"), "set_buffer_length", "get_buffer_length");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "opus_sample_rate", PROPERTY_HINT_RANGE, "20,192000,1"), "set_opus_sample_rate", "get_opus_sample_rate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opus_channels", PROPERTY_HINT_RANGE, "1,2,1"), "set_opus_channels", "get_opus_channels");
}

void AudioStreamPlaybackOpus::_bind_methods() {

    ClassDB::bind_method(D_METHOD("available_space_frames"), &AudioStreamPlaybackOpus::available_space_frames);
    ClassDB::bind_method(D_METHOD("queue_length_frames"), &AudioStreamPlaybackOpus::queue_length_frames);
    ClassDB::bind_method(D_METHOD("push_opus_packet", "opusbytepacket", "begin", "decode_fec"), &AudioStreamPlaybackOpus::push_opus_packet);
    ClassDB::bind_method(D_METHOD("mark_end_opus_stream", "clear_mark"), &AudioStreamPlaybackOpus::mark_end_opus_stream);
    ClassDB::bind_method(D_METHOD("get_chunk_max"), &AudioStreamPlaybackOpus::get_chunk_max);
    ClassDB::bind_method(D_METHOD("get_skips", "overflow"), &AudioStreamPlaybackOpus::get_skips);
    ClassDB::bind_method(D_METHOD("get_underflow_frames"), &AudioStreamPlaybackOpus::get_underflow_frames);
    ClassDB::bind_method(D_METHOD("get_overflow_frames"), &AudioStreamPlaybackOpus::get_overflow_frames);
    ClassDB::bind_method(D_METHOD("get_decode_errors"), &AudioStreamPlaybackOpus::get_decode_errors);
    ClassDB::bind_method(D_METHOD("get_last_decode_error"), &AudioStreamPlaybackOpus::get_last_decode_error);
    ClassDB::bind_method(D_METHOD("set_sinewave_frames", "sinewaveframes", "volume"), &AudioStreamPlaybackOpus::set_sinewave_frames);
}

Ref<AudioStreamPlayback> AudioStreamOpus::_instantiate_playback() const {
    godot::UtilityFunctions::print_verbose("ref AudioStreamPlaybackOpus");
    Ref<AudioStreamPlaybackOpus> playback;
    godot::UtilityFunctions::print_verbose("instantiate AudioStreamPlaybackOpus");
    playback.instantiate();
    playback->initialize(this); 
    return playback;
}

AudioStreamPlaybackOpus::AudioStreamPlaybackOpus() {
    godot::UtilityFunctions::print_verbose("construct AudioStreamPlaybackOpus");
}

void AudioStreamPlaybackOpus::initialize(const AudioStreamOpus* pbase) {
    godot::UtilityFunctions::print_verbose("initialize AudioStreamPlaybackOpus");
    base = Ref<AudioStreamOpus>(pbase);
    int opuserror = 0;
    godot::UtilityFunctions::print_verbose("opus_decoder_create ");
    opusdecoder = opus_decoder_create(base->opus_sample_rate, base->opus_channels, &opuserror);
    godot::UtilityFunctions::print_verbose("opus_decoder_created ");
    if (opuserror == 0) {
        // opus_decode_float()'s frame size is per channel. Opus packets can
        // contain up to 120 ms, and the output buffer must include all channels.
        max_decoded_frames = static_cast<int>(base->opus_sample_rate * 120 / 1000);
        audiounpackedbuffer.resize(max_decoded_frames * base->opus_channels);
        int audiosamplebuffersize = std::max(1, static_cast<int>(base->buffer_len * base->opus_sample_rate));
        audiosamplebuffer.resize(audiosamplebuffersize); 
    } else {
        godot::UtilityFunctions::printerr("Opus_decoder_create error ", opuserror);   // will be one of OPUS_BAD_ARG=-1, OPUS_ALLOC_FAIL=-7, OPUS_INTERNAL_ERROR=-3
        if (!((base->opus_sample_rate == 8000) || (base->opus_sample_rate == 12000) || (base->opus_sample_rate == 16000) || (base->opus_sample_rate == 24000) || (base->opus_sample_rate == 48000))) {
            godot::UtilityFunctions::printerr("Opus sample rate must be one of 48000,24000,16000,12000,8000"); 
        }
        if (!((base->opus_channels == 1) || (base->opus_channels == 2))) {
            godot::UtilityFunctions::printerr("Opus channels must be 1 or 2"); 
        }
        opusdecoder = NULL;  // or assert this
    }
    bufferbegin.store(0, std::memory_order_relaxed);
    buffertail.store(0, std::memory_order_relaxed);
    bufferstreamend.store(0, std::memory_order_relaxed); // start out paused
}

AudioStreamPlaybackOpus::~AudioStreamPlaybackOpus() {
    if (opusdecoder != NULL) {
        opus_decoder_destroy(opusdecoder);
        godot::UtilityFunctions::print_verbose("opus_decoder_destroy ");
        opusdecoder = NULL; 
    }
}

void AudioStreamPlaybackOpus::mark_end_opus_stream(bool clearmark) {
    if (clearmark) {
        bufferstreamend.store(NO_STREAM_END, std::memory_order_release);
        if (queue_length_frames() == 0)
            begin_resample(); 
    } else {
        if (opusdecoder != NULL) 
            opus_decoder_ctl(opusdecoder, OPUS_RESET_STATE);
        bufferstreamend.store(buffertail.load(std::memory_order_acquire), std::memory_order_release);
        // This sets the pause point. We should eventually fade down as we
        // reach it, like AudioStreamPlaybackListNode::FADE_OUT_TO_PAUSE.
    }
    godot::UtilityFunctions::print_verbose("bufferstreamend set to ", bufferstreamend.load(std::memory_order_acquire));
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
    // Read the consumer-owned counter first so this concurrent snapshot can
    // overestimate the queue briefly, but cannot wrap below zero.
    const int64_t begin = bufferbegin.load(std::memory_order_acquire);
    const int64_t tail = buffertail.load(std::memory_order_acquire);
    return static_cast<int>(std::clamp<int64_t>(tail - begin, 0, audiosamplebuffer.size()));
}

int AudioStreamPlaybackOpus::available_space_frames() const {
    return static_cast<int>(audiosamplebuffer.size()) - queue_length_frames();
}

//  *  not be capable of decoding some packets. In the case of PLC (data==NULL) or FEC (decode_fec=1),
//  *  then frame_size needs to be exactly the duration of audio that is missing, otherwise the
//  *  decoder will not be in the optimal state to decode the next incoming packet. For the PLC and
//  *  FEC cases, frame_size <b>must</b> be a multiple of 2.5 ms.
int AudioStreamPlaybackOpus::push_opus_packet(const PackedByteArray& opusbytepacket, int begin, int decode_fec) {
    if (opusdecoder == nullptr || begin < 0 || begin >= opusbytepacket.size()) {
        last_decode_error.store(OPUS_BAD_ARG, std::memory_order_relaxed);
        decode_errors.fetch_add(1, std::memory_order_relaxed);
        return OPUS_BAD_ARG;
    }

    int decodedsamples = opus_decode_float(opusdecoder,
                opusbytepacket.ptr() + begin, opusbytepacket.size() - begin,
                audiounpackedbuffer.ptrw(),
                decode_fec ? lastpacketsizeforfec : max_decoded_frames,
                decode_fec != 0);
    if (decodedsamples < 0) {
        last_decode_error.store(decodedsamples, std::memory_order_relaxed);
        decode_errors.fetch_add(1, std::memory_order_relaxed);
        return decodedsamples;
    }
    last_decode_error.store(OPUS_OK, std::memory_order_relaxed);
    if (decodedsamples > 0) {
        lastpacketsizeforfec = decodedsamples;
    }

    // Replace decoded audio with a pure sine wave to listen for playback crackles.
    if (Dsinewaveframes > 0) {
        for (int i = 0; i < decodedsamples; i++) {
            float w = std::sin(Dsinewavephase * 2 * 3.14159265358979323846 / Dsinewaveframes) * Dsinewavevolume;
            if (base->opus_channels == 2) {
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
    return decodedsamples;
}

int AudioStreamPlaybackOpus::queue_decoded_frames(const float *decoded_samples, int frame_count) {
    const int64_t tail = buffertail.load(std::memory_order_relaxed);
    const int64_t begin = bufferbegin.load(std::memory_order_acquire);
    const int64_t queued = std::clamp<int64_t>(tail - begin, 0, audiosamplebuffer.size());
    const int64_t writable = std::min<int64_t>(frame_count, audiosamplebuffer.size() - queued);

    for (int64_t i = 0; i < writable; i++) {
        AudioFrame &output = audiosamplebuffer[(tail + i) % audiosamplebuffer.size()];
        if (base->opus_channels == 2) {
            output = { decoded_samples[i * 2], decoded_samples[i * 2 + 1] };
        } else {
            output = { decoded_samples[i], decoded_samples[i] };
        }
    }

    // Publishing the tail after all sample writes makes them visible to the
    // audio-thread acquire load before it reads those slots.
    buffertail.store(tail + writable, std::memory_order_release);
    const int64_t dropped = frame_count - writable;
    if (dropped > 0) {
        overflow_frames.fetch_add(dropped, std::memory_order_relaxed);
    }
    return static_cast<int>(writable);
}

float AudioStreamPlaybackOpus::get_chunk_max() { 
    return chunkmax.exchange(0.0f, std::memory_order_acq_rel);
};

void AudioStreamPlaybackOpus::update_chunk_max(float magnitude) {
    float previous = chunkmax.load(std::memory_order_relaxed);
    while (previous < magnitude && !chunkmax.compare_exchange_weak(previous, magnitude, std::memory_order_relaxed)) {
    }
}

void AudioStreamPlaybackOpus::set_sinewave_frames(int sinewaveframes, float volume) {
    Dsinewaveframes = sinewaveframes;
    Dsinewavephase = 0;
    Dsinewavevolume = volume;
    godot::UtilityFunctions::print_verbose("Sinewave frames set to ", Dsinewaveframes, " volume ", Dsinewavevolume);
}

int32_t AudioStreamPlaybackOpus::_mix_resampled(AudioFrame *buffer, int32_t frames) {
    int64_t begin = bufferbegin.load(std::memory_order_relaxed);
    const int64_t stream_end = bufferstreamend.load(std::memory_order_acquire);
    const int64_t tail = buffertail.load(std::memory_order_acquire);
    int64_t consumed = 0;
    int64_t underflows = 0;
    float local_chunk_max = 0.0f;
    int i = 0; 
    while (i < frames) {
        if (begin == stream_end) {
            buffer[i] = { 0.0, 0.0 };  // we should fade down when we get to the streamend
        } else if (begin == tail) {
            buffer[i] = { 0.0, 0.0 };
            underflows++;
        } else {
            buffer[i] = audiosamplebuffer[begin % audiosamplebuffer.size()];
            begin++;
            consumed++;
        }
        local_chunk_max = std::max(local_chunk_max, std::max(std::abs(buffer[i].left), std::abs(buffer[i].right)));
        i++;
    }
    if (consumed > 0) {
        bufferbegin.store(begin, std::memory_order_release);
    }
    if (underflows > 0) {
        underflow_frames.fetch_add(underflows, std::memory_order_relaxed);
    }
    update_chunk_max(local_chunk_max);
    mixed_frames.fetch_add(frames, std::memory_order_relaxed);
    return frames;
}

void AudioStreamPlaybackOpus::_start(double p_from_pos) {
    if (mixed_frames.load(std::memory_order_relaxed) == 0) {
        begin_resample();
    }
    underflow_frames.store(0, std::memory_order_relaxed);
    overflow_frames.store(0, std::memory_order_relaxed);
    decode_errors.store(0, std::memory_order_relaxed);
    last_decode_error.store(OPUS_OK, std::memory_order_relaxed);
    active.store(true, std::memory_order_release);
    mixed_frames.store(0, std::memory_order_relaxed);
}

void AudioStreamPlaybackOpus::_stop() {
    active.store(false, std::memory_order_release);
}

bool AudioStreamPlaybackOpus::_is_playing() const {
    return active.load(std::memory_order_acquire);
}

int AudioStreamPlaybackOpus::_get_loop_count() const {
    return 0;
}

double AudioStreamPlaybackOpus::_get_playback_position() const {
    return mixed_frames.load(std::memory_order_relaxed) / _get_stream_sampling_rate();
}

void AudioStreamPlaybackOpus::_seek(double p_time) {
    //no seek possible
}

void AudioStreamPlaybackOpus::_tag_used_streams() {
    //base->_tag_used(0);
}
