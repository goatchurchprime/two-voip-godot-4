#include <godot_cpp/variant/utility_functions.hpp>

#include "handyopusnode.h"

#include <cassert>

using namespace godot;


HandyOpusNode::HandyOpusNode() {
    opus_decoder = opus_decoder_create(OPUS_SAMPLE_RATE, CHANNELS, &last_opus_error);
    assert (opus_decoder != NULL);
    resampler = speex_resampler_init(CHANNELS, OPUS_SAMPLE_RATE, GODOT_SAMPLE_RATE, RESAMPLING_QUALITY, &last_resampler_error);
    sample_buf.resize(OPUS_FRAME_SIZE);
    
    
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
    opus_decoder_destroy(opus_decoder);
    speex_resampler_destroy(resampler);
    
    destroyallsamplers();
}


int HandyOpusNode::createencoder(int opussamplerate, int opusframesize, int audiosamplerate, int audiosamplesize) {
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
    int opuserror = 0;
    opusencoder = opus_encoder_create(opussamplerate, channels, opusapplication, &opuserror);

    opusframebuffer.resize(opusframesize);
    bytepacketbuffer.resize(sizeof(float)*channels*opusframesize);

    return opuserror; 
}

PackedByteArray HandyOpusNode::encodeopuspacket(PackedVector2Array audiosamples) {
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


void HandyOpusNode::_bind_methods() {
    ClassDB::bind_method(D_METHOD("decode_opus_packet", "packet"), &HandyOpusNode::decode_opus_packet);

    ClassDB::bind_method(D_METHOD("createencoder", "opussamplerate", "opusframesize", "audiosamplerate", "audiosamplesize"), &HandyOpusNode::createencoder); 
    ClassDB::bind_method(D_METHOD("encodeopuspacket", "audiosamples"), &HandyOpusNode::encodeopuspacket);

}

PackedVector2Array HandyOpusNode::decode_opus_packet(const PackedByteArray& packet) {
    PackedVector2Array samples;
    samples.resize(OPUS_FRAME_SIZE * GODOT_SAMPLE_RATE / OPUS_SAMPLE_RATE);

    int decoded_samples = opus_decode_float(opus_decoder, packet.ptr(), packet.size(), (float*)sample_buf.ptrw(), OPUS_FRAME_SIZE, 0);
    assert (decoded_samples > 0);

    unsigned int num_samples = samples.size();
    unsigned int num_buffer_samples = sample_buf.size();
    int resampling_result = speex_resampler_process_interleaved_float(resampler, (float*)sample_buf.ptr(), &num_buffer_samples, (float*)samples.ptrw(), &num_samples);
    samples.resize(num_samples);
    assert (resampling_result == 0);

    return samples;
}




