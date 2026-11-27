#ifndef TWO_VOIP_OPUS_ENCODER_H
#define TWO_VOIP_OPUS_ENCODER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include "opus.h"

namespace godot {

class TwoVoipOpusEncoder : public RefCounted {
    GDCLASS(TwoVoipOpusEncoder, RefCounted)

public:
    enum SignalType {
        SIGNAL_AUTO,
        SIGNAL_VOICE,
        SIGNAL_MUSIC,
    };

private:
    OpusEncoder *encoder = nullptr;
    int sample_rate = 0;
    int channels = 0;
    int frame_size = 0;
    int bitrate = 0;
    int complexity = 0;
    int packet_loss_perc = -1;
    SignalType signal_type = SIGNAL_AUTO;

    void destroy_encoder();

protected:
    static void _bind_methods();

public:
    static String get_version_info();
    Error initialize(int p_sample_rate, int p_channels, int p_frame_size);
    PackedByteArray encode_chunk(const PackedVector2Array &p_audio_frames,
            const PackedByteArray &p_prefix_bytes = PackedByteArray());
    Error set_bitrate(int p_bitrate);
    int get_bitrate() const { return bitrate; }
    Error set_complexity(int p_complexity);
    int get_complexity() const { return complexity; }
    Error set_signal_type(SignalType p_signal_type);
    SignalType get_signal_type() const { return signal_type; }
    Error set_inband_perc(int p_packet_loss_perc);
    int get_inband_perc() const { return packet_loss_perc; }
    void reset();

    ~TwoVoipOpusEncoder();
};

} // namespace godot

VARIANT_ENUM_CAST(godot::TwoVoipOpusEncoder::SignalType)

#endif
