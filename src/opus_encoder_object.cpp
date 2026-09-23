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

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/audio_server.hpp>

#include <algorithm>
#include <cmath>

#include "opus_encoder_object.h"

using namespace godot;

namespace {

bool is_valid_opus_sample_rate(int p_sample_rate) {
    return p_sample_rate == 8000 || p_sample_rate == 12000 || p_sample_rate == 16000 ||
            p_sample_rate == 24000 || p_sample_rate == 48000;
}

bool is_valid_opus_frame_size(int p_sample_rate, int p_frame_size) {
    return p_frame_size == p_sample_rate / 400 || // 2.5 ms
            p_frame_size == p_sample_rate / 200 || // 5 ms
            p_frame_size == p_sample_rate / 100 || // 10 ms
            p_frame_size == p_sample_rate / 50 || // 20 ms
            p_frame_size == p_sample_rate / 25 || // 40 ms
            p_frame_size == p_sample_rate * 3 / 50; // 60 ms
}

int get_opus_signal_type(TwovoipOpusEncoder::SignalType p_signal_type) {
    switch (p_signal_type) {
        case TwovoipOpusEncoder::SIGNAL_AUTO:
            return OPUS_AUTO;
        case TwovoipOpusEncoder::SIGNAL_VOICE:
            return OPUS_SIGNAL_VOICE;
        case TwovoipOpusEncoder::SIGNAL_MUSIC:
            return OPUS_SIGNAL_MUSIC;
    }
    return 0;
}

} // namespace

void TwovoipOpusEncoder::_bind_methods() {
    ClassDB::bind_method(D_METHOD("initialize", "input_mix_rate", "opus_sample_rate", "channels", "denoiser_mode", "agc_mode", "output_chunk_size"), &TwovoipOpusEncoder::initialize);
    ClassDB::bind_method(D_METHOD("get_required_input_chunk_size"), &TwovoipOpusEncoder::get_required_input_chunk_size);
    ClassDB::bind_method(D_METHOD("process_chunk", "audio_frames"), &TwovoipOpusEncoder::process_chunk);
    ClassDB::bind_method(D_METHOD("denoise_chunk", "chunk_offset_back"), &TwovoipOpusEncoder::denoise_chunk);
    ClassDB::bind_method(D_METHOD("get_peak"), &TwovoipOpusEncoder::get_peak);
    ClassDB::bind_method(D_METHOD("get_rms"), &TwovoipOpusEncoder::get_rms);
    ClassDB::bind_method(D_METHOD("get_speech_probability"), &TwovoipOpusEncoder::get_speech_probability);
    ClassDB::bind_method(D_METHOD("get_current_chunk"), &TwovoipOpusEncoder::get_current_chunk);
    ClassDB::bind_method(D_METHOD("get_current_chunk_16khz", "reset_sampler"), &TwovoipOpusEncoder::get_current_chunk_16khz);
    ClassDB::bind_method(D_METHOD("set_gain", "gain"), &TwovoipOpusEncoder::set_gain);
    ClassDB::bind_method(D_METHOD("get_gain"), &TwovoipOpusEncoder::get_gain);
    ClassDB::bind_method(D_METHOD("get_agc_gain"), &TwovoipOpusEncoder::get_agc_gain);
    ClassDB::bind_method(D_METHOD("target_agc_gain", "target_gain"), &TwovoipOpusEncoder::target_agc_gain);
    ClassDB::bind_method(D_METHOD("set_bitrate", "bitrate"), &TwovoipOpusEncoder::set_bitrate);
    ClassDB::bind_method(D_METHOD("get_bitrate"), &TwovoipOpusEncoder::get_bitrate);
    ClassDB::bind_method(D_METHOD("set_complexity", "complexity"), &TwovoipOpusEncoder::set_complexity);
    ClassDB::bind_method(D_METHOD("get_complexity"), &TwovoipOpusEncoder::get_complexity);
    ClassDB::bind_method(D_METHOD("set_signal_type", "signal_type"), &TwovoipOpusEncoder::set_signal_type);
    ClassDB::bind_method(D_METHOD("get_signal_type"), &TwovoipOpusEncoder::get_signal_type);
    ClassDB::bind_method(D_METHOD("reset_opus_encoder"), &TwovoipOpusEncoder::reset_opus_encoder);
    ClassDB::bind_method(D_METHOD("encode_chunk", "prefix_bytes", "chunk_offset_back"), &TwovoipOpusEncoder::encode_chunk, DEFVAL(PackedByteArray()), DEFVAL(0));

    uint32_t read_only = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY;
    ADD_PROPERTY(PropertyInfo(Variant::INT, "required_input_chunk_size", PROPERTY_HINT_NONE, "", read_only), "", "get_required_input_chunk_size");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "gain"), "set_gain", "get_gain");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "bitrate", PROPERTY_HINT_RANGE, "500,512000,500,suffix:bps"), "set_bitrate", "get_bitrate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "complexity", PROPERTY_HINT_RANGE, "0,10,1"), "set_complexity", "get_complexity");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "signal_type", PROPERTY_HINT_ENUM, "Auto,Voice,Music"), "set_signal_type", "get_signal_type");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "agc_gain", PROPERTY_HINT_NONE, "", read_only), "", "get_agc_gain");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "peak", PROPERTY_HINT_NONE, "", read_only), "", "get_peak");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "rms", PROPERTY_HINT_NONE, "", read_only), "", "get_rms");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "speech_probability", PROPERTY_HINT_NONE, "", read_only), "", "get_speech_probability");
    ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR2_ARRAY, "current_chunk", PROPERTY_HINT_NONE, "", read_only), "", "get_current_chunk");

    BIND_ENUM_CONSTANT(DENOISER_DISABLED);
    BIND_ENUM_CONSTANT(DENOISER_SPEEX);
    BIND_ENUM_CONSTANT(DENOISER_RNNOISE);
    BIND_ENUM_CONSTANT(DENOISER_RNNOISE_DEFERRED);
    BIND_ENUM_CONSTANT(AGC_DISABLED);
    BIND_ENUM_CONSTANT(AGC_APPLIED);
    BIND_ENUM_CONSTANT(AGC_MONITOR);
    BIND_ENUM_CONSTANT(SIGNAL_AUTO);
    BIND_ENUM_CONSTANT(SIGNAL_VOICE);
    BIND_ENUM_CONSTANT(SIGNAL_MUSIC);
}

