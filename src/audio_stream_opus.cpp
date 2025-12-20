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
    ClassDB::bind_method(D_METHOD("set_buffer_length", "seconds"), &AudioStreamOpus::set_buffer_length);
    ClassDB::bind_method(D_METHOD("get_buffer_length"), &AudioStreamOpus::get_buffer_length);


    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "buffer_length", PROPERTY_HINT_RANGE, "0.01,10,0.01,suffix:s"), "set_buffer_length", "get_buffer_length");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "opus_sample_rate", PROPERTY_HINT_RANGE, "20,192000,1"), "set_opus_sample_rate", "get_opus_sample_rate");
}


Ref<AudioStreamPlayback> AudioStreamOpus::_instantiate_playback() const {
    Ref<AudioStreamPlaybackOpus> playback;
    playback.instantiate();
    playback->base = Ref<AudioStreamOpus>(this);
    godot::UtilityFunctions::prints("instantiate_playback");
    return playback;
}

void AudioStreamPlaybackOpus::delete_decoder() {
    if (opusdecoder != NULL) {
        opus_decoder_destroy(opusdecoder);
        opusdecoder = NULL;
    }
}

void AudioStreamPlaybackOpus::reset_decoder() {
    if (opusdecoder != NULL) 
        opus_decoder_ctl(opusdecoder, OPUS_RESET_STATE);
    // playback->begin_resample(); // there should be a link to the playback stream, but there isn't
}

void AudioStreamPlaybackOpus::create_decoder() {
    delete_decoder();  // In case called from GDScript
    int opuserror = 0;
    int channels = 2;
    
    opusdecoder = opus_decoder_create(base->opus_sample_rate, channels, &opuserror);
    if (opuserror != 0) {
        godot::UtilityFunctions::print("------non-opus sample rate for decoder resample testing "); 
        godot::UtilityFunctions::print(opusdecoder); 
        godot::UtilityFunctions::print("non-opus sample rate for decoder resample testing "); 
        if ((base->opus_sample_rate == 8000) || (base->opus_sample_rate == 12000) || (base->opus_sample_rate == 16000) || (base->opus_sample_rate == 24000) || (base->opus_sample_rate == 48000)) {
            godot::UtilityFunctions::printerr("opus_decoder_create error ", opuserror); 
            return;
        }
        godot::UtilityFunctions::print("------non-opus sample rate for decoder resample testing "); 
        godot::UtilityFunctions::print(opusdecoder); 
        godot::UtilityFunctions::print("non-opus sample rate for decoder resample testing "); 
        opusdecoder = NULL;
    }
 
    Naudiosamplebuffer = (int)(base->buffer_len*base->opus_sample_rate);
    audiounpackedbuffer.resize(Naudiounpackedbuffer);
    audiosamplebuffer.resize(Naudiosamplebuffer); 

    bufferbegin = 0;
    buffertail = 0; 
    match_buffersizechanges = base->buffersizechanges;
}

int AudioStreamPlaybackOpus::queue_length_frames() {
    int queueframes = buffertail - bufferbegin;
    if (queueframes < 0)
        queueframes += Naudiosamplebuffer;
    return queueframes;
}

bool AudioStreamPlaybackOpus::opus_segment_space_available() {
    return (audiounpackedbuffer.size() < Naudiosamplebuffer - queue_length_frames());
}


//  *  not be capable of decoding some packets. In the case of PLC (data==NULL) or FEC (decode_fec=1),
//  *  then frame_size needs to be exactly the duration of audio that is missing, otherwise the
//  *  decoder will not be in the optimal state to decode the next incoming packet. For the PLC and
//  *  FEC cases, frame_size <b>must</b> be a multiple of 2.5 ms.
void AudioStreamPlaybackOpus::push_opus_packet(const PackedByteArray& opusbytepacket, int begin, int decode_fec) {
    if ((match_buffersizechanges != base->buffersizechanges) || (opusdecoder == NULL)) {
        create_decoder();
    }
    
    int decodedsamples = opus_decode_float(opusdecoder, 
                opusbytepacket.ptr() + begin, opusbytepacket.size() - begin, 
                (float*)audiounpackedbuffer.ptrw(), 
                (decode_fec ? lastpacketsizeforfec : audiounpackedbuffer.size()), 
                decode_fec);
    // assert(decodedsamples < audiounpackedbuffer.size());  // make sure there was suffient space
    if (decodedsamples)
        lastpacketsizeforfec = decodedsamples;
    for (int i = 0; i < decodedsamples; i++) {
        audiosamplebuffer.set(buffertail, audiounpackedbuffer[i]);
        buffertail += 1;
        if (buffertail == Naudiosamplebuffer)
            buffertail = 0;
    }
}

int AudioStreamPlaybackOpus::Apop_front_chunk(AudioFrame *buffer, int frames) {
    int i = 0; 
    float chunkmax = 0.0;
    while (i < frames) {
        if (bufferbegin == buffertail) 
            break;
        buffer[i] = { audiosamplebuffer[bufferbegin].x, audiosamplebuffer[bufferbegin].y };
        float l = fabs(buffer[i].left);
        if (chunkmax < l)  chunkmax = l;
        float r = fabs(buffer[i].right);
        if (chunkmax < r)  chunkmax = r;
        bufferbegin += 1;
        if (bufferbegin == Naudiosamplebuffer) 
            bufferbegin = 0;
        i++;
    }
    lastchunkmax = chunkmax;
    return i;
}


void AudioStreamPlaybackOpus::_bind_methods() {

    ClassDB::bind_method(D_METHOD("get_last_chunk_max"), &AudioStreamPlaybackOpus::get_last_chunk_max);
    ClassDB::bind_method(D_METHOD("opus_segment_space_available"), &AudioStreamPlaybackOpus::opus_segment_space_available);
    ClassDB::bind_method(D_METHOD("queue_length_frames"), &AudioStreamPlaybackOpus::queue_length_frames);
    ClassDB::bind_method(D_METHOD("push_opus_packet", "opusbytepacket", "begin", "decode_fec"), &AudioStreamPlaybackOpus::push_opus_packet);

    ClassDB::bind_method(D_METHOD("reset_decoder"), &AudioStreamPlaybackOpus::reset_decoder);
}


int32_t AudioStreamPlaybackOpus::_mix_resampled(AudioFrame *buffer, int32_t frames) {
    int rframes = Apop_front_chunk(buffer, frames);
    mixed += rframes/_get_stream_sampling_rate();
    for (int i = rframes; i < frames; i++) {
        buffer[i] = { 0.0F, 0.0F };  // pad excess with zeros so the stream never ends
        skips += 1;
    }
    return frames;
}



void AudioStreamPlaybackOpus::_start(double p_from_pos) {
    if (mixed == 0.0) {
        begin_resample();
    }
    skips = 0;
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


