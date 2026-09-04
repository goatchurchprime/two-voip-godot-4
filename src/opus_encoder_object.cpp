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

void TwovoipOpusEncoder::_bind_methods() {
    ClassDB::bind_method(D_METHOD("create_sampler", "input_mix_rate", "opus_sample_rate", "channels", "denoiser", "agc_mode", "output_chunk_size"), &TwovoipOpusEncoder::create_sampler);
    ClassDB::bind_method(D_METHOD("set_output_chunk_size", "output_chunk_size"), &TwovoipOpusEncoder::set_output_chunk_size);
    ClassDB::bind_method(D_METHOD("get_output_chunk_size"), &TwovoipOpusEncoder::get_output_chunk_size);
    ClassDB::bind_method(D_METHOD("get_required_input_chunk_size"), &TwovoipOpusEncoder::get_required_input_chunk_size);
    ClassDB::bind_method(D_METHOD("process_chunk", "audio_frames"), &TwovoipOpusEncoder::process_chunk);
    ClassDB::bind_method(D_METHOD("get_peak"), &TwovoipOpusEncoder::get_peak);
    ClassDB::bind_method(D_METHOD("get_rms"), &TwovoipOpusEncoder::get_rms);
    ClassDB::bind_method(D_METHOD("get_speech_probability"), &TwovoipOpusEncoder::get_speech_probability);
    ClassDB::bind_method(D_METHOD("get_current_chunk_16khz"), &TwovoipOpusEncoder::get_current_chunk_16khz);
    ClassDB::bind_method(D_METHOD("set_gain", "gain"), &TwovoipOpusEncoder::set_gain);
    ClassDB::bind_method(D_METHOD("get_gain"), &TwovoipOpusEncoder::get_gain);
    ClassDB::bind_method(D_METHOD("get_agc_gain"), &TwovoipOpusEncoder::get_agc_gain);
    ClassDB::bind_method(D_METHOD("get_denoiser"), &TwovoipOpusEncoder::get_denoiser);
    ClassDB::bind_method(D_METHOD("get_agc_mode"), &TwovoipOpusEncoder::get_agc_mode);
    ClassDB::bind_method(D_METHOD("create_opus_encoder", "bit_rate", "complexity", "voice_optimal"), &TwovoipOpusEncoder::create_opus_encoder);
    ClassDB::bind_method(D_METHOD("reset_opus_encoder"), &TwovoipOpusEncoder::reset_opus_encoder);
    ClassDB::bind_method(D_METHOD("calc_audio_chunk_size", "opus_chunk_size"), &TwovoipOpusEncoder::calc_audio_chunk_size);
    ClassDB::bind_method(D_METHOD("process_pre_encoded_chunk", "audio_frames", "opus_chunk_size", "speech_probability", "rms"), &TwovoipOpusEncoder::process_pre_encoded_chunk);
    ClassDB::bind_method(D_METHOD("encode_chunk", "prefix_bytes"), &TwovoipOpusEncoder::encode_chunk, DEFVAL(PackedByteArray()));

    uint32_t read_only = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY;
    ADD_PROPERTY(PropertyInfo(Variant::INT, "output_chunk_size", PROPERTY_HINT_NONE, "", read_only), "", "get_output_chunk_size");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "required_input_chunk_size", PROPERTY_HINT_NONE, "", read_only), "", "get_required_input_chunk_size");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "gain", PROPERTY_HINT_NONE, "", read_only), "", "get_gain");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "agc_gain", PROPERTY_HINT_NONE, "", read_only), "", "get_agc_gain");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "denoiser", PROPERTY_HINT_ENUM, "Disabled,Speex,RNNoise", read_only), "", "get_denoiser");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "agc_mode", PROPERTY_HINT_ENUM, "Disabled,Applied,Monitor", read_only), "", "get_agc_mode");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "peak", PROPERTY_HINT_NONE, "", read_only), "", "get_peak");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "rms", PROPERTY_HINT_NONE, "", read_only), "", "get_rms");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "speech_probability", PROPERTY_HINT_NONE, "", read_only), "", "get_speech_probability");
    ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT32_ARRAY, "current_chunk_16khz", PROPERTY_HINT_NONE, "", read_only), "", "get_current_chunk_16khz");

    BIND_ENUM_CONSTANT(DENOISER_DISABLED);
    BIND_ENUM_CONSTANT(DENOISER_SPEEX);
    BIND_ENUM_CONSTANT(DENOISER_RNNOISE);
    BIND_ENUM_CONSTANT(AGC_DISABLED);
    BIND_ENUM_CONSTANT(AGC_APPLIED);
    BIND_ENUM_CONSTANT(AGC_MONITOR);
}

