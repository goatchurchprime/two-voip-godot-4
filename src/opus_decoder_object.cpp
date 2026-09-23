/**************************************************************************/
/*  opus_decoder_object.cpp                                               */
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

#include "opus_decoder_object.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstring>

using namespace godot;

void TwovoipOpusDecoder::_bind_methods() {
    ClassDB::bind_method(D_METHOD("initialize", "sample_rate", "channels"), &TwovoipOpusDecoder::initialize);
    ClassDB::bind_method(D_METHOD("decode_packet", "opus_packet", "begin", "decode_fec", "frame_size"), &TwovoipOpusDecoder::decode_packet, DEFVAL(0), DEFVAL(false), DEFVAL(0));
    ClassDB::bind_method(D_METHOD("decode_missing", "frame_size"), &TwovoipOpusDecoder::decode_missing);
    ClassDB::bind_method(D_METHOD("reset"), &TwovoipOpusDecoder::reset);
    ClassDB::bind_method(D_METHOD("is_initialized"), &TwovoipOpusDecoder::is_initialized);
    ClassDB::bind_method(D_METHOD("get_sample_rate"), &TwovoipOpusDecoder::get_sample_rate);
    ClassDB::bind_method(D_METHOD("get_channels"), &TwovoipOpusDecoder::get_channels);
    ClassDB::bind_method(D_METHOD("get_last_frame_size"), &TwovoipOpusDecoder::get_last_frame_size);
    ClassDB::bind_method(D_METHOD("get_last_error"), &TwovoipOpusDecoder::get_last_error);
    ClassDB::bind_method(D_METHOD("get_last_error_message"), &TwovoipOpusDecoder::get_last_error_message);

    uint32_t read_only = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY;
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "initialized", PROPERTY_HINT_NONE, "", read_only), "", "is_initialized");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "sample_rate", PROPERTY_HINT_NONE, "", read_only), "", "get_sample_rate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "channels", PROPERTY_HINT_NONE, "", read_only), "", "get_channels");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "last_frame_size", PROPERTY_HINT_NONE, "", read_only), "", "get_last_frame_size");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "last_error", PROPERTY_HINT_NONE, "", read_only), "", "get_last_error");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "last_error_message", PROPERTY_HINT_NONE, "", read_only), "", "get_last_error_message");
}

TwovoipOpusDecoder::TwovoipOpusDecoder() {}

void TwovoipOpusDecoder::destroy_decoder() {
    if (opus_decoder != nullptr) {
        opus_decoder_destroy(opus_decoder);
        opus_decoder = nullptr;
    }
    decode_buffer.resize(0);
    sample_rate = 0;
    channels = 0;
    maximum_frame_size = 0;
    last_frame_size = 0;
    initialized = false;
}

Error TwovoipOpusDecoder::initialize(int p_sample_rate, int p_channels) {
    if (initialized) {
        UtilityFunctions::printerr("TwovoipOpusDecoder is already initialized");
        return ERR_ALREADY_IN_USE;
    }
    if ((p_sample_rate != 8000 && p_sample_rate != 12000 && p_sample_rate != 16000 &&
                p_sample_rate != 24000 && p_sample_rate != 48000) ||
            (p_channels != 1 && p_channels != 2)) {
        last_error = OPUS_BAD_ARG;
        UtilityFunctions::printerr("Invalid Opus decoder sample rate or channel count");
        return ERR_INVALID_PARAMETER;
    }

    int opus_error = OPUS_OK;
    OpusDecoder *decoder = opus_decoder_create(p_sample_rate, p_channels, &opus_error);
    if (decoder == nullptr || opus_error != OPUS_OK) {
        if (decoder != nullptr) {
            opus_decoder_destroy(decoder);
        }
        last_error = opus_error;
        UtilityFunctions::printerr("Opus decoder creation failed: ", opus_strerror(opus_error));
        return opus_error == OPUS_ALLOC_FAIL ? ERR_OUT_OF_MEMORY : ERR_CANT_CREATE;
    }

    opus_decoder = decoder;
    sample_rate = p_sample_rate;
    channels = p_channels;
    maximum_frame_size = sample_rate * 120 / 1000;
    decode_buffer.resize(maximum_frame_size * channels);
    last_frame_size = 0;
    last_error = OPUS_OK;
    initialized = true;
    return OK;
}

PackedFloat32Array TwovoipOpusDecoder::decode_packet(const PackedByteArray &p_opus_packet, int p_begin, bool p_decode_fec, int p_frame_size) {
    if (!initialized) {
        last_error = OPUS_INVALID_STATE;
        UtilityFunctions::printerr("TwovoipOpusDecoder is not initialized");
        return PackedFloat32Array();
    }
    if (p_begin < 0 || p_begin >= p_opus_packet.size()) {
        last_error = OPUS_BAD_ARG;
        UtilityFunctions::printerr("Opus packet prefix length is outside the packet");
        return PackedFloat32Array();
    }

    int frame_size = p_frame_size;
    if (frame_size == 0) {
        frame_size = p_decode_fec ? last_frame_size : maximum_frame_size;
    }
    return decode_internal(p_opus_packet.ptr() + p_begin, p_opus_packet.size() - p_begin, frame_size, p_decode_fec);
}

PackedFloat32Array TwovoipOpusDecoder::decode_missing(int p_frame_size) {
    return decode_internal(nullptr, 0, p_frame_size, false);
}

PackedFloat32Array TwovoipOpusDecoder::decode_internal(const unsigned char *p_data, int p_data_size, int p_frame_size, bool p_decode_fec) {
    if (!initialized) {
        last_error = OPUS_INVALID_STATE;
        UtilityFunctions::printerr("TwovoipOpusDecoder is not initialized");
        return PackedFloat32Array();
    }
    if (p_frame_size <= 0 || p_frame_size > maximum_frame_size) {
        last_error = OPUS_BAD_ARG;
        UtilityFunctions::printerr("Opus decode frame size must be between 1 and ", maximum_frame_size);
        return PackedFloat32Array();
    }

    int decoded_frames = opus_decode_float(opus_decoder, p_data, p_data_size,
            decode_buffer.ptrw(), p_frame_size, p_decode_fec ? 1 : 0);
    if (decoded_frames < 0) {
        last_error = decoded_frames;
        UtilityFunctions::printerr("Opus decode failed: ", opus_strerror(decoded_frames));
        return PackedFloat32Array();
    }

    last_error = OPUS_OK;
    last_frame_size = decoded_frames;
    PackedFloat32Array output;
    output.resize(decoded_frames * channels);
    if (!output.is_empty()) {
        std::memcpy(output.ptrw(), decode_buffer.ptr(), output.size() * sizeof(float));
    }
    return output;
}

void TwovoipOpusDecoder::reset() {
    if (!initialized) {
        last_error = OPUS_INVALID_STATE;
        UtilityFunctions::printerr("TwovoipOpusDecoder is not initialized");
        return;
    }
    last_error = opus_decoder_ctl(opus_decoder, OPUS_RESET_STATE);
    if (last_error != OPUS_OK) {
        UtilityFunctions::printerr("Opus decoder reset failed: ", opus_strerror(last_error));
        return;
    }
    last_frame_size = 0;
}

String TwovoipOpusDecoder::get_last_error_message() const {
    return String::utf8(opus_strerror(last_error));
}

TwovoipOpusDecoder::~TwovoipOpusDecoder() {
    destroy_decoder();
}