TwovoipOpusEncoder::TwovoipOpusEncoder() {}

void TwovoipOpusEncoder::destroy_audio_pipeline() {
    if (opus_encoder != NULL) {
        opus_encoder_destroy(opus_encoder);
        opus_encoder = NULL;
    }
    bitrate = 0;
    complexity = 0;
    signal_type = SIGNAL_AUTO;
    destroy_voice_processor();
    if (speex_resampler != NULL) {
        speex_resampler_destroy(speex_resampler);
        speex_resampler = NULL;
    }
    if (resampler_16khz != NULL) {
        speex_resampler_destroy(resampler_16khz);
        resampler_16khz = NULL;
    }
    mono_audio_frames.resize(0);
    prepared_audio_ringbuffer.resize(0);
    output_chunk_size = 0;
    required_input_chunk_size = 0;
    initialized = false;
}

void TwovoipOpusEncoder::destroy_voice_processor() {
    if (speex_denoiser != NULL) {
        speex_preprocess_state_destroy(speex_denoiser);
        speex_denoiser = NULL;
    }
    if (speex_agc != NULL) {
        speex_preprocess_state_destroy(speex_agc);
        speex_agc = NULL;
    }
#ifdef RNNOISE
    if (rnnoise_st != NULL) {
        rnnoise_destroy(rnnoise_st);
        rnnoise_st = NULL;
    }
    rnnoise_in.resize(0);
    rnnoise_out.resize(0);
#endif
    preprocess_frame_size = 0;
    speex_frame.clear();
    agc_gain = 1.0F;
}

