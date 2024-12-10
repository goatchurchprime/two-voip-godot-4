/**************************************************************************/
/*  audio_effect_opus_chunked.cpp                                              */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED httpTO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "audio_effect_opus_chunked.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void AudioEffectOpusChunked::_bind_methods() {

    ClassDB::bind_method(D_METHOD("set_opussamplerate", "opussamplerate"), &AudioEffectOpusChunked::set_opussamplerate);
    ClassDB::bind_method(D_METHOD("get_opussamplerate"), &AudioEffectOpusChunked::get_opussamplerate);
    ClassDB::bind_method(D_METHOD("set_opusframesize", "opusframesize"), &AudioEffectOpusChunked::set_opusframesize);
    ClassDB::bind_method(D_METHOD("get_opusframesize"), &AudioEffectOpusChunked::get_opusframesize);
    ClassDB::bind_method(D_METHOD("set_opusbitrate", "opusbitrate"), &AudioEffectOpusChunked::set_opusbitrate);
    ClassDB::bind_method(D_METHOD("get_opusbitrate"), &AudioEffectOpusChunked::get_opusbitrate);
    ClassDB::bind_method(D_METHOD("set_opuscomplexity", "opuscomplexity"), &AudioEffectOpusChunked::set_opuscomplexity);
    ClassDB::bind_method(D_METHOD("get_opuscomplexity"), &AudioEffectOpusChunked::get_opuscomplexity);
    ClassDB::bind_method(D_METHOD("set_opusoptimizeforvoice", "opusoptimizeforvoice"), &AudioEffectOpusChunked::set_opusoptimizeforvoice);
    ClassDB::bind_method(D_METHOD("get_opusoptimizeforvoice"), &AudioEffectOpusChunked::get_opusoptimizeforvoice);
    ClassDB::bind_method(D_METHOD("set_audiosamplerate", "audiosamplerate"), &AudioEffectOpusChunked::set_audiosamplerate);
    ClassDB::bind_method(D_METHOD("get_audiosamplerate"), &AudioEffectOpusChunked::get_audiosamplerate);
    ClassDB::bind_method(D_METHOD("set_audiosamplesize", "audiosamplesize"), &AudioEffectOpusChunked::set_audiosamplesize);
    ClassDB::bind_method(D_METHOD("get_audiosamplesize"), &AudioEffectOpusChunked::get_audiosamplesize);
    ClassDB::bind_method(D_METHOD("set_audiosamplechunks", "audiosamplechunks"), &AudioEffectOpusChunked::set_audiosamplechunks);
    ClassDB::bind_method(D_METHOD("get_audiosamplechunks"), &AudioEffectOpusChunked::get_audiosamplechunks);

    ADD_PROPERTY(PropertyInfo(Variant::INT, "opussamplerate", PROPERTY_HINT_RANGE, "20,192000,1"), "set_opussamplerate", "get_opussamplerate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opusframesize", PROPERTY_HINT_RANGE, "20,2880,1"), "set_opusframesize", "get_opusframesize");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opusbitrate", PROPERTY_HINT_RANGE, "500,200000,1"), "set_opusbitrate", "get_opusbitrate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "opuscomplexity", PROPERTY_HINT_RANGE, "0,10,1"), "set_opuscomplexity", "get_opuscomplexity");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "opusoptimizeforvoice"), "set_opusoptimizeforvoice", "get_opusoptimizeforvoice");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplerate", PROPERTY_HINT_RANGE, "20,192000,1"), "set_audiosamplerate", "get_audiosamplerate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplesize", PROPERTY_HINT_RANGE, "10,4000,1"), "set_audiosamplesize", "get_audiosamplesize");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audiosamplechunks", PROPERTY_HINT_RANGE, "1,200,1"), "set_audiosamplechunks", "get_audiosamplechunks");

    ClassDB::bind_method(D_METHOD("chunk_available"), &AudioEffectOpusChunked::chunk_available);
    ClassDB::bind_method(D_METHOD("resampled_current_chunk"), &AudioEffectOpusChunked::resampled_current_chunk);
    ClassDB::bind_method(D_METHOD("denoiser_available"), &AudioEffectOpusChunked::denoiser_available);
    ClassDB::bind_method(D_METHOD("denoise_resampled_chunk"), &AudioEffectOpusChunked::denoise_resampled_chunk);
    ClassDB::bind_method(D_METHOD("chunk_max", "rms", "resampled"), &AudioEffectOpusChunked::chunk_max);

    ClassDB::bind_method(D_METHOD("chunk_to_lipsync", "resampled"), &AudioEffectOpusChunked::chunk_to_lipsync);
    ClassDB::bind_method(D_METHOD("read_visemes"), &AudioEffectOpusChunked::read_visemes);
    
    ClassDB::bind_method(D_METHOD("read_chunk", "resampled"), &AudioEffectOpusChunked::read_chunk);
    ClassDB::bind_method(D_METHOD("drop_chunk"), &AudioEffectOpusChunked::drop_chunk);
    ClassDB::bind_method(D_METHOD("undrop_chunk"), &AudioEffectOpusChunked::undrop_chunk);
    ClassDB::bind_method(D_METHOD("read_opus_packet", "prefixbytes"), &AudioEffectOpusChunked::read_opus_packet);
    ClassDB::bind_method(D_METHOD("resetencoder"), &AudioEffectOpusChunked::resetencoder);
    ClassDB::bind_method(D_METHOD("chunk_to_opus_packet", "prefixbytes", "audiosamples", "denoise"), &AudioEffectOpusChunked::chunk_to_opus_packet);
    ClassDB::bind_method(D_METHOD("chunk_resample", "audiosamples", "denoise", "backresample"), &AudioEffectOpusChunked::chunk_resample);
}

