/**************************************************************************/
/*  audio_effect_opus_chunked.cpp                                         */
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

    ClassDB::bind_method(D_METHOD("set_opussamplerate", "opussamplerate"), &AudioStreamOpus::set_opussamplerate);
    ClassDB::bind_method(D_METHOD("get_opussamplerate"), &AudioStreamOpus::get_opussamplerate);
    ClassDB::bind_method(D_METHOD("set_mix_rate", "mix_rate"), &AudioStreamOpus::set_mix_rate);
    ClassDB::bind_method(D_METHOD("get_mix_rate"), &AudioStreamOpus::get_mix_rate);

    ADD_PROPERTY(PropertyInfo(Variant::INT, "opussamplerate", PROPERTY_HINT_RANGE, "20,192000,1"), "set_opussamplerate", "get_opussamplerate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opusframesize", PROPERTY_HINT_RANGE, "20,2880,2"), "set_opusframesize", "get_opusframesize");

    ADD_PROPERTY(PropertyInfo(Variant::INT, "mix_rate", PROPERTY_HINT_RANGE, "20,192000,1"), "set_mix_rate", "get_mix_rate");

    ClassDB::bind_method(D_METHOD("chunk_space_available"), &AudioStreamOpus::chunk_space_available);
    ClassDB::bind_method(D_METHOD("queue_length_frames"), &AudioStreamOpus::queue_length_frames);
    ClassDB::bind_method(D_METHOD("push_audio_chunk", "audiochunk"), &AudioStreamOpus::push_audio_chunk);

    ClassDB::bind_method(D_METHOD("push_opus_packet", "opusbytepacket", "begin", "decode_fec"), &AudioStreamOpus::push_opus_packet);

    ClassDB::bind_method(D_METHOD("resetdecoder"), &AudioStreamOpus::resetdecoder);
}


Ref<AudioStreamPlayback> AudioStreamOpus::_instantiate_playback() const {
    Ref<AudioStreamPlaybackOpus> playback;
    playback.instantiate();
    playback->base = Ref<AudioStreamOpus>(this);
    godot::UtilityFunctions::prints("instantiate_playback");
    return playback;
}

void AudioStreamOpus::deletedecoder() {
    chunknumber = -1;
    if (opusdecoder != NULL) {
        opus_decoder_destroy(opusdecoder);
        opusdecoder = NULL;
    }
}

void AudioStreamOpus::resetdecoder() {
    if (opusdecoder != NULL) 
        opus_decoder_ctl(opusdecoder, OPUS_RESET_STATE);
    // playback->begin_resample(); // there is no link to the playback stream
    chunknumber = -1;
}

void AudioStreamOpus::createdecoder() {
    deletedecoder();  // In case called from GDScript
    int opuserror = 0;
    int channels = 2;
    
    opusdecoder = opus_decoder_create(opussamplerate, channels, &opuserror);
    if (opuserror != 0) {
        if ((opussamplerate == 8000) || (opussamplerate == 12000) || (opussamplerate == 16000) || (opussamplerate == 24000) || (opussamplerate == 48000)) {
            godot::UtilityFunctions::printerr("opus_decoder_create error ", opuserror); 
            chunknumber = -2;
            return;
        }
        godot::UtilityFunctions::print("non-opus sample rate for decoder resample testing"); 
        opusdecoder = NULL;
    }
 
    audiopreresampledbuffer.resize(Naudiopreresampledbuffer);
    audiosamplebuffer.resize(Naudiosamplebuffer); 

    bufferbegin = 0;
    buffertail = 0; 
}

bool AudioStreamOpus::chunk_space_available() {
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

int AudioStreamOpus::queue_length_frames() {
    int queueframes = buffertail - bufferbegin;
    if (queueframes < 0)
        queueframes += Naudiosamplebuffer;
    return queueframes;
}

void AudioStreamOpus::push_audio_chunk(const PackedVector2Array& audiochunk) {
    for (int i = 0; i < audiochunk.size(); i++) {
        audiosamplebuffer.set(buffertail, audiochunk[i]);
        buffertail += 1;
        if (buffertail == Naudiosamplebuffer)
            buffertail = 0;
    }
}

PackedVector2Array* AudioStreamOpus::Popus_packet_to_chunk(const PackedByteArray& opusbytepacket, int begin, int decode_fec) {
    if (opusdecoder == NULL) {
        createdecoder();
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


//  *  not be capable of decoding some packets. In the case of PLC (data==NULL) or FEC (decode_fec=1),
//  *  then frame_size needs to be exactly the duration of audio that is missing, otherwise the
//  *  decoder will not be in the optimal state to decode the next incoming packet. For the PLC and
//  *  FEC cases, frame_size <b>must</b> be a multiple of 2.5 ms.

void AudioStreamOpus::push_opus_packet(const PackedByteArray& opusbytepacket, int begin, int decode_fec) {
    if (opusdecoder == NULL) {
        createdecoder();
    }
    int decodedsamples = opus_decode_float(opusdecoder, opusbytepacket.ptr() + begin, opusbytepacket.size() - begin, 
                                           (float*)audiopreresampledbuffer.ptrw(), Naudiopreresampledbuffer, decode_fec);
    for (int i = 0; i < decodedsamples; i++) {
        audiosamplebuffer.set(buffertail, audiopreresampledbuffer[i]);
        buffertail += 1;
        if (buffertail == Naudiosamplebuffer)
            buffertail = 0;
    }
}

int AudioStreamOpus::Apop_front_chunk(AudioFrame *buffer, int frames) {
    if ((chunknumber == -1) || (bufferbegin == buffertail))
        return 0;
    int i = 0; 
    while (i < frames) {
        if (bufferbegin == buffertail) 
            break;
        buffer[i] = { audiosamplebuffer[bufferbegin].x, audiosamplebuffer[bufferbegin].y };
        bufferbegin += 1;
        if (bufferbegin == audiosamplesize*audiosamplechunks) 
            bufferbegin = 0;
        i++;
    }
    return i;
}


int32_t AudioStreamPlaybackOpus::_mix_resampled(AudioFrame *buffer, int32_t frames) {
    int rframes = base->Apop_front_chunk(buffer, frames);
    mixed += rframes/_get_stream_sampling_rate();
    for (int i = rframes; i < frames; i++) {
        buffer[i] = { 0.0F, 0.0F };  // pad excess with zeros so the stream never ends
        skips += 1;
    }
    return frames;
}


double AudioStreamPlaybackOpus::_get_stream_sampling_rate() const { 
    return base->mix_rate; 
};


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