Error TwovoipOpusEncoder::create_voice_processor() {
    destroy_voice_processor();
    if (denoiser_mode == DENOISER_DISABLED && agc_mode == AGC_DISABLED)
        return OK;
    if (output_chunk_size <= 0 || opus_sample_rate <= 0)
        return ERR_UNCONFIGURED;
    if (channels != 1) {
        UtilityFunctions::printerr("Denoising and automatic gain require mono audio");
        return ERR_UNAVAILABLE;
    }

    if (denoiser_mode == DENOISER_RNNOISE || denoiser_mode == DENOISER_RNNOISE_DEFERRED) {
#ifdef RNNOISE
        int frame_size = rnnoise_get_frame_size();
        if (opus_sample_rate != 48000 || output_chunk_size % frame_size != 0) {
            UtilityFunctions::printerr("RNNoise requires mono 48000 Hz audio and a chunk divisible by ", frame_size, " samples");
            return ERR_INVALID_PARAMETER;
        }
        rnnoise_st = rnnoise_create(NULL);
        if (rnnoise_st == NULL)
            return ERR_CANT_CREATE;
        rnnoise_in.resize(frame_size);
        rnnoise_out.resize(frame_size);
#else
        UtilityFunctions::printerr("This TwoVoIP build does not include RNNoise");
        return ERR_UNAVAILABLE;
#endif
    }

    if (denoiser_mode != DENOISER_SPEEX && agc_mode == AGC_DISABLED)
        return OK;

    int frame_20ms = opus_sample_rate / 50;
    int frame_10ms = opus_sample_rate / 100;
    if ((opus_sample_rate % 50) == 0 && frame_20ms > 0 && output_chunk_size >= frame_20ms && (output_chunk_size % frame_20ms) == 0)
        preprocess_frame_size = frame_20ms;
    else if ((opus_sample_rate % 100) == 0 && frame_10ms > 0 && output_chunk_size >= frame_10ms && (output_chunk_size % frame_10ms) == 0)
        preprocess_frame_size = frame_10ms;
    else {
        UtilityFunctions::printerr("Speex preprocessing requires a chunk divisible into 10 ms or 20 ms frames");
        return ERR_INVALID_PARAMETER;
    }

    if (denoiser_mode == DENOISER_SPEEX) {
        speex_denoiser = speex_preprocess_state_init(preprocess_frame_size, opus_sample_rate);
        if (speex_denoiser == NULL) {
            preprocess_frame_size = 0;
            return ERR_CANT_CREATE;
        }
        spx_int32_t enabled = 1;
        spx_int32_t disabled = 0;
        speex_preprocess_ctl(speex_denoiser, SPEEX_PREPROCESS_SET_DENOISE, &enabled);
        speex_preprocess_ctl(speex_denoiser, SPEEX_PREPROCESS_SET_AGC, &disabled);
    }
    if (agc_mode != AGC_DISABLED) {
        speex_agc = speex_preprocess_state_init(preprocess_frame_size, opus_sample_rate);
        if (speex_agc == NULL) {
            destroy_voice_processor();
            return ERR_CANT_CREATE;
        }
        spx_int32_t disabled = 0;
        spx_int32_t enabled = 1;
        speex_preprocess_ctl(speex_agc, SPEEX_PREPROCESS_SET_DENOISE, &disabled);
        speex_preprocess_ctl(speex_agc, SPEEX_PREPROCESS_SET_AGC, &enabled);
    }
    speex_frame.resize(preprocess_frame_size);
    return OK;
}

