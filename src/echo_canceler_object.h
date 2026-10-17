#ifndef ECHO_CANCELER_OBJECT_H
#define ECHO_CANCELER_OBJECT_H

#include <vector>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include "speex/speex_echo.h"

namespace godot {

class TwoVoipEchoCanceler : public RefCounted {
    GDCLASS(TwoVoipEchoCanceler, RefCounted)

    SpeexEchoState *echo_state = nullptr;
    int sample_rate = 0;
    int frame_size = 0;
    std::vector<spx_int16_t> microphone_samples;
    std::vector<spx_int16_t> playback_samples;
    std::vector<spx_int16_t> cleaned_samples;

protected:
    static void _bind_methods();

public:
    Error initialize(int p_sample_rate, int p_frame_size);
    PackedVector2Array cancel_echo(const PackedVector2Array &p_microphone_frames, const PackedVector2Array &p_playback_frames);
    void reset();

    ~TwoVoipEchoCanceler();
};

}

#endif
