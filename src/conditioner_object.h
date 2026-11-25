#ifndef CONDITIONER_OBJECT_H
#define CONDITIONER_OBJECT_H

#include <vector>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#ifdef WEBRTC_APM
#include "api/audio/audio_processing.h"
#endif

namespace godot {

class TwoVoipConditioner : public RefCounted {
    GDCLASS(TwoVoipConditioner, RefCounted)

#ifdef WEBRTC_APM
    rtc::scoped_refptr<webrtc::AudioProcessing> processor;
#endif
    int input_chunk_size = 0;
    int input_frame_10ms = 0;
    int output_frame_10ms = 0;
    int stream_delay_ms = 0;
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

protected:
    static void _bind_methods();

public:
    Error initialize(int p_input_sample_rate, int p_output_sample_rate, int p_input_chunk_size);
    PackedVector2Array condition(const PackedVector2Array &p_microphone_frames,
            const PackedVector2Array &p_render_frames);
    void set_stream_delay_ms(int p_stream_delay_ms);
    void reset();
};

} // namespace godot

#endif
