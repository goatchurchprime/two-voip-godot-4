#include "conditioner_object.h"

#include <cstdint>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void TwoVoipConditioner::_bind_methods() {
    ClassDB::bind_method(D_METHOD("initialize", "chunk_ms", "input_sample_rate", "output_sample_rate"),
            &TwoVoipConditioner::initialize);
    ClassDB::bind_method(D_METHOD("get_input_chunk_size"), &TwoVoipConditioner::get_input_chunk_size);
    ClassDB::bind_method(D_METHOD("get_output_chunk_size"), &TwoVoipConditioner::get_output_chunk_size);
    ClassDB::bind_method(D_METHOD("condition", "microphone_frames", "render_frames"), &TwoVoipConditioner::condition);
    ClassDB::bind_method(D_METHOD("reset"), &TwoVoipConditioner::reset);
}

void TwoVoipConditioner::destroy_resampler() {
    if (resampler) {
        speex_resampler_destroy(resampler);
        resampler = nullptr;
    }
}

Error TwoVoipConditioner::initialize(int p_chunk_ms, int p_input_sample_rate, int p_output_sample_rate) {
    destroy_resampler();
    input_chunk_size = 0;
    output_chunk_size = 0;
    if (p_chunk_ms <= 0 || p_input_sample_rate <= 0 || p_output_sample_rate <= 0 ||
            (static_cast<int64_t>(p_input_sample_rate) * p_chunk_ms) % 1000 != 0 ||
            (static_cast<int64_t>(p_output_sample_rate) * p_chunk_ms) % 1000 != 0) {
        return ERR_INVALID_PARAMETER;
    }

    input_chunk_size = p_input_sample_rate * p_chunk_ms / 1000;
    output_chunk_size = p_output_sample_rate * p_chunk_ms / 1000;
    if (p_input_sample_rate == p_output_sample_rate)
        return OK;

    int error = RESAMPLER_ERR_SUCCESS;
    resampler = speex_resampler_init(2, p_input_sample_rate, p_output_sample_rate,
            SPEEX_RESAMPLER_QUALITY_DEFAULT, &error);
    if (!resampler || error != RESAMPLER_ERR_SUCCESS) {
        UtilityFunctions::printerr("TwoVoipConditioner Speex resampler initialization failed: ", error);
        destroy_resampler();
        input_chunk_size = 0;
        output_chunk_size = 0;
        return ERR_CANT_CREATE;
    }
    return OK;
}

PackedVector2Array TwoVoipConditioner::condition(const PackedVector2Array &p_microphone_frames,
        const PackedVector2Array &p_render_frames) {
    (void)p_render_frames;
    if (input_chunk_size <= 0 || output_chunk_size <= 0) {
        UtilityFunctions::printerr("TwoVoipConditioner is not initialized");
        return PackedVector2Array();
    }
    if (p_microphone_frames.size() != input_chunk_size) {
        UtilityFunctions::printerr("TwoVoipConditioner expected ", input_chunk_size,
                " microphone frames, got ", p_microphone_frames.size());
        return PackedVector2Array();
    }
    if (!resampler)
        return p_microphone_frames;

    PackedVector2Array output;
    output.resize(output_chunk_size);
    spx_uint32_t input_frames = input_chunk_size;
    spx_uint32_t output_frames = output_chunk_size;
    const int error = speex_resampler_process_interleaved_float(resampler,
            reinterpret_cast<const float *>(p_microphone_frames.ptr()), &input_frames,
            reinterpret_cast<float *>(output.ptrw()), &output_frames);
    if (error != RESAMPLER_ERR_SUCCESS || input_frames != static_cast<spx_uint32_t>(input_chunk_size) ||
            output_frames != static_cast<spx_uint32_t>(output_chunk_size)) {
        UtilityFunctions::printerr("TwoVoipConditioner resampling failed: error ", error,
                ", consumed ", input_frames, " of ", input_chunk_size,
                ", produced ", output_frames, " of ", output_chunk_size, " frames");
        return PackedVector2Array();
    }
    return output;
}

void TwoVoipConditioner::reset() {
    if (resampler)
        speex_resampler_reset_mem(resampler);
}

TwoVoipConditioner::~TwoVoipConditioner() {
    destroy_resampler();
}
