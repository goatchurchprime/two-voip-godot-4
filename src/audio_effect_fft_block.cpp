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

void AudioEffectFFTBlock::_bind_methods() {

    ClassDB::bind_method(D_METHOD("set_opussamplerate", "opussamplerate"), &AudioEffectFFTBlock::set_opussamplerate);
    ClassDB::bind_method(D_METHOD("get_opussamplerate"), &AudioEffectFFTBlock::get_opussamplerate);
    ClassDB::bind_method(D_METHOD("set_opusframesize", "opusframesize"), &AudioEffectFFTBlock::set_opusframesize);
    ClassDB::bind_method(D_METHOD("get_opusframesize"), &AudioEffectFFTBlock::get_opusframesize);
    ClassDB::bind_method(D_METHOD("set_audiosamplerate", "audiosamplerate"), &AudioEffectFFTBlock::set_audiosamplerate);
    ClassDB::bind_method(D_METHOD("get_audiosamplerate"), &AudioEffectFFTBlock::get_audiosamplerate);
    ClassDB::bind_method(D_METHOD("set_audiosamplesize", "audiosamplesize"), &AudioEffectFFTBlock::set_audiosamplesize);
    ClassDB::bind_method(D_METHOD("get_audiosamplesize"), &AudioEffectFFTBlock::get_audiosamplesize);

    ADD_PROPERTY(PropertyInfo(Variant::INT, "opussamplerate", PROPERTY_HINT_RANGE, "20,192000,1"), "set_opussamplerate", "get_opussamplerate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opusframesize", PROPERTY_HINT_RANGE, "20,2880,1"), "set_opusframesize", "get_opusframesize");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplerate", PROPERTY_HINT_RANGE, "20,192000,1"), "set_audiosamplerate", "get_audiosamplerate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplesize", PROPERTY_HINT_RANGE, "10,4000,1"), "set_audiosamplesize", "get_audiosamplesize");

    ClassDB::bind_method(D_METHOD("push_chunk", "audiosamples"), &AudioEffectFFTBlock::push_chunk);
    ClassDB::bind_method(D_METHOD("set_images", "audiosampleframetexture"), &AudioEffectFFTBlock::set_images);
}



static void smbFft(float *fftBuffer, long fftFrameSize, long sign)
/*
	FFT routine, (C)1996 S.M.Bernsee. Sign = -1 is FFT, 1 is iFFT (inverse)
	Fills fftBuffer[0...2*fftFrameSize-1] with the Fourier transform of the
	time domain data in fftBuffer[0...2*fftFrameSize-1]. The FFT array takes
	and returns the cosine and sine parts in an interleaved manner, ie.
	fftBuffer[0] = cosPart[0], fftBuffer[1] = sinPart[0], asf. fftFrameSize
	must be a power of 2. It expects a complex input signal (see footnote 2),
	ie. when working with 'common' audio signals our input signal has to be
	passed as {in[0],0.,in[1],0.,in[2],0.,...} asf. In that case, the transform
	of the frequencies of interest is in fftBuffer[0...fftFrameSize].
*/
{
	float wr, wi, arg, *p1, *p2, temp;
	float tr, ti, ur, ui, *p1r, *p1i, *p2r, *p2i;
	long i, bitm, j, le, le2, k, logN;
	logN = (long)(Math::log((double)fftFrameSize) / Math::log(2.) + .5);

	for (i = 2; i < 2 * fftFrameSize - 2; i += 2) {
		for (bitm = 2, j = 0; bitm < 2 * fftFrameSize; bitm <<= 1) {
			if (i & bitm) {
				j++;
			}
			j <<= 1;
		}
		if (i < j) {
			p1 = fftBuffer + i;
			p2 = fftBuffer + j;
			temp = *p1;
			*(p1++) = *p2;
			*(p2++) = temp;
			temp = *p1;
			*p1 = *p2;
			*p2 = temp;
		}
	}
	for (k = 0, le = 2; k < logN; k++) {
		le <<= 1;
		le2 = le >> 1;
		ur = 1.0;
		ui = 0.0;
		arg = Math_PI / (le2 >> 1);
		wr = std::cos(arg);
		wi = sign * std::sin(arg);
		for (j = 0; j < le2; j += 2) {
			p1r = fftBuffer + j;
			p1i = p1r + 1;
			p2r = p1r + le2;
			p2i = p2r + 1;
			for (i = j; i < 2 * fftFrameSize; i += le) {
				tr = *p2r * ur - *p2i * ui;
				ti = *p2r * ui + *p2i * ur;
				*p2r = *p1r - tr;
				*p2i = *p1i - ti;
				*p1r += tr;
				*p1i += ti;
				p1r += le;
				p1i += le;
				p2r += le;
				p2i += le;
			}
			tr = ur * wr - ui * wi;
			ui = ur * wi + ui * wr;
			ur = tr;
		}
	}
}

AudioEffectFFTBlock::AudioEffectFFTBlock() {
    createencoder();
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
    audiosamplebuffer.resize(audiosamplebuffer_size); 
    bufferend = 0;

    fftslab.resize(fftsize*2*4*fftrows);
    fftirow = 0;

    if (opusframesize == 0)
        return;
        
    singleresamplebuffer.resize(opusframesize);
}

void AudioEffectFFTBlockInstance::_process(const void *src_buffer, AudioFrame *p_dst_frames, int p_frame_count) {
    base->process((const AudioFrame *)src_buffer, p_dst_frames, p_frame_count); 
}

void AudioEffectFFTBlock::push_sample(const Vector2 &sample) {
    audiosamplebuffer.set(bufferend % audiosamplebuffer.size(), sample);
    bufferend += 1; 
    if ((bufferend % fftsize) == 0) {
        float* ac = ((float*)fftslab.ptrw()) + fftirow*(fftsize*2);
        for (int i = 0; i < fftsize; i++) {
            Vector2 v = audiosamplebuffer[(bufferend - 1024 + i)%audiosamplebuffer.size()];
            ac[i*2] = (v.x + v.y)*0.5;
            ac[i*2 + 1] = 0.0;
        }
        smbFft(ac, fftsize, -1);
        audiosampleframetextureimage->set_data(fftsize, fftrows, false, Image::FORMAT_RGF, fftslab);
        audiosampleframetexture->update(audiosampleframetextureimage);
        fftirow = (fftirow + 1)%fftrows;
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

void AudioEffectFFTBlock::set_images(Ref<Image> laudiosampleframetextureimage, Ref<ImageTexture> laudiosampleframetexture) {
    audiosampleframetextureimage = laudiosampleframetextureimage;
    audiosampleframetexture = laudiosampleframetexture;
}




