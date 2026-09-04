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
    ClassDB::bind_method(D_METHOD("create_sampler", "p_input_mix_rate", "p_opus_sample_rate", "p_channels", "use_rnnoise", "output_chunk_size"), &TwovoipOpusEncoder::create_sampler, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("set_output_chunk_size", "output_chunk_size"), &TwovoipOpusEncoder::set_output_chunk_size);
    ClassDB::bind_method(D_METHOD("get_output_chunk_size"), &TwovoipOpusEncoder::get_output_chunk_size);
    ClassDB::bind_method(D_METHOD("get_required_input_chunk_size"), &TwovoipOpusEncoder::get_required_input_chunk_size);
    ClassDB::bind_method(D_METHOD("process_chunk", "audio_frames"), &TwovoipOpusEncoder::process_chunk);
    ClassDB::bind_method(D_METHOD("get_peak"), &TwovoipOpusEncoder::get_peak);
    ClassDB::bind_method(D_METHOD("get_rms"), &TwovoipOpusEncoder::get_rms);
    ClassDB::bind_method(D_METHOD("get_speech_probability"), &TwovoipOpusEncoder::get_speech_probability);
    ClassDB::bind_method(D_METHOD("set_gain", "gain"), &TwovoipOpusEncoder::set_gain);
    ClassDB::bind_method(D_METHOD("get_gain"), &TwovoipOpusEncoder::get_gain);
    ClassDB::bind_method(D_METHOD("set_automatic_gain", "enabled"), &TwovoipOpusEncoder::set_automatic_gain);
    ClassDB::bind_method(D_METHOD("get_automatic_gain"), &TwovoipOpusEncoder::get_automatic_gain);
    ClassDB::bind_method(D_METHOD("create_opus_encoder", "bit_rate", "complexity", "voice_optimal"), &TwovoipOpusEncoder::create_opus_encoder);
    ClassDB::bind_method(D_METHOD("reset_opus_encoder"), &TwovoipOpusEncoder::reset_opus_encoder);
    ClassDB::bind_method(D_METHOD("calc_audio_chunk_size", "opus_chunk_size"), &TwovoipOpusEncoder::calc_audio_chunk_size);
    ClassDB::bind_method(D_METHOD("process_pre_encoded_chunk", "audio_frames", "opus_chunk_size", "speech_probability", "rms"), &TwovoipOpusEncoder::process_pre_encoded_chunk);
    ClassDB::bind_method(D_METHOD("encode_chunk", "prefix_bytes"), &TwovoipOpusEncoder::encode_chunk, DEFVAL(PackedByteArray()));

    uint32_t read_only = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY;
    ADD_PROPERTY(PropertyInfo(Variant::INT, "output_chunk_size", PROPERTY_HINT_NONE, "", read_only), "", "get_output_chunk_size");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "required_input_chunk_size", PROPERTY_HINT_NONE, "", read_only), "", "get_required_input_chunk_size");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "gain", PROPERTY_HINT_NONE, "", read_only), "", "get_gain");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "automatic_gain", PROPERTY_HINT_NONE, "", read_only), "", "get_automatic_gain");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "peak", PROPERTY_HINT_NONE, "", read_only), "", "get_peak");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "rms", PROPERTY_HINT_NONE, "", read_only), "", "get_rms");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "speech_probability", PROPERTY_HINT_NONE, "", read_only), "", "get_speech_probability");
}

TwovoipOpusEncoder::TwovoipOpusEncoder() {}

void TwovoipOpusEncoder::destroy_agc() {
    if (speex_agc != NULL) {
        speex_preprocess_state_destroy(speex_agc);
        speex_agc = NULL;
    }
    agc_frame_size = 0;
    agc_warmup_frames = 0;
    agc_mono_frame.clear();
}

