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

#include "audio_effect_fft_block.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/gd_extension_manager.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "utils.h"

using namespace godot;

void AudioEffectOpusChunked::_bind_methods() {

    ClassDB::bind_method(D_METHOD("set_opussamplerate", "opussamplerate"), &AudioEffectOpusChunked::set_opussamplerate);
    ClassDB::bind_method(D_METHOD("get_opussamplerate"), &AudioEffectOpusChunked::get_opussamplerate);
    ClassDB::bind_method(D_METHOD("set_opusframesize", "opusframesize"), &AudioEffectOpusChunked::set_opusframesize);
    ClassDB::bind_method(D_METHOD("get_opusframesize"), &AudioEffectOpusChunked::get_opusframesize);
    ClassDB::bind_method(D_METHOD("set_audiosamplerate", "audiosamplerate"), &AudioEffectOpusChunked::set_audiosamplerate);
    ClassDB::bind_method(D_METHOD("get_audiosamplerate"), &AudioEffectOpusChunked::get_audiosamplerate);
    ClassDB::bind_method(D_METHOD("set_audiosamplesize", "audiosamplesize"), &AudioEffectOpusChunked::set_audiosamplesize);
    ClassDB::bind_method(D_METHOD("get_audiosamplesize"), &AudioEffectOpusChunked::get_audiosamplesize);
    ClassDB::bind_method(D_METHOD("set_audiosamplechunks", "audiosamplechunks"), &AudioEffectOpusChunked::set_audiosamplechunks);
    ClassDB::bind_method(D_METHOD("get_audiosamplechunks"), &AudioEffectOpusChunked::get_audiosamplechunks);

    ADD_PROPERTY(PropertyInfo(Variant::INT, "opussamplerate", PROPERTY_HINT_RANGE, "20,192000,1"), "set_opussamplerate", "get_opussamplerate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opusframesize", PROPERTY_HINT_RANGE, "20,2880,1"), "set_opusframesize", "get_opusframesize");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplerate", PROPERTY_HINT_RANGE, "20,192000,1"), "set_audiosamplerate", "get_audiosamplerate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplesize", PROPERTY_HINT_RANGE, "10,4000,1"), "set_audiosamplesize", "get_audiosamplesize");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplechunks", PROPERTY_HINT_RANGE, "1,200,1"), "set_audiosamplechunks", "get_audiosamplechunks");

    ClassDB::bind_method(D_METHOD("push_chunk", "audiosamples"), &AudioEffectOpusChunked::push_chunk);

    ClassDB::bind_method(D_METHOD("read_chunk", "resampled"), &AudioEffectOpusChunked::read_chunk);
    ClassDB::bind_method(D_METHOD("resetencoder", "clearbuffers"), &AudioEffectOpusChunked::resetencoder);
}

const int MAXPREFIXBYTES = 100;

AudioEffectFFTBlock::AudioEffectFFTBlock() {
}

AudioEffectFFTBlock::~AudioEffectFFTBlock() 
{
    deleteencoder();
};

Ref<AudioEffectInstance> AudioEffectFFTBlock::_instantiate() {
    instanceinstantiations += 1;
    // this triggers when re-ordering effects in AudioBus
    //if (instanceinstantiations > 1)
    //    godot::UtilityFunctions::printerr("Warning: more than one AudioEffectOpusChunkedInstance instantiation");
    Ref<AudioEffectFFTBlockInstance> ins;
    ins.instantiate();
    ins->base = Ref<AudioEffectFFTBlock>(this);
    return ins;
}

AudioEffectFFTBlockInstance::~AudioEffectFFTBlockInstance() {
    if (!base.is_null()) {
        base->instanceinstantiations -= 1;
        // this triggers when re-ordering effects in AudioBus
        //if (base->instanceinstantiations == 0)
        //    godot::UtilityFunctions::printerr("Warning: unexpected number of AudioEffectOpusChunkedInstance instantiations after destructor");
    }
}

void AudioEffectFFTBlock::resetencoder(bool clearbuffers) {
    if (speexresampler != NULL)
        speex_resampler_reset_mem(speexresampler);
    if (clearbuffers) {
        DEV_ASSERT(audiosamplebuffer.size() == audiosamplesize*ringbufferchunks); 
        chunknumber = 0;
        bufferend = 0;
    }
}

void AudioEffectFFTBlock::deleteencoder() {
    if (speexresampler != NULL) {
        speex_resampler_destroy(speexresampler);
        speexresampler = NULL;
    }
}

void AudioEffectFFTBlock::createencoder() {
    deleteencoder();  
    audiosamplebuffer.resize(audiosamplesize*ringbufferchunks); 
    chunknumber = 0;
    bufferend = 0;

    if (opusframesize == 0)
        return;
        
    singleresamplebuffer.resize(opusframesize);
    if (audiosamplesize != opusframesize) {
        int speexerror = 0; 
        int resamplingquality = 10;
        // the speex resampler needs sample rates to be consistent with the sample buffer sizes
        speexresampler = speex_resampler_init(channels, audiosamplerate, opussamplerate, resamplingquality, &speexerror);
        godot::UtilityFunctions::prints("Encoder timeframeopus resampler", Dtimeframeopus, "timeframeaudio", Dtimeframeaudio); 
    } else {
        godot::UtilityFunctions::prints("Encoder timeframeopus no-resampling needed", Dtimeframeopus, "timeframeaudio", Dtimeframeaudio); 
    }

}

void AudioEffectFFTBlockInstance::_process(const void *src_buffer, AudioFrame *p_dst_frames, int p_frame_count) {
    base->process((const AudioFrame *)src_buffer, p_dst_frames, p_frame_count); 
}

void AudioEffectFFTBlock::push_sample(const Vector2 &sample) {
    audiosamplebuffer.set(bufferend % audiosamplebuffer.size(), sample);
    bufferend += 1; 
    if (bufferend == (chunknumber + ringbufferchunks)*audiosamplesize) {
        drop_chunk(); 
        discardedchunks += 1; 
        if (!Engine::get_singleton()->is_editor_hint())
            if ((discardedchunks < 5) || ((discardedchunks % 1000) == 0))
                godot::UtilityFunctions::prints("Discarding chunk", discardedchunks, bufferend, (chunknumber + 1)*audiosamplesize); 
    }
}

void AudioEffectFFTBlock::process(const AudioFrame *p_src_frames, AudioFrame *p_dst_frames, int p_frame_count) {
    for (int i = 0; i < p_frame_count; i++) {
        p_dst_frames[i] = p_src_frames[i];
        push_sample(Vector2(p_src_frames[i].left, p_src_frames[i].right));
    }
}

void AudioEffectFFTBlock::push_chunk(const PackedVector2Array& audiosamples) {
    for (int i = 0; i < audiosamples.size(); i++)
        push_sample(audiosamples[i]);
}




