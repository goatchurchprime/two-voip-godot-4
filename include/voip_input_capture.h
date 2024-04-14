#ifndef VOIP_INPUT_CAPTURE_H
#define VOIP_INPUT_CAPTURE_H

#include <godot_cpp/classes/audio_effect_capture.hpp>

#include "audio_stream_voip.h"
#include "opus.h"
#include "speex/speex_resampler.h"


namespace godot {


class VOIPInputCapture : public AudioEffectCapture {
    GDCLASS(VOIPInputCapture, AudioEffectCapture)

protected:
    static void _bind_methods();

private:
    int _last_opus_error = 0;
    int _last_resampler_error = 0;
    OpusEncoder* _opus_encoder;
    SpeexResamplerState* _resampler;
    PackedVector2Array _sample_buf; // Resample audio here before sending through opus

    PackedByteArray _sample_buf_to_packet(PackedVector2Array samples);

public:
    // Constants

    const int GODOT_SAMPLE_RATE = 44100;
    const int OPUS_FRAME_SIZE = 480;
    const int OPUS_SAMPLE_RATE = 48000;
    const int CHANNELS = 2;
    const int RESAMPLING_QUALITY = 10; // 0 to 10
    const int DEFAULT_BITRATE = 24000; // bits / second from 500 to 512000
    const int EXPECTED_PACKET_LOSS = 5; // percentage from 0 to 100


    // Properties

    bool muted = false;
    float volume = 1; // [0, 1]


    // Property Set / Get

    void set_muted(const bool _muted) { muted = _muted; }
    bool is_muted() const { return muted; }

    void set_volume(const float _volume) { volume = _volume; } // Error condition for outside [0,1]?
    float get_volume() const { return volume; }

    void set_bitrate(const int _bitrate);
    int get_bitrate() const;


    // Methods

    VOIPInputCapture();
    ~VOIPInputCapture();

    void send_test_packets();

};


}

#endif // VOIP_INPUT_CAPTURE_H