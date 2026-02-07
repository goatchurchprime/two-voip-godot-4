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
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void AudioStreamOpus::_bind_methods() {

    ClassDB::bind_method(D_METHOD("set_opus_sample_rate", "opus_sample_rate"), &AudioStreamOpus::set_opus_sample_rate);
    ClassDB::bind_method(D_METHOD("get_opus_sample_rate"), &AudioStreamOpus::get_opus_sample_rate);
    ClassDB::bind_method(D_METHOD("set_opus_channels", "opus_sample_rate"), &AudioStreamOpus::set_opus_channels);
    ClassDB::bind_method(D_METHOD("get_opus_channels"), &AudioStreamOpus::get_opus_channels);
    ClassDB::bind_method(D_METHOD("set_buffer_length", "seconds"), &AudioStreamOpus::set_buffer_length);
    ClassDB::bind_method(D_METHOD("get_buffer_length"), &AudioStreamOpus::get_buffer_length);


    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "buffer_length", PROPERTY_HINT_RANGE, "0.01,10,0.01,suffix:s"), "set_buffer_length", "get_buffer_length");
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
    ClassDB::bind_method(D_METHOD("set_sinewave_frames", "sinewaveframes", "volume"), &AudioStreamPlaybackOpus::set_sinewave_frames);
}

Ref<AudioStreamPlayback> AudioStreamOpus::_instantiate_playback() const {
    godot::UtilityFunctions::prints("ref AudioStreamPlaybackOpus");
    Ref<AudioStreamPlaybackOpus> playback;
    godot::UtilityFunctions::prints("instantiate AudioStreamPlaybackOpus");
    playback.instantiate();
    playback->initialize(this); 
    return playback;
}

AudioStreamPlaybackOpus::AudioStreamPlaybackOpus() {
    godot::UtilityFunctions::print("construct AudioStreamPlaybackOpus"); 
}