const int MAXPREFIXBYTES = 100;

AudioEffectOpusChunked::AudioEffectOpusChunked() {
    visemes.resize(ovrLipSyncViseme_Count + 3);  // we append laughterscore, framedelay and framenumber to this list
    ovrlipsyncframe.visemes = visemes.ptrw();
    ovrlipsyncframe.visemesLength = ovrLipSyncViseme_Count;
    ovrlipsyncframe.laughterCategories = NULL;
    ovrlipsyncframe.laughterCategoriesLength = 0;
}

AudioEffectOpusChunked::~AudioEffectOpusChunked() 
{
    deleteencoder();
};

Ref<AudioEffectInstance> AudioEffectOpusChunked::_instantiate() {
    Ref<AudioEffectOpusChunkedInstance> ins;
    ins.instantiate();
    ins->base = Ref<AudioEffectOpusChunked>(this);
    return ins;
}

void AudioEffectOpusChunked::resetencoder() {
    if ((opusframesize == 0) || (chunknumber == -1)) 
        return;
    if (speexresampler != NULL)
        speex_resampler_reset_mem(speexresampler);
    if (speexbackresampler != NULL) 
        speex_resampler_reset_mem(speexbackresampler);
    if (st != NULL) 
        rnnoise_init(st, NULL);        
    if (opusencoder != NULL) 
        opus_encoder_ctl(opusencoder, OPUS_RESET_STATE);
    lastopuschunk = chunknumber - 1;
}


void AudioEffectOpusChunked::deleteencoder() {
    if (speexresampler != NULL) {
        speex_resampler_destroy(speexresampler);
        speexresampler = NULL;
    }
    if (opusencoder != NULL) {
        opus_encoder_destroy(opusencoder);
        opusencoder = NULL;
    }

    if (govrlipsyncstatus == GovrLipSyncValid) {
        auto rc = ovrLipSync_DestroyContext(ovrlipsyncctx);
        godot::UtilityFunctions::prints("lipsync destroy context", rc); 
        rc = ovrLipSync_Shutdown();
        godot::UtilityFunctions::prints("lipsync shutdown", rc); 
        govrlipsyncstatus = GovrLipSyncUninitialized;
    }
    
    if (st != NULL) {
        rnnoise_destroy(st);
        st = NULL;
    }

    if (speexbackresampler != NULL) {
        speex_resampler_destroy(speexbackresampler);
        speexbackresampler = NULL;
    }
}

