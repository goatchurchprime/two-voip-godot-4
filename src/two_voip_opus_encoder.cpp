#include "two_voip_opus_encoder.h"

#include <cstring>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "version.h"

using namespace godot;

namespace {

bool is_valid_sample_rate(int p_sample_rate) {
    return p_sample_rate == 8000 || p_sample_rate == 12000 || p_sample_rate == 16000 ||
            p_sample_rate == 24000 || p_sample_rate == 48000;
}

bool is_valid_frame_size(int p_sample_rate, int p_frame_size) {
    return p_frame_size == p_sample_rate / 400 || p_frame_size == p_sample_rate / 200 ||
            p_frame_size == p_sample_rate / 100 || p_frame_size == p_sample_rate / 50 ||
            p_frame_size == p_sample_rate / 25 || p_frame_size == p_sample_rate * 3 / 50;
}

int opus_signal(TwoVoipOpusEncoder::SignalType p_signal_type) {
    switch (p_signal_type) {
        case TwoVoipOpusEncoder::SIGNAL_AUTO: return OPUS_AUTO;
        case TwoVoipOpusEncoder::SIGNAL_VOICE: return OPUS_SIGNAL_VOICE;
        case TwoVoipOpusEncoder::SIGNAL_MUSIC: return OPUS_SIGNAL_MUSIC;
    }
    return 0;
}

} // namespace

void TwoVoipOpusEncoder::_bind_methods() {
    ClassDB::bind_static_method("TwoVoipOpusEncoder", D_METHOD("get_version_info"), &TwoVoipOpusEncoder::get_version_info);
    ClassDB::bind_method(D_METHOD("initialize", "sample_rate", "channels", "frame_size"), &TwoVoipOpusEncoder::initialize);
    ClassDB::bind_method(D_METHOD("encode_chunk", "audio_frames", "prefix_bytes"),
            &TwoVoipOpusEncoder::encode_chunk, DEFVAL(PackedByteArray()));
    ClassDB::bind_method(D_METHOD("set_bitrate", "bitrate"), &TwoVoipOpusEncoder::set_bitrate);
    ClassDB::bind_method(D_METHOD("get_bitrate"), &TwoVoipOpusEncoder::get_bitrate);
    ClassDB::bind_method(D_METHOD("set_complexity", "complexity"), &TwoVoipOpusEncoder::set_complexity);
    ClassDB::bind_method(D_METHOD("get_complexity"), &TwoVoipOpusEncoder::get_complexity);
    ClassDB::bind_method(D_METHOD("set_signal_type", "signal_type"), &TwoVoipOpusEncoder::set_signal_type);
    ClassDB::bind_method(D_METHOD("get_signal_type"), &TwoVoipOpusEncoder::get_signal_type);
    ClassDB::bind_method(D_METHOD("set_inband_perc", "packet_loss_perc"), &TwoVoipOpusEncoder::set_inband_perc);
    ClassDB::bind_method(D_METHOD("get_inband_perc"), &TwoVoipOpusEncoder::get_inband_perc);
    ClassDB::bind_method(D_METHOD("reset"), &TwoVoipOpusEncoder::reset);
    BIND_ENUM_CONSTANT(SIGNAL_AUTO);
    BIND_ENUM_CONSTANT(SIGNAL_VOICE);
    BIND_ENUM_CONSTANT(SIGNAL_MUSIC);
}

String TwoVoipOpusEncoder::get_version_info() {
    return TWOVOIP_VERSION_STR;
}

void TwoVoipOpusEncoder::destroy_encoder() {
    if (encoder) {
        opus_encoder_destroy(encoder);
        encoder = nullptr;
    }
    sample_rate = 0;
    channels = 0;
    frame_size = 0;
    bitrate = 0;
    complexity = 0;
    packet_loss_perc = -1;
    signal_type = SIGNAL_AUTO;
}

Error TwoVoipOpusEncoder::initialize(int p_sample_rate, int p_channels, int p_frame_size) {
    if (encoder)
        return ERR_ALREADY_IN_USE;
    if (!is_valid_sample_rate(p_sample_rate) || (p_channels != 1 && p_channels != 2) ||
            !is_valid_frame_size(p_sample_rate, p_frame_size)) {
        return ERR_INVALID_PARAMETER;
    }
    int error = OPUS_OK;
    encoder = opus_encoder_create(p_sample_rate, p_channels, OPUS_APPLICATION_VOIP, &error);
    if (!encoder || error != OPUS_OK) {
        destroy_encoder();
        return ERR_CANT_CREATE;
    }
    sample_rate = p_sample_rate;
    channels = p_channels;
    frame_size = p_frame_size;
    opus_encoder_ctl(encoder, OPUS_GET_BITRATE(&bitrate));
    opus_encoder_ctl(encoder, OPUS_GET_COMPLEXITY(&complexity));
    return OK;
}