void AudioStreamPlaybackOpus::initialize(const AudioStreamOpus* pbase) {
    godot::UtilityFunctions::print("initialize AudioStreamPlaybackOpus"); 
    base = Ref<AudioStreamOpus>(pbase);
    int opuserror = 0;
    godot::UtilityFunctions::print("opus_decoder_create "); 
    opusdecoder = opus_decoder_create(base->opus_sample_rate, base->opus_channels, &opuserror);
    godot::UtilityFunctions::print("opus_decoder_created "); 
    if (opuserror == 0) {
        audiounpackedbuffer.resize(48000*60/1000*2); // max opus chunk size is 60ms x 48000Hz x 2channels 
        int audiosamplebuffersize = (int)(base->buffer_len*base->opus_sample_rate);
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
    bufferbegin = 0;
    buffertail = 0; 
}

AudioStreamPlaybackOpus::~AudioStreamPlaybackOpus() {
    if (opusdecoder != NULL) {
        opus_decoder_destroy(opusdecoder);
        godot::UtilityFunctions::print("opus_decoder_destroy "); 
        opusdecoder = NULL;
    }
}

void AudioStreamPlaybackOpus::mark_end_opus_stream(bool clearmark) {
    if (clearmark) {
        bufferstreamend = -1;
        begin_resample();
    } else {
        if (opusdecoder != NULL) 
            opus_decoder_ctl(opusdecoder, OPUS_RESET_STATE);
        bufferstreamend = buffertail;
    }
    godot::UtilityFunctions::prints("bufferstreamend set to", bufferstreamend);
}

int AudioStreamPlaybackOpus::get_skips(bool overflow) {
    return (overflow ? skips_over : skips);
}

int AudioStreamPlaybackOpus::queue_length_frames() {
    return buffertail - bufferbegin;
}

int AudioStreamPlaybackOpus::available_space_frames() {
    return audiosamplebuffer.size() - queue_length_frames() - 1;
}

//  *  not be capable of decoding some packets. In the case of PLC (data==NULL) or FEC (decode_fec=1),
//  *  then frame_size needs to be exactly the duration of audio that is missing, otherwise the
//  *  decoder will not be in the optimal state to decode the next incoming packet. For the PLC and
//  *  FEC cases, frame_size <b>must</b> be a multiple of 2.5 ms.
void AudioStreamPlaybackOpus::push_opus_packet(const PackedByteArray& opusbytepacket, int begin, int decode_fec) {
    if (opusdecoder != NULL) {
        int decodedsamples = opus_decode_float(opusdecoder, 
                    opusbytepacket.ptr() + begin, opusbytepacket.size() - begin, 
                    (float*)audiounpackedbuffer.ptrw(), 
                    (decode_fec ? lastpacketsizeforfec : audiounpackedbuffer.size()), 
                    decode_fec);
        // assert(decodedsamples < audiounpackedbuffer.size());  // make sure there was suffient space
        if (decodedsamples)
            lastpacketsizeforfec = decodedsamples;

        // Replace decoded audio with pure sine wave to listen for crackles in playback.
        if (Dsinewaveframes > 0) {
            for (int i = 0; i < decodedsamples; i++) {
                float w = sin(Dsinewavephase*2*3.14159265358979323846/Dsinewaveframes)*Dsinewavevolume;
                if (base->opus_channels == 2) {
                    audiounpackedbuffer[i*2] = w;
                    audiounpackedbuffer[i*2+1] = w;
                } else {
                    audiounpackedbuffer[i] = w;
                }
                Dsinewavephase++;
                if (Dsinewavephase == Dsinewaveframes)
                    Dsinewavephase = 0;
            }
        }

        // Copy the samples into the RingBuffer.
        int ib1 = (bufferbegin + audiosamplebuffer.size() - 1) % audiosamplebuffer.size();
        for (int i = 0; i < decodedsamples; i++) {
            int it = buffertail % audiosamplebuffer.size();
            if (it == ib1) {
                skips_over++;
                continue;
            }
            if (base->opus_channels == 2) {
                audiosamplebuffer.set(it, Vector2(audiounpackedbuffer[i*2], audiounpackedbuffer[i*2+1]));
            } else {
                audiosamplebuffer.set(it, Vector2(audiounpackedbuffer[i], audiounpackedbuffer[i]));
            }
            buffertail++;
        }
    }
}

float AudioStreamPlaybackOpus::get_chunk_max() { 
    float res = chunkmax;
    chunkmax = 0.0;
    return res;
};

void AudioStreamPlaybackOpus::set_sinewave_frames(int sinewaveframes, float volume) {
    Dsinewaveframes = sinewaveframes;
    Dsinewavephase = 0;
    Dsinewavevolume = volume;
    godot::UtilityFunctions::prints("Sinewave frames set to", Dsinewaveframes, "volume", Dsinewavevolume);
}

int32_t AudioStreamPlaybackOpus::_mix_resampled(AudioFrame *buffer, int32_t frames) {
    int i = 0; 
    while (i < frames) {
        if (bufferbegin == bufferstreamend) {
            buffer[i] = { 0.0, 0.0 };  // we should fade down when we get to the streamend
        } else if (bufferbegin == buffertail) {
            buffer[i] = { 0.0, 0.0 };
            skips++;
        } else {
            int ib = bufferbegin % audiosamplebuffer.size();
            buffer[i] = { audiosamplebuffer[ib].x, audiosamplebuffer[ib].y };
            bufferbegin++;
        }
        float l = fabs(buffer[i].left);
        if (chunkmax < l)
            chunkmax = l;
        float r = fabs(buffer[i].right);
        if (chunkmax < r)
            chunkmax = r;
        i++;
    }
    mixed += frames/_get_stream_sampling_rate();
    return frames;
}

void AudioStreamPlaybackOpus::_start(double p_from_pos) {
    if (mixed == 0.0) {
        begin_resample();
    }
    skips = 0;
    skips_over = 0;
    active = true;
    mixed = 0.0;
}

void AudioStreamPlaybackOpus::_stop() {
    active = false;
}

bool AudioStreamPlaybackOpus::_is_playing() const {
    return active;
}

int AudioStreamPlaybackOpus::_get_loop_count() const {
    return 0;
}

double AudioStreamPlaybackOpus::_get_playback_position() const {
    return mixed;
}

void AudioStreamPlaybackOpus::_seek(double p_time) {
    //no seek possible
}

void AudioStreamPlaybackOpus::_tag_used_streams() {
    //base->_tag_used(0);
}


