#include <godot_cpp/variant/utility_functions.hpp>

#include "handyopusnode.h"

#include <cassert>

using namespace godot;

void HandyOpusNode::_bind_methods() {
    ClassDB::bind_method(D_METHOD("createencoder", "audiosamplerate", "audiosamplesize", "opussamplerate", "opusframesize"), &HandyOpusNode::createencoder); 
    ClassDB::bind_method(D_METHOD("encodeopuspacket", "audiosamples"), &HandyOpusNode::encodeopuspacket);

    ClassDB::bind_method(D_METHOD("createdecoder", "opussamplerate", "opusframesize", "audiosamplerate", "audiosamplesize"), &HandyOpusNode::createdecoder); 
    ClassDB::bind_method(D_METHOD("decodeopuspacket", "bytepacket", "decode_fec"), &HandyOpusNode::decodeopuspacket); 

    ClassDB::bind_method(D_METHOD("destroyallsamplers"), &HandyOpusNode::decodeopuspacket); 
    ClassDB::bind_method(D_METHOD("maxabsvalue", "audiosamples"), &HandyOpusNode::maxabsvalue); 
}

HandyOpusNode::HandyOpusNode() {
    opusencoder = NULL;
    opusdecoder = NULL;
    speexresampler = NULL;
}

void HandyOpusNode::destroyallsamplers() {
    if (opusencoder != NULL) {
        opus_encoder_destroy(opusencoder);
        opusencoder = NULL;
    }
    if (opusdecoder != NULL) {
        opus_decoder_destroy(opusdecoder);
        opusdecoder = NULL;
    }
    if (speexresampler != NULL) {
        speex_resampler_destroy(speexresampler);
        speexresampler = NULL;
    }
}


HandyOpusNode::~HandyOpusNode() {
    destroyallsamplers();
}


int HandyOpusNode::createencoder(int audiosamplerate, int audiosamplesize, int opussamplerate, int opusframesize) {
    destroyallsamplers();
    this->opussamplerate = opussamplerate;
    this->opusframesize = opusframesize;
    this->audiosamplerate = audiosamplerate;
    this->audiosamplesize = audiosamplesize;
    this->Dtimeframeopus = opusframesize/opussamplerate;
    this->Dtimeframeaudio = opusframesize/opussamplerate;
    assert (Dtimeframeopus == Dtimeframeaudio);
    
    int channels = 2;

    // godotsamplerate = 44100 or 48000 (to disable resampling)
    if (audiosamplerate != opussamplerate) {
        int speexerror = 0; 
        int resamplingquality = 10;
        speexresampler = speex_resampler_init(channels, audiosamplerate, opussamplerate, resamplingquality, &speexerror);
    }

    // opussamplerate is one of 8000,12000,16000,24000,48000
    // opussamplesize is 480 for 10ms at 48000
    int opusapplication = OPUS_APPLICATION_VOIP; // or OPUS_APPLICATION_AUDIO
        // OPUS_APPLICATION_VOIP includes in-band forward error correction
    int opuserror = 0;
    opusencoder = opus_encoder_create(opussamplerate, channels, opusapplication, &opuserror);

    opusframebuffer.resize(opusframesize);
    bytepacketbuffer.resize(sizeof(float)*channels*opusframesize);

    return opuserror; 
}

float HandyOpusNode::maxabsvalue(const PackedVector2Array& audiosamples) {
    float r = 0.0F;
    float* p = (float*)opusframebuffer.ptr();
    int N = opusframebuffer.size()*2;
    for (int i = 0; i < N; i++) {
        float s = abs(p[i]);
        if (s > r)
            r = s;
    }
    return r;
}


PackedByteArray HandyOpusNode::encodeopuspacket(const PackedVector2Array& audiosamples) {
    unsigned int Nsamples = audiosamples.size();
    assert (Nsamples == audiosamplesize); 
    unsigned int Nopusframebuffer = opusframebuffer.size();
    assert (Nopusframebuffer == opusframesize); 
    int sxerr = speex_resampler_process_interleaved_float(speexresampler, 
            (float*)audiosamples.ptr(), &Nsamples, 
            (float*)opusframebuffer.ptrw(), &Nopusframebuffer);
    int bytepacketsize = opus_encode_float(opusencoder, (float*)opusframebuffer.ptr(), opusframebuffer.size(), 
                                                        (unsigned char*)bytepacketbuffer.ptrw(), bytepacketbuffer.size());
    return bytepacketbuffer.slice(0, bytepacketsize);
}



int HandyOpusNode::createdecoder(int opussamplerate, int opusframesize, int audiosamplerate, int audiosamplesize) {
    destroyallsamplers();
    this->opussamplerate = opussamplerate;
    this->opusframesize = opusframesize;
    this->audiosamplerate = audiosamplerate;
    this->audiosamplesize = audiosamplesize;
    this->Dtimeframeopus = opusframesize/opussamplerate;
    this->Dtimeframeaudio = opusframesize/opussamplerate;
    assert (Dtimeframeopus == Dtimeframeaudio);
    
    int channels = 2;

    if (audiosamplerate != opussamplerate) {
        int speexerror = 0; 
        int resamplingquality = 10;
        speexresampler = speex_resampler_init(channels, opussamplerate, audiosamplerate, resamplingquality, &speexerror);
    }

    int opuserror = 0;
    opusdecoder = opus_decoder_create(opussamplerate, channels, &opuserror);
    opusframebuffer.resize(opusframesize);
    return opuserror; 
}

PackedVector2Array HandyOpusNode::decodeopuspacket(const PackedByteArray& bytepacket, int decode_fec) {
    int decodedsamples = opus_decode_float(opusdecoder, bytepacket.ptr(), bytepacket.size(), (float*)opusframebuffer.ptrw(), opusframesize, decode_fec);
    assert (decodedsamples > 0);

    PackedVector2Array audiosamples;
    audiosamples.resize(audiosamplesize);
    unsigned int Nopusframebuffer = opusframebuffer.size();
    assert (Nopusframebuffer == opusframesize); 
    unsigned int Nsamples = audiosamples.size();
    assert (Nsamples == audiosamplesize); 
    int resampling_result = speex_resampler_process_interleaved_float(speexresampler, (float*)opusframebuffer.ptr(), &Nopusframebuffer, (float*)audiosamples.ptrw(), &Nsamples);
    return audiosamples;
}

