#include "ovr_lipsync_backend.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>

#include <algorithm>

#ifdef OVR_LIP_SYNC
#include <OVRLipSync.h>
#endif

using namespace godot;

void OvrLipSyncBackend::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "sample_rate", "frame_size", "provider", "acceleration"), &OvrLipSyncBackend::configure, DEFVAL(2), DEFVAL(true));
    ClassDB::bind_method(D_METHOD("push_pcm", "mono_pcm"), &OvrLipSyncBackend::push_pcm);
    ClassDB::bind_method(D_METHOD("push_stereo_pcm", "stereo_pcm"), &OvrLipSyncBackend::push_stereo_pcm);
    ClassDB::bind_method(D_METHOD("reset"), &OvrLipSyncBackend::reset);
    ClassDB::bind_method(D_METHOD("is_available"), &OvrLipSyncBackend::is_available);
    ClassDB::bind_method(D_METHOD("is_ready"), &OvrLipSyncBackend::is_ready);
    ClassDB::bind_method(D_METHOD("get_levels"), &OvrLipSyncBackend::get_levels);
    ClassDB::bind_method(D_METHOD("get_status"), &OvrLipSyncBackend::get_status);
    ClassDB::bind_method(D_METHOD("get_frame_delay_ms"), &OvrLipSyncBackend::get_frame_delay_ms);
    ClassDB::bind_method(D_METHOD("get_laughter_score"), &OvrLipSyncBackend::get_laughter_score);
    ClassDB::bind_method(D_METHOD("get_run_count"), &OvrLipSyncBackend::get_run_count);
    ClassDB::bind_method(D_METHOD("get_average_run_ms"), &OvrLipSyncBackend::get_average_run_ms);
    ClassDB::bind_method(D_METHOD("get_maximum_run_ms"), &OvrLipSyncBackend::get_maximum_run_ms);
}

OvrLipSyncBackend::OvrLipSyncBackend() {
    levels.resize(15);
    levels.fill(0.0f);
    levels.set(0, 1.0f);
}

OvrLipSyncBackend::~OvrLipSyncBackend() {
    reset();
}

Error OvrLipSyncBackend::configure(int p_sample_rate, int p_frame_size, int p_provider, bool p_acceleration) {
    reset();
#ifndef OVR_LIP_SYNC
    status = "OVRLipSync support was not compiled into this build";
    return ERR_UNAVAILABLE;
#else
    if (p_sample_rate <= 0 || p_frame_size <= 0 || p_provider < 0 || p_provider > 2) {
        status = "invalid configuration";
        return ERR_INVALID_PARAMETER;
    }
    ovrLipSyncResult result = ovrLipSync_Initialize(p_sample_rate, p_frame_size);
    if (result != ovrLipSyncSuccess) {
        status = String("OVRLipSync initialization failed: ") + String::num_int64(result);
        return ERR_CANT_CREATE;
    }
    initialized = true;
    ovrLipSyncContext created_context = 0;
    result = ovrLipSync_CreateContextEx(
        &created_context,
        static_cast<ovrLipSyncContextProvider>(p_provider),
        p_sample_rate,
        p_acceleration
    );
    if (result != ovrLipSyncSuccess) {
        String failure = String("OVRLipSync context failed: ") + String::num_int64(result);
        reset();
        status = failure;
        return ERR_CANT_CREATE;
    }
    context = static_cast<int>(created_context);
    sample_rate = p_sample_rate;
    frame_size = p_frame_size;
    status = "ready";
    return OK;
#endif
}

