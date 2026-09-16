/**************************************************************************/
/*  opus_decoder_object.h                                                 */
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

#ifndef OPUS_DECODER_OBJECT_H
#define OPUS_DECODER_OBJECT_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include "opus.h"

namespace godot {

class TwovoipOpusDecoder : public RefCounted {
    GDCLASS(TwovoipOpusDecoder, RefCounted)

private:
    OpusDecoder *opus_decoder = nullptr;
    PackedFloat32Array decode_buffer;
    int sample_rate = 0;
    int channels = 0;
    int maximum_frame_size = 0;
    int last_frame_size = 0;
    int last_error = OPUS_OK;
    bool initialized = false;

    void destroy_decoder();
    PackedFloat32Array decode_internal(const unsigned char *p_data, int p_data_size, int p_frame_size, bool p_decode_fec);

protected:
    static void _bind_methods();

public:
    Error initialize(int p_sample_rate, int p_channels);
    PackedFloat32Array decode_packet(const PackedByteArray &p_opus_packet, int p_begin = 0, bool p_decode_fec = false, int p_frame_size = 0);
    PackedFloat32Array decode_missing(int p_frame_size);
    void reset();

    bool is_initialized() const { return initialized; }
    int get_sample_rate() const { return sample_rate; }
    int get_channels() const { return channels; }
    int get_last_frame_size() const { return last_frame_size; }
    int get_last_error() const { return last_error; }
    String get_last_error_message() const;

    TwovoipOpusDecoder();
    ~TwovoipOpusDecoder();
};

}

#endif // OPUS_DECODER_OBJECT_H
