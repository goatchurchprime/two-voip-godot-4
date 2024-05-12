#ifndef HANDYOPUSNODE_H
#define HANDYOPUSNODE_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/audio_stream_generator_playback.hpp>
#include <godot_cpp/classes/audio_effect_capture.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "opus.h"
#include "speex_resampler/speex_resampler.h"

namespace godot {

class HandyOpusNode : public Node {
    GDCLASS(HandyOpusNode, Node)

protected:
    static void _bind_methods();

private:
    OpusEncoder* opusencoder;
    OpusDecoder* opusdecoder;
    SpeexResamplerState* speexresampler;
    int opussamplerate;
    int opusframesize;
    int audiosamplerate;
    int audiosamplesize;
    int opusbitrate;
    float Dtimeframeopus;
    float Dtimeframeaudio;

    PackedVector2Array opusframebuffer;
    PackedByteArray bytepacketbuffer;
    PackedVector2Array audiosamplesOut;


public:
    int createencoder(int audiosamplerate, int audiosamplesize, int opussamplerate, int opusframesize, int opusbitrate);  // defaults: (48000, 480, 44100, 441, 24000)
    PackedByteArray encodeopuspacket(const PackedVector2Array& audiosamples); 
    float maxabsvalue(const PackedVector2Array& audiosamples); 

    int createdecoder(int opussamplerate, int opusframesize, int audiosamplerate, int audiosamplesize); 
    PackedVector2Array decodeopuspacket(const PackedByteArray& bytepacket, int decode_fec);
    bool decodeopuspacketSP(const PackedByteArray& bytepacket, int decode_fec, AudioStreamGeneratorPlayback* audiostreamgeneratorplayback);

    PackedVector2Array resampledecodedopuspacket(const PackedVector2Array& lopusframebuffer);

    void destroyallsamplers(); 

    HandyOpusNode();
    ~HandyOpusNode();
};




class OpusEncoderNode : public Node {
    GDCLASS(OpusEncoderNode, Node)

protected:
    static void _bind_methods();

private:
    PackedVector2Array capturedaudioframe;
    PackedVector2Array resampledaudioframe;
    PackedByteArray opuspacketbuffer;

    OpusEncoder* opusencoder = NULL;
    SpeexResamplerState* speexresampler = NULL;

    int opussamplerate = 48000;
    int opusframesize = 960;
    int opusbitrate = 24000;
    
    int audiosamplerate = 44100;
    int audiosamplesize = 441;

    void destructencoder();
    
public:
    void set_opussamplerate(int lopussamplerate);
    int get_opussamplerate();
    void set_opusframesize(int lopusframesize);
    int get_opusframesize();
    void set_opusbitrate(int lopusbitrate);
    int get_opusbitrate();
    void set_audiosamplerate(int laudiosamplerate);
    int get_audiosamplerate();
    void set_audiosamplesize(int laudiosamplesize);
    int get_audiosamplesize();
    
    float captureaudio(AudioEffectCapture* audioeffectcapture);
    PackedByteArray convertaudio();

    OpusEncoderNode();
    ~OpusEncoderNode();
    
};

}

#endif // HANDYOPUSNODE_H
