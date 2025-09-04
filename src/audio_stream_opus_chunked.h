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

// Note: This is the decoding class.  The functions are similar so don't mix it up with the encoding AudioEffect class

namespace godot {

class AudioStreamOpusChunked;

class AudioStreamPlaybackOpusChunked : public AudioStreamPlaybackResampled {
    GDCLASS(AudioStreamPlaybackOpusChunked, AudioStreamPlaybackResampled)
    friend class AudioStreamOpusChunked;
    Ref<AudioStreamOpusChunked> base;
    
    int skips = 0;
    bool active = false;
    float mixed = 0.0;

protected:
    static void _bind_methods() {;};

public:
    virtual int32_t _mix_resampled(AudioFrame *dst_buffer, int32_t frame_count) override;
    virtual double _get_stream_sampling_rate() const override;

    virtual void _start(double p_from_pos = 0.0) override;
    virtual void _stop() override;
    virtual bool _is_playing() const override;
    virtual int _get_loop_count() const override; 
    virtual double _get_playback_position() const override;
    virtual void _seek(double p_time) override;
    virtual void _tag_used_streams() override;
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
    int audiosamplesize = 882;
    PackedVector2Array Daudioresampledbuffer;
    
    float mix_rate = 44100.0;

    PackedVector2Array audiosamplebuffer;
    int audiosamplechunks = 50;
    int chunknumber = -1;  // -1 is uninitialized, -2 is error state
    int bufferbegin = 0;
    int buffertail = 0;
    int missingsamples = 0;
    PackedVector2Array* Popus_packet_to_chunk(const PackedByteArray& opusbytepacket, int begin, int decode_fec);
    int Apop_front_chunk(AudioFrame *buffer, int frames);
    int Ppop_front_chunk(Vector2 *buffer, int frames); // same as Apop_front_chunk but different array type

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
    void deletedecoder();
    void resetdecoder();
    
    bool chunk_space_available();
    int queue_length_frames();
    void push_audio_chunk(const PackedVector2Array& audiochunk);
    void push_resampled_audio_chunk(const PackedVector2Array& resampledaudiochunk);
    void push_opus_packet(const PackedByteArray& opusbytepacket, int begin, int decode_fec);
    
    float last_chunk_max();
    float last_chunk_rms();
    PackedVector2Array read_last_chunk();
    PackedVector2Array pop_front_chunk(int frames);

    void set_opussamplerate(int lopussamplerate) { deletedecoder(); opussamplerate = lopussamplerate; };
    int get_opussamplerate() { return opussamplerate; };
    void set_opusframesize(int lopusframesize) { deletedecoder(); opusframesize = lopusframesize; };
    int get_opusframesize() { return opusframesize; };
    void set_audiosamplerate(int laudiosamplerate) { deletedecoder(); audiosamplerate = laudiosamplerate; };
    int get_audiosamplerate() { return audiosamplerate; };
    void set_audiosamplesize(int laudiosamplesize) { deletedecoder(); audiosamplesize = laudiosamplesize; };
    int get_audiosamplesize() { return audiosamplesize; };
    void set_audiosamplechunks(int laudiosamplechunks) { deletedecoder(); audiosamplechunks = laudiosamplechunks; };
    int get_audiosamplechunks() { return audiosamplechunks; };
    void set_mix_rate(int lmix_rate) { deletedecoder(); mix_rate = lmix_rate; };
    int get_mix_rate() { return mix_rate; };

    AudioStreamOpusChunked() {;};
    ~AudioStreamOpusChunked() { deletedecoder(); };
};

}

#endif // AUDIO_STREAM_OPUS_CHUNKED_H