Error TwovoipOpusEncoder::initialize(int p_input_mix_rate, int p_opus_sample_rate, int p_channels, Denoiser p_denoiser_mode, AgcMode p_agc_mode, int p_output_chunk_size) {
    if (initialized) {
        UtilityFunctions::printerr("TwovoipOpusEncoder is already initialized");
        return ERR_ALREADY_IN_USE;
    }
    if (p_input_mix_rate <= 0 || !is_valid_opus_sample_rate(p_opus_sample_rate) ||
            !is_valid_opus_frame_size(p_opus_sample_rate, p_output_chunk_size) ||
            (p_channels != 1 && p_channels != 2) ||
            p_denoiser_mode < DENOISER_DISABLED || p_denoiser_mode > DENOISER_RNNOISE_DEFERRED ||
            p_agc_mode < AGC_DISABLED || p_agc_mode > AGC_MONITOR) {
        UtilityFunctions::printerr("Invalid audio pipeline configuration");
        return ERR_INVALID_PARAMETER;
    }
    destroy_audio_pipeline();

    input_mix_rate = p_input_mix_rate;
    opus_sample_rate = p_opus_sample_rate;
    channels = p_channels;
    denoiser_mode = p_denoiser_mode;
    agc_mode = p_agc_mode;
    if (input_mix_rate != opus_sample_rate) {
        int speexerror = 0;
        int resamplingquality = 4;
        speex_resampler = speex_resampler_init(channels, input_mix_rate, opus_sample_rate, resamplingquality, &speexerror);
        if (speex_resampler == NULL) {
            godot::UtilityFunctions::printerr("Speex resampler init failed code ", speexerror); 
            destroy_audio_pipeline();
            return ERR_CANT_CREATE;
        }
    }

    Error error = configure_output_chunk_size(p_output_chunk_size, (int)ceil(max_lead_time*opus_sample_rate/p_output_chunk_size) + 1);
    if (error != OK) {
        destroy_audio_pipeline();
        return error;
    }
    error = create_opus_encoder();
    if (error != OK) {
        destroy_audio_pipeline();
        return error;
    }
    initialized = true;
    return OK;
}

Error TwovoipOpusEncoder::configure_output_chunk_size(int p_output_chunk_size, int p_audio_ringbuffer_size_chunks) {
    if (p_output_chunk_size <= 0 || input_mix_rate <= 0 || opus_sample_rate <= 0 || p_audio_ringbuffer_size_chunks <= 0) {
        UtilityFunctions::printerr("Output chunk size and sample rates must be positive");
        return ERR_INVALID_PARAMETER;
    }
    output_chunk_size = p_output_chunk_size;
    required_input_chunk_size = static_cast<int>((static_cast<int64_t>(output_chunk_size) * input_mix_rate + opus_sample_rate - 1) / opus_sample_rate);

    audio_ringbuffer_size_chunks = p_audio_ringbuffer_size_chunks;
    audio_ringbuffer_index = 0;
    prepared_audio_ringbuffer.resize(output_chunk_size * channels * p_audio_ringbuffer_size_chunks);

    Error error = create_voice_processor();
    if (error != OK)
        return error;
    return OK;
}

void TwovoipOpusEncoder::set_gain(float p_gain) {
    if (!std::isfinite(p_gain) || p_gain < 0.0F) {
        UtilityFunctions::printerr("Gain must be a finite value greater than or equal to zero");
        return;
    }
    gain = p_gain;
}

void TwovoipOpusEncoder::update_agc_gain() {
    spx_int32_t gain_db = 0;
    speex_preprocess_ctl(speex_agc, SPEEX_PREPROCESS_GET_AGC_GAIN, &gain_db);
    agc_gain = std::pow(10.0F, static_cast<float>(gain_db) / 20.0F);
}