void AudioEffectOpusChunked::createencoder() {
    deleteencoder();  
    audiosamplebuffer.resize(audiosamplesize*ringbufferchunks); 
    chunknumber = 0;
    bufferend = 0;

#ifdef OVR_LIP_SYNC
    govrlipsyncstatus = GovrLipSyncUninitialized;
#else
    govrlipsyncstatus = GovrLipSyncUnavailable;
#endif

    if (opusframesize == 0)
        return;
        
    int channels = 2;
    float Dtimeframeopus = opusframesize*1.0F/opussamplerate;
    float Dtimeframeaudio = audiosamplesize*1.0F/audiosamplerate;
    audioresampledbuffer.resize(opusframesize*ringbufferchunks);
    lastresampledchunk = -1;
    singleresamplebuffer.resize(opusframesize);
    if (audiosamplesize != opusframesize) {
        int speexerror = 0; 
        int resamplingquality = 10;
        // the speex resampler needs sample rates to be consistent with the sample buffer sizes
        speexresampler = speex_resampler_init(channels, audiosamplerate, opussamplerate, resamplingquality, &speexerror);
        godot::UtilityFunctions::prints("Encoder timeframeopus resampler", Dtimeframeopus, "timeframeaudio", Dtimeframeaudio); 
    } else {
        godot::UtilityFunctions::prints("Encoder timeframeopus no-resampling needed", Dtimeframeopus, "timeframeaudio", Dtimeframeaudio); 
    }

    st = rnnoise_create(NULL);
    rnnoiseframesize = rnnoise_get_frame_size();
    rnnoise_in.resize(rnnoiseframesize);
    rnnoise_out.resize(rnnoiseframesize);
    audiodenoisedbuffer.resize(opusframesize*ringbufferchunks);
    audiodenoisedvalues.resize(ringbufferchunks);
    lastdenoisedchunk = -1;

    if ((opussamplerate > 0) && (opussamplerate < 8000)) {
        godot::UtilityFunctions::print("non-opus-samplerate for resample testing");
        opusencoder = NULL;
        return;
    }

    // opussamplerate is one of 8000,12000,16000,24000,48000
    // opussamplesize is 480 for 10ms at 48000
    int opusapplication = OPUS_APPLICATION_VOIP; // this option includes in-band forward error correction
    int opuserror = 0;
    opusencoder = opus_encoder_create(opussamplerate, channels, opusapplication, &opuserror);
    if (opuserror != 0) {
        godot::UtilityFunctions::printerr("opus_encoder_create error ", opuserror);
        if (!((opussamplerate == 8000) || (opussamplerate == 12000) || (opussamplerate == 16000) || (opussamplerate == 24000) || (opussamplerate == 48000)))
            godot::UtilityFunctions::printerr("  opussamplerate must be  one of 8000,12000,16000,24000,48000");
        chunknumber = -2;
        return;
    }
    int opuserror2 = opus_encoder_ctl(opusencoder, OPUS_SET_BITRATE(opusbitrate));
    if (opuserror2 != 0) {
        godot::UtilityFunctions::printerr("opus_encoder_ctl bitrate error ", opuserror2);
        chunknumber = -2;
        return;
    }
    int opuserror3 = opus_encoder_ctl(opusencoder, OPUS_SET_COMPLEXITY(complexity));
    if (opuserror3 != 0) {
        godot::UtilityFunctions::printerr("opus_encoder_ctl complexity error ", opuserror3);
        chunknumber = -2;
        return;
    }
    int opuserror4 = opus_encoder_ctl(opusencoder, OPUS_SET_SIGNAL(signal_type));
    if (opuserror4 != 0) {
        godot::UtilityFunctions::printerr("opus_encoder_ctl signal_type error ", opuserror4);
        chunknumber = -2;
        return;
    }
    // we don't set DTX because it's for letting opus decide internally when it is quiet https://github.com/xiph/opus/issues/381
    //int opuserror5 = opus_encoder_ctl(opusencoder, OPUS_SET_DTX(1));

    opusbytebuffer.resize(sizeof(float)*channels*opusframesize + MAXPREFIXBYTES);
    lastopuschunk = -1;
}

void AudioEffectOpusChunkedInstance::_process(const void *src_buffer, AudioFrame *p_dst_frames, int p_frame_count) {
    base->process((const AudioFrame *)src_buffer, p_dst_frames, p_frame_count); 
}

void AudioEffectOpusChunked::process(const AudioFrame *p_src_frames, AudioFrame *p_dst_frames, int p_frame_count) {
    if (chunknumber < 0) { 
        if (chunknumber == -1) 
            createencoder();
        else
            return;
    }
    for (int i = 0; i < p_frame_count; i++) {
        p_dst_frames[i] = p_src_frames[i];
        audiosamplebuffer.set(bufferend % audiosamplebuffer.size(), Vector2(p_src_frames[i].left, p_src_frames[i].right));
        bufferend += 1; 
        if (bufferend == (chunknumber + ringbufferchunks)*audiosamplesize) {
            drop_chunk(); 
            discardedchunks += 1; 
            if (!Engine::get_singleton()->is_editor_hint())
                if ((discardedchunks < 5) || ((discardedchunks % 1000) == 0))
                    godot::UtilityFunctions::prints("Discarding chunk", discardedchunks, bufferend, (chunknumber + 1)*audiosamplesize); 
        }
    }
}

