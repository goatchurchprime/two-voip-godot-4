#include <godot_cpp/variant/utility_functions.hpp>

#include "handyopusnode.h"

#include <cassert>

using namespace godot;


HandyOpusNode::HandyOpusNode() : jitter_buffer(OPUS_FRAME_SIZE * GODOT_SAMPLE_RATE / OPUS_SAMPLE_RATE) {
    _opus_decoder = opus_decoder_create(OPUS_SAMPLE_RATE, CHANNELS, &_last_opus_error);
    assert(_opus_decoder != NULL);

    _resamplerE = speex_resampler_init(CHANNELS, OPUS_SAMPLE_RATE, GODOT_SAMPLE_RATE, RESAMPLING_QUALITY, &_last_resampler_errorE);
    assert( _resamplerE != NULL );
    _sample_bufE.resize(OPUS_FRAME_SIZE);

    _sample_buf.resize(OPUS_FRAME_SIZE);
    
    
    _opus_encoder = opus_encoder_create(OPUS_SAMPLE_RATE, CHANNELS, OPUS_APPLICATION_VOIP, &_last_opus_errorE);
    opus_encoder_ctl(_opus_encoder, OPUS_SET_BITRATE(DEFAULT_BITRATE));
}

HandyOpusNode::~HandyOpusNode(){
    opus_decoder_destroy(_opus_decoder);
    opus_encoder_destroy(_opus_encoder);
    speex_resampler_destroy(_resampler);
    speex_resampler_destroy(_resamplerE);
}


void HandyOpusNode::_bind_methods(){
    ClassDB::bind_method(D_METHOD("decode_opus_packet", "packet"), &HandyOpusNode::decode_opus_packet);
    ClassDB::bind_method(D_METHOD("encode_opus_packet", "samples"), &HandyOpusNode::encode_opus_packet);
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

    // Push to the jitter buffer

    return samples;
}

PackedByteArray HandyOpusNode::encode_opus_packet(PackedVector2Array samples){
    assert( _sample_bufE.size() == OPUS_FRAME_SIZE );
    assert( samples.size() == OPUS_FRAME_SIZE * GODOT_SAMPLE_RATE / OPUS_SAMPLE_RATE );

    PackedByteArray packet;
    packet.resize( sizeof(float) * CHANNELS * OPUS_FRAME_SIZE );

    unsigned int num_samples = samples.size();
    unsigned int num_buffer_samples = OPUS_FRAME_SIZE;
    int resampling_result = speex_resampler_process_interleaved_float(_resamplerE, (float*) samples.ptr(), &num_samples, (float*) _sample_bufE.ptrw(), &num_buffer_samples);
    assert( resampling_result == 0 );

    int packet_size = opus_encode_float(_opus_encoder, (float*) _sample_bufE.ptr(), OPUS_FRAME_SIZE, (unsigned char*) packet.ptrw(), packet.size());
    assert( packet_size > 0 );
    packet.resize( packet_size );

    return packet;
}
