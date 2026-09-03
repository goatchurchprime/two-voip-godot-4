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

#ifndef OPUS_ENCODER_OBJECT_H
#define OPUS_ENCODER_OBJECT_H

#include <godot_cpp/classes/audio_effect.hpp>
#include <godot_cpp/classes/audio_effect_instance.hpp>
#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/mutex.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/audio_stream_microphone.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/audio_stream_playback_resampled.hpp>

#include "opus.h"
#include "speex_resampler/speex_resampler.h"


#ifdef RNNOISE
    #include "rnnoise.h"
#else
    #include "rnnoise_stub.h"
#endif


namespace godot {
    

class TwovoipOpusEncoder : public RefCounted {
    GDCLASS(TwovoipOpusEncoder, RefCounted)
    
    int input_mix_rate = 44100;   // AudioServer.get_input_mixrate()
    int opus_sample_rate = 48000; // AudioServer.get_input_mixrate()
    int channels = 2;
    
    SpeexResamplerState* speex_resampler = NULL;
    DenoiseState* rnnoise_st = NULL;
    OpusEncoder* opus_encoder = NULL;

    PackedFloat32Array mono_audio_frames; 
    PackedFloat32Array pre_encoded_chunk; 
    PackedFloat32Array rnnoise_in;
    PackedFloat32Array rnnoise_out;
    PackedByteArray opus_byte_buffer;
    
protected:
    static void _bind_methods();
    
public:
    bool create_sampler(int p_input_mix_rate, int p_opus_sample_rate, int p_channels, bool use_rnnoise);
    bool create_opus_encoder(int bit_rate, int complexity, bool voice_optimal);
    void reset_opus_encoder();

    int calc_audio_chunk_size(int opus_chunk_size);
    float process_pre_encoded_chunk(PackedVector2Array audio_frames, int opus_chunk_size, bool speech_probability, bool rms);
    PackedVector2Array fetch_pre_encoded_chunk() { return PackedVector2Array(); pre_encoded_chunk; }
    PackedByteArray encode_chunk(const PackedByteArray& prefix_bytes, float gain=1.0);

    TwovoipOpusEncoder();
    ~TwovoipOpusEncoder();
};

}

#endif // OPUS_ENCODER_OBJECT_H
