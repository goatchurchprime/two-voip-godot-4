#include "echo_canceler_object.h"

#include <algorithm>
#include <cmath>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void TwoVoipEchoCanceler::_bind_methods() {
    ClassDB::bind_method(D_METHOD("initialize", "sample_rate", "frame_size"), &TwoVoipEchoCanceler::initialize);
    ClassDB::bind_method(D_METHOD("cancel_echo", "microphone_frames", "playback_frames"), &TwoVoipEchoCanceler::cancel_echo);
    ClassDB::bind_method(D_METHOD("reset"), &TwoVoipEchoCanceler::reset);
}

Error TwoVoipEchoCanceler::initialize(int p_sample_rate, int p_frame_size) {
    if (p_sample_rate <= 0 || p_frame_size <= 0)
        return ERR_INVALID_PARAMETER;
    if (echo_state != nullptr)
        speex_echo_state_destroy(echo_state);
    sample_rate = p_sample_rate;
    frame_size = p_frame_size;
    echo_state = speex_echo_state_init_mc(frame_size, sample_rate / 5, 2, 2);
    if (echo_state == nullptr)
        return ERR_CANT_CREATE;
    speex_echo_ctl(echo_state, SPEEX_ECHO_SET_SAMPLING_RATE, &sample_rate);
    microphone_samples.resize(frame_size * 2);
    playback_samples.resize(frame_size * 2);
    cleaned_samples.resize(frame_size * 2);
    return OK;
}

PackedVector2Array TwoVoipEchoCanceler::cancel_echo(const PackedVector2Array &p_microphone_frames, const PackedVector2Array &p_playback_frames) {
    if (echo_state == nullptr || p_microphone_frames.size() != frame_size || p_playback_frames.size() != frame_size) {
        UtilityFunctions::printerr("TwoVoipEchoCanceler requires two equal, initialized frame blocks");
        return p_microphone_frames;
    }
    for (int frame = 0; frame < frame_size; frame++) {
        microphone_samples[frame * 2] = static_cast<spx_int16_t>(std::round(std::clamp(p_microphone_frames[frame].x, -1.0F, 1.0F) * 32767.0F));
        microphone_samples[frame * 2 + 1] = static_cast<spx_int16_t>(std::round(std::clamp(p_microphone_frames[frame].y, -1.0F, 1.0F) * 32767.0F));
        playback_samples[frame * 2] = static_cast<spx_int16_t>(std::round(std::clamp(p_playback_frames[frame].x, -1.0F, 1.0F) * 32767.0F));
        playback_samples[frame * 2 + 1] = static_cast<spx_int16_t>(std::round(std::clamp(p_playback_frames[frame].y, -1.0F, 1.0F) * 32767.0F));
    }
    speex_echo_cancellation(echo_state, microphone_samples.data(), playback_samples.data(), cleaned_samples.data());
    PackedVector2Array cleaned_frames;
    cleaned_frames.resize(frame_size);
    for (int frame = 0; frame < frame_size; frame++)
        cleaned_frames[frame] = Vector2(cleaned_samples[frame * 2] / 32768.0F, cleaned_samples[frame * 2 + 1] / 32768.0F);
    return cleaned_frames;
}

void TwoVoipEchoCanceler::reset() {
    if (echo_state != nullptr)
        speex_echo_state_reset(echo_state);
}

TwoVoipEchoCanceler::~TwoVoipEchoCanceler() {
    if (echo_state != nullptr)
        speex_echo_state_destroy(echo_state);
}