Error TwovoipOpusEncoder::target_agc_gain(float p_target_gain) {
    if (!initialized)
        return ERR_UNCONFIGURED;
    if (speex_agc == NULL)
        return ERR_UNAVAILABLE;
    if (!std::isfinite(p_target_gain) || p_target_gain < 1.0F)
        return ERR_INVALID_PARAMETER;

    spx_int32_t max_gain_db = 0;
    speex_preprocess_ctl(speex_agc, SPEEX_PREPROCESS_GET_AGC_MAX_GAIN, &max_gain_db);
    const float max_gain = std::pow(10.0F, static_cast<float>(max_gain_db) / 20.0F);
    if (p_target_gain > max_gain)
        return ERR_INVALID_PARAMETER;

    const double tau = 6.283185307179586;
    const int max_frames = 10 * opus_sample_rate / preprocess_frame_size;
    int64_t sample_index = 0;
    for (int processed_frames = 0; agc_gain < p_target_gain && processed_frames < max_frames; processed_frames++) {
        for (int frame = 0; frame < preprocess_frame_size; frame++, sample_index++) {
            const double time = static_cast<double>(sample_index) / opus_sample_rate;
            const double pitch = 105.0 + 20.0 * std::sin(tau * time / 0.3);
            const double phase = tau * pitch * time;
            const double voice = 0.0005 * (0.6 * std::sin(phase) + 0.3 * std::sin(2.0 * phase) + 0.1 * std::sin(3.0 * phase));
            speex_frame[frame] = static_cast<spx_int16_t>(std::round(voice * 32767.0));
        }
        speex_preprocess_run(speex_agc, speex_frame.data());
        update_agc_gain();
    }
    if (agc_gain < p_target_gain)
        return ERR_TIMEOUT;

    // Speex overlaps a whole preprocessing frame. Three discarded silent frames
    // clear its saved analysis input and output tail before real microphone audio.
    std::fill(speex_frame.begin(), speex_frame.end(), 0);
    for (int frame = 0; frame < 3; frame++)
        speex_preprocess_run(speex_agc, speex_frame.data());
    update_agc_gain();
    return OK;
}

Error TwovoipOpusEncoder::create_opus_encoder() {
    int opuserror = 0;
    OpusEncoder *new_encoder = opus_encoder_create(opus_sample_rate, channels, OPUS_APPLICATION_VOIP, &opuserror);
    if (new_encoder == NULL || opuserror != OPUS_OK) {
        godot::UtilityFunctions::printerr("opus_encoder_create error ", opuserror);
        return ERR_CANT_CREATE;
    }

    int new_bitrate = 0;
    int new_complexity = 0;
    int new_signal_type = OPUS_AUTO;
    opuserror = opus_encoder_ctl(new_encoder, OPUS_GET_BITRATE(&new_bitrate));
    if (opuserror == OPUS_OK) {
        opuserror = opus_encoder_ctl(new_encoder, OPUS_GET_COMPLEXITY(&new_complexity));
    }
    if (opuserror == OPUS_OK) {
        opuserror = opus_encoder_ctl(new_encoder, OPUS_GET_SIGNAL(&new_signal_type));
    }
    if (opuserror != OPUS_OK) {
        godot::UtilityFunctions::printerr("Could not read initial Opus encoder settings: ", opuserror);
        opus_encoder_destroy(new_encoder);
        return ERR_CANT_CREATE;
    }

    opus_encoder = new_encoder;
    bitrate = new_bitrate;
    complexity = new_complexity;
    signal_type = new_signal_type == OPUS_SIGNAL_VOICE ? SIGNAL_VOICE :
            (new_signal_type == OPUS_SIGNAL_MUSIC ? SIGNAL_MUSIC : SIGNAL_AUTO);
    return OK;
}

Error TwovoipOpusEncoder::set_bitrate(int p_bitrate) {
    if (!initialized || opus_encoder == NULL) {
        return ERR_UNCONFIGURED;
    }
    if (p_bitrate < 500 || p_bitrate > 512000) {
        return ERR_INVALID_PARAMETER;
    }
    const int opuserror = opus_encoder_ctl(opus_encoder, OPUS_SET_BITRATE(p_bitrate));
    if (opuserror != OPUS_OK) {
        UtilityFunctions::printerr("opus_encoder_ctl bitrate error ", opuserror);
        return ERR_INVALID_PARAMETER;
    }
    bitrate = p_bitrate;
    return OK;
}

Error TwovoipOpusEncoder::set_complexity(int p_complexity) {
    if (!initialized || opus_encoder == NULL) {
        return ERR_UNCONFIGURED;
    }
    if (p_complexity < 0 || p_complexity > 10) {
        return ERR_INVALID_PARAMETER;
    }
    const int opuserror = opus_encoder_ctl(opus_encoder, OPUS_SET_COMPLEXITY(p_complexity));
    if (opuserror != OPUS_OK) {
        UtilityFunctions::printerr("opus_encoder_ctl complexity error ", opuserror);
        return ERR_INVALID_PARAMETER;
    }
    complexity = p_complexity;
    return OK;
}