bool AudioEffectOpusChunked::chunk_available() {
    return ((chunknumber >= 0) && (bufferend >= (chunknumber + 1)*audiosamplesize)); 
}

void AudioEffectOpusChunked::drop_chunk() {
    if (!chunk_available()) 
        return;
    chunknumber += 1;
}

bool AudioEffectOpusChunked::undrop_chunk() {
    if ((chunknumber < 0) || (chunknumber == 0)) 
        return false;
    if (bufferend >= (chunknumber - 1 + ringbufferchunks)*audiosamplesize)
        return false;
    chunknumber -= 1;
    return true;
}


void AudioEffectOpusChunked::resampled_current_chunk() {
    if (!chunk_available() || (opusframesize == 0)) 
        return;
    if (lastresampledchunk < chunknumber) {
        float* paudiosamples = (float*)audiosamplebuffer.ptrw() + (chunknumber % ringbufferchunks)*audiosamplesize*2; 
        float* paudioresamples = (float*)audioresampledbuffer.ptrw() + (chunknumber % ringbufferchunks)*opusframesize*2; 
        resample_single_chunk(paudioresamples, paudiosamples);
        lastresampledchunk = chunknumber;
    }
}

bool AudioEffectOpusChunked::denoiser_available() {
    return (rnnoise_get_size() != 0);
}

float AudioEffectOpusChunked::denoise_resampled_chunk() {
    if (!chunk_available() || (opusframesize == 0)) 
        return -1.0;
    resampled_current_chunk();
    int rchunknumber = (chunknumber % ringbufferchunks);
    if (lastdenoisedchunk < chunknumber) {
        float* paudioresamples = (float*)audioresampledbuffer.ptrw() + rchunknumber*opusframesize*2; 
        float* pdenoisedaudioresamples = (float*)audiodenoisedbuffer.ptrw() + rchunknumber*opusframesize*2;
        audiodenoisedvalues[rchunknumber] = denoise_single_chunk(pdenoisedaudioresamples, paudioresamples);
        lastdenoisedchunk = chunknumber; 
    }
    return audiodenoisedvalues[rchunknumber];
}


float AudioEffectOpusChunked::chunk_max(bool rms, bool resampled) {
    if (!chunk_available()) 
        return -1.0;
    float* p;
    int n;
    if ((opusframesize == 0) || (chunknumber > lastresampledchunk) || !resampled) {
        p = (float*)audiosamplebuffer.ptr() + (chunknumber % ringbufferchunks)*audiosamplesize*2; 
        n = audiosamplesize*2; 
    } else {
        p = (chunknumber > lastdenoisedchunk ? (float*)audioresampledbuffer.ptr() : (float*)audiodenoisedbuffer.ptr());
        p += (chunknumber % ringbufferchunks)*opusframesize*2; 
        n = opusframesize*2;
    } 

    if (rms) {
        float s = 0.0F;
        for (int i = 0; i < n; i++) {
            s += p[i]*p[i];
        }
        return sqrt(s/n);
    } else {
        float r = 0.0F;
        for (int i = 0; i < n; i++) {
            float s = fabs(p[i]);
            if (s > r)
                r = s;
        }
        return r;
    }
}

PackedVector2Array AudioEffectOpusChunked::read_chunk(bool resampled) {
    if (!chunk_available() || (resampled && (opusframesize == 0))) 
        return PackedVector2Array();
    if (!resampled) {
        int begin = (chunknumber % ringbufferchunks)*audiosamplesize; 
        return audiosamplebuffer.slice(begin, begin + audiosamplesize); 
    }
    resampled_current_chunk();
    int begin = (chunknumber % ringbufferchunks)*opusframesize; 
    if (chunknumber > lastdenoisedchunk)
        return audioresampledbuffer.slice(begin, begin + opusframesize); 
    return audiodenoisedbuffer.slice(begin, begin + opusframesize); 
}

PackedByteArray AudioEffectOpusChunked::read_opus_packet(const PackedByteArray& prefixbytes) {
    if (!chunk_available() || (opusframesize == 0))
        return PackedByteArray();
    if (chunknumber != lastopuschunk + 1) 
        godot::UtilityFunctions::prints("Warning: opuspacket conversion not in sequence", lastopuschunk, chunknumber);
    lastopuschunk = chunknumber;
    resampled_current_chunk();
    float* paudioresamples = (chunknumber > lastdenoisedchunk ? (float*)audioresampledbuffer.ptr() : (float*)audiodenoisedbuffer.ptr()) \
                             + (chunknumber % ringbufferchunks)*opusframesize*2; 
    return opus_frame_to_opus_packet(prefixbytes, paudioresamples);
}


int AudioEffectOpusChunked::chunk_to_lipsync(bool resampled) {
#ifdef OVR_LIP_SYNC
    if (!chunk_available() || (resampled && (opusframesize == 0))) 
        return -1;
        
    if (govrlipsyncstatus == GovrLipSyncUninitialized) {
        resampledlipsync = resampled;
        ovrLipSyncResult rc = ovrLipSync_Initialize(resampledlipsync ? opussamplerate : audiosamplerate, 
                                                    resampledlipsync ? opusframesize : audiosamplesize);
        if (rc == ovrLipSyncSuccess) {
            ovrLipSyncContextProvider provider = ovrLipSyncContextProvider_EnhancedWithLaughter;
            rc = ovrLipSync_CreateContextEx(&ovrlipsyncctx, provider, audiosamplerate, true);
            if (rc == ovrLipSyncSuccess) {
                govrlipsyncstatus = GovrLipSyncValid;
                godot::UtilityFunctions::prints("lipsync context successfully created:", ovrlipsyncctx); 
            } else {
                godot::UtilityFunctions::printerr("Failed to create ovrLipSync context: ", rc);
                rc = ovrLipSync_Shutdown();
                godot::UtilityFunctions::printerr("lipsync shutdown due to lack of context: ", rc);
                govrlipsyncstatus = GovrLipSyncUnavailable;
            }
        } else {
            if (rc == ovrLipSyncError_MissingDLL)
                godot::UtilityFunctions::printerr("Failed to initialize ovrLipSynchunk_to_lipsyncc engine: Cannot find OVRLipSync.DLL.");
            else
                godot::UtilityFunctions::printerr("Failed to initialize ovrLipSync engine: ", rc);
            govrlipsyncstatus = GovrLipSyncUnavailable;
        }
    }

    if (govrlipsyncstatus != GovrLipSyncValid)
        return -1;
    if (resampledlipsync != resampled) {
        godot::UtilityFunctions::printerr("Cannot mix lipsync sample rates");
        return -1;
    }

    const void* audioBuffer;
    int sampleCount;
    if (!resampled) {
        audioBuffer = (float*)audiosamplebuffer.ptr() + (chunknumber % ringbufferchunks)*audiosamplesize*2; 
        sampleCount = audiosamplesize; 
    } else {
        resampled_current_chunk();
        audioBuffer = (chunknumber > lastdenoisedchunk ? (float*)audioresampledbuffer.ptr() : (float*)audiodenoisedbuffer.ptr()) \
                      + (chunknumber % ringbufferchunks)*opusframesize*2; 
        sampleCount = opusframesize;
    } 

    auto rc = ovrLipSync_ProcessFrameEx(ovrlipsyncctx, audioBuffer, sampleCount,
                                        ovrLipSyncAudioDataType_F32_Stereo, &ovrlipsyncframe);
    visemes[ovrLipSyncViseme_Count] = ovrlipsyncframe.laughterScore;
    visemes[ovrLipSyncViseme_Count+1] = ovrlipsyncframe.frameDelay;
    visemes[ovrLipSyncViseme_Count+2] = ovrlipsyncframe.frameNumber;
    float* array = (float*)visemes.ptrw();
    int res = 0;
    for (int i = 1; i < ovrLipSyncViseme_Count; i++) {
        if (array[i] > array[res])
            res = i;
    }
    return res;
#else
    return -1;
#endif
}

PackedByteArray AudioEffectOpusChunked::chunk_to_opus_packet(const PackedByteArray& prefixbytes, const PackedVector2Array& audiosamples, bool denoise) {
    if (chunknumber < 0) {
        if (chunknumber == -1) 
            createencoder();
        else
            return PackedByteArray();
    }
    resample_single_chunk((float*)singleresamplebuffer.ptrw(), (float*)audiosamples.ptr());
    if (denoise)
        denoise_single_chunk((float*)singleresamplebuffer.ptrw(), (float*)singleresamplebuffer.ptrw());
    return opus_frame_to_opus_packet(prefixbytes, (float*)singleresamplebuffer.ptrw());
}