PackedByteArray TwoVoipOpusEncoder::encode_chunk(const PackedVector2Array &p_audio_frames,
        const PackedByteArray &p_prefix_bytes) {
    if (!encoder || p_audio_frames.size() != frame_size) {
        UtilityFunctions::printerr("TwoVoipOpusEncoder expected ", frame_size,
                " conditioned frames, got ", p_audio_frames.size());
        return PackedByteArray();
    }

    const float *input = reinterpret_cast<const float *>(p_audio_frames.ptr());
    std::vector<float> mono;
    if (channels == 1) {
        mono.resize(frame_size);
        for (int frame = 0; frame < frame_size; frame++)
            mono[frame] = (p_audio_frames[frame].x + p_audio_frames[frame].y) * 0.5F;
        input = mono.data();
    }

    PackedByteArray packet;
    const int prefix_size = p_prefix_bytes.size();
    // Opus packets are at most 1275 bytes, independently of the PCM frame size.
    packet.resize(prefix_size + 1275);
    if (prefix_size > 0)
        memcpy(packet.ptrw(), p_prefix_bytes.ptr(), prefix_size);
    const int packet_size = opus_encode_float(encoder, input, frame_size,
            packet.ptrw() + prefix_size, packet.size() - prefix_size);
    if (packet_size < 0) {
        UtilityFunctions::printerr("Opus encoding failed: ", opus_strerror(packet_size));
        return PackedByteArray();
    }
    packet.resize(prefix_size + packet_size);
    return packet;
}

Error TwoVoipOpusEncoder::set_bitrate(int p_bitrate) {
    if (!encoder) return ERR_UNCONFIGURED;
    if (p_bitrate < 500 || p_bitrate > 512000) return ERR_INVALID_PARAMETER;
    if (opus_encoder_ctl(encoder, OPUS_SET_BITRATE(p_bitrate)) != OPUS_OK) return ERR_INVALID_PARAMETER;
    bitrate = p_bitrate;
    return OK;
}

Error TwoVoipOpusEncoder::set_complexity(int p_complexity) {
    if (!encoder) return ERR_UNCONFIGURED;
    if (p_complexity < 0 || p_complexity > 10) return ERR_INVALID_PARAMETER;
    if (opus_encoder_ctl(encoder, OPUS_SET_COMPLEXITY(p_complexity)) != OPUS_OK) return ERR_INVALID_PARAMETER;
    complexity = p_complexity;
    return OK;
}

Error TwoVoipOpusEncoder::set_signal_type(SignalType p_signal_type) {
    if (!encoder) return ERR_UNCONFIGURED;
    const int value = opus_signal(p_signal_type);
    if (!value || opus_encoder_ctl(encoder, OPUS_SET_SIGNAL(value)) != OPUS_OK) return ERR_INVALID_PARAMETER;
    signal_type = p_signal_type;
    return OK;
}

Error TwoVoipOpusEncoder::set_inband_perc(int p_packet_loss_perc) {
    if (!encoder) return ERR_UNCONFIGURED;
    if (p_packet_loss_perc < -1 || p_packet_loss_perc > 100) return ERR_INVALID_PARAMETER;
    int error = opus_encoder_ctl(encoder, OPUS_SET_INBAND_FEC(p_packet_loss_perc == -1 ? 0 : 1));
    if (error == OPUS_OK && p_packet_loss_perc != -1)
        error = opus_encoder_ctl(encoder, OPUS_SET_PACKET_LOSS_PERC(p_packet_loss_perc));
    if (error != OPUS_OK) return ERR_INVALID_PARAMETER;
    packet_loss_perc = p_packet_loss_perc;
    return OK;
}

void TwoVoipOpusEncoder::reset() {
    if (encoder)
        opus_encoder_ctl(encoder, OPUS_RESET_STATE);
}

TwoVoipOpusEncoder::~TwoVoipOpusEncoder() {
    destroy_encoder();
}
