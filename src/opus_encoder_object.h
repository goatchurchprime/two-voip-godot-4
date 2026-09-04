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

#include <vector>

#include "opus.h"
#include "speex/speex_preprocess.h"
#include "speex/speex_resampler.h"


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
    SpeexPreprocessState* speex_agc = NULL;
    DenoiseState* rnnoise_st = NULL;
    OpusEncoder* opus_encoder = NULL;

    PackedFloat32Array mono_audio_frames; 
    PackedFloat32Array pre_encoded_chunk; 
    PackedFloat32Array rnnoise_in;
    PackedFloat32Array rnnoise_out;
    std::vector<spx_int16_t> agc_mono_frame;
    PackedByteArray opus_byte_buffer;

    int output_chunk_size = 0;
    int required_input_chunk_size = 0;
    int agc_frame_size = 0;
    float last_peak = 0.0F;
    float last_rms = 0.0F;
    float last_speech_probability = 0.0F;
    float manual_gain = 1.0F;
    float current_gain = 1.0F;
    bool automatic_gain = false;

    void destroy_agc();
    bool create_agc();
    int process_chunk_internal(const PackedVector2Array &audio_frames);
    void apply_gain();
    void update_measurements();
    
protected:
    static void _bind_methods();
    
public:
    bool create_sampler(int p_input_mix_rate, int p_opus_sample_rate, int p_channels, bool use_rnnoise);
    bool set_output_chunk_size(int p_output_chunk_size);
    int get_required_input_chunk_size() const { return required_input_chunk_size; }
    int process_chunk(const PackedVector2Array &audio_frames);
    float get_peak() const { return last_peak; }
    float get_rms() const { return last_rms; }
    float get_speech_probability() const { return last_speech_probability; }
    void set_gain(float p_gain);
    float get_gain() const { return current_gain; }
    bool set_automatic_gain(bool p_enabled);
    bool create_opus_encoder(int bit_rate, int complexity, bool voice_optimal);
    void reset_opus_encoder();

    int calc_audio_chunk_size(int opus_chunk_size);
    float process_pre_encoded_chunk(PackedVector2Array audio_frames, int opus_chunk_size, bool speech_probability, bool rms);
    PackedByteArray encode_chunk(const PackedByteArray& prefix_bytes, float gain=1.0);

    TwovoipOpusEncoder();
    ~TwovoipOpusEncoder();
};

}

#endif // OPUS_ENCODER_OBJECT_H