Error TwovoipOpusEncoder::set_signal_type(SignalType p_signal_type) {
    if (!initialized || opus_encoder == NULL) {
        return ERR_UNCONFIGURED;
    }
    const int opus_signal_type = get_opus_signal_type(p_signal_type);
    if (opus_signal_type == 0) {
        return ERR_INVALID_PARAMETER;
    }
    const int opuserror = opus_encoder_ctl(opus_encoder, OPUS_SET_SIGNAL(opus_signal_type));
    if (opuserror != OPUS_OK) {
        UtilityFunctions::printerr("opus_encoder_ctl signal type error ", opuserror);
        return ERR_INVALID_PARAMETER;
    }
    signal_type = p_signal_type;
    return OK;
}

void TwovoipOpusEncoder::reset_opus_encoder() {
    if (opus_encoder != NULL) 
        opus_encoder_ctl(opus_encoder, OPUS_RESET_STATE);
}

int TwovoipOpusEncoder::process_chunk(const PackedVector2Array &audio_frames) {
    int consumed_input_frames = 0;
    last_peak = 0.0F;
    last_rms = 0.0F;
    last_speech_probability = 0.0F;
    if (!initialized) {
        UtilityFunctions::printerr("TwovoipOpusEncoder not initialized");
        return -1;
    }
    if (audio_frames.size() < required_input_chunk_size) {
        UtilityFunctions::printerr("Process_chunk audio_frames is too short: expected at least ", required_input_chunk_size, ", got ", audio_frames.size());
        return -1;
    }

    const float* speexin;
    if (channels == 1) {
        if (mono_audio_frames.size() != required_input_chunk_size)
            mono_audio_frames.resize(required_input_chunk_size);
        for (int i = 0; i < required_input_chunk_size; i++) {
            mono_audio_frames[i] = (audio_frames[i].x + audio_frames[i].y)*0.5;
        }
        speexin = (const float*)mono_audio_frames.ptr();
    } else {
        speexin = (const float*)audio_frames.ptr();
    }

    audio_ringbuffer_index++;
    float* prepared_audio_chunk = (float*)prepared_audio_ringbuffer.ptrw() + (audio_ringbuffer_index % audio_ringbuffer_size_chunks) * output_chunk_size * channels;

    if (speex_resampler != NULL) {
        unsigned int input_frames = required_input_chunk_size;
        unsigned int output_frames = output_chunk_size;
        int sxerr = speex_resampler_process_interleaved_float(speex_resampler, 
                                                              speexin, &input_frames,
                                                              prepared_audio_chunk, &output_frames);
        if (sxerr != RESAMPLER_ERR_SUCCESS || output_frames != static_cast<unsigned int>(output_chunk_size)) {
            UtilityFunctions::printerr("Speex resampling failed: error ", sxerr, ", produced ", output_frames, " of ", output_chunk_size, " frames");
            return -2;
        }
        consumed_input_frames = input_frames;
    } else if (required_input_chunk_size == output_chunk_size) {
        memcpy(prepared_audio_chunk, (const float*)speexin, output_chunk_size*channels*sizeof(float));
        consumed_input_frames = output_chunk_size;
    } else {
        UtilityFunctions::printerr("No resampler is available for differing input and output chunk sizes");
        return -2;
    }

    if (speex_agc != NULL) {
        for (int offset = 0; offset < output_chunk_size; offset += preprocess_frame_size) {
            for (int frame = 0; frame < preprocess_frame_size; frame++) {
                float sample = std::clamp(prepared_audio_chunk[offset + frame], -1.0F, 1.0F);
                speex_frame[frame] = static_cast<spx_int16_t>(std::round(sample * 32767.0F));
            }
            speex_preprocess_run(speex_agc, speex_frame.data());
            if (agc_mode == AGC_APPLIED) {
                for (int frame = 0; frame < preprocess_frame_size; frame++)
                    prepared_audio_chunk[offset + frame] = speex_frame[frame] / 32768.0F;
            }
            update_agc_gain();
        }
    }

    // apply fixed gain and measure peaks
    float sum_squares = 0.0F;
    for (int i = 0; i < output_chunk_size*channels; i++) {
        float sample = prepared_audio_chunk[i] * gain;
        prepared_audio_chunk[i] = sample;
        last_peak = std::max(last_peak, std::abs(sample));
        sum_squares += sample * sample;
    }
    last_rms = std::sqrt(sum_squares / (output_chunk_size*channels));

    return consumed_input_frames;
}

