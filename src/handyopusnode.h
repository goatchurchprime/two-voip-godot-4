#ifndef HANDYOPUSNODE_H
#define HANDYOPUSNODE_H

#include <godot_cpp/classes/node.hpp>

#include "opus.h"
#include "spsc_jitter_buffer.h"
#include "speex/speex_resampler.h"

namespace godot {

class HandyOpusNode : public Node {
	GDCLASS(HandyOpusNode, Node)

private:
	double time_passed;

    int _last_opus_error = 0;
    int _last_resampler_error = 0;
    OpusDecoder* _opus_decoder;
    SpeexResamplerState* _resampler;
    PackedVector2Array _sample_buf;

    const int GODOT_SAMPLE_RATE = 44100;
    const int OPUS_FRAME_SIZE = 480;
    const int OPUS_SAMPLE_RATE = 48000;
    const int CHANNELS = 2;
    const int RESAMPLING_QUALITY = 10; // 0 to 10

    SPSCJitterBuffer jitter_buffer;


protected:
	static void _bind_methods();

public:
	HandyOpusNode();
	~HandyOpusNode();

    PackedVector2Array decode_opus_packet(const PackedByteArray&);
};

}

#endif // HANDYOPUSNODE_H
