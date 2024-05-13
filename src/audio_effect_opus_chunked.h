/**************************************************************************/
/*  audio_effect_opus_chunked.h                                                */
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

#ifndef AUDIO_EFFECT_OPUS_CHUNKED_H
#define AUDIO_EFFECT_OPUS_CHUNKED_H


#include <godot_cpp/classes/audio_effect.hpp>
#include <godot_cpp/classes/audio_effect_instance.hpp>
#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/node.hpp>

#include "opus.h"
#include "speex_resampler/speex_resampler.h"

namespace godot {

class AudioEffectOpusChunked;

class AudioEffectOpusChunkedInstance : public AudioEffectInstance {
	GDCLASS(AudioEffectOpusChunkedInstance, AudioEffectInstance);
	friend class AudioEffectOpusChunked;
	Ref<AudioEffectOpusChunked> base;

protected:
	static void _bind_methods() {;};

public:
	virtual void _process(const void *src_buffer, AudioFrame *p_dst_frames, int p_frame_count) override;
	virtual bool _process_silence() const override;
};

class AudioEffectOpusChunked : public AudioEffect {
	GDCLASS(AudioEffectOpusChunked, AudioEffect)
	friend class AudioEffectOpusChunkedInstance;

    OpusEncoder* opusencoder = NULL;
    SpeexResamplerState* speexresampler = NULL;

    int opussamplerate = 48000;
    int opusframesize = 960;
    int opusbitrate = 24000;
    
    int audiosamplerate = 44100;
    int audiosamplesize = 441;
    int audiosamplechunks = 50;

	PackedVector2Array audiosamplebuffer;
	int chunknumber = -1;
	int bufferend = 0;
	int discardedchunks = 0;

	void process(const AudioFrame *p_src_frames, AudioFrame *p_dst_frames, int p_frame_count);

protected:
	static void _bind_methods();

public:
	virtual Ref<AudioEffectInstance> _instantiate() override;

	void resetencoder();
	bool chunk_available();
	float chunk_max();
	PackedVector2Array pop_chunk(bool keep=false);

    void set_opussamplerate(int lopussamplerate);
    int get_opussamplerate();
    void set_opusframesize(int lopusframesize);
    int get_opusframesize();
    void set_opusbitrate(int lopusbitrate);
    int get_opusbitrate();
    void set_audiosamplerate(int laudiosamplerate);
    int get_audiosamplerate();
    void set_audiosamplesize(int laudiosamplesize);
    int get_audiosamplesize();
    void set_audiosamplechunks(int laudiosamplechunks) { resetencoder(); audiosamplechunks = laudiosamplechunks; };
    int get_audiosamplechunks() { return audiosamplechunks; };
};

}

#endif // AUDIO_EFFECT_OPUS_CHUNKED_H
