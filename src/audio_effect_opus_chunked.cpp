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

    ClassDB::bind_method(D_METHOD("Dcreateencoder"), &AudioEffectOpusChunked::createencoder);

    ClassDB::bind_method(D_METHOD("chunk_available"), &AudioEffectOpusChunked::chunk_available);
    ClassDB::bind_method(D_METHOD("chunk_max"), &AudioEffectOpusChunked::chunk_max);
    ClassDB::bind_method(D_METHOD("read_chunk"), &AudioEffectOpusChunked::read_chunk);
    ClassDB::bind_method(D_METHOD("drop_chunk"), &AudioEffectOpusChunked::drop_chunk);
    ClassDB::bind_method(D_METHOD("pop_opus_packet"), &AudioEffectOpusChunked::pop_opus_packet);
    ClassDB::bind_method(D_METHOD("chunk_to_opus_packet", "audiosamplebuffer", "begin"), &AudioEffectOpusChunked::chunk_to_opus_packet);
}

Ref<AudioEffectInstance> AudioEffectOpusChunked::_instantiate() {
	resetencoder();
	Ref<AudioEffectOpusChunkedInstance> ins;
	ins.instantiate();
	ins->base = Ref<AudioEffectOpusChunked>(this);
	return ins;
}

void AudioEffectOpusChunked::resetencoder() {
	chunknumber = -1;
    if (speexresampler != NULL) {
        speex_resampler_destroy(speexresampler);
        speexresampler = NULL;
    }
    if (opusencoder != NULL) {
        opus_encoder_destroy(opusencoder);
        opusencoder = NULL;
    }
}

void AudioEffectOpusChunked::createencoder() {
	resetencoder();  // In case called from GDScript
	audiosamplebuffer.resize(audiosamplesize*audiosamplechunks); 
	chunknumber = 0;
	bufferend = 0;

	int channels = 2;
    if (audiosamplesize != opusframesize) {
        int speexerror = 0; 
        int resamplingquality = 10;
        // the speex resampler needs sample rates to be consistent with the sample buffer sizes
        speexresampler = speex_resampler_init(channels, audiosamplerate, opussamplerate, resamplingquality, &speexerror);
		audioresampledbuffer.resize(opusframesize);
	    printf("Encoder timeframeopus equating different sample rates\n"); 
    } else {
		float Dtimeframeopus = opusframesize*1.0F/opussamplerate;
    	float Dtimeframeaudio = audiosamplesize*1.0F/audiosamplerate;
	    printf("Encoder timeframeopus %f timeframeaudio %f\n", Dtimeframeopus, Dtimeframeaudio); 
	}

    // opussamplerate is one of 8000,12000,16000,24000,48000
    // opussamplesize is 480 for 10ms at 48000
	if (opusframesize != 0) {
		int opusapplication = OPUS_APPLICATION_VOIP; // this option includes in-band forward error correction
		int opuserror = 0;
		opusencoder = opus_encoder_create(opussamplerate, channels, opusapplication, &opuserror);
		opus_encoder_ctl(opusencoder, OPUS_SET_BITRATE(opusbitrate));
		opusbytebuffer.resize(sizeof(float)*channels*opusframesize);
		if (opuserror != 0) 
			printf("We have an opus error*** %d\n", opuserror); 
	}
}

void AudioEffectOpusChunked::process(const AudioFrame *p_src_frames, AudioFrame *p_dst_frames, int p_frame_count) {
	if (chunknumber == -1) 
		createencoder();
	
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
	return ((chunknumber != -1) && 
		((bufferend < chunknumber*audiosamplesize) || (bufferend >= (chunknumber + 1)*audiosamplesize))); 
}

float AudioEffectOpusChunked::chunk_max() {
	if (chunknumber == -1) 
		return -1.0;
	float r = 0.0F;
	float* p = (float*)audiosamplebuffer.ptr() + 2*chunknumber*audiosamplesize;
	for (int i = 0; i < audiosamplesize*2; i++) {
		float s = fabs(p[i]);
		if (s > r)
			r = s;
	}
	return r;
}

void AudioEffectOpusChunked::drop_chunk() {
	if (chunknumber == -1) 
		return;
	chunknumber += 1;
	if (chunknumber == audiosamplechunks)
		chunknumber = 0;
}

PackedVector2Array AudioEffectOpusChunked::read_chunk() {
	if (chunknumber == -1) 
		return PackedVector2Array();
	int begin = chunknumber*audiosamplesize; 
	int end = (chunknumber+1)*audiosamplesize; 
	return audiosamplebuffer.slice(begin, end); 
}

PackedByteArray AudioEffectOpusChunked::chunk_to_opus_packet(const PackedVector2Array& audiosamplebuffer, int begin) {
	float* paudiosamples = (float*)audiosamplebuffer.ptr() + begin*2; 
    if (audiosamplesize != opusframesize) {
		unsigned int Uaudiosamplesize = audiosamplesize;
		unsigned int Uopusframesize = opusframesize;
        int sxerr = speex_resampler_process_interleaved_float(speexresampler, 
                paudiosamples, &Uaudiosamplesize, 
                (float*)audioresampledbuffer.ptrw(), &Uopusframesize);
		paudiosamples = (float*)audioresampledbuffer.ptr(); 
    }
	int bytepacketsize = opus_encode_float(opusencoder, paudiosamples, opusframesize, 
										  (unsigned char*)opusbytebuffer.ptrw(), opusbytebuffer.size());
    return opusbytebuffer.slice(0, bytepacketsize);
}

PackedByteArray AudioEffectOpusChunked::pop_opus_packet() {
	if ((chunknumber == -1) || (opusframesize == 0))
		return PackedByteArray();
	int begin = chunknumber*audiosamplesize; 
	drop_chunk();
	return chunk_to_opus_packet(audiosamplebuffer, begin);
}

void AudioEffectOpusChunkedInstance::_process(const void *src_buffer, AudioFrame *p_dst_frames, int p_frame_count) {
	base->process((const AudioFrame *)src_buffer, p_dst_frames, p_frame_count); 
}

