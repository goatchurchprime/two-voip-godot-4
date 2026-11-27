#include "webrtc_conditioner_object.h"

#include <algorithm>
#include <cmath>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void TwoVoipWebRTCConditioner::_bind_methods() {
    BIND_ENUM_CONSTANT(DENOISING_DISABLED);
    BIND_ENUM_CONSTANT(DENOISING_LOW);
    BIND_ENUM_CONSTANT(DENOISING_MODERATE);
    BIND_ENUM_CONSTANT(DENOISING_HIGH);
    BIND_ENUM_CONSTANT(DENOISING_VERY_HIGH);

    ClassDB::bind_method(D_METHOD("initialize", "chunk_ms", "input_sample_rate", "output_sample_rate", "channels"),
            &TwoVoipWebRTCConditioner::initialize);
    ClassDB::bind_method(D_METHOD("get_input_chunk_size"), &TwoVoipWebRTCConditioner::get_input_chunk_size);
    ClassDB::bind_method(D_METHOD("get_output_chunk_size"), &TwoVoipWebRTCConditioner::get_output_chunk_size);
    ClassDB::bind_method(D_METHOD("condition", "microphone_frames", "render_frames"), &TwoVoipWebRTCConditioner::condition);
    ClassDB::bind_method(D_METHOD("set_echo_cancel_enabled", "enabled"),
            &TwoVoipWebRTCConditioner::set_echo_cancel_enabled);
    ClassDB::bind_method(D_METHOD("set_denoising_level", "level"), &TwoVoipWebRTCConditioner::set_denoising_level);
    ClassDB::bind_method(D_METHOD("set_agc_enabled", "enabled"), &TwoVoipWebRTCConditioner::set_agc_enabled);
    ClassDB::bind_method(D_METHOD("set_stream_delay_ms", "stream_delay_ms"), &TwoVoipWebRTCConditioner::set_stream_delay_ms);
    ClassDB::bind_method(D_METHOD("get_stream_delay_ms"), &TwoVoipWebRTCConditioner::get_stream_delay_ms);
    ClassDB::bind_method(D_METHOD("set_gain", "gain"), &TwoVoipWebRTCConditioner::set_gain);
    ClassDB::bind_method(D_METHOD("get_gain"), &TwoVoipWebRTCConditioner::get_gain);
    ClassDB::bind_method(D_METHOD("get_peak"), &TwoVoipWebRTCConditioner::get_peak);
    ClassDB::bind_method(D_METHOD("get_rms"), &TwoVoipWebRTCConditioner::get_rms);
    ClassDB::bind_method(D_METHOD("reset"), &TwoVoipWebRTCConditioner::reset);
}

void TwoVoipWebRTCConditioner::apply_gain_and_measure(PackedVector2Array &p_frames) {
    last_peak = 0.0F;
    double sum_squares = 0.0;
    for (int frame = 0; frame < p_frames.size(); frame++) {
        Vector2 sample = p_frames[frame] * gain;
        p_frames.set(frame, sample);
        last_peak = std::max(last_peak, std::max(std::abs(sample.x), std::abs(sample.y)));
        sum_squares += sample.length_squared();
    }
    last_rms = p_frames.is_empty() ? 0.0F : std::sqrt(sum_squares / (p_frames.size() * 2));
}

