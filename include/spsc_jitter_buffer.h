#ifndef SPSC_JITTER_BUFFER_H
#define SPSC_JITTER_BUFFER_H

#include <godot_cpp/classes/packed_data_container.hpp>
#include <godot_cpp/classes/audio_frame.hpp>

#include "ring_buffer.h"


namespace godot {


class SPSCJitterBuffer{

protected:
    RingBuffer<Vector2> sample_queue;

public:
    SPSCJitterBuffer(int frame_size);
    ~SPSCJitterBuffer();

    // Push samples here and the time they were received
    void push_samples(int timestamp, PackedVector2Array samples);

    // Pop samples from here on the realtime audio thread
    void pop_samples(AudioFrame* samples, int frames);
};


}

#endif