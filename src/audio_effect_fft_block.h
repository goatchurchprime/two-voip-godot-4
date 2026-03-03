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

#ifndef AUDIO_EFFECT_FFT_BLOCK_H
#define AUDIO_EFFECT_FFT_BLOCK_H

#include <godot_cpp/classes/audio_effect.hpp>
#include <godot_cpp/classes/audio_effect_instance.hpp>
#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/mutex.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/audio_stream_playback_resampled.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>


#include "speex_resampler/speex_resampler.h"

namespace godot {
    

class AudioEffectFFTBlock;

class AudioEffectFFTBlockInstance : public AudioEffectInstance {
    GDCLASS(AudioEffectFFTBlockInstance, AudioEffectInstance);
    friend class AudioEffectFFTBlock;
    Ref<AudioEffectFFTBlock> base;

protected:
    static void _bind_methods() {;};

public:
    virtual void _process(const void *src_buffer, AudioFrame *p_dst_frames, int p_frame_count) override; 
    virtual bool _process_silence() const override { return true; }

    ~AudioEffectFFTBlockInstance();
};

class AudioEffectFFTBlock : public AudioEffect {
    GDCLASS(AudioEffectFFTBlock, AudioEffect)
    friend class AudioEffectFFTBlockInstance;

    int audiosamplerate = 44100;
    int audiosamplesize = 882;

    PackedVector2Array audiosamplebuffer; 

    int audiosamplebuffer_size = 10240;
    int fftsize = 1024;
    int fftrows = 16;
    int fftirow = 0;
    PackedByteArray fftslab; 
    
    Ref<Image> audiosampleframetextureimage;
    Ref<ImageTexture> audiosampleframetexture;
    PackedFloat32Array windowarray;

    int bufferend = 0;    // apply %(audiosamplesize*ringbufferchunks) for actual position

    int opussamplerate = 48000;
    int opusframesize = 960;

    SpeexResamplerState* speexresampler = NULL;
    PackedVector2Array audioresampledbuffer;  // size opusframesize*ringbufferchunks
    PackedVector2Array singleresamplebuffer;  // size opusframesize, for use by chunk_to_opus_packet()
    SpeexResamplerState* speexbackresampler = NULL;

    int instanceinstantiations = 0;
    void process(const AudioFrame *p_src_frames, AudioFrame *p_dst_frames, int p_frame_count);

protected:
    static void _bind_methods();

    void push_sample(const Vector2 &sample);
    void resample_single_chunk(float* paudioresamples, const float* paudiosamples);
    
public:
    virtual Ref<AudioEffectInstance> _instantiate() override;

    void set_images(Ref<Image> laudiosampleframetextureimage, Ref<ImageTexture> laudiosampleframetexture, PackedFloat32Array lwindowarray);

    void createencoder();
    void deleteencoder();
    void resetencoder(bool clearbuffers);

    bool chunk_available();
    void drop_chunk();
    bool undrop_chunk();
    void push_chunk(const PackedVector2Array& audiosamples); 

    void set_opussamplerate(int lopussamplerate) { opussamplerate = lopussamplerate; };
    int get_opussamplerate() { return opussamplerate; };
    void set_opusframesize(int lopusframesize) { opusframesize = lopusframesize; };
    int get_opusframesize() { return opusframesize; };
    void set_audiosamplerate(int laudiosamplerate) { audiosamplerate = laudiosamplerate; };
    int get_audiosamplerate() { return audiosamplerate; };
    void set_audiosamplesize(int laudiosamplesize) { audiosamplesize = laudiosamplesize; };
    int get_audiosamplesize() { return audiosamplesize; };

    AudioEffectFFTBlock();
    ~AudioEffectFFTBlock();
};

}

#endif // AUDIO_EFFECT_FFT_BLOCK_H