Error TwoVoipWebRTCConditioner::initialize(int p_chunk_ms, int p_input_sample_rate, int p_output_sample_rate,
        int p_channels) {
    input_chunk_size = 0;
    output_chunk_size = 0;
    channels = 0;
    last_peak = 0.0F;
    last_rms = 0.0F;
    if (p_chunk_ms <= 0 || p_chunk_ms % 10 != 0 ||
            p_input_sample_rate < 8000 || p_input_sample_rate > 384000 || p_input_sample_rate % 100 != 0 ||
            p_output_sample_rate < 8000 || p_output_sample_rate > 384000 || p_output_sample_rate % 100 != 0 ||
            (p_channels != 1 && p_channels != 2)) {
        return ERR_INVALID_PARAMETER;
    }

#ifdef WEBRTC_APM
    config.pipeline.multi_channel_render = true;
    config.pipeline.multi_channel_capture = p_channels == 2;
    config.echo_canceller.enforce_high_pass_filtering = false;
    processor = webrtc::AudioProcessingBuilder().SetConfig(config).Create();
    if (!processor || processor->Initialize() != webrtc::AudioProcessing::kNoError) {
        processor = nullptr;
        return ERR_CANT_CREATE;
    }

    input_frame_10ms = p_input_sample_rate / 100;
    output_frame_10ms = p_output_sample_rate / 100;
    input_chunk_size = input_frame_10ms * (p_chunk_ms / 10);
    output_chunk_size = output_frame_10ms * (p_chunk_ms / 10);
    channels = p_channels;
    capture_left.resize(input_frame_10ms);
    capture_right.resize(input_frame_10ms);
    render_left.resize(input_frame_10ms);
    render_right.resize(input_frame_10ms);
    aligned_render_frames.resize(input_chunk_size);
    previous_render_frames.resize(input_chunk_size, Vector2());
    render_output_left.resize(input_frame_10ms);
    render_output_right.resize(input_frame_10ms);
    conditioned_left.resize(output_frame_10ms);
    conditioned_right.resize(output_frame_10ms);

    input_config = webrtc::StreamConfig(input_frame_10ms * 100, 2);
    output_config = webrtc::StreamConfig(output_frame_10ms * 100, channels);

    return OK;
#else
    UtilityFunctions::printerr("This TwoVoIP build does not include WebRTC APM");
    return ERR_UNAVAILABLE;
#endif
}

PackedVector2Array TwoVoipWebRTCConditioner::condition(const PackedVector2Array &p_microphone_frames,
        const PackedVector2Array &p_render_frames) {
    last_peak = 0.0F;
    last_rms = 0.0F;
    if (p_microphone_frames.size() != input_chunk_size) {
        UtilityFunctions::printerr("TwoVoipWebRTCConditioner expected ", input_chunk_size,
                " microphone frames, got ", p_microphone_frames.size());
        return PackedVector2Array();
    }
#ifdef WEBRTC_APM
    if (!processor)
        return PackedVector2Array();
    if (config.echo_canceller.enabled && p_render_frames.size() > input_chunk_size) {
        UtilityFunctions::printerr("TwoVoipWebRTCConditioner expected at most ", input_chunk_size,
                " render frames, got ", p_render_frames.size());
        return PackedVector2Array();
    }

    const int block_count = input_chunk_size / input_frame_10ms;
    PackedVector2Array conditioned_frames;
    conditioned_frames.resize(output_chunk_size);

    if (config.echo_canceller.enabled) {
        const int render_prefix_size = input_chunk_size - p_render_frames.size();
        for (int frame = 0; frame < render_prefix_size; frame++)
            aligned_render_frames[frame] = previous_render_frames[p_render_frames.size() + frame];
        for (int frame = render_prefix_size; frame < input_chunk_size; frame++)
            aligned_render_frames[frame] = p_render_frames[frame - render_prefix_size];
        previous_render_frames = aligned_render_frames;
    }

    for (int block = 0; block < block_count; block++) {
        const int input_offset = block * input_frame_10ms;
        const int output_offset = block * output_frame_10ms;
        for (int frame = 0; frame < input_frame_10ms; frame++) {
            capture_left[frame] = p_microphone_frames[input_offset + frame].x;
            capture_right[frame] = p_microphone_frames[input_offset + frame].y;
            if (config.echo_canceller.enabled) {
                render_left[frame] = aligned_render_frames[input_offset + frame].x;
                render_right[frame] = aligned_render_frames[input_offset + frame].y;
            }
        }

        if (config.echo_canceller.enabled) {
            const float *render_input[] = { render_left.data(), render_right.data() };
            float *render_output[] = { render_output_left.data(), render_output_right.data() };
            if (processor->ProcessReverseStream(render_input, input_config, input_config, render_output) !=
                    webrtc::AudioProcessing::kNoError) {
                return PackedVector2Array();
            }
        }
        const float *capture_input[] = { capture_left.data(), capture_right.data() };
        if (channels == 1) {
            float *capture_output[] = { conditioned_left.data() };
            if (processor->ProcessStream(capture_input, input_config, output_config, capture_output) !=
                    webrtc::AudioProcessing::kNoError) {
                return PackedVector2Array();
            }
            for (int frame = 0; frame < output_frame_10ms; frame++)
                conditioned_frames[output_offset + frame] = Vector2(conditioned_left[frame], conditioned_left[frame]);
        } else {
            float *capture_output[] = { conditioned_left.data(), conditioned_right.data() };
            if (processor->ProcessStream(capture_input, input_config, output_config, capture_output) !=
                    webrtc::AudioProcessing::kNoError) {
                return PackedVector2Array();
            }
            for (int frame = 0; frame < output_frame_10ms; frame++)
                conditioned_frames[output_offset + frame] = Vector2(conditioned_left[frame], conditioned_right[frame]);
        }
    }
    apply_gain_and_measure(conditioned_frames);
    return conditioned_frames;
#else
    return PackedVector2Array();
#endif
}

