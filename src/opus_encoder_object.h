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

    enum SignalType {
        SIGNAL_AUTO,
        SIGNAL_VOICE,
        SIGNAL_MUSIC,
    };

private:
    
    int input_mix_rate = 44100;   // AudioServer.get_input_mixrate()
    int opus_sample_rate = 48000;
    int channels = 2;
    
    int required_input_chunk_size = 0;

    PackedFloat32Array mono_audio_frames; 
    SpeexResamplerState* speex_resampler = NULL;

    std::vector<spx_int16_t> speex_frame;
    SpeexPreprocessState* speex_denoiser = NULL;
    SpeexPreprocessState* speex_agc = NULL;

    int output_chunk_size = 0;  // usually 960 = 48000 * 20ms
    int preprocess_frame_size = 0; // usually 960, factor 10ms size

    const float max_lead_time = 1.0;
    int audio_ringbuffer_size_chunks = 0; // about 50 for one clear second (over the top but good for testing)
    int audio_ringbuffer_index = 0; // goes around like a ring
    PackedFloat32Array prepared_audio_ringbuffer; // output_chunk_size*channels*audio_ringbuffer_size_chunks

#ifdef RNNOISE
    DenoiseState* rnnoise_st = NULL;
    PackedFloat32Array rnnoise_in;
    PackedFloat32Array rnnoise_out;
#endif

    OpusEncoder* opus_encoder = NULL;
    int bitrate = 0;
    int complexity = 0;
    SignalType signal_type = SIGNAL_AUTO;

    PackedByteArray opus_byte_buffer;

    SpeexResamplerState* resampler_16khz = NULL;


    float last_peak = 0.0F;
    float last_rms = 0.0F;
    float last_speech_probability = 0.0F;
    float gain = 1.0F;
    float agc_gain = 1.0F;
    Denoiser denoiser_mode = DENOISER_DISABLED;
    AgcMode agc_mode = AGC_DISABLED;
    bool initialized = false;

    void destroy_audio_pipeline();
    void destroy_voice_processor();
    Error create_opus_encoder();
    Error create_voice_processor();
    Error configure_output_chunk_size(int p_output_chunk_size, int p_audio_ringbuffer_size_chunks);
    void process_denoiser(float* prepared_audio_chunk);
    void update_agc_gain();
    
protected:
    static void _bind_methods();
    
public:
    Error initialize(int p_input_mix_rate, int p_opus_sample_rate, int p_channels, Denoiser p_denoiser_mode, AgcMode p_agc_mode, int p_output_chunk_size);
    int get_required_input_chunk_size() const { return required_input_chunk_size; }
    int process_chunk(const PackedVector2Array &audio_frames);
    float get_peak() const { return last_peak; }
    float get_rms() const { return last_rms; }
    float get_speech_probability() const { return last_speech_probability; }
    PackedVector2Array get_current_chunk() const;
    PackedFloat32Array get_current_chunk_16khz(bool p_reset_sampler);
    void set_gain(float p_gain);
    float get_gain() const { return gain; }
    float get_agc_gain() const { return agc_gain; }
    Error target_agc_gain(float p_target_gain);
    Error set_bitrate(int p_bitrate);
    int get_bitrate() const { return bitrate; }
    Error set_complexity(int p_complexity);
    int get_complexity() const { return complexity; }
    Error set_signal_type(SignalType p_signal_type);
    SignalType get_signal_type() const { return signal_type; }
    void reset_opus_encoder();
    PackedByteArray encode_chunk(const PackedByteArray& prefix_bytes=PackedByteArray(), int chunk_offset_back=0);

    TwovoipOpusEncoder();
    ~TwovoipOpusEncoder();
};

}

VARIANT_ENUM_CAST(godot::TwovoipOpusEncoder::Denoiser)
VARIANT_ENUM_CAST(godot::TwovoipOpusEncoder::AgcMode)
VARIANT_ENUM_CAST(godot::TwovoipOpusEncoder::SignalType)

#endif // OPUS_ENCODER_OBJECT_H