Error TwovoipOpusEncoder::denoise_chunk(int p_chunk_offset_back) {
    if (!initialized)
        return ERR_UNCONFIGURED;
    if (audio_ringbuffer_index == 0)
        return ERR_UNAVAILABLE;
    const int available_chunks_back = std::min(audio_ringbuffer_index - 1, audio_ringbuffer_size_chunks - 1);
    if (p_chunk_offset_back < 0 || p_chunk_offset_back > available_chunks_back)
        return ERR_INVALID_PARAMETER;
    float* prepared_audio_chunk = prepared_audio_ringbuffer.ptrw() +
            (audio_ringbuffer_index - p_chunk_offset_back) % audio_ringbuffer_size_chunks * output_chunk_size;
    last_speech_probability = 0.0F;

#ifdef RNNOISE
    if (rnnoise_st != NULL) {
        int nnoisechunks = (int)(output_chunk_size/rnnoise_get_frame_size());
        for (int j = 0; j < nnoisechunks; j++) {
            for (int i = 0; i < rnnoise_get_frame_size(); i++) {
                int k = j*rnnoise_get_frame_size() + i;
                rnnoise_in[i] = std::clamp(prepared_audio_chunk[k], -1.0F, 1.0F)*32768.0F;
            }
            float speech_prob = rnnoise_process_frame(rnnoise_st, (float*)rnnoise_out.ptr(), (float*)rnnoise_in.ptrw());
            last_speech_probability = std::max(last_speech_probability, speech_prob);
            for (int i = 0; i < rnnoise_get_frame_size(); i++) {
                int k = j*rnnoise_get_frame_size() + i;
                prepared_audio_chunk[k] = rnnoise_out[i]/32768.0F;
            }
        }
    }
#endif

    if (speex_denoiser != NULL) {
        for (int offset = 0; offset < output_chunk_size; offset += preprocess_frame_size) {
            for (int frame = 0; frame < preprocess_frame_size; frame++) {
                float sample = std::clamp(prepared_audio_chunk[offset + frame], -1.0F, 1.0F);
                speex_frame[frame] = static_cast<spx_int16_t>(std::round(sample * 32767.0F));
            }
            speex_preprocess_run(speex_denoiser, speex_frame.data());
            spx_int32_t speech_percent = 0;
            speex_preprocess_ctl(speex_denoiser, SPEEX_PREPROCESS_GET_PROB, &speech_percent);
            last_speech_probability = std::max(last_speech_probability, speech_percent / 100.0F);
            for (int frame = 0; frame < preprocess_frame_size; frame++)
                prepared_audio_chunk[offset + frame] = speex_frame[frame] / 32768.0F;
        }
    }
    return OK;
}

PackedVector2Array TwovoipOpusEncoder::get_current_chunk() const {
    PackedVector2Array frames;
    const float* prepared_audio_chunk = (const float*)prepared_audio_ringbuffer.ptr() + (audio_ringbuffer_index % audio_ringbuffer_size_chunks) * output_chunk_size * channels;
    frames.resize(output_chunk_size);
    for (int frame = 0; frame < output_chunk_size; frame++) {
        if (channels == 1) {
            float sample = prepared_audio_chunk[frame];
            frames.set(frame, Vector2(sample, sample));
        } else {
            int index = frame * 2;
            frames.set(frame, Vector2(prepared_audio_chunk[index], prepared_audio_chunk[index + 1]));
        }
    }
    return frames;
}