Error TwovoipOpusEncoder::create_agc() {
    destroy_agc();
    if (output_chunk_size <= 0 || opus_sample_rate <= 0)
        return ERR_UNCONFIGURED;

    int frame_20ms = opus_sample_rate / 50;
    int frame_10ms = opus_sample_rate / 100;
    if ((opus_sample_rate % 50) == 0 && frame_20ms > 0 && output_chunk_size >= frame_20ms && (output_chunk_size % frame_20ms) == 0)
        agc_frame_size = frame_20ms;
    else if ((opus_sample_rate % 100) == 0 && frame_10ms > 0 && output_chunk_size >= frame_10ms && (output_chunk_size % frame_10ms) == 0)
        agc_frame_size = frame_10ms;
    else {
        UtilityFunctions::printerr("Automatic gain requires an output chunk divisible into 10 ms or 20 ms analysis frames");
        return ERR_INVALID_PARAMETER;
    }

    speex_agc = speex_preprocess_state_init(agc_frame_size, opus_sample_rate);
    if (speex_agc == NULL) {
        UtilityFunctions::printerr("Speex automatic gain initialization failed");
        agc_frame_size = 0;
        return ERR_CANT_CREATE;
    }
    spx_int32_t enabled = 1;
    spx_int32_t disabled = 0;
    speex_preprocess_ctl(speex_agc, SPEEX_PREPROCESS_SET_DENOISE, &disabled);
    speex_preprocess_ctl(speex_agc, SPEEX_PREPROCESS_SET_AGC, &enabled);
    agc_mono_frame.resize(agc_frame_size);
    agc_warmup_frames = 21;
    return OK;
}

bool TwovoipOpusEncoder::create_sampler(int p_input_mix_rate, int p_opus_sample_rate, int p_channels, bool use_rnnoise, int p_output_chunk_size) {
    if (p_input_mix_rate <= 0 || p_opus_sample_rate <= 0 || (p_channels != 1 && p_channels != 2)) {
        UtilityFunctions::printerr("Invalid sampler configuration");
        return false;
    }
    destroy_agc();
    output_chunk_size = 0;
    required_input_chunk_size = 0;
    input_mix_rate = p_input_mix_rate;
    opus_sample_rate = p_opus_sample_rate;
    channels = p_channels;
    if (speex_resampler != NULL) {
        speex_resampler_destroy(speex_resampler);
        speex_resampler = NULL;
    }
    if (input_mix_rate != opus_sample_rate) {
        int speexerror = 0; 
        int resamplingquality = 10;
        speex_resampler = speex_resampler_init(channels, input_mix_rate, opus_sample_rate, resamplingquality, &speexerror);
        if (speex_resampler == NULL) {
            godot::UtilityFunctions::printerr("Speex resampler init failed code ", speexerror); 
        }
    }
    
    if (rnnoise_st != NULL) {
        rnnoise_destroy(rnnoise_st);
        rnnoise_st = NULL;
    }
    if (use_rnnoise) {
        if (opus_sample_rate == 48000) {
            rnnoise_st = rnnoise_create(NULL);
            if (rnnoise_st != NULL) {
                rnnoise_in.resize(rnnoise_get_frame_size());
                rnnoise_out.resize(rnnoise_get_frame_size());
                godot::UtilityFunctions::print_verbose("rnnoise sample_rate=48000 frame_size=", rnnoise_get_frame_size()); // expected 480/10ms
            }
        } else {
            godot::UtilityFunctions::printerr("rnnoise only works for sample_rate=48000"); 
        }            
    }
    bool configured = ((input_mix_rate == opus_sample_rate) || (speex_resampler != NULL)) && (!use_rnnoise || (rnnoise_st != NULL));
    if (configured && p_output_chunk_size > 0)
        configured = configure_output_chunk_size(p_output_chunk_size);
    return configured;
}

bool TwovoipOpusEncoder::configure_output_chunk_size(int p_output_chunk_size) {
    if (p_output_chunk_size <= 0 || input_mix_rate <= 0 || opus_sample_rate <= 0) {
        UtilityFunctions::printerr("Output chunk size and sample rates must be positive");
        return false;
    }
    if (output_chunk_size == p_output_chunk_size)
        return true;

    output_chunk_size = p_output_chunk_size;
    required_input_chunk_size = static_cast<int>((static_cast<int64_t>(output_chunk_size) * input_mix_rate + opus_sample_rate - 1) / opus_sample_rate);
    pre_encoded_chunk.resize(output_chunk_size * channels);
    if (automatic_gain && create_agc() != OK) {
        automatic_gain = false;
        return false;
    }
    return true;
}

bool TwovoipOpusEncoder::set_output_chunk_size(int p_output_chunk_size) {
    UtilityFunctions::push_warning("set_output_chunk_size() is deprecated; pass output_chunk_size to create_sampler()");
    return configure_output_chunk_size(p_output_chunk_size);
}

