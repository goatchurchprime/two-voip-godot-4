#include "conditioner_object.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void TwoVoipConditioner::_bind_methods() {
    ClassDB::bind_method(D_METHOD("initialize", "input_sample_rate", "output_sample_rate", "input_chunk_size"),
            &TwoVoipConditioner::initialize);
    ClassDB::bind_method(D_METHOD("condition", "microphone_frames", "render_frames"), &TwoVoipConditioner::condition);
    ClassDB::bind_method(D_METHOD("set_stream_delay_ms", "stream_delay_ms"), &TwoVoipConditioner::set_stream_delay_ms);
    ClassDB::bind_method(D_METHOD("reset"), &TwoVoipConditioner::reset);
}

Error TwoVoipConditioner::initialize(int p_input_sample_rate, int p_output_sample_rate, int p_input_chunk_size) {
    if (p_input_sample_rate < 8000 || p_input_sample_rate > 384000 || p_input_sample_rate % 100 != 0 ||
            p_output_sample_rate < 8000 || p_output_sample_rate > 384000 || p_output_sample_rate % 100 != 0 ||
            p_input_chunk_size <= 0 || p_input_chunk_size % (p_input_sample_rate / 100) != 0) {
        return ERR_INVALID_PARAMETER;
    }

#ifdef WEBRTC_APM
    webrtc::AudioProcessing::Config config;
    config.pipeline.multi_channel_render = true;
    config.pipeline.multi_channel_capture = true;
    config.echo_canceller.enabled = true;
    config.echo_canceller.enforce_high_pass_filtering = false;
    processor = webrtc::AudioProcessingBuilder().SetConfig(config).Create();
    if (!processor || processor->Initialize() != webrtc::AudioProcessing::kNoError) {
        processor = nullptr;
        return ERR_CANT_CREATE;
    }

    input_chunk_size = p_input_chunk_size;
    input_frame_10ms = p_input_sample_rate / 100;
    output_frame_10ms = p_output_sample_rate / 100;
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
    return OK;
#else
    UtilityFunctions::printerr("This TwoVoIP build does not include WebRTC APM");
    return ERR_UNAVAILABLE;
#endif
}

PackedVector2Array TwoVoipConditioner::condition(const PackedVector2Array &p_microphone_frames,
        const PackedVector2Array &p_render_frames) {
    if (p_microphone_frames.size() != input_chunk_size || p_render_frames.size() > input_chunk_size) {
        UtilityFunctions::printerr("TwoVoipConditioner requires one full microphone block and at most one render block");
        return PackedVector2Array();
    }

#ifdef WEBRTC_APM
    if (!processor)
        return PackedVector2Array();

    const int block_count = input_chunk_size / input_frame_10ms;
    PackedVector2Array conditioned_frames;
    conditioned_frames.resize(block_count * output_frame_10ms);
    const webrtc::StreamConfig input_config(input_frame_10ms * 100, 2);
    const webrtc::StreamConfig output_config(output_frame_10ms * 100, 2);

    const int render_prefix_size = input_chunk_size - p_render_frames.size();
    for (int frame = 0; frame < render_prefix_size; frame++)
        aligned_render_frames[frame] = previous_render_frames[p_render_frames.size() + frame];
    for (int frame = render_prefix_size; frame < input_chunk_size; frame++)
        aligned_render_frames[frame] = p_render_frames[frame - render_prefix_size];
    previous_render_frames = aligned_render_frames;

    for (int block = 0; block < block_count; block++) {
        const int input_offset = block * input_frame_10ms;
        const int output_offset = block * output_frame_10ms;
        for (int frame = 0; frame < input_frame_10ms; frame++) {
            capture_left[frame] = p_microphone_frames[input_offset + frame].x;
            capture_right[frame] = p_microphone_frames[input_offset + frame].y;
            render_left[frame] = aligned_render_frames[input_offset + frame].x;
            render_right[frame] = aligned_render_frames[input_offset + frame].y;
        }

        const float *render_input[] = { render_left.data(), render_right.data() };
        float *render_output[] = { render_output_left.data(), render_output_right.data() };
        if (processor->ProcessReverseStream(render_input, input_config, input_config, render_output) !=
                webrtc::AudioProcessing::kNoError) {
            return PackedVector2Array();
        }
        processor->set_stream_delay_ms(stream_delay_ms);
        const float *capture_input[] = { capture_left.data(), capture_right.data() };
        float *capture_output[] = { conditioned_left.data(), conditioned_right.data() };
        if (processor->ProcessStream(capture_input, input_config, output_config, capture_output) !=
                webrtc::AudioProcessing::kNoError) {
            return PackedVector2Array();
        }
        for (int frame = 0; frame < output_frame_10ms; frame++)
            conditioned_frames[output_offset + frame] = Vector2(conditioned_left[frame], conditioned_right[frame]);
    }
    return conditioned_frames;
#else
    return PackedVector2Array();
#endif
}

void TwoVoipConditioner::set_stream_delay_ms(int p_stream_delay_ms) {
    stream_delay_ms = p_stream_delay_ms < 0 ? 0 : p_stream_delay_ms;
}

void TwoVoipConditioner::reset() {
#ifdef WEBRTC_APM
    if (processor)
        processor->Initialize();
#endif
}
