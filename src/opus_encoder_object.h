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
#endif


namespace godot {
    

class TwovoipOpusEncoder : public RefCounted {
    GDCLASS(TwovoipOpusEncoder, RefCounted)

public:
    enum Denoiser {
        DENOISER_DISABLED,
        DENOISER_SPEEX,
        DENOISER_RNNOISE,
    };

    enum AgcMode {
        AGC_DISABLED,
        AGC_APPLIED,
        AGC_MONITOR,
    };

private:
    
    int input_mix_rate = 44100;   // AudioServer.get_input_mixrate()
    int opus_sample_rate = 48000; // AudioServer.get_input_mixrate()
    int channels = 2;
    
    SpeexResamplerState* speex_resampler = NULL;
    SpeexResamplerState* resampler_16khz = NULL;
    SpeexPreprocessState* speex_preprocessor = NULL;
    SpeexPreprocessState* speex_agc_monitor = NULL;
#ifdef RNNOISE
    DenoiseState* rnnoise_st = NULL;
#endif
    OpusEncoder* opus_encoder = NULL;

    PackedFloat32Array mono_audio_frames; 
    PackedFloat32Array pre_encoded_chunk; 
    PackedFloat32Array mono_output_chunk;
    PackedFloat32Array current_chunk_16khz;
    std::vector<spx_int16_t> speex_frame;
#ifdef RNNOISE
    PackedFloat32Array rnnoise_in;
    PackedFloat32Array rnnoise_out;
#endif
    PackedByteArray opus_byte_buffer;

    int output_chunk_size = 0;
    int required_input_chunk_size = 0;
    int preprocess_frame_size = 0;
    int chunk_size_16khz = 0;
    float last_peak = 0.0F;
    float last_rms = 0.0F;
    float last_speech_probability = 0.0F;
    float gain = 1.0F;
    float agc_gain = 1.0F;
    Denoiser denoiser = DENOISER_DISABLED;
    AgcMode agc_mode = AGC_DISABLED;
    bool legacy_processing_warning_printed = false;

    void destroy_voice_processor();
    Error create_voice_processor();
    Error configure_output_chunk_size(int p_output_chunk_size);
    Error configure_16khz_output();
    int process_chunk_internal(const PackedVector2Array &audio_frames);
    void process_voice();
    void apply_manual_gain();
    Error update_current_chunk_16khz();
    void update_measurements();
    
protected:
    static void _bind_methods();
    
public:
    Error create_sampler(int p_input_mix_rate, int p_opus_sample_rate, int p_channels, Denoiser p_denoiser, AgcMode p_agc_mode, int p_output_chunk_size);
    bool set_output_chunk_size(int p_output_chunk_size);
    int get_output_chunk_size() const { return output_chunk_size; }
    int get_required_input_chunk_size() const { return required_input_chunk_size; }
    int process_chunk(const PackedVector2Array &audio_frames);
    float get_peak() const { return last_peak; }
    float get_rms() const { return last_rms; }
    float get_speech_probability() const { return last_speech_probability; }
    PackedFloat32Array get_current_chunk_16khz() const { return current_chunk_16khz; }
    void set_gain(float p_gain);
    float get_gain() const { return gain; }
    float get_agc_gain() const { return agc_gain; }
    Denoiser get_denoiser() const { return denoiser; }
    AgcMode get_agc_mode() const { return agc_mode; }
    bool create_opus_encoder(int bit_rate, int complexity, bool voice_optimal);
    void reset_opus_encoder();

    /** @deprecated Configure the output size once and call get_required_input_chunk_size(). */
    int calc_audio_chunk_size(int opus_chunk_size);
    /** @deprecated Use process_chunk() followed by the measurement getters. */
    float process_pre_encoded_chunk(PackedVector2Array audio_frames, int opus_chunk_size, bool speech_probability, bool rms);
    PackedByteArray encode_chunk(const PackedByteArray& prefix_bytes=PackedByteArray());

    TwovoipOpusEncoder();
    ~TwovoipOpusEncoder();
};

}

VARIANT_ENUM_CAST(godot::TwovoipOpusEncoder::Denoiser)
VARIANT_ENUM_CAST(godot::TwovoipOpusEncoder::AgcMode)

#endif // OPUS_ENCODER_OBJECT_H