bool OvrLipSyncBackend::push_pcm(const PackedFloat32Array &p_mono_pcm) {
#ifndef OVR_LIP_SYNC
    return false;
#else
    if (!initialized || context == 0 || p_mono_pcm.size() != frame_size) {
        status = p_mono_pcm.size() == frame_size ? "not configured" : "unexpected PCM frame size";
        return false;
    }
    ovrLipSyncFrame frame = {};
    frame.visemes = levels.ptrw();
    frame.visemesLength = 15;
    uint64_t started_usec = Time::get_singleton()->get_ticks_usec();
    ovrLipSyncResult result = ovrLipSync_ProcessFrameEx(
        static_cast<ovrLipSyncContext>(context),
        p_mono_pcm.ptr(),
        p_mono_pcm.size(),
        ovrLipSyncAudioDataType_F32_Mono,
        &frame
    );
    int64_t elapsed_usec = static_cast<int64_t>(Time::get_singleton()->get_ticks_usec() - started_usec);
    if (result != ovrLipSyncSuccess) {
        status = String("OVRLipSync processing failed: ") + String::num_int64(result);
        return false;
    }
    run_count += 1;
    total_run_usec += elapsed_usec;
    maximum_run_usec = std::max(maximum_run_usec, elapsed_usec);
    frame_delay_ms = frame.frameDelay;
    laughter_score = frame.laughterScore;
    status = "running";
    return true;
#endif
}

bool OvrLipSyncBackend::push_stereo_pcm(const PackedVector2Array &p_stereo_pcm) {
#ifndef OVR_LIP_SYNC
    return false;
#else
    if (!initialized || context == 0 || p_stereo_pcm.size() != frame_size) {
        status = p_stereo_pcm.size() == frame_size ? "not configured" : "unexpected PCM frame size";
        return false;
    }
    ovrLipSyncFrame frame = {};
    frame.visemes = levels.ptrw();
    frame.visemesLength = 15;
    uint64_t started_usec = Time::get_singleton()->get_ticks_usec();
    ovrLipSyncResult result = ovrLipSync_ProcessFrameEx(
        static_cast<ovrLipSyncContext>(context),
        p_stereo_pcm.ptr(),
        p_stereo_pcm.size(),
        ovrLipSyncAudioDataType_F32_Stereo,
        &frame
    );
    int64_t elapsed_usec = static_cast<int64_t>(Time::get_singleton()->get_ticks_usec() - started_usec);
    if (result != ovrLipSyncSuccess) {
        status = String("OVRLipSync processing failed: ") + String::num_int64(result);
        return false;
    }
    run_count += 1;
    total_run_usec += elapsed_usec;
    maximum_run_usec = std::max(maximum_run_usec, elapsed_usec);
    frame_delay_ms = frame.frameDelay;
    laughter_score = frame.laughterScore;
    status = "running";
    return true;
#endif
}

void OvrLipSyncBackend::reset() {
#ifdef OVR_LIP_SYNC
    if (context != 0) {
        ovrLipSync_DestroyContext(static_cast<ovrLipSyncContext>(context));
    }
    if (initialized) {
        ovrLipSync_Shutdown();
    }
#endif
    context = 0;
    initialized = false;
    sample_rate = 0;
    frame_size = 0;
    frame_delay_ms = 0;
    laughter_score = 0.0f;
    run_count = 0;
    total_run_usec = 0;
    maximum_run_usec = 0;
    status = "not configured";
}

bool OvrLipSyncBackend::is_available() const {
#ifdef OVR_LIP_SYNC
    return true;
#else
    return false;
#endif
}

bool OvrLipSyncBackend::is_ready() const { return initialized && context != 0; }
PackedFloat32Array OvrLipSyncBackend::get_levels() const { return levels; }
String OvrLipSyncBackend::get_status() const { return status; }
int OvrLipSyncBackend::get_frame_delay_ms() const { return frame_delay_ms; }
float OvrLipSyncBackend::get_laughter_score() const { return laughter_score; }
int OvrLipSyncBackend::get_run_count() const { return run_count; }
double OvrLipSyncBackend::get_average_run_ms() const { return run_count == 0 ? 0.0 : static_cast<double>(total_run_usec) / run_count / 1000.0; }
double OvrLipSyncBackend::get_maximum_run_ms() const { return static_cast<double>(maximum_run_usec) / 1000.0; }
