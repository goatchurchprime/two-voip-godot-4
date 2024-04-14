#include "spsc_jitter_buffer.h"

#include <cassert>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;


SPSCJitterBuffer::SPSCJitterBuffer(int frame_size){
    sample_queue.resize(16);
}

SPSCJitterBuffer::~SPSCJitterBuffer(){
}


void SPSCJitterBuffer::push_samples(int timestamp, PackedVector2Array samples){
    int num_written = sample_queue.write(samples.ptr(), samples.size());

    if(num_written < samples.size()){
        UtilityFunctions::print("TOO MANY SAMPLES - samples: ", samples.size(), " written: ", num_written);
        sample_queue.advance_read(32768); // Skip forward
    }
    // UtilityFunctions::print("num_written: ",num_written);
}

void SPSCJitterBuffer::pop_samples(AudioFrame* samples, int frames){
    assert(sizeof(AudioFrame) == sizeof(Vector2));
    int num_read = sample_queue.read((Vector2*) samples, frames, true);

    // DEBUG
    //PackedVector2Array debug_samples;
    //debug_samples.resize(num_read);
    //memcpy(debug_samples.ptrw(), samples, sizeof(AudioFrame) * num_read);
    //UtilityFunctions::print("Samples: ", debug_samples);

    if(num_read < frames) UtilityFunctions::print("NOT ENOUGH SAMPLES - frames: ", frames, " num_read: ", num_read);
    // UtilityFunctions::print("num_read: ",num_read);
}