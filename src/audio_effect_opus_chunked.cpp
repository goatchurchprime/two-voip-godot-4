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
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "audio_effect_opus_chunked.h"

using namespace godot;


void AudioEffectOpusChunked::_bind_methods() {

    ClassDB::bind_method(D_METHOD("set_opussamplerate", "opussamplerate"), &AudioEffectOpusChunked::set_opussamplerate);
    ClassDB::bind_method(D_METHOD("get_opussamplerate"), &AudioEffectOpusChunked::get_opussamplerate);
    ClassDB::bind_method(D_METHOD("set_opusframesize", "opusframesize"), &AudioEffectOpusChunked::set_opusframesize);
    ClassDB::bind_method(D_METHOD("get_opusframesize"), &AudioEffectOpusChunked::get_opusframesize);
    ClassDB::bind_method(D_METHOD("set_opusbitrate", "opusbitrate"), &AudioEffectOpusChunked::set_opusbitrate);
    ClassDB::bind_method(D_METHOD("get_opusbitrate"), &AudioEffectOpusChunked::get_opusbitrate);
    ClassDB::bind_method(D_METHOD("set_audiosamplerate", "audiosamplerate"), &AudioEffectOpusChunked::set_audiosamplerate);
    ClassDB::bind_method(D_METHOD("get_audiosamplerate"), &AudioEffectOpusChunked::get_audiosamplerate);
    ClassDB::bind_method(D_METHOD("set_audiosamplesize", "audiosamplesize"), &AudioEffectOpusChunked::set_audiosamplesize);
    ClassDB::bind_method(D_METHOD("get_audiosamplesize"), &AudioEffectOpusChunked::get_audiosamplesize);
    ClassDB::bind_method(D_METHOD("set_audiosamplechunks", "audiosamplechunks"), &AudioEffectOpusChunked::set_audiosamplechunks);
    ClassDB::bind_method(D_METHOD("get_audiosamplechunks"), &AudioEffectOpusChunked::get_audiosamplechunks);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opussamplerate", PROPERTY_HINT_RANGE, "8000,48000,4000"), "set_opussamplerate", "get_opussamplerate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opusframesize", PROPERTY_HINT_RANGE, "20,2880,2"), "set_opusframesize", "get_opusframesize");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opusbitrate", PROPERTY_HINT_RANGE, "3000,24000,1000"), "set_opusbitrate", "get_opusbitrate");

    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplerate", PROPERTY_HINT_RANGE, "44100,44100,1"), "set_audiosamplerate", "get_audiosamplerate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplesize", PROPERTY_HINT_RANGE, "10,4000,1"), "set_audiosamplesize", "get_audiosamplesize");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplechunks", PROPERTY_HINT_RANGE, "1,200,1"), "set_audiosamplechunks", "get_audiosamplechunks");


    ClassDB::bind_method(D_METHOD("chunk_available"), &AudioEffectOpusChunked::chunk_available);
    ClassDB::bind_method(D_METHOD("chunk_max"), &AudioEffectOpusChunked::chunk_max);
    ClassDB::bind_method(D_METHOD("pop_chunk", "keep"), &AudioEffectOpusChunked::pop_chunk);
}

Ref<AudioEffectInstance> AudioEffectOpusChunked::_instantiate() {
	resetencoder();
	Ref<AudioEffectOpusChunkedInstance> ins;
	ins.instantiate();
	ins->base = Ref<AudioEffectOpusChunked>(this);
	return ins;
}


void AudioEffectOpusChunked::process(const AudioFrame *p_src_frames, AudioFrame *p_dst_frames, int p_frame_count) {
	if (chunknumber == -1) {
		audiosamplebuffer.resize(audiosamplesize*audiosamplechunks); 
		chunknumber = 0;
		bufferend = 0;
	}

	int chunkstart = chunknumber*audiosamplesize;
	for (int i = 0; i < p_frame_count; i++) {
		p_dst_frames[i] = p_src_frames[i];
		audiosamplebuffer.set(bufferend, Vector2(p_src_frames[i].left, p_src_frames[i].right));
		if (bufferend == chunkstart) {
			chunknumber += 1; 
			if (chunknumber == audiosamplechunks) 
				chunknumber = 0;
			chunkstart = chunknumber*audiosamplesize;
			discardedchunks += 1; 
		}
		bufferend += 1; 
		if (bufferend == audiosamplebuffer.size())
			bufferend = 0;
	}
}

bool AudioEffectOpusChunked::chunk_available() {
	return ((bufferend < chunknumber*audiosamplesize) || (bufferend >= (chunknumber + 1)*audiosamplesize)); 
}

float AudioEffectOpusChunked::chunk_max() {
	float r = 0.0F;
	float* p = (float*)audiosamplebuffer.ptr() + 2*chunknumber*audiosamplesize;
	for (int i = 0; i < audiosamplesize*2; i++) {
		float s = fabs(p[i]);
		if (s > r)
			r = s;
	}
	return r;
}

PackedVector2Array AudioEffectOpusChunked::pop_chunk(bool keep) {
	int begin = chunknumber*audiosamplesize; 
	int end = (chunknumber+1)*audiosamplesize; 
	if (!keep) {
		chunknumber += 1;
		if (chunknumber == audiosamplechunks)
			chunknumber = 0;
	}
	return audiosamplebuffer.slice(begin, end); 
}

void AudioEffectOpusChunkedInstance::_process(const void *src_buffer, AudioFrame *p_dst_frames, int p_frame_count) {
	base->process((const AudioFrame *)src_buffer, p_dst_frames, p_frame_count);
}
bool AudioEffectOpusChunkedInstance::_process_silence() const {
	return true;
}

void AudioEffectOpusChunked::set_opussamplerate(int lopussamplerate) {
    resetencoder();
    opussamplerate = lopussamplerate;
}
int AudioEffectOpusChunked::get_opussamplerate() {
    return opussamplerate;
}

void AudioEffectOpusChunked::set_opusframesize(int lopusframesize) {
    resetencoder();
    opusframesize = lopusframesize;
}
int AudioEffectOpusChunked::get_opusframesize() {
    return opusframesize;
}

void AudioEffectOpusChunked::set_opusbitrate(int lopusbitrate) {
    resetencoder();
    opusbitrate = lopusbitrate;
}
int AudioEffectOpusChunked::get_opusbitrate() {
    return opusbitrate;
}

void AudioEffectOpusChunked::set_audiosamplerate(int laudiosamplerate) {
    resetencoder();
    audiosamplerate = laudiosamplerate;
}
int AudioEffectOpusChunked::get_audiosamplerate() {
    return audiosamplerate;
}

void AudioEffectOpusChunked::set_audiosamplesize(int laudiosamplesize) {
    resetencoder();
    audiosamplesize = laudiosamplesize;
}
int AudioEffectOpusChunked::get_audiosamplesize() {
    return audiosamplesize;
}

void AudioEffectOpusChunked::resetencoder() {
	chunknumber = -1;
}