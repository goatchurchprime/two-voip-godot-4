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

using namespace godot;


void AudioStreamOpusChunked::_bind_methods() {

    ClassDB::bind_method(D_METHOD("set_opussamplerate", "opussamplerate"), &AudioStreamOpusChunked::set_opussamplerate);
    ClassDB::bind_method(D_METHOD("get_opussamplerate"), &AudioStreamOpusChunked::get_opussamplerate);
    ClassDB::bind_method(D_METHOD("set_opusframesize", "opusframesize"), &AudioStreamOpusChunked::set_opusframesize);
    ClassDB::bind_method(D_METHOD("get_opusframesize"), &AudioStreamOpusChunked::get_opusframesize);
    ClassDB::bind_method(D_METHOD("set_opusbitrate", "opusbitrate"), &AudioStreamOpusChunked::set_opusbitrate);
    ClassDB::bind_method(D_METHOD("get_opusbitrate"), &AudioStreamOpusChunked::get_opusbitrate);
    ClassDB::bind_method(D_METHOD("set_audiosamplerate", "audiosamplerate"), &AudioStreamOpusChunked::set_audiosamplerate);
    ClassDB::bind_method(D_METHOD("get_audiosamplerate"), &AudioStreamOpusChunked::get_audiosamplerate);
    ClassDB::bind_method(D_METHOD("set_audiosamplesize", "audiosamplesize"), &AudioStreamOpusChunked::set_audiosamplesize);
    ClassDB::bind_method(D_METHOD("get_audiosamplesize"), &AudioStreamOpusChunked::get_audiosamplesize);
    ClassDB::bind_method(D_METHOD("set_audiosamplechunks", "audiosamplechunks"), &AudioStreamOpusChunked::set_audiosamplechunks);
    ClassDB::bind_method(D_METHOD("get_audiosamplechunks"), &AudioStreamOpusChunked::get_audiosamplechunks);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opussamplerate", PROPERTY_HINT_RANGE, "8000,48000,4000"), "set_opussamplerate", "get_opussamplerate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opusframesize", PROPERTY_HINT_RANGE, "20,2880,2"), "set_opusframesize", "get_opusframesize");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opusbitrate", PROPERTY_HINT_RANGE, "3000,24000,1000"), "set_opusbitrate", "get_opusbitrate");

    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplerate", PROPERTY_HINT_RANGE, "44100,44100,1"), "set_audiosamplerate", "get_audiosamplerate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplesize", PROPERTY_HINT_RANGE, "10,4000,1"), "set_audiosamplesize", "get_audiosamplesize");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplechunks", PROPERTY_HINT_RANGE, "1,200,1"), "set_audiosamplechunks", "get_audiosamplechunks");

    ClassDB::bind_method(D_METHOD("chunk_space_available"), &AudioStreamOpusChunked::chunk_space_available);
    ClassDB::bind_method(D_METHOD("push_audio_chunk", "audiochunk"), &AudioStreamOpusChunked::push_audio_chunk);
    ClassDB::bind_method(D_METHOD("push_opus_packet", "opusbytepacket"), &AudioStreamOpusChunked::push_opus_packet);
}

Ref<AudioStreamPlayback> AudioStreamOpusChunked::_instantiate_playback() const {
    Ref<AudioStreamPlaybackOpusChunked> playback;
    playback.instantiate();
    playback->base = Ref<AudioStreamOpusChunked>(this);
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
	audiosamplebuffer.resize(audiosamplesize*audiosamplechunks); 
	chunknumber = 0;
	bufferbegin = 0;
	if (opusframesize == 0)
		return; 
	
	int channels = 2;
	float Dtimeframeopus = opusframesize*1.0F/opussamplerate;
	float Dtimeframeaudio = audiosamplesize*1.0F/audiosamplerate;
    if (audiosamplesize != opusframesize) {
        int speexerror = 0; 
        int resamplingquality = 10;
        speexresampler = speex_resampler_init(channels, opussamplerate, audiosamplerate, resamplingquality, &speexerror);
        audiopreresampledbuffer.resize(opusframesize);
	    printf("Decoder timeframeopus preresampler %f timeframeaudio %f\n", Dtimeframeopus, Dtimeframeaudio); 
    } else {
	    printf("Decoder timeframeopus equating %f timeframeaudio %f\n", Dtimeframeopus, Dtimeframeaudio); 
	}

    // opussamplerate is one of 8000,12000,16000,24000,48000
    int opuserror = 0;
    opusdecoder = opus_decoder_create(opussamplerate, channels, &opuserror);
	if (opuserror != 0) 
		printf("We have an opus error*** %d\n", opuserror); 
}

bool AudioStreamOpusChunked::chunk_space_available() {
	return ((chunknumber != -1) && 
		((bufferbegin < chunknumber*audiosamplesize) || (bufferbegin >= (chunknumber + 1)*audiosamplesize))); 
}

int AudioStreamOpusChunked::buffered_audiosamples() {
    int chunkbegin = chunknumber*audiosamplesize;
    return chunkbegin - bufferbegin;  // do the negative case
}

void AudioStreamOpusChunked::push_audio_chunk(const PackedVector2Array& audiochunk) {
    int chunkbegin = chunknumber*audiosamplesize;
    for (int i = 0; i < audiosamplesize; i++) 
        audiosamplebuffer.set(chunkbegin + i, audiochunk[i]);
    chunknumber += 1;
    if (chunknumber == audiosamplechunks)
        chunknumber = 0;
}

void AudioStreamOpusChunked::push_opus_packet(const PackedByteArray& opusbytepacket) {
/*	int chunknumber = -1;
	int bufferbegin = 0;
	int missingsamples = 0;



	if (chunknumber == -1) 
		createencoder();
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
*/
}

// this needs to call the resampled one that lets us vary the speed and keep the 
// buffer from starving, or to run it up to catch up to the rest
int32_t AudioStreamPlaybackOpusChunked::_mix(AudioFrame *buffer, double rate_scale, int32_t frames) {
    memset(buffer, 0, sizeof(AudioFrame) * frames);
    //base->jitter_buffer.pop_samples(buffer, frames);
    return frames;
}



