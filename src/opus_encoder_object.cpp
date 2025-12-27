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

#include "opus_encoder_object.h"

using namespace godot;

void TwovoipOpusEncoder::_bind_methods() {
    ClassDB::bind_method(D_METHOD("create_sampler", "p_input_mix_rate", "p_channels", "use_rnnoise"), &TwovoipOpusEncoder::create_sampler);
    ClassDB::bind_method(D_METHOD("create_opus_encoder", "bit_rate", "complexity"), &TwovoipOpusEncoder::create_opus_encoder);
    ClassDB::bind_method(D_METHOD("calc_audio_chunk_size", "opus_chunk_size"), &TwovoipOpusEncoder::calc_audio_chunk_size);
    ClassDB::bind_method(D_METHOD("process_pre_encoded_chunk", "audio_frames", "opus_chunk_size", "speech_probability", "rms"), &TwovoipOpusEncoder::process_pre_encoded_chunk);
    ClassDB::bind_method(D_METHOD("fetch_pre_encoded_chunk"), &TwovoipOpusEncoder::fetch_pre_encoded_chunk);
    ClassDB::bind_method(D_METHOD("encode_chunk", "prefix_bytes"), &TwovoipOpusEncoder::encode_chunk);
}

TwovoipOpusEncoder::TwovoipOpusEncoder() {
    visemes.resize(ovrLipSyncViseme_Count + 3);  // we append laughterscore, framedelay and framenumber to this list
    ovrlipsyncframe.visemes = visemes.ptrw();
    ovrlipsyncframe.visemesLength = ovrLipSyncViseme_Count;
    ovrlipsyncframe.laughterCategories = NULL;
    ovrlipsyncframe.laughterCategoriesLength = 0;
}

bool TwovoipOpusEncoder::create_sampler(int p_input_mix_rate, int p_opus_sample_rate, int p_channels, bool use_rnnoise) {
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
                godot::UtilityFunctions::print("rnnoise sample_rate=48000 frame_size=", rnnoise_get_frame_size()); // expected 480/10ms
            }
        } else {
            godot::UtilityFunctions::printerr("rnnoise only works for sample_rate=48000"); 
        }            
    }
    return (((input_mix_rate == opus_sample_rate) || (speex_resampler != NULL)) && (!use_rnnoise || (rnnoise_st != NULL)));
}


bool TwovoipOpusEncoder::create_opus_encoder(int bit_rate, int complexity) {
    if (opus_encoder != NULL) {
        opus_encoder_destroy(opus_encoder);
        opus_encoder = NULL;
    }

    int opus_application = OPUS_APPLICATION_VOIP; // this option includes in-band forward error correction
    int signal_type = OPUS_SIGNAL_VOICE;
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


int TwovoipOpusEncoder::calc_audio_chunk_size(int opus_chunk_size) {
    int audio_chunk_size = opus_chunk_size*input_mix_rate/opus_sample_rate;
    return audio_chunk_size;
}

float TwovoipOpusEncoder::process_pre_encoded_chunk(PackedVector2Array audio_frames, int opus_chunk_size, bool speech_probability, bool rms) {
    float res = 0.0;
    if (pre_encoded_chunk.size() != opus_chunk_size)
        pre_encoded_chunk.resize(opus_chunk_size);

    int audio_chunk_size = opus_chunk_size*input_mix_rate/opus_sample_rate;
    // PackedVector2Array audio_frames = AudioServer::get_singleton()->get_input_frames(audio_chunk_size);
    if (audio_frames.size() != audio_chunk_size) 
        return -1.0;
    
    if (speex_resampler != NULL) {
        unsigned int Uaudiosamplesize = audio_chunk_size;
        unsigned int Uopusframesize = opus_chunk_size;
        int sxerr = speex_resampler_process_interleaved_float(speex_resampler, 
                                                              (float*)audio_frames.ptr(), &Uaudiosamplesize, 
                                                              (float*)pre_encoded_chunk.ptrw(), &Uopusframesize);
    } else if (audio_chunk_size == opus_chunk_size) {
        for (int i = 0; i < opus_chunk_size; i++)
            pre_encoded_chunk[i] = audio_frames[i];
    } else {
        for (int i = 0; i < opus_chunk_size; i++) {
            pre_encoded_chunk[i].x = 0.0;
            pre_encoded_chunk[i].y = 0.0;
        }
    }
    
    if ((rnnoise_st != NULL) && ((opus_chunk_size % rnnoise_get_frame_size()) == 0)) {
        int nnoisechunks = (int)(opus_chunk_size/rnnoise_get_frame_size());
        for (int j = 0; j < nnoisechunks; j++) {
            for (int i = 0; i < rnnoise_get_frame_size(); i++) 
                rnnoise_in[i] = (pre_encoded_chunk[j*rnnoise_get_frame_size() + i].x + pre_encoded_chunk[j*rnnoise_get_frame_size() + i].y)*0.5F*32768.0F;
            float speech_prob = rnnoise_process_frame(rnnoise_st, (float*)rnnoise_in.ptr(), (float*)rnnoise_out.ptrw());
            if (speech_probability && (speech_prob > res))
                res = speech_prob;
            for (int i = 0; i < rnnoise_get_frame_size(); i++) {
                pre_encoded_chunk[j*rnnoise_get_frame_size() + i].x = rnnoise_out[i]/32768.0F;
                pre_encoded_chunk[j*rnnoise_get_frame_size() + i].y = rnnoise_out[i]/32768.0F;
            }
        }
    }
    if (!speech_probability) {
        if (rms) {
            float s = 0.0F;
            for (int i = 0; i < opus_chunk_size; i++)
                s += pre_encoded_chunk[i].length_squared();
            res = sqrt(s/opus_chunk_size);
        } else {
            for (int i = 0; i < opus_chunk_size; i++)
                res = std::max<float>(std::max<float>(res, fabs(pre_encoded_chunk[i].x)), fabs(pre_encoded_chunk[i].y));
        }
    }
    return res;
}

PackedByteArray TwovoipOpusEncoder::encode_chunk(const PackedByteArray& prefix_bytes) {
    if (opus_encoder == NULL) {
        godot::UtilityFunctions::printerr("Error: opusencoder is null");
        return PackedByteArray();
    }
    int max_opus_byte_buffer = prefix_bytes.size() + 8*pre_encoded_chunk.size();
    if (max_opus_byte_buffer > opus_byte_buffer.size())
        opus_byte_buffer.resize(max_opus_byte_buffer);
    
    unsigned char* popus_bytes = opus_byte_buffer.ptrw();
    int nprefbytes = prefix_bytes.size();
    if (nprefbytes != 0) 
        memcpy(popus_bytes, prefix_bytes.ptr(), nprefbytes); 
    int bytepacketsize = opus_encode_float(opus_encoder, (const float*)pre_encoded_chunk.ptr(), pre_encoded_chunk.size(), 
                                           opus_byte_buffer.ptrw() + nprefbytes, max_opus_byte_buffer - nprefbytes);
    return opus_byte_buffer.slice(0, nprefbytes + bytepacketsize);
}
    

TwovoipOpusEncoder::~TwovoipOpusEncoder() {
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




