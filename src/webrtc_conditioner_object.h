#ifndef WEBRTC_CONDITIONER_OBJECT_H
#define WEBRTC_CONDITIONER_OBJECT_H

#include <vector>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#ifdef WEBRTC_APM
#include "api/audio/audio_processing.h"
#endif

namespace godot {

class TwoVoipWebRTCConditioner : public RefCounted {
    GDCLASS(TwoVoipWebRTCConditioner, RefCounted)

#ifdef WEBRTC_APM
    rtc::scoped_refptr<webrtc::AudioProcessing> processor;
    webrtc::StreamConfig input_config;
    webrtc::StreamConfig output_config;
    webrtc::AudioProcessing::Config config;

    void apply_config();
#endif

    int input_chunk_size = 0;
    int output_chunk_size = 0;
    int input_frame_10ms = 0;
    int output_frame_10ms = 0;
    float gain = 1.0F;
    float last_peak = 0.0F;
    float last_rms = 0.0F;
    std::vector<float> capture_left;
    std::vector<float> capture_right;
    std::vector<float> render_left;
    std::vector<float> render_right;
    std::vector<Vector2> aligned_render_frames;
    std::vector<Vector2> previous_render_frames;
    std::vector<float> render_output_left;
    std::vector<float> render_output_right;
    std::vector<float> conditioned_left;
    std::vector<float> conditioned_right;

    void apply_gain_and_measure(PackedVector2Array &p_frames);

protected:
    static void _bind_methods();

public:
    enum DenoisingLevel {
        DENOISING_DISABLED,
        DENOISING_LOW,
        DENOISING_MODERATE,
        DENOISING_HIGH,
        DENOISING_VERY_HIGH,
    };

    Error initialize(int p_chunk_ms, int p_input_sample_rate, int p_output_sample_rate);
    int get_input_chunk_size() const { return input_chunk_size; }
    int get_output_chunk_size() const { return output_chunk_size; }
    PackedVector2Array condition(const PackedVector2Array &p_microphone_frames,
            const PackedVector2Array &p_render_frames);
    void set_echo_cancel_enabled(bool p_enabled);
    void set_denoising_level(DenoisingLevel p_level);
    void set_agc_enabled(bool p_enabled);
    void set_stream_delay_ms(int p_stream_delay_ms);
    int get_stream_delay_ms();
    void set_gain(float p_gain);
    float get_gain() const { return gain; }
    float get_peak() const { return last_peak; }
    float get_rms() const { return last_rms; }
    void reset();
};

} // namespace godot

VARIANT_ENUM_CAST(godot::TwoVoipWebRTCConditioner::DenoisingLevel);

#endif
