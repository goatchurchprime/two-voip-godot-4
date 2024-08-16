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
#include "rnnoise.h"

#ifdef OVR_LIP_SYNC
    #include "OVRLipSync.h"
#else
    #include "OVRLipSync_Stub.h"
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


// This AudioEffect copies samples from the microphone input into the ringbuffer audiosamplebuffer of size audiosamplesize*audiosamplechunks
// These chunks are resampled into audioresampledbuffer of size opusframesize*audiosamplechunks

// The chunking is for the purpose of the opus encoder.  GDScript code consumes these chunks as they become available.
// There is no reason to leave unprocessed data available in the buffer other than a processing delay.
// Use chunk_max() or chunk_rms() to determin whether to trigger a Vox signal (Voice Operated theshold) so 
// that the opus coding does not need to be applied to all the unspoken silence.
// Use undrop_chunks() to roll-back the buffer to back-date when the Vox should come on and stop pre-clipping

class AudioEffectOpusChunked : public AudioEffect {
    GDCLASS(AudioEffectOpusChunked, AudioEffect)
    friend class AudioEffectOpusChunkedInstance;

    int audiosamplerate = 44100;
    int audiosamplesize = 881;
    int ringbufferchunks = 50;

    PackedVector2Array audiosamplebuffer;  // size audiosamplesize*ringbufferchunks
    int chunknumber = -1;
    int bufferend = 0;    // apply %(audiosamplesize*ringbufferchunks) for actual position
    int discardedchunks = 0;

    int opussamplerate = 48000;
    int opusframesize = 960;
    int opusbitrate = 24000;

    SpeexResamplerState* speexresampler = NULL;
    PackedVector2Array audioresampledbuffer;  // size opusframesize*ringbufferchunks
    int lastresampledchunk = -1;
    PackedVector2Array singleresamplebuffer;  // size opusframesize, for use by chunk_to_opus_packet()
    
    DenoiseState *st = NULL;
    int rnnoiseframesize = 0;
    PackedVector2Array audiodenoisedbuffer;  // size opusframesize*ringbufferchunks
    PackedFloat32Array rnnoise_in;
    PackedFloat32Array rnnoise_out;

    OpusEncoder* opusencoder = NULL;
    PackedByteArray opusbytebuffer;

    GovrLipSyncStatus govrlipsyncstatus = GovrLipSyncUninitialized;
    PackedFloat32Array visemes; 
    ovrLipSyncFrame ovrlipsyncframe;
    ovrLipSyncContext ovrlipsyncctx = 0;

    void process(const AudioFrame *p_src_frames, AudioFrame *p_dst_frames, int p_frame_count);

protected:
    static void _bind_methods();

    float* resampled_current_chunk();
    PackedByteArray opus_frame_to_opus_packet(const PackedByteArray& prefixbytes, float* paudiosamples);
    void resample_single_chunk(float* paudiosamples, float* paudioresamples);

public:
    virtual Ref<AudioEffectInstance> _instantiate() override;

    void createencoder();
    void resetencoder(int Dreason=3);

    bool chunk_available();
    float chunk_max();
    float chunk_rms();
    int chunk_to_lipsync(); 
    float denoise_resampled_chunk();
    PackedFloat32Array read_visemes(); 
    PackedByteArray read_opus_packet(const PackedByteArray& prefixbytes); 
    PackedVector2Array read_chunk();
    PackedByteArray chunk_to_opus_packet(const PackedByteArray& prefixbytes, const PackedVector2Array& laudiosamplebuffer);
    void drop_chunk();
    bool undrop_chunk();

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