#ifdef WEBRTC_APM
void TwoVoipWebRTCConditioner::apply_config() {
    if (processor)
        processor->ApplyConfig(config);
}
#endif

void TwoVoipWebRTCConditioner::set_echo_cancel_enabled(bool p_enabled) {
#ifdef WEBRTC_APM
    config.echo_canceller.enabled = p_enabled;
    if (!p_enabled)
        previous_render_frames.assign(previous_render_frames.size(), Vector2());
    apply_config();
#endif
}

void TwoVoipWebRTCConditioner::set_denoising_level(DenoisingLevel p_level) {
#ifdef WEBRTC_APM
    switch (p_level) {
        case DENOISING_DISABLED:
            config.noise_suppression.enabled = false;
            break;
        case DENOISING_LOW:
            config.noise_suppression.enabled = true;
            config.noise_suppression.level = webrtc::AudioProcessing::Config::NoiseSuppression::kLow;
            break;
        case DENOISING_MODERATE:
            config.noise_suppression.enabled = true;
            config.noise_suppression.level = webrtc::AudioProcessing::Config::NoiseSuppression::kModerate;
            break;
        case DENOISING_HIGH:
            config.noise_suppression.enabled = true;
            config.noise_suppression.level = webrtc::AudioProcessing::Config::NoiseSuppression::kHigh;
            break;
        case DENOISING_VERY_HIGH:
            config.noise_suppression.enabled = true;
            config.noise_suppression.level = webrtc::AudioProcessing::Config::NoiseSuppression::kVeryHigh;
            break;
        default:
            UtilityFunctions::push_error("Invalid TwoVoipWebRTCConditioner denoising level");
            return;
    }
    apply_config();
#endif
}

void TwoVoipWebRTCConditioner::set_agc_enabled(bool p_enabled) {
#ifdef WEBRTC_APM
    config.gain_controller1.enabled = false;
    config.gain_controller2.enabled = p_enabled;
    config.gain_controller2.input_volume_controller.enabled = false;
    config.gain_controller2.adaptive_digital.enabled = p_enabled;
    apply_config();
#endif
}

void TwoVoipWebRTCConditioner::set_stream_delay_ms(int p_stream_delay_ms) {
#ifdef WEBRTC_APM
    if (processor)
        processor->set_stream_delay_ms(p_stream_delay_ms);
#endif
}

int TwoVoipWebRTCConditioner::get_stream_delay_ms() {
#ifdef WEBRTC_APM
    if (processor)
        return processor->GetStatistics().delay_ms.value_or(-1);
#endif
    return -1;
}

void TwoVoipWebRTCConditioner::set_gain(float p_gain) {
    if (std::isfinite(p_gain) && p_gain >= 0.0F)
        gain = p_gain;
}


void TwoVoipWebRTCConditioner::reset() {
#ifdef WEBRTC_APM
    if (processor)
        processor->Initialize();
#endif
    last_peak = 0.0F;
    last_rms = 0.0F;
}