PackedVector2Array AudioEffectOpusChunked::chunk_resample(const PackedVector2Array& audiosamples, bool denoise, bool backresample) {
    if (chunknumber < 0) {
        if (chunknumber == -1) 
            createencoder();
        else
            return PackedVector2Array();
    }
    resample_single_chunk((float*)singleresamplebuffer.ptrw(), (float*)audiosamples.ptr());
    if (denoise)
        denoise_single_chunk((float*)singleresamplebuffer.ptrw(), (float*)singleresamplebuffer.ptrw());
    if ((audiosamplesize != opusframesize) && backresample) {
        if (speexbackresampler == NULL) {
            int channels = 2;
            int speexerror = 0; 
            int resamplingquality = 10;
            speexbackresampler = speex_resampler_init(channels, opussamplerate, audiosamplerate, resamplingquality, &speexerror);
        }
        PackedVector2Array singlereresamplebuffer;
        singlereresamplebuffer.resize(audiosamplesize);
        unsigned int Uaudiosamplesize = audiosamplesize;
        unsigned int Uopusframesize = opusframesize;
        int sxerr = speex_resampler_process_interleaved_float(speexbackresampler, 
                                                              (float*)singleresamplebuffer.ptrw(), &Uopusframesize,
                                                              (float*)singlereresamplebuffer.ptrw(), &Uaudiosamplesize);
        return singlereresamplebuffer;
    } else {
        return singleresamplebuffer;
    }
}


void AudioEffectOpusChunked::resample_single_chunk(float* paudioresamples, const float* paudiosamples) {
    if (audiosamplesize != opusframesize) {
        unsigned int Uaudiosamplesize = audiosamplesize;
        unsigned int Uopusframesize = opusframesize;
        int sxerr = speex_resampler_process_interleaved_float(speexresampler, 
                                                              paudiosamples, &Uaudiosamplesize, 
                                                              paudioresamples, &Uopusframesize);
    } else {
        for (int i = 0; i < opusframesize*2; i++)
            paudioresamples[i] = paudiosamples[i];
    }
}

float AudioEffectOpusChunked::denoise_single_chunk(float* pdenoisedaudioresamples, const float* paudiosamples) {
    int nnoisechunks = (int)(opusframesize/rnnoiseframesize);
    float res = -1.0F;
    if (nnoisechunks*rnnoiseframesize == opusframesize) {
        float* rin = (float*)rnnoise_in.ptr();
        float* rout = (float*)rnnoise_out.ptr();
        for (int j = 0; j < nnoisechunks; j++) {
            const float* p = paudiosamples + 2*j*rnnoiseframesize;
            for (int i = 0; i < rnnoiseframesize; i++) {
                rin[i] = (p[i*2] + p[i*2+1])*0.5F*32768.0F;
            }
            float r = rnnoise_process_frame(st, rout, rin);
            if (r > res)
                res = r;
            float* q = pdenoisedaudioresamples + 2*j*rnnoiseframesize;
            for (int i = 0; i < rnnoiseframesize; i++) {
                q[i*2] = rout[i]/32768.0F;
                q[i*2+1] = rout[i]/32768.0F;
            }
        }
    } else {
        godot::UtilityFunctions::printerr("Warning: noise framesize", rnnoiseframesize, "does not divide opusframesize", opusframesize);
        for (int i = 0; i < opusframesize; i++) {
            pdenoisedaudioresamples[i*2] = paudiosamples[i*2];
            pdenoisedaudioresamples[i*2 + 1] = paudiosamples[i*2 + 1];
        }
    }
    return res;
}


PackedByteArray AudioEffectOpusChunked::opus_frame_to_opus_packet(const PackedByteArray& prefixbytes, float* paudiosamples) {
    unsigned char* popusbytes = opusbytebuffer.ptrw(); 
    int nprefbytes = prefixbytes.size();
    if (nprefbytes > MAXPREFIXBYTES) {
        godot::UtilityFunctions::printerr("Error: prefixbytes longer than ", MAXPREFIXBYTES);
        nprefbytes = 0;
        return PackedByteArray();
    }
    if (nprefbytes != 0) {
        memcpy(popusbytes, prefixbytes.ptr(), nprefbytes); 
    }
    if (opusencoder == NULL) {
        godot::UtilityFunctions::printerr("Error: opusencoder is null");
        return PackedByteArray();
    }
    int bytepacketsize = opus_encode_float(opusencoder, paudiosamples, opusframesize, 
                                           popusbytes + nprefbytes, opusbytebuffer.size() - nprefbytes);
    return opusbytebuffer.slice(0, nprefbytes + bytepacketsize);
}