void TwovoipOpusEncoder::set_gain(float p_gain) {
    if (!std::isfinite(p_gain) || p_gain < 0.0F) {
        UtilityFunctions::printerr("Gain must be a finite value greater than or equal to zero");
        return;
    }
    automatic_gain = false;
    gain = p_gain;
}

Error TwovoipOpusEncoder::set_automatic_gain(bool p_enabled) {
    if (p_enabled == automatic_gain)
        return OK;
    if (!p_enabled) {
        automatic_gain = false;
        return OK;
    }
    automatic_gain = true;
    Error error = speex_agc == NULL ? create_agc() : OK;
    if (error != OK) {
        automatic_gain = false;
        return error;
    }
    return OK;
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
    
    if ((rnnoise_st != NULL) && ((output_chunk_size % rnnoise_get_frame_size()) == 0)) {
        int nnoisechunks = (int)(output_chunk_size/rnnoise_get_frame_size());
        for (int j = 0; j < nnoisechunks; j++) {
            for (int i = 0; i < rnnoise_get_frame_size(); i++) {
                int k = j*rnnoise_get_frame_size() + i;
                if (channels == 2) {
                    rnnoise_in[i] = (pre_encoded_chunk[k*2] + pre_encoded_chunk[k*2+1])*0.5F*32768.0F; 
                } else {
                    rnnoise_in[i] = pre_encoded_chunk[k]*32768.0F; 
                }
            }
            float speech_prob = rnnoise_process_frame(rnnoise_st, (float*)rnnoise_out.ptr(), (float*)rnnoise_in.ptrw());
            last_speech_probability = std::max(last_speech_probability, speech_prob);
            for (int i = 0; i < rnnoise_get_frame_size(); i++) {
                int k = j*rnnoise_get_frame_size() + i;
                if (channels == 2) {
                    pre_encoded_chunk[k*2] = rnnoise_out[i]/32768.0F;
                    pre_encoded_chunk[k*2 + 1] = rnnoise_out[i]/32768.0F;
                } else {
                    pre_encoded_chunk[k] = rnnoise_out[i]/32768.0F;
                }
            }
        }
    }
    apply_gain();
    update_measurements();
    return consumed_input_frames;
}

void TwovoipOpusEncoder::apply_gain() {
    if (!automatic_gain) {
        for (int i = 0; i < pre_encoded_chunk.size(); i++)
            pre_encoded_chunk[i] *= gain;
        return;
    }

    for (int offset = 0; offset < output_chunk_size; offset += agc_frame_size) {
        for (int frame = 0; frame < agc_frame_size; frame++) {
            int index = (offset + frame) * channels;
            float mono = pre_encoded_chunk[index];
            if (channels == 2)
                mono = (mono + pre_encoded_chunk[index + 1]) * 0.5F;
            mono = std::clamp(mono, -1.0F, 1.0F);
            agc_mono_frame[frame] = static_cast<spx_int16_t>(std::round(mono * 32767.0F));
        }
        speex_preprocess_run(speex_agc, agc_mono_frame.data());
        float target_gain = gain;
        if (agc_warmup_frames > 0) {
            agc_warmup_frames--;
        } else {
            spx_int32_t gain_db = 0;
            speex_preprocess_ctl(speex_agc, SPEEX_PREPROCESS_GET_AGC_GAIN, &gain_db);
            target_gain = std::pow(10.0F, static_cast<float>(gain_db) / 20.0F);
        }
        float starting_gain = gain;
        for (int frame = 0; frame < agc_frame_size; frame++) {
            float t = static_cast<float>(frame + 1) / agc_frame_size;
            float frame_gain = starting_gain + (target_gain - starting_gain) * t;
            for (int channel = 0; channel < channels; channel++)
                pre_encoded_chunk[(offset + frame) * channels + channel] *= frame_gain;
        }
        gain = target_gain;
    }
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
    if (!configure_output_chunk_size(opus_chunk_size))
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
    destroy_agc();
    if (rnnoise_st != NULL) {
        rnnoise_destroy(rnnoise_st);
        rnnoise_st = NULL;
    }
    if (speex_resampler != NULL) {
        speex_resampler_destroy(speex_resampler);
        speex_resampler = NULL;
    }
    if (opus_encoder != NULL) {
        opus_encoder_destroy(opus_encoder);
        opus_encoder = NULL;
    }
}
