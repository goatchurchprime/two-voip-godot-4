#include <godot_cpp/variant/utility_functions.hpp>

#include "audio_stream_voip.h"
#include "audio_stream_playback_voip.h"

#include <cassert>

using namespace godot;



AudioStreamVOIP::AudioStreamVOIP() : jitter_buffer(OPUS_FRAME_SIZE * GODOT_SAMPLE_RATE / OPUS_SAMPLE_RATE) {
    _opus_decoder = opus_decoder_create(OPUS_SAMPLE_RATE, CHANNELS, &_last_opus_error);
    assert(_opus_decoder != NULL);

    _resampler = speex_resampler_init(CHANNELS, OPUS_SAMPLE_RATE, GODOT_SAMPLE_RATE, RESAMPLING_QUALITY, &_last_resampler_error);
    assert( _resampler != NULL );

    _sample_buf.resize(OPUS_FRAME_SIZE);
}

AudioStreamVOIP::~AudioStreamVOIP(){
    opus_decoder_destroy(_opus_decoder);
    speex_resampler_destroy(_resampler);
}


void AudioStreamVOIP::_bind_methods(){

    // Methods

    ClassDB::bind_method(D_METHOD("push_packet", "packet"), &AudioStreamVOIP::push_packet);
}


Ref<AudioStreamPlayback> AudioStreamVOIP::_instantiate_playback() const{
    Ref<AudioStreamPlaybackVOIP> playback;
    playback.instantiate();
    playback->base = Ref<AudioStreamVOIP>(this);
    return playback;
}

void AudioStreamVOIP::push_packet(const PackedByteArray& packet){
    // UtilityFunctions::print("Received bytes: ", packet.size());

    // Convert to PackedVector2Array in 44100 kHz

    PackedVector2Array samples;
    samples.resize(OPUS_FRAME_SIZE * GODOT_SAMPLE_RATE / OPUS_SAMPLE_RATE);

    int decoded_samples = opus_decode_float(_opus_decoder, packet.ptr(), packet.size(), (float*) _sample_buf.ptrw(), OPUS_FRAME_SIZE, 0);
    assert( decoded_samples > 0 );

    unsigned int num_samples = samples.size();
    unsigned int num_buffer_samples = _sample_buf.size();
    int resampling_result = speex_resampler_process_interleaved_float(_resampler, (float*) _sample_buf.ptr(), &num_buffer_samples, (float*) samples.ptrw(), &num_samples);
    samples.resize(num_samples);
    assert( resampling_result == 0 );

    // Push to the jitter buffer

    jitter_buffer.push_samples(0, samples);
}
