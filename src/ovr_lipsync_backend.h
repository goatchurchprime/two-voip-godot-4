#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class OvrLipSyncBackend : public RefCounted {
    GDCLASS(OvrLipSyncBackend, RefCounted)

    PackedFloat32Array levels;
    String status = "not configured";
    int sample_rate = 0;
    int frame_size = 0;
    int context = 0;
    int frame_delay_ms = 0;
    int run_count = 0;
    int64_t total_run_usec = 0;
    int64_t maximum_run_usec = 0;
    float laughter_score = 0.0f;
    int smoothing = -1;
    bool initialized = false;

protected:
    static void _bind_methods();

public:
    OvrLipSyncBackend();
    ~OvrLipSyncBackend();

    Error configure(int p_sample_rate, int p_frame_size, const String &p_library_dir = "", int p_provider = 2, bool p_acceleration = true);
    bool push_pcm(const PackedFloat32Array &p_mono_pcm);
    bool push_stereo_pcm(const PackedVector2Array &p_stereo_pcm);
    Error set_smoothing(int p_amount);
    void reset();

    bool is_available() const;
    bool is_ready() const;
    PackedFloat32Array get_levels() const;
    String get_status() const;
    int get_frame_delay_ms() const;
    float get_laughter_score() const;
    int get_smoothing() const;
    int get_run_count() const;
    double get_average_run_ms() const;
    double get_maximum_run_ms() const;
};

} // namespace godot