TwovoipOpusEncoder::TwovoipOpusEncoder() {}

void TwovoipOpusEncoder::destroy_voice_processor() {
    if (speex_preprocessor != NULL) {
        speex_preprocess_state_destroy(speex_preprocessor);
        speex_preprocessor = NULL;
    }
    if (speex_agc_monitor != NULL) {
        speex_preprocess_state_destroy(speex_agc_monitor);
        speex_agc_monitor = NULL;
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
    if (denoiser == DENOISER_DISABLED && agc_mode == AGC_DISABLED)
        return OK;
    if (output_chunk_size <= 0 || opus_sample_rate <= 0)
        return ERR_UNCONFIGURED;
    if (channels != 1) {
        UtilityFunctions::printerr("Denoising and automatic gain require mono audio");
        return ERR_UNAVAILABLE;
    }

    if (denoiser == DENOISER_RNNOISE) {
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

    if (denoiser != DENOISER_SPEEX && agc_mode == AGC_DISABLED)
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

    if (denoiser == DENOISER_SPEEX || agc_mode == AGC_APPLIED) {
        speex_preprocessor = speex_preprocess_state_init(preprocess_frame_size, opus_sample_rate);
        if (speex_preprocessor == NULL) {
            preprocess_frame_size = 0;
            return ERR_CANT_CREATE;
        }
        spx_int32_t denoise_enabled = denoiser == DENOISER_SPEEX;
        spx_int32_t agc_enabled = agc_mode == AGC_APPLIED;
        speex_preprocess_ctl(speex_preprocessor, SPEEX_PREPROCESS_SET_DENOISE, &denoise_enabled);
        speex_preprocess_ctl(speex_preprocessor, SPEEX_PREPROCESS_SET_AGC, &agc_enabled);
    }
    if (agc_mode == AGC_MONITOR) {
        speex_agc_monitor = speex_preprocess_state_init(preprocess_frame_size, opus_sample_rate);
        if (speex_agc_monitor == NULL) {
            destroy_voice_processor();
            return ERR_CANT_CREATE;
        }
        spx_int32_t disabled = 0;
        spx_int32_t enabled = 1;
        speex_preprocess_ctl(speex_agc_monitor, SPEEX_PREPROCESS_SET_DENOISE, &disabled);
        speex_preprocess_ctl(speex_agc_monitor, SPEEX_PREPROCESS_SET_AGC, &enabled);
    }
    speex_frame.resize(preprocess_frame_size);
    return OK;
}

Error TwovoipOpusEncoder::create_sampler(int p_input_mix_rate, int p_opus_sample_rate, int p_channels, Denoiser p_denoiser, AgcMode p_agc_mode, int p_output_chunk_size) {
    if (p_input_mix_rate <= 0 || p_opus_sample_rate <= 0 || (p_channels != 1 && p_channels != 2) ||
            p_denoiser < DENOISER_DISABLED || p_denoiser > DENOISER_RNNOISE ||
            p_agc_mode < AGC_DISABLED || p_agc_mode > AGC_MONITOR) {
        UtilityFunctions::printerr("Invalid sampler configuration");
        return ERR_INVALID_PARAMETER;
    }
    destroy_voice_processor();
    output_chunk_size = 0;
    required_input_chunk_size = 0;
    input_mix_rate = p_input_mix_rate;
    opus_sample_rate = p_opus_sample_rate;
    channels = p_channels;
    denoiser = p_denoiser;
    agc_mode = p_agc_mode;
    if (speex_resampler != NULL) {
        speex_resampler_destroy(speex_resampler);
        speex_resampler = NULL;
    }
    if (resampler_16khz != NULL) {
        speex_resampler_destroy(resampler_16khz);
        resampler_16khz = NULL;
    }
    current_chunk_16khz.resize(0);
    chunk_size_16khz = 0;
    if (input_mix_rate != opus_sample_rate) {
        int speexerror = 0; 
        int resamplingquality = 10;
        speex_resampler = speex_resampler_init(channels, input_mix_rate, opus_sample_rate, resamplingquality, &speexerror);
        if (speex_resampler == NULL) {
            godot::UtilityFunctions::printerr("Speex resampler init failed code ", speexerror); 
            return ERR_CANT_CREATE;
        }
    }
    return configure_output_chunk_size(p_output_chunk_size);
}

Error TwovoipOpusEncoder::configure_output_chunk_size(int p_output_chunk_size) {
    if (p_output_chunk_size <= 0 || input_mix_rate <= 0 || opus_sample_rate <= 0) {
        UtilityFunctions::printerr("Output chunk size and sample rates must be positive");
        return ERR_INVALID_PARAMETER;
    }
    if (output_chunk_size == p_output_chunk_size)
        return OK;
    int previous_output_chunk_size = output_chunk_size;
    int previous_required_input_chunk_size = required_input_chunk_size;
    output_chunk_size = p_output_chunk_size;
    required_input_chunk_size = static_cast<int>((static_cast<int64_t>(output_chunk_size) * input_mix_rate + opus_sample_rate - 1) / opus_sample_rate);
    pre_encoded_chunk.resize(output_chunk_size * channels);
    Error error = create_voice_processor();
    if (error != OK) {
        output_chunk_size = previous_output_chunk_size;
        required_input_chunk_size = previous_required_input_chunk_size;
        pre_encoded_chunk.resize(output_chunk_size * channels);
        create_voice_processor();
        return error;
    }
    error = configure_16khz_output();
    if (error != OK)
        return error;
    return OK;
}

Error TwovoipOpusEncoder::configure_16khz_output() {
    if (resampler_16khz != NULL) {
        speex_resampler_destroy(resampler_16khz);
        resampler_16khz = NULL;
    }
    current_chunk_16khz.resize(0);
    chunk_size_16khz = 0;
    if ((static_cast<int64_t>(output_chunk_size) * 16000) % opus_sample_rate != 0) {
        UtilityFunctions::printerr("The configured chunk duration does not contain a whole number of 16 kHz samples");
        return ERR_INVALID_PARAMETER;
    }
    chunk_size_16khz = static_cast<int>(static_cast<int64_t>(output_chunk_size) * 16000 / opus_sample_rate);
    mono_output_chunk.resize(output_chunk_size);
    if (opus_sample_rate == 16000)
        return OK;
    int speexerror = 0;
    resampler_16khz = speex_resampler_init(1, opus_sample_rate, 16000, 10, &speexerror);
    if (resampler_16khz == NULL) {
        UtilityFunctions::printerr("16 kHz Speex resampler init failed code ", speexerror);
        chunk_size_16khz = 0;
        return ERR_CANT_CREATE;
    }
    return OK;
}

bool TwovoipOpusEncoder::set_output_chunk_size(int p_output_chunk_size) {
    UtilityFunctions::push_warning("set_output_chunk_size() is deprecated; pass output_chunk_size to create_sampler()");
    return configure_output_chunk_size(p_output_chunk_size) == OK;
}

void TwovoipOpusEncoder::set_gain(float p_gain) {
    if (!std::isfinite(p_gain) || p_gain < 0.0F) {
        UtilityFunctions::printerr("Gain must be a finite value greater than or equal to zero");
        return;
    }
    gain = p_gain;
}

bool TwovoipOpusEncoder::create_opus_encoder(int bit_rate, int complexity, bool voice_optimal) {
    if (opus_encoder != NULL) {
        opus_encoder_destroy(opus_encoder);
        opus_encoder = NULL;
    }

    int opus_application = OPUS_APPLICATION_VOIP; // this option includes in-band forward error correction
    int signal_type = (voice_optimal ? OPUS_SIGNAL_VOICE : OPUS_SIGNAL_MUSIC);
    int opuserror = 0;
    // opussamplerate is one of 8000,12000,16000,24000,48000
    opus_encoder = opus_encoder_create(opus_sample_rate, channels, opus_application, &opuserror);
    if (opuserror != 0) {
        godot::UtilityFunctions::printerr("opus_encoder_create error ", opuserror);
        opus_encoder = NULL;
        return false;
    }
    opuserror = opus_encoder_ctl(opus_encoder, OPUS_SET_SIGNAL(signal_type));
    if (opuserror != 0) {
        godot::UtilityFunctions::printerr("opus_encoder_ctl signal_type error ", opuserror);
    }
    opuserror = opus_encoder_ctl(opus_encoder, OPUS_SET_BITRATE(bit_rate));
    if (opuserror != 0) {
        godot::UtilityFunctions::printerr("opus_encoder_ctl bit_rate error ", opuserror);
    }
    opuserror = opus_encoder_ctl(opus_encoder, OPUS_SET_COMPLEXITY(complexity));
    if (opuserror != 0) {
        godot::UtilityFunctions::printerr("opus_encoder_ctl complexity error ", opuserror);
    }
    return true;
}

void TwovoipOpusEncoder::reset_opus_encoder() {
    if (opus_encoder != NULL) 
        opus_encoder_ctl(opus_encoder, OPUS_RESET_STATE);
}

int TwovoipOpusEncoder::calc_audio_chunk_size(int opus_chunk_size) {
    if (!legacy_processing_warning_printed) {
        UtilityFunctions::push_warning("calc_audio_chunk_size() and process_pre_encoded_chunk() are deprecated; configure the output chunk once and use get_required_input_chunk_size() with process_chunk()");
        legacy_processing_warning_printed = true;
    }
    if (opus_chunk_size <= 0 || input_mix_rate <= 0 || opus_sample_rate <= 0)
        return 0;
    return static_cast<int>((static_cast<int64_t>(opus_chunk_size) * input_mix_rate + opus_sample_rate - 1) / opus_sample_rate);
}

int TwovoipOpusEncoder::process_chunk_internal(const PackedVector2Array &audio_frames) {
    int consumed_input_frames = 0;
    last_peak = 0.0F;
    last_rms = 0.0F;
    last_speech_probability = 0.0F;
    current_chunk_16khz.resize(0);
    if (output_chunk_size <= 0 || required_input_chunk_size <= 0) {
        UtilityFunctions::printerr("Pass output_chunk_size to create_sampler() before process_chunk()");
        return -1;
    }
    if (audio_frames.size() < required_input_chunk_size) {
        UtilityFunctions::printerr("Audio chunk is too short: expected at least ", required_input_chunk_size, ", got ", audio_frames.size());
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
    if (speex_resampler != NULL) {
        unsigned int input_frames = required_input_chunk_size;
        unsigned int output_frames = output_chunk_size;
        int sxerr = speex_resampler_process_interleaved_float(speex_resampler, 
                                                              speexin, &input_frames,
                                                              (float*)pre_encoded_chunk.ptrw(), &output_frames);
        if (sxerr != RESAMPLER_ERR_SUCCESS || output_frames != static_cast<unsigned int>(output_chunk_size)) {
            UtilityFunctions::printerr("Speex resampling failed: error ", sxerr, ", produced ", output_frames, " of ", output_chunk_size, " frames");
            return -2;
        }
        consumed_input_frames = input_frames;
    } else if (required_input_chunk_size == output_chunk_size) {
        memcpy((float*)pre_encoded_chunk.ptrw(), (const float*)speexin, output_chunk_size*sizeof(float)*channels);
        consumed_input_frames = output_chunk_size;
    } else {
        UtilityFunctions::printerr("No resampler is available for differing input and output chunk sizes");
        return -2;
    }
    
    process_voice();
    apply_manual_gain();
    if (update_current_chunk_16khz() != OK)
        return -3;
    update_measurements();
    return consumed_input_frames;
}

void TwovoipOpusEncoder::process_voice() {
#ifdef RNNOISE
    if (rnnoise_st != NULL) {
        int nnoisechunks = (int)(output_chunk_size/rnnoise_get_frame_size());
        for (int j = 0; j < nnoisechunks; j++) {
            for (int i = 0; i < rnnoise_get_frame_size(); i++) {
                int k = j*rnnoise_get_frame_size() + i;
                rnnoise_in[i] = pre_encoded_chunk[k]*32768.0F;
            }
            float speech_prob = rnnoise_process_frame(rnnoise_st, (float*)rnnoise_out.ptr(), (float*)rnnoise_in.ptrw());
            last_speech_probability = std::max(last_speech_probability, speech_prob);
            for (int i = 0; i < rnnoise_get_frame_size(); i++) {
                int k = j*rnnoise_get_frame_size() + i;
                pre_encoded_chunk[k] = rnnoise_out[i]/32768.0F;
            }
        }
    }
#endif

    if (speex_preprocessor == NULL && speex_agc_monitor == NULL)
        return;

    for (int offset = 0; offset < output_chunk_size; offset += preprocess_frame_size) {
        if (speex_preprocessor != NULL) {
            for (int frame = 0; frame < preprocess_frame_size; frame++) {
                float sample = std::clamp(pre_encoded_chunk[offset + frame], -1.0F, 1.0F);
                speex_frame[frame] = static_cast<spx_int16_t>(std::round(sample * 32767.0F));
            }
            speex_preprocess_run(speex_preprocessor, speex_frame.data());
            if (denoiser == DENOISER_SPEEX) {
                spx_int32_t speech_percent = 0;
                speex_preprocess_ctl(speex_preprocessor, SPEEX_PREPROCESS_GET_PROB, &speech_percent);
                last_speech_probability = std::max(last_speech_probability, speech_percent / 100.0F);
            }
            for (int frame = 0; frame < preprocess_frame_size; frame++)
                pre_encoded_chunk[offset + frame] = speex_frame[frame] / 32768.0F;
        }
        if (speex_agc_monitor != NULL) {
            for (int frame = 0; frame < preprocess_frame_size; frame++) {
                float sample = std::clamp(pre_encoded_chunk[offset + frame], -1.0F, 1.0F);
                speex_frame[frame] = static_cast<spx_int16_t>(std::round(sample * 32767.0F));
            }
            speex_preprocess_run(speex_agc_monitor, speex_frame.data());
        }
        if (agc_mode != AGC_DISABLED) {
            spx_int32_t gain_db = 0;
            SpeexPreprocessState* agc_state = agc_mode == AGC_APPLIED ? speex_preprocessor : speex_agc_monitor;
            speex_preprocess_ctl(agc_state, SPEEX_PREPROCESS_GET_AGC_GAIN, &gain_db);
            agc_gain = std::pow(10.0F, static_cast<float>(gain_db) / 20.0F);
        }
    }
}

void TwovoipOpusEncoder::apply_manual_gain() {
    for (int i = 0; i < pre_encoded_chunk.size(); i++)
        pre_encoded_chunk[i] *= gain;
}

Error TwovoipOpusEncoder::update_current_chunk_16khz() {
    current_chunk_16khz.resize(chunk_size_16khz);
    for (int frame = 0; frame < output_chunk_size; frame++) {
        int index = frame * channels;
        mono_output_chunk[frame] = channels == 1 ? pre_encoded_chunk[index] :
                (pre_encoded_chunk[index] + pre_encoded_chunk[index + 1]) * 0.5F;
    }
    if (resampler_16khz == NULL) {
        memcpy(current_chunk_16khz.ptrw(), mono_output_chunk.ptr(), output_chunk_size * sizeof(float));
        return OK;
    }
    unsigned int input_frames = output_chunk_size;
    unsigned int output_frames = current_chunk_16khz.size();
    int error = speex_resampler_process_float(resampler_16khz, 0,
            mono_output_chunk.ptr(), &input_frames, current_chunk_16khz.ptrw(), &output_frames);
    if (error != RESAMPLER_ERR_SUCCESS || input_frames != static_cast<unsigned int>(output_chunk_size) ||
            output_frames != static_cast<unsigned int>(current_chunk_16khz.size())) {
        UtilityFunctions::printerr("16 kHz resampling failed: error ", error, ", consumed ", input_frames,
                " of ", output_chunk_size, ", produced ", output_frames, " of ", current_chunk_16khz.size());
        current_chunk_16khz.resize(0);
        return ERR_CANT_CREATE;
    }
    return OK;
}

void TwovoipOpusEncoder::update_measurements() {
    float sum_squares = 0.0F;
    for (int i = 0; i < pre_encoded_chunk.size(); i++) {
        float sample = pre_encoded_chunk[i];
        last_peak = std::max(last_peak, std::abs(sample));
        sum_squares += sample * sample;
    }
    last_rms = std::sqrt(sum_squares / output_chunk_size);
}

int TwovoipOpusEncoder::process_chunk(const PackedVector2Array &audio_frames) {
    return process_chunk_internal(audio_frames);
}

float TwovoipOpusEncoder::process_pre_encoded_chunk(PackedVector2Array audio_frames, int opus_chunk_size, bool speech_probability, bool rms) {
    if (!legacy_processing_warning_printed) {
        UtilityFunctions::push_warning("process_pre_encoded_chunk() is deprecated; use process_chunk() followed by get_peak(), get_rms(), or get_speech_probability()");
        legacy_processing_warning_printed = true;
    }
    if (configure_output_chunk_size(opus_chunk_size) != OK)
        return -1.0F;
    if (process_chunk_internal(audio_frames) < 0)
        return -1.0F;
    if (speech_probability)
        return last_speech_probability;
    return rms ? last_rms : last_peak;
}

PackedByteArray TwovoipOpusEncoder::encode_chunk(const PackedByteArray& prefix_bytes) {
    if (opus_encoder == NULL) {
        godot::UtilityFunctions::printerr("Error: opusencoder is null");
        return PackedByteArray();
    }
    int max_opus_byte_buffer = prefix_bytes.size() + 4*pre_encoded_chunk.size();
    if (max_opus_byte_buffer > opus_byte_buffer.size())
        opus_byte_buffer.resize(max_opus_byte_buffer);
    
    unsigned char* popus_bytes = opus_byte_buffer.ptrw();
    int nprefbytes = prefix_bytes.size();
    if (nprefbytes != 0) 
        memcpy(popus_bytes, prefix_bytes.ptr(), nprefbytes); 
    int bytepacketsize = opus_encode_float(opus_encoder, (const float*)pre_encoded_chunk.ptr(), pre_encoded_chunk.size()/channels, 
                                           opus_byte_buffer.ptrw() + nprefbytes, max_opus_byte_buffer - nprefbytes);
    return opus_byte_buffer.slice(0, nprefbytes + bytepacketsize);
}
    

TwovoipOpusEncoder::~TwovoipOpusEncoder() {
    destroy_voice_processor();
    if (speex_resampler != NULL) {
        speex_resampler_destroy(speex_resampler);
        speex_resampler = NULL;
    }
    if (resampler_16khz != NULL) {
        speex_resampler_destroy(resampler_16khz);
        resampler_16khz = NULL;
    }
    if (opus_encoder != NULL) {
        opus_encoder_destroy(opus_encoder);
        opus_encoder = NULL;
    }
}
