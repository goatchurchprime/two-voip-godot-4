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

#ifndef AUDIO_STREAM_OPUS_H
#define AUDIO_STREAM_OPUS_H


#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/classes/audio_stream_playback_resampled.hpp>
#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/node.hpp>

#include "opus.h"

namespace godot {

class AudioStreamOpus;


class AudioStreamOpus : public AudioStream {
    GDCLASS(AudioStreamOpus, AudioStream)
    friend class AudioStreamPlaybackOpus;

    float opus_sample_rate = 48000.0;  // must be one of 48000,24000,16000,12000,8000
    int opus_channels = 2;  // must be 1 or 2

    float buffer_len = 2.0;

protected:
    static void _bind_methods();

public:
    virtual Ref<AudioStreamPlayback> _instantiate_playback() const override;
    virtual String _get_stream_name() const override { return "Opus Peer"; }
    virtual double _get_length() const override { return 0; }
    virtual bool _is_monophonic() const override { return true; }
    virtual double _get_bpm() const override { return 0.0; }
    virtual int32_t _get_beat_count() const override { return 0; }
    
    void set_opus_sample_rate(int p_sample_rate) { opus_sample_rate = p_sample_rate;  };
    float get_opus_sample_rate() { return opus_sample_rate; };
    void set_opus_channels(int p_channels) { opus_channels = p_channels;  };
    float get_opus_channels() { return opus_channels; };
    void set_buffer_length(int p_seconds) { buffer_len = p_seconds; };
    int get_buffer_length() { return buffer_len; };
};

class AudioStreamPlaybackOpus : public AudioStreamPlaybackResampled {
    GDCLASS(AudioStreamPlaybackOpus, AudioStreamPlaybackResampled)
    friend class AudioStreamOpus;
    Ref<AudioStreamOpus> base;
    
    int skips = 0;
    bool active = false;
    float mixed = 0.0;

    OpusDecoder* opusdecoder = NULL;
    PackedFloat32Array audiounpackedbuffer;
    int Naudiounpackedbuffer = 6000;   //  *  If this is less than the maximum packet duration (120ms; 5760 for 48kHz), this function will    

    PackedVector2Array audiosamplebuffer;

    int Naudiosamplebuffer = 96000;
    int bufferbegin = 0;
    int buffertail = 0;
    
    int lastpacketsizeforfec = 960;
    float lastchunkmax = 0.0;
    int pop_front_frames(AudioFrame *buffer, int frames);

protected:
    static void _bind_methods();
    void initialize(const AudioStreamOpus* pbase);

public:
    virtual int32_t _mix_resampled(AudioFrame *dst_buffer, int32_t frame_count) override;
    virtual double _get_stream_sampling_rate() const override  { return base->opus_sample_rate; };

    virtual void _start(double p_from_pos = 0.0) override;
    virtual void _stop() override;
    virtual bool _is_playing() const override;
    virtual int _get_loop_count() const override; 
    virtual double _get_playback_position() const override;
    virtual void _seek(double p_time) override;
    virtual void _tag_used_streams() override;

    void reset_opus_decoder();
    bool opus_segment_space_available();
    int queue_length_frames();
    void push_opus_packet(const PackedByteArray& opusbytepacket, int begin, int decode_fec);
    float get_last_chunk_max() { return lastchunkmax; };

    AudioStreamPlaybackOpus();
    ~AudioStreamPlaybackOpus();
};



}

#endif // AUDIO_STREAM_OPUS_CHUNKED_H
