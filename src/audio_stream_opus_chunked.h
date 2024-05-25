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

#ifndef AUDIO_STREAM_OPUS_CHUNKED_H
#define AUDIO_STREAM_OPUS_CHUNKED_H


#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/classes/audio_stream_playback_resampled.hpp>
#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/node.hpp>

#include "opus.h"
#include "speex_resampler/speex_resampler.h"

namespace godot {

class AudioStreamOpusChunked;


// This should use AudioStreamPlaybackResampled, so we get the mix_rate done automatically
class AudioStreamPlaybackOpusChunked : public AudioStreamPlaybackResampled {
    GDCLASS(AudioStreamPlaybackOpusChunked, AudioStreamPlaybackResampled)
    friend class AudioStreamOpusChunked;
    Ref<AudioStreamOpusChunked> base;
    
protected:
    static void _bind_methods() {;};

public:
	virtual int32_t _mix_resampled(AudioFrame *dst_buffer, int32_t frame_count) override;
	virtual double _get_stream_sampling_rate() const override { return 44100.0F; };
};


class AudioStreamOpusChunked : public AudioStream {
    GDCLASS(AudioStreamOpusChunked, AudioStream)
    friend class AudioStreamPlaybackOpusChunked;

    int opussamplerate = 48000;
    int opusframesize = 960;
    OpusDecoder* opusdecoder = NULL;
 	PackedVector2Array audiopreresampledbuffer;

    SpeexResamplerState* speexresampler = NULL;
    int audiosamplerate = 44100;
    int audiosamplesize = 881;
 	PackedVector2Array Daudioresampledbuffer;

	PackedVector2Array audiosamplebuffer;
    int audiosamplechunks = 50;
	int chunknumber = -1;
	int bufferbegin = 0;
	int buffertail = 0;
	int missingsamples = 0;

protected:
	static void _bind_methods();

public:
    virtual Ref<AudioStreamPlayback> _instantiate_playback() const override;
    virtual String _get_stream_name() const override { return "OpusChunked Peer"; }
    virtual double _get_length() const override { return 0; }
    virtual bool _is_monophonic() const override { return true; }
    virtual double _get_bpm() const override { return 0.0; }
    virtual int32_t _get_beat_count() const override { return 0; }

	void createdecoder();
	void resetdecoder();
	bool chunk_space_available();
	int buffered_audiosamples();
	void push_audio_chunk(const PackedVector2Array& audiochunk);
	void push_opus_packet(const PackedByteArray& opusbytepacket, int begin, int decode_fec);

    void set_opussamplerate(int lopussamplerate) { resetdecoder(); opussamplerate = lopussamplerate; };
    int get_opussamplerate() { return opussamplerate; };
    void set_opusframesize(int lopusframesize) { resetdecoder(); opusframesize = lopusframesize; };
    int get_opusframesize() { return opusframesize; };
    void set_audiosamplerate(int laudiosamplerate) { resetdecoder(); audiosamplerate = laudiosamplerate; };
    int get_audiosamplerate() { return audiosamplerate; };
    void set_audiosamplesize(int laudiosamplesize) { resetdecoder(); audiosamplesize = laudiosamplesize; };
    int get_audiosamplesize() { return audiosamplesize; };
    void set_audiosamplechunks(int laudiosamplechunks) { resetdecoder(); audiosamplechunks = laudiosamplechunks; };
    int get_audiosamplechunks() { return audiosamplechunks; };

	AudioStreamOpusChunked() {;};
	~AudioStreamOpusChunked() { resetdecoder(); };
};

}

#endif // AUDIO_STREAM_OPUS_CHUNKED_H
