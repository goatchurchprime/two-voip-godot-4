#include <godot_cpp/variant/utility_functions.hpp>

#include "handyopusnode.h"

#include <cassert>

using namespace godot;


HandyOpusNode::HandyOpusNode() : jitter_buffer(OPUS_FRAME_SIZE * GODOT_SAMPLE_RATE / OPUS_SAMPLE_RATE) {
    _opus_decoder = opus_decoder_create(OPUS_SAMPLE_RATE, CHANNELS, &_last_opus_error);
    assert(_opus_decoder != NULL);

    _resampler = speex_resampler_init(CHANNELS, OPUS_SAMPLE_RATE, GODOT_SAMPLE_RATE, RESAMPLING_QUALITY, &_last_resampler_error);
    assert( _resampler != NULL );

    _sample_buf.resize(OPUS_FRAME_SIZE);
}

HandyOpusNode::~HandyOpusNode(){
    opus_decoder_destroy(_opus_decoder);
    speex_resampler_destroy(_resampler);
}


void HandyOpusNode::_bind_methods(){
    ClassDB::bind_method(D_METHOD("decode_opus_packet", "packet"), &HandyOpusNode::decode_opus_packet);
}

PackedVector2Array HandyOpusNode::decode_opus_packet(const PackedByteArray& packet){
    // UtilityFunctions::print("Received bytes: ", packet.size());

    // Convert to PackedVector2Array in 44100 kHz

    PackedVector2Array samples;
    samples.resize(OPUS_FRAME_SIZE * GODOT_SAMPLE_RATE / OPUS_SAMPLE_RATE);

    int decoded_samples = opus_decode_float(_opus_decoder, packet.ptr(), packet.size(), (float*) _sample_buf.ptrw(), OPUS_FRAME_SIZE, 0);
    assert( decoded_samples > 0 );

    unsigned int num_samples = samples.size();
    unsigned int num_buffer_samples = _sample_buf.size();
    int resampling_result = speex_resampler_process_interleaved_float(_resampler, (float*) _sample_buf.ptr(), &num_buffer_samples, (float*) samples.ptrw(), &num_samples);
    samples.resize(num_samples);
    assert( resampling_result == 0 );

    return samples;
}
