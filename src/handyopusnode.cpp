#include <godot_cpp/variant/utility_functions.hpp>

#include "handyopusnode.h"

#include <cassert>

using namespace godot;


HandyOpusNode::HandyOpusNode() {
    opus_decoder = opus_decoder_create(OPUS_SAMPLE_RATE, CHANNELS, &last_opus_error);
    assert (opus_decoder != NULL);
    resampler = speex_resampler_init(CHANNELS, OPUS_SAMPLE_RATE, GODOT_SAMPLE_RATE, RESAMPLING_QUALITY, &last_resampler_error);
    sample_buf.resize(OPUS_FRAME_SIZE);
    
    opus_encoder = opus_encoder_create(OPUS_SAMPLE_RATE, CHANNELS, OPUS_APPLICATION_VOIP, &last_opus_errorE);
    opus_encoder_ctl(opus_encoder, OPUS_SET_BITRATE(DEFAULT_BITRATE));
    resamplerE = speex_resampler_init(CHANNELS, GODOT_SAMPLE_RATE, OPUS_SAMPLE_RATE, RESAMPLING_QUALITY, &last_resampler_errorE);
    assert (resamplerE != NULL);
    sample_bufE.resize(OPUS_FRAME_SIZE);
}

HandyOpusNode::~HandyOpusNode() {
    opus_decoder_destroy(opus_decoder);
    opus_encoder_destroy(opus_encoder);
    speex_resampler_destroy(resampler);
    speex_resampler_destroy(resamplerE);
}


void HandyOpusNode::_bind_methods() {
    ClassDB::bind_method(D_METHOD("decode_opus_packet", "packet"), &HandyOpusNode::decode_opus_packet);
    ClassDB::bind_method(D_METHOD("encode_opus_packet", "samples"), &HandyOpusNode::encode_opus_packet);
   
}

PackedVector2Array HandyOpusNode::decode_opus_packet(const PackedByteArray& packet) {
    PackedVector2Array samples;
    samples.resize(OPUS_FRAME_SIZE * GODOT_SAMPLE_RATE / OPUS_SAMPLE_RATE);

    int decoded_samples = opus_decode_float(opus_decoder, packet.ptr(), packet.size(), (float*)sample_buf.ptrw(), OPUS_FRAME_SIZE, 0);
    assert (decoded_samples > 0);

    unsigned int num_samples = samples.size();
    unsigned int num_buffer_samples = sample_buf.size();
    int resampling_result = speex_resampler_process_interleaved_float(resampler, (float*)sample_buf.ptr(), &num_buffer_samples, (float*)samples.ptrw(), &num_samples);
    samples.resize(num_samples);
    assert (resampling_result == 0);

    return samples;
}

PackedByteArray HandyOpusNode::encode_opus_packet(PackedVector2Array samples) {
    assert(sample_bufE.size() == OPUS_FRAME_SIZE);
    assert(samplesE.size() == OPUS_FRAME_SIZE * GODOT_SAMPLE_RATE / OPUS_SAMPLE_RATE);

    PackedByteArray packet;
    packet.resize(sizeof(float) * CHANNELS * OPUS_FRAME_SIZE);

    unsigned int num_samples = samples.size();
    unsigned int num_buffer_samples = OPUS_FRAME_SIZE;
    int resampling_result = speex_resampler_process_interleaved_float(resamplerE, (float*)samples.ptr(), &num_samples, (float*)sample_bufE.ptrw(), &num_buffer_samples);
    assert (resampling_result == 0);

    int packet_size = opus_encode_float(opus_encoder, (float*)sample_bufE.ptr(), OPUS_FRAME_SIZE, (unsigned char*)packet.ptrw(), packet.size());
    assert (packet_size > 0);
    packet.resize(packet_size);

    return packet;
}




