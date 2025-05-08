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

#include "audio_effect_opus_chunked.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void AudioEffectOpusChunked::_bind_methods() {

    ClassDB::bind_method(D_METHOD("set_opussamplerate", "opussamplerate"), &AudioEffectOpusChunked::set_opussamplerate);
    ClassDB::bind_method(D_METHOD("get_opussamplerate"), &AudioEffectOpusChunked::get_opussamplerate);
    ClassDB::bind_method(D_METHOD("set_opusframesize", "opusframesize"), &AudioEffectOpusChunked::set_opusframesize);
    ClassDB::bind_method(D_METHOD("get_opusframesize"), &AudioEffectOpusChunked::get_opusframesize);
    ClassDB::bind_method(D_METHOD("set_opusbitrate", "opusbitrate"), &AudioEffectOpusChunked::set_opusbitrate);
    ClassDB::bind_method(D_METHOD("get_opusbitrate"), &AudioEffectOpusChunked::get_opusbitrate);
    ClassDB::bind_method(D_METHOD("set_opuscomplexity", "opuscomplexity"), &AudioEffectOpusChunked::set_opuscomplexity);
    ClassDB::bind_method(D_METHOD("get_opuscomplexity"), &AudioEffectOpusChunked::get_opuscomplexity);
    ClassDB::bind_method(D_METHOD("set_opusoptimizeforvoice", "opusoptimizeforvoice"), &AudioEffectOpusChunked::set_opusoptimizeforvoice);
    ClassDB::bind_method(D_METHOD("get_opusoptimizeforvoice"), &AudioEffectOpusChunked::get_opusoptimizeforvoice);
    ClassDB::bind_method(D_METHOD("set_audiosamplerate", "audiosamplerate"), &AudioEffectOpusChunked::set_audiosamplerate);
    ClassDB::bind_method(D_METHOD("get_audiosamplerate"), &AudioEffectOpusChunked::get_audiosamplerate);
    ClassDB::bind_method(D_METHOD("set_audiosamplesize", "audiosamplesize"), &AudioEffectOpusChunked::set_audiosamplesize);
    ClassDB::bind_method(D_METHOD("get_audiosamplesize"), &AudioEffectOpusChunked::get_audiosamplesize);
    ClassDB::bind_method(D_METHOD("set_audiosamplechunks", "audiosamplechunks"), &AudioEffectOpusChunked::set_audiosamplechunks);
    ClassDB::bind_method(D_METHOD("get_audiosamplechunks"), &AudioEffectOpusChunked::get_audiosamplechunks);

    ADD_PROPERTY(PropertyInfo(Variant::INT, "opussamplerate", PROPERTY_HINT_RANGE, "20,192000,1"), "set_opussamplerate", "get_opussamplerate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opusframesize", PROPERTY_HINT_RANGE, "20,2880,1"), "set_opusframesize", "get_opusframesize");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opusbitrate", PROPERTY_HINT_RANGE, "500,200000,1"), "set_opusbitrate", "get_opusbitrate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opuscomplexity", PROPERTY_HINT_RANGE, "0,10,1"), "set_opuscomplexity", "get_opuscomplexity");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "opusoptimizeforvoice"), "set_opusoptimizeforvoice", "get_opusoptimizeforvoice");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplerate", PROPERTY_HINT_RANGE, "20,192000,1"), "set_audiosamplerate", "get_audiosamplerate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplesize", PROPERTY_HINT_RANGE, "10,4000,1"), "set_audiosamplesize", "get_audiosamplesize");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplechunks", PROPERTY_HINT_RANGE, "1,200,1"), "set_audiosamplechunks", "get_audiosamplechunks");

    ClassDB::bind_method(D_METHOD("chunk_available"), &AudioEffectOpusChunked::chunk_available);
    ClassDB::bind_method(D_METHOD("resampled_current_chunk"), &AudioEffectOpusChunked::resampled_current_chunk);
    ClassDB::bind_method(D_METHOD("denoiser_available"), &AudioEffectOpusChunked::denoiser_available);
    ClassDB::bind_method(D_METHOD("denoise_resampled_chunk"), &AudioEffectOpusChunked::denoise_resampled_chunk);
    ClassDB::bind_method(D_METHOD("chunk_max", "rms", "resampled"), &AudioEffectOpusChunked::chunk_max);

    ClassDB::bind_method(D_METHOD("chunk_to_lipsync", "resampled"), &AudioEffectOpusChunked::chunk_to_lipsync);
    ClassDB::bind_method(D_METHOD("read_visemes"), &AudioEffectOpusChunked::read_visemes);
    
    ClassDB::bind_method(D_METHOD("push_chunk", "audiosamples"), &AudioEffectOpusChunked::push_chunk);
    ClassDB::bind_method(D_METHOD("drop_chunk"), &AudioEffectOpusChunked::drop_chunk);
    ClassDB::bind_method(D_METHOD("undrop_chunk"), &AudioEffectOpusChunked::undrop_chunk);

    ClassDB::bind_method(D_METHOD("read_chunk", "resampled"), &AudioEffectOpusChunked::read_chunk);

    ClassDB::bind_method(D_METHOD("read_opus_packet", "prefixbytes"), &AudioEffectOpusChunked::read_opus_packet);
    ClassDB::bind_method(D_METHOD("resetencoder", "clearbuffers"), &AudioEffectOpusChunked::resetencoder);
}

const int MAXPREFIXBYTES = 100;

AudioEffectOpusChunked::AudioEffectOpusChunked() {
    godot::UtilityFunctions::print("ccccc AudioEffectOpusChunked");
}

AudioEffectOpusChunked::~AudioEffectOpusChunked() {
    godot::UtilityFunctions::print("ddddd AudioEffectOpusChunked");
};

Ref<AudioEffectInstance> AudioEffectOpusChunked::_instantiate() {
    instanceinstantiations += 1;
    godot::UtilityFunctions::print("******** AudioEffectOpusChunkedInstance instantiations ", instanceinstantiations);
    // this triggers when re-ordering effects in AudioBus
    if (instanceinstantiations > 1)
        godot::UtilityFunctions::printerr("Warning: more than one AudioEffectOpusChunkedInstance instantiation");
    Ref<AudioEffectOpusChunkedInstance> ins;
    ins.instantiate();
    ins->base = Ref<AudioEffectOpusChunked>(this);
    return ins;
}

AudioEffectOpusChunkedInstance::~AudioEffectOpusChunkedInstance() {
    if (!base.is_null()) {
        base->instanceinstantiations -= 1;
        godot::UtilityFunctions::print("----- AudioEffectOpusChunkedInstance instantiations ", base->instanceinstantiations);
        // this triggers when re-ordering effects in AudioBus
        if (base->instanceinstantiations != 0)
            godot::UtilityFunctions::printerr("Warning: unexpected number of AudioEffectOpusChunkedInstance instantiations after destructor");
    }
}

void AudioEffectOpusChunked::resetencoder(bool clearbuffers) {
}

void AudioEffectOpusChunked::deleteencoder() {
}

void AudioEffectOpusChunked::createencoder() {
}

void AudioEffectOpusChunkedInstance::_process(const void *src_buffer, AudioFrame *p_dst_frames, int p_frame_count) {
    base->process((const AudioFrame *)src_buffer, p_dst_frames, p_frame_count); 
}



void AudioEffectOpusChunked::push_sample(const Vector2 &sample) {
}

void AudioEffectOpusChunked::process(const AudioFrame *p_src_frames, AudioFrame *p_dst_frames, int p_frame_count) {
    godot::UtilityFunctions::prints("sssprocess called ", p_frame_count); 
}

void AudioEffectOpusChunked::push_chunk(const PackedVector2Array& audiosamples) {
}

bool AudioEffectOpusChunked::chunk_available() {
    return false;
}

void AudioEffectOpusChunked::drop_chunk() {
}

bool AudioEffectOpusChunked::undrop_chunk() {
    return true;
}


void AudioEffectOpusChunked::resampled_current_chunk() {
}

bool AudioEffectOpusChunked::denoiser_available() {
    return false;
}

float AudioEffectOpusChunked::denoise_resampled_chunk() {
    return -1.0;
}


float AudioEffectOpusChunked::chunk_max(bool rms, bool resampled) {
    return -1.0;
}

PackedVector2Array AudioEffectOpusChunked::read_chunk(bool resampled) {
    return PackedVector2Array();
}

PackedByteArray AudioEffectOpusChunked::read_opus_packet(const PackedByteArray& prefixbytes) {
    return PackedByteArray();
}


int AudioEffectOpusChunked::chunk_to_lipsync(bool resampled) {
    return -1;
}

void AudioEffectOpusChunked::resample_single_chunk(float* paudioresamples, const float* paudiosamples) {
}

float AudioEffectOpusChunked::denoise_single_chunk(float* pdenoisedaudioresamples, const float* paudiosamples) {
    return -1.0;
}


PackedByteArray AudioEffectOpusChunked::opus_frame_to_opus_packet(const PackedByteArray& prefixbytes, float* paudiosamples) {
    return PackedByteArray();
}




