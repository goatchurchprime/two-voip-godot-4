/**************************************************************************/
/*  audio_effect_opus_chunked.h                                                */
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
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#ifndef AUDIO_EFFECT_OPUS_CHUNKED_H
#define AUDIO_EFFECT_OPUS_CHUNKED_H

#include <godot_cpp/classes/audio_effect.hpp>
#include <godot_cpp/classes/audio_effect_instance.hpp>
#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/mutex.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/node.hpp>

#include "opus.h"
#include "speex_resampler/speex_resampler.h"

#ifdef OVR_LIP_SYNC
    #include "OVRLipSync.h"
#else
    #include "OVRLipSync_Stub.h"
#endif

#ifdef RNNOISE
    #include "rnnoise.h"
#else
    #include "rnnoise_stub.h"
#endif

namespace godot {

class AudioEffectOpusChunked;

class AudioEffectOpusChunkedInstance : public AudioEffectInstance {
    GDCLASS(AudioEffectOpusChunkedInstance, AudioEffectInstance);
    friend class AudioEffectOpusChunked;
    Ref<AudioEffectOpusChunked> base;

protected:
	static void _bind_methods() {;};

public:
	virtual void _process(const void *src_buffer, AudioFrame *p_dst_frames, int p_frame_count) override; 
	virtual bool _process_silence() const override { return true; }
};

typedef enum {
    GovrLipSyncUninitialized,
    GovrLipSyncValid,
    GovrLipSyncUnavailable,
} GovrLipSyncStatus;

// This AudioEffect records 44.1kHz samples from the microphone into a ring buffer.
// If there are enough samples to make up a chunk (usually 20ms), chunk_available() returns true.
// An available chunk can be resampled up to 48kHz in a second ringbuffer by resampled_current_chunk()
// A resampled 48kHz chunk can be denoised into a third ringbuffer by denoise_resampled_chunk()
// read_chunk() will return a chunk from either of these three buffers depending on progress through the above two functions.

// chunk_to_lipsync() and read_opus() will apply to the same chunk as read_chunk(), so keep it consistent, 
//   This design is so we can defer calling either of these functions until we are sure it's a speaking episode
// drop_chunk() advances to next chunk, undrop_chunk() rolls back the buffer it so we can run the deferred functions
// and avoid pre-clipping of the spoken episode.

// chunk_to_opus_packet() is for encoding a series of chunks not in the ring buffer.

// TODO
// fix any crashes  
// plot the float value of the noise detector in the screen as a threshold
// plot the resampled denoised view in the same texture too. (aligned)
// hack the main scons module so it builds on the actions
// make a stub so it can run without the rnnoise library if necessary
// get help with this compiling

// finish folding and delivering GP leaflets


class AudioEffectOpusChunked : public AudioEffect {
    GDCLASS(AudioEffectOpusChunked, AudioEffect)
    friend class AudioEffectOpusChunkedInstance;

    int audiosamplerate = 44100;
    int audiosamplesize = 881;
    int ringbufferchunks = 50;

    PackedVector2Array audiosamplebuffer;  // size audiosamplesize*ringbufferchunks
    int chunknumber = -1; // -1 is uninitialized, -2 is error state
    int bufferend = 0;    // apply %(audiosamplesize*ringbufferchunks) for actual position
    int discardedchunks = 0;

    int opussamplerate = 48000;
    int opusframesize = 960;
    int opusbitrate = 24000;

    SpeexResamplerState* speexresampler = NULL;
    PackedVector2Array audioresampledbuffer;  // size opusframesize*ringbufferchunks
    PackedVector2Array singleresamplebuffer;  // size opusframesize, for use by chunk_to_opus_packet()
    int lastresampledchunk = -1;
    SpeexResamplerState* speexbackresampler = NULL;

    DenoiseState *st = NULL;
    int rnnoiseframesize = 0;
    PackedVector2Array audiodenoisedbuffer;  // size opusframesize*ringbufferchunks
    PackedFloat32Array audiodenoisedvalues;  // size ringbufferchunks
    int lastdenoisedchunk = -1;
    PackedFloat32Array rnnoise_in;
    PackedFloat32Array rnnoise_out;

    OpusEncoder* opusencoder = NULL;
    PackedByteArray opusbytebuffer;
    int lastopuschunk = -1;

    GovrLipSyncStatus govrlipsyncstatus = GovrLipSyncUninitialized;
    bool resampledlipsync;
    PackedFloat32Array visemes; 
    ovrLipSyncFrame ovrlipsyncframe;
    ovrLipSyncContext ovrlipsyncctx = 0;

    void process(const AudioFrame *p_src_frames, AudioFrame *p_dst_frames, int p_frame_count);

protected:
    static void _bind_methods();

    void resample_single_chunk(float* paudioresamples, const float* paudiosamples);
    float denoise_single_chunk(float* pdenoisedaudioresamples, const float* paudiosamples);
    PackedByteArray opus_frame_to_opus_packet(const PackedByteArray& prefixbytes, float* paudiosamples);
    
public:
    virtual Ref<AudioEffectInstance> _instantiate() override;

    void createencoder();
    void resetencoder(int Dreason=3);

    bool chunk_available();
    void drop_chunk();
    bool undrop_chunk();

    void resampled_current_chunk();
    float denoise_resampled_chunk();
    bool denoiser_available();
    PackedVector2Array read_chunk(bool resampled=false);
    float chunk_max(bool rms=false, bool resampled=false);

    PackedByteArray read_opus_packet(const PackedByteArray& prefixbytes); 
    void flush_opus_encoder(bool denoise);
    int chunk_to_lipsync(bool resampled=false); 
    PackedFloat32Array read_visemes() { return visemes; };

    PackedByteArray chunk_to_opus_packet(const PackedByteArray& prefixbytes, const PackedVector2Array& audiosamples, bool denoise=false);
    PackedVector2Array chunk_resample(const PackedVector2Array& audiosamples, bool denoise=false, bool backresample=false);

    void set_opussamplerate(int lopussamplerate) { chunknumber = -1; opussamplerate = lopussamplerate; };
    int get_opussamplerate() { return opussamplerate; };
    void set_opusframesize(int lopusframesize) { chunknumber = -1; opusframesize = lopusframesize; };
    int get_opusframesize() { return opusframesize; };
    void set_opusbitrate(int lopusbitrate) { chunknumber = -1; opusbitrate = lopusbitrate; };
    int get_opusbitrate() { return opusbitrate; };
    void set_audiosamplerate(int laudiosamplerate) { chunknumber = -1; audiosamplerate = laudiosamplerate; };
    int get_audiosamplerate() { return audiosamplerate; };
    void set_audiosamplesize(int laudiosamplesize) { chunknumber = -1; audiosamplesize = laudiosamplesize; };
    int get_audiosamplesize() { return audiosamplesize; };
    void set_audiosamplechunks(int laudiosamplechunks) { chunknumber = -1; ringbufferchunks = laudiosamplechunks; };
    int get_audiosamplechunks() { return ringbufferchunks; };

    AudioEffectOpusChunked();
    ~AudioEffectOpusChunked();
};

}

#endif // AUDIO_EFFECT_OPUS_CHUNKED_H
