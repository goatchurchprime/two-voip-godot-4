#ifndef HANDYOPUSNODE_H
#define HANDYOPUSNODE_H

#include <godot_cpp/classes/node.hpp>
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

    PackedVector2Array resampledecodedopuspacket(const PackedVector2Array& lopusframebuffer);

    void destroyallsamplers(); 

    HandyOpusNode();
    ~HandyOpusNode();
};





}

#endif // HANDYOPUSNODE_H
