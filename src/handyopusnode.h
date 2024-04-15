#ifndef HANDYOPUSNODE_H
#define HANDYOPUSNODE_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/audio_effect_capture.hpp>

#include "opus.h"
#include "spsc_jitter_buffer.h"
#include "speex/speex_resampler.h"

namespace godot {

class HandyOpusNode : public Node {
	GDCLASS(HandyOpusNode, Node)

protected:
    static void _bind_methods();

private:
    double time_passed;
    int _last_opus_error = 0;
    int _last_resampler_error = 0;
    OpusDecoder* _opus_decoder;
    SpeexResamplerState* _resampler;
    PackedVector2Array _sample_buf;

    int _last_opus_errorE = 0;
    int _last_resampler_errorE = 0;
    OpusEncoder* _opus_encoder;
    SpeexResamplerState* _resamplerE;
    PackedVector2Array _sample_bufE; // Resample audio here before sending through opus

public:
    PackedVector2Array decode_opus_packet(const PackedByteArray&);
    PackedByteArray _sample_buf_to_packet(PackedVector2Array samples);

    // Constants

    const int GODOT_SAMPLE_RATE = 44100;
    const int OPUS_FRAME_SIZE = 480;
    const int OPUS_SAMPLE_RATE = 48000;
    const int CHANNELS = 2;
    const int RESAMPLING_QUALITY = 10; // 0 to 10
    const int DEFAULT_BITRATE = 24000; // bits / second from 500 to 512000
    const int EXPECTED_PACKET_LOSS = 5; // percentage from 0 to 100


    HandyOpusNode();
    ~HandyOpusNode();

};





class VOIPInputCaptureE : public Node {
    GDCLASS(VOIPInputCaptureE, Node)

protected:
    static void _bind_methods();

private:
    double time_passed;
    int _last_opus_error = 0;
    int _last_resampler_error = 0;
    OpusDecoder* _opus_decoder;
    SpeexResamplerState* _resampler;
    PackedVector2Array _sample_buf;

    int _last_opus_errorE = 0;
    int _last_resampler_errorE = 0;
    OpusEncoder* _opus_encoder;
    SpeexResamplerState* _resamplerE;
    PackedVector2Array _sample_bufE; // Resample audio here before sending through opus

public:
    PackedVector2Array decode_opus_packet(const PackedByteArray&);
    PackedByteArray _sample_buf_to_packet(PackedVector2Array samples);

    // Constants

    const int GODOT_SAMPLE_RATE = 44100;
    const int OPUS_FRAME_SIZE = 480;
    const int OPUS_SAMPLE_RATE = 48000;
    const int CHANNELS = 2;
    const int RESAMPLING_QUALITY = 10; // 0 to 10
    const int DEFAULT_BITRATE = 24000; // bits / second from 500 to 512000
    const int EXPECTED_PACKET_LOSS = 5; // percentage from 0 to 100


    VOIPInputCaptureE();
    ~VOIPInputCaptureE();

};



}

#endif // HANDYOPUSNODE_H
