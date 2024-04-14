#include "audio_stream_playback_voip.h"

using namespace godot;


void AudioStreamPlaybackVOIP::_start(double _){
}

void AudioStreamPlaybackVOIP::_stop(){
}

bool AudioStreamPlaybackVOIP::_is_playing() const{
    return false;
}



// WARNING: REALTIME THREAD
// DO NOT MUTEX LOCK
// DO NOT MALLOC/NEW
int32_t AudioStreamPlaybackVOIP::_mix(AudioFrame *buffer, double rate_scale, int32_t frames){
    memset(buffer, 0, sizeof(AudioFrame) * frames);

    base->jitter_buffer.pop_samples(buffer, frames);

    return frames;
}