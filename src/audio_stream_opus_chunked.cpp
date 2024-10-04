/**************************************************************************/
/*  audio_effect_opus_chunked.cpp                                              */
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

#include "audio_stream_opus_chunked.h"
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;


void AudioStreamOpusChunked::_bind_methods() {

    ClassDB::bind_method(D_METHOD("set_opussamplerate", "opussamplerate"), &AudioStreamOpusChunked::set_opussamplerate);
    ClassDB::bind_method(D_METHOD("get_opussamplerate"), &AudioStreamOpusChunked::get_opussamplerate);
    ClassDB::bind_method(D_METHOD("set_opusframesize", "opusframesize"), &AudioStreamOpusChunked::set_opusframesize);
    ClassDB::bind_method(D_METHOD("get_opusframesize"), &AudioStreamOpusChunked::get_opusframesize);
    ClassDB::bind_method(D_METHOD("set_audiosamplerate", "audiosamplerate"), &AudioStreamOpusChunked::set_audiosamplerate);
    ClassDB::bind_method(D_METHOD("get_audiosamplerate"), &AudioStreamOpusChunked::get_audiosamplerate);
    ClassDB::bind_method(D_METHOD("set_audiosamplesize", "audiosamplesize"), &AudioStreamOpusChunked::set_audiosamplesize);
    ClassDB::bind_method(D_METHOD("get_audiosamplesize"), &AudioStreamOpusChunked::get_audiosamplesize);
    ClassDB::bind_method(D_METHOD("set_audiosamplechunks", "audiosamplechunks"), &AudioStreamOpusChunked::set_audiosamplechunks);
    ClassDB::bind_method(D_METHOD("get_audiosamplechunks"), &AudioStreamOpusChunked::get_audiosamplechunks);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opussamplerate", PROPERTY_HINT_RANGE, "8000,48000,4000"), "set_opussamplerate", "get_opussamplerate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opusframesize", PROPERTY_HINT_RANGE, "20,2880,2"), "set_opusframesize", "get_opusframesize");

    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplerate", PROPERTY_HINT_RANGE, "8000,96000,100"), "set_audiosamplerate", "get_audiosamplerate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplesize", PROPERTY_HINT_RANGE, "10,4000,1"), "set_audiosamplesize", "get_audiosamplesize");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplechunks", PROPERTY_HINT_RANGE, "1,200,1"), "set_audiosamplechunks", "get_audiosamplechunks");

    ClassDB::bind_method(D_METHOD("chunk_space_available"), &AudioStreamOpusChunked::chunk_space_available);
    ClassDB::bind_method(D_METHOD("queue_length_frames"), &AudioStreamOpusChunked::queue_length_frames);
    ClassDB::bind_method(D_METHOD("push_audio_chunk", "audiochunk"), &AudioStreamOpusChunked::push_audio_chunk);
    ClassDB::bind_method(D_METHOD("push_opus_packet", "opusbytepacket", "begin", "decode_fec"), &AudioStreamOpusChunked::push_opus_packet);
    ClassDB::bind_method(D_METHOD("opus_packet_to_chunk", "opusbytepacket", "begin", "decode_fec"), &AudioStreamOpusChunked::opus_packet_to_chunk);
    ClassDB::bind_method(D_METHOD("resample_chunk", "resampledaudio"), &AudioStreamOpusChunked::resample_chunk);

    ClassDB::bind_method(D_METHOD("last_chunk_max"), &AudioStreamOpusChunked::last_chunk_max);
    ClassDB::bind_method(D_METHOD("last_chunk_rms"), &AudioStreamOpusChunked::last_chunk_rms);
    ClassDB::bind_method(D_METHOD("read_last_chunk"), &AudioStreamOpusChunked::read_last_chunk);
}


Ref<AudioStreamPlayback> AudioStreamOpusChunked::_instantiate_playback() const {
    Ref<AudioStreamPlaybackOpusChunked> playback;
    playback.instantiate();
    playback->base = Ref<AudioStreamOpusChunked>(this);
    godot::UtilityFunctions::prints("instantiate_playback");
    return playback;
}

void AudioStreamOpusChunked::resetdecoder() {
    chunknumber = -1;
    if (speexresampler != NULL) {
        speex_resampler_destroy(speexresampler);
        speexresampler = NULL;
    }
    if (opusdecoder != NULL) {
        opus_decoder_destroy(opusdecoder);
        opusdecoder = NULL;
    }
}

void AudioStreamOpusChunked::createdecoder() {
    resetdecoder();  // In case called from GDScript
    int opuserror = 0;
    int channels = 2;
    
    if ((opussamplerate == 2000) || (opussamplerate == 4000)) {
        godot::UtilityFunctions::print("non-opus sample rate for resample testing "); 
        opusdecoder = NULL;
    } else {
        opusdecoder = opus_decoder_create(opussamplerate, channels, &opuserror);
        if (opuserror != 0) {
            godot::UtilityFunctions::printerr("opus_decoder_create error ", opuserror); 
            chunknumber = -2;
            return;
        }
    }
    float Dtimeframeopus = opusframesize*1.0F/opussamplerate;
    float Dtimeframeaudio = audiosamplesize*1.0F/audiosamplerate;
    if (audiosamplesize != opusframesize) {
        int speexerror = 0; 
        int resamplingquality = 10;
        speexresampler = speex_resampler_init(channels, opussamplerate, audiosamplerate, resamplingquality, &speexerror);
        audiopreresampledbuffer.resize(opusframesize);
        godot::UtilityFunctions::prints("Decoder timeframeopus preresampler", Dtimeframeopus, "timeframeaudio", Dtimeframeaudio); 
    } else {
        godot::UtilityFunctions::prints("Decoder timeframeopus no-resampling needed", Dtimeframeopus, "timeframeaudio", Dtimeframeaudio); 
    }
    Daudioresampledbuffer.resize(audiosamplesize);

    audiosamplebuffer.resize(audiosamplesize*audiosamplechunks); 
    bufferbegin = 0;
    buffertail = 0; 
    chunknumber = 0;

    //printf("before beginresample\n");
    //playback->begin_resample();
    //printf("after beginresample\n");
}

bool AudioStreamOpusChunked::chunk_space_available() {
    if (chunknumber < 0) {
        if (chunknumber == -1) 
            createdecoder();
        else
            return false;
    }
    //buffertail = chunknumber*audiosamplesize; 
    if (chunknumber == -1)
        return false;
    if (buffertail == bufferbegin)
        return true;
    int nbuffertail = buffertail + audiosamplesize;
    if ((bufferbegin > buffertail) && (bufferbegin <= nbuffertail))
        return false;
    int nbufferlength = audiosamplesize*audiosamplechunks;
    if ((bufferbegin > buffertail - nbufferlength) && (bufferbegin <= nbuffertail - nbufferlength))
        return false;
    return true;
}

int AudioStreamOpusChunked::queue_length_frames() {
    int queueframes = buffertail - bufferbegin;
    if (queueframes < 0)
        queueframes += audiosamplesize*audiosamplechunks;
    return queueframes;
}


void AudioStreamOpusChunked::push_audio_chunk(const PackedVector2Array& audiochunk) {
    if (chunknumber < 0) {
        if (chunknumber == -1) 
            createdecoder();
        else
            return;
    }
    if (audiochunk.size() != audiosamplesize)
        godot::UtilityFunctions::print("Warning mismatch expected audiochunk size");
    for (int i = 0; i < audiochunk.size(); i++) 
        audiosamplebuffer.set(buffertail + i, audiochunk[i]);
    chunknumber += 1;
    if (chunknumber == audiosamplechunks)
        chunknumber = 0;
    buffertail = chunknumber*audiochunk.size(); 
}


float AudioStreamOpusChunked::last_chunk_max() {
    if (queue_length_frames() < audiosamplesize)
        return 0.0F;
    int prevbuffertail = (chunknumber != 0 ? chunknumber-1 : audiosamplechunks-1)*audiosamplesize; 
    float r = 0.0F;
    float* p = (float*)audiosamplebuffer.ptr() + 2*prevbuffertail;
    for (int i = 0; i < audiosamplesize*2; i++) {
        float s = fabs(p[i]);
        if (s > r)
            r = s;
    }
    return r;
}

float AudioStreamOpusChunked::last_chunk_rms() {
    if (queue_length_frames() < audiosamplesize)
        return 0.0F;
    int prevbuffertail = (chunknumber != 0 ? chunknumber-1 : audiosamplechunks-1)*audiosamplesize; 
    float s = 0.0F;
    float* p = (float*)audiosamplebuffer.ptr() + 2*prevbuffertail;
    for (int i = 0; i < audiosamplesize*2; i++) {
        s += p[i]*p[i];
    }
    return sqrt(s/(audiosamplesize*2));
}

PackedVector2Array AudioStreamOpusChunked::read_last_chunk() {
    if (queue_length_frames() < audiosamplesize)
        return PackedVector2Array();
    int prevbuffertail = (chunknumber != 0 ? chunknumber-1 : audiosamplechunks-1)*audiosamplesize; 
    return audiosamplebuffer.slice(prevbuffertail, prevbuffertail+audiosamplesize); 
}


PackedVector2Array* AudioStreamOpusChunked::Popus_packet_to_chunk(const PackedByteArray& opusbytepacket, int begin, int decode_fec) {
    if (chunknumber < 0) {
        if (chunknumber == -1) 
            createdecoder();
        else
            return &audiopreresampledbuffer;
    }
    int decodedsamples = opus_decode_float(opusdecoder, opusbytepacket.ptr() + begin, opusbytepacket.size() - begin, 
                                           (float*)audiopreresampledbuffer.ptrw(), opusframesize, decode_fec);
    if (audiosamplesize == opusframesize) {
        return &audiopreresampledbuffer; 
    }
    unsigned int Uaudiosamplesize = audiosamplesize;
    unsigned int Uopusframesize = opusframesize;
    int resampling_result = speex_resampler_process_interleaved_float(speexresampler, (float*)audiopreresampledbuffer.ptr(), &Uopusframesize, 
                            (float*)Daudioresampledbuffer.ptrw(), &Uaudiosamplesize);
    return &Daudioresampledbuffer; 
}

PackedVector2Array AudioStreamOpusChunked::resample_chunk(const PackedVector2Array& resampledaudio) {
    if (chunknumber < 0) {
        if (chunknumber == -1) 
            createdecoder();
        else
            return audiopreresampledbuffer;
    }
    if (resampledaudio.size() != opusframesize)
        godot::UtilityFunctions::printerr("Error mismatch resampledaudio size");
    if (audiosamplesize == opusframesize) {
        return resampledaudio; 
    }
    unsigned int Uaudiosamplesize = audiosamplesize;
    unsigned int Uopusframesize = opusframesize;
    int resampling_result = speex_resampler_process_interleaved_float(speexresampler, (float*)resampledaudio.ptr(), &Uopusframesize, 
                            (float*)Daudioresampledbuffer.ptrw(), &Uaudiosamplesize);
    return Daudioresampledbuffer; 
}

void AudioStreamOpusChunked::push_opus_packet(const PackedByteArray& opusbytepacket, int begin, int decode_fec) {
    push_audio_chunk(*Popus_packet_to_chunk(opusbytepacket, begin, decode_fec)); 
}

PackedVector2Array AudioStreamOpusChunked::opus_packet_to_chunk(const PackedByteArray& opusbytepacket, int begin, int decode_fec) {
    return *Popus_packet_to_chunk(opusbytepacket, begin, decode_fec); 
}


// this needs to call the resampled one that lets us vary the speed and keep the 
// buffer from starving, or to run it up to catch up to the rest
int32_t AudioStreamPlaybackOpusChunked::_mix_resampled(AudioFrame *buffer, int32_t frames) {
    if ((base->chunknumber == -1) || (base->bufferbegin == base->buffertail)) {
        memset(buffer, 0, sizeof(AudioFrame)*frames);
        return frames;
    }
    //printf("_mix_resampled called %d f %d t %d\n", base->bufferbegin, frames, base->buffertail);
    for (int i = 0; i < frames; i++) {
        if (base->bufferbegin != base->buffertail) {
            buffer[i] = { base->audiosamplebuffer[base->bufferbegin].x, base->audiosamplebuffer[base->bufferbegin].y };
            base->bufferbegin += 1; 
            if (base->bufferbegin == base->audiosamplesize*base->audiosamplechunks) 
                base->bufferbegin = 0;
        } else {
            buffer[i] = { 0.0F, 0.0F };
            skips++;
        }
    }
    mixed += frames/_get_stream_sampling_rate();
    return frames;
}

void AudioStreamPlaybackOpusChunked::_start(double p_from_pos) {
    if (mixed == 0.0) {
        begin_resample();
    }
    skips = 0;
    active = true;
    mixed = 0.0;
}

void AudioStreamPlaybackOpusChunked::_stop() {
    active = false;
}

bool AudioStreamPlaybackOpusChunked::_is_playing() const {
    return active;
}

int AudioStreamPlaybackOpusChunked::_get_loop_count() const {
    return 0;
}

double AudioStreamPlaybackOpusChunked::_get_playback_position() const {
    return mixed;
}

void AudioStreamPlaybackOpusChunked::_seek(double p_time) {
    //no seek possible
}

void AudioStreamPlaybackOpusChunked::_tag_used_streams() {
    //base->_tag_used(0);
}