PackedFloat32Array TwovoipOpusEncoder::get_current_chunk_16khz(bool p_reset_sampler) {
    PackedFloat32Array output_16khz;
    if (!initialized) {
        UtilityFunctions::printerr("TwovoipOpusEncoder not initialized");
        return output_16khz;
    }

    int64_t output_size_numerator = static_cast<int64_t>(output_chunk_size) * 16000;
    if (output_size_numerator % opus_sample_rate != 0) {
        UtilityFunctions::printerr("The current chunk duration does not contain a whole number of 16 kHz samples");
        return output_16khz;
    }

    PackedVector2Array current_chunk = get_current_chunk();
    PackedFloat32Array mono_chunk;
    mono_chunk.resize(current_chunk.size());
    for (int frame = 0; frame < current_chunk.size(); frame++)
        mono_chunk[frame] = (current_chunk[frame].x + current_chunk[frame].y) * 0.5F;

    int output_size = static_cast<int>(output_size_numerator / opus_sample_rate);
    output_16khz.resize(output_size);
    if (opus_sample_rate == 16000) {
        memcpy(output_16khz.ptrw(), mono_chunk.ptr(), output_size * sizeof(float));
        return output_16khz;
    }

    if (resampler_16khz == NULL) {
        int speexerror = 0;
        resampler_16khz = speex_resampler_init(1, opus_sample_rate, 16000, 10, &speexerror);
        if (resampler_16khz == NULL) {
            UtilityFunctions::printerr("16 kHz Speex resampler init failed code ", speexerror);
            output_16khz.resize(0);
            return output_16khz;
        }
    } else if (p_reset_sampler) {
        speex_resampler_reset_mem(resampler_16khz);
    }

    unsigned int input_frames = mono_chunk.size();
    unsigned int output_frames = output_16khz.size();
    int error = speex_resampler_process_float(resampler_16khz, 0,
            mono_chunk.ptr(), &input_frames, output_16khz.ptrw(), &output_frames);
    if (error != RESAMPLER_ERR_SUCCESS || input_frames != static_cast<unsigned int>(mono_chunk.size()) ||
            output_frames != static_cast<unsigned int>(output_16khz.size())) {
        UtilityFunctions::printerr("16 kHz resampling failed: error ", error, ", consumed ", input_frames,
                " of ", mono_chunk.size(), ", produced ", output_frames, " of ", output_16khz.size());
        output_16khz.resize(0);
    }
    return output_16khz;
}

PackedByteArray TwovoipOpusEncoder::encode_chunk(const PackedByteArray& prefix_bytes, int chunk_offset_back) {
    if (opus_encoder == NULL) {
        godot::UtilityFunctions::printerr("Error: opusencoder is null");
        return PackedByteArray();
    }
    if (chunk_offset_back < 0) {
        UtilityFunctions::printerr("chunk_offset_back must be positive or zero");
        return PackedByteArray();
    }

    float* prepared_audio_chunk = (float*)prepared_audio_ringbuffer.ptrw() + \
        (std::max(audio_ringbuffer_index - chunk_offset_back, 0) % audio_ringbuffer_size_chunks)*output_chunk_size*channels;

    int max_opus_byte_buffer = prefix_bytes.size() + 4*output_chunk_size*channels;
    if (max_opus_byte_buffer > opus_byte_buffer.size())
        opus_byte_buffer.resize(max_opus_byte_buffer);
    

    unsigned char* popus_bytes = opus_byte_buffer.ptrw();
    int nprefbytes = prefix_bytes.size();
    if (nprefbytes != 0) 
        memcpy(popus_bytes, prefix_bytes.ptr(), nprefbytes); 
    int bytepacketsize = opus_encode_float(opus_encoder, (const float*)prepared_audio_chunk, output_chunk_size,
                                           opus_byte_buffer.ptrw() + nprefbytes, max_opus_byte_buffer - nprefbytes);
    if (bytepacketsize < 0) {
        UtilityFunctions::printerr("Opus encoding failed: ", opus_strerror(bytepacketsize), " (", bytepacketsize, ")");
        return PackedByteArray();
    }
    return opus_byte_buffer.slice(0, nprefbytes + bytepacketsize);
}
    

TwovoipOpusEncoder::~TwovoipOpusEncoder() {
    destroy_audio_pipeline();
}
