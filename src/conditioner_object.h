#ifndef CONDITIONER_OBJECT_H
#define CONDITIONER_OBJECT_H

#include <vector>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include "speex/speex_resampler.h"

namespace godot {

class TwoVoipConditioner : public RefCounted {
    GDCLASS(TwoVoipConditioner, RefCounted)

    SpeexResamplerState *resampler = nullptr;
    int input_chunk_size = 0;
    int output_chunk_size = 0;
    int channels = 0;
    float gain = 1.0F;
    float last_peak = 0.0F;
    float last_rms = 0.0F;
    std::vector<float> mono_input;
    std::vector<float> mono_output;

    void destroy_resampler();
    void apply_gain_and_measure(PackedVector2Array &p_frames);

protected:
    static void _bind_methods();

public:
    Error initialize(int p_chunk_ms, int p_input_sample_rate, int p_output_sample_rate, int p_channels);
    int get_input_chunk_size() const { return input_chunk_size; }
    int get_output_chunk_size() const { return output_chunk_size; }
    PackedVector2Array condition(const PackedVector2Array &p_microphone_frames,
            const PackedVector2Array &p_render_frames);
    void set_gain(float p_gain);
    float get_gain() const { return gain; }
    float get_peak() const { return last_peak; }
    float get_rms() const { return last_rms; }
    void reset();

    ~TwoVoipConditioner();
};

} // namespace godot

#endif
