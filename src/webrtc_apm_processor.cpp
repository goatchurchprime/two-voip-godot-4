#include "webrtc_apm_processor.h"

#include "api/audio/audio_processing.h"

#include <vector>

namespace godot {

struct WebRtcApmProcessor::Impl {
    rtc::scoped_refptr<webrtc::AudioProcessing> apm;
    int sample_rate_hz = 0;
};

WebRtcApmProcessor *WebRtcApmProcessor::create(int p_sample_rate_hz, bool p_enable_noise_suppression, bool p_enable_agc2) {
    WebRtcApmProcessor *processor = new WebRtcApmProcessor();
    if (!processor->initialize(p_sample_rate_hz, p_enable_noise_suppression, p_enable_agc2)) {
        delete processor;
        return nullptr;
    }
    return processor;
}

WebRtcApmProcessor::WebRtcApmProcessor() : impl(new Impl()) {}

WebRtcApmProcessor::~WebRtcApmProcessor() {
    delete impl;
}

bool WebRtcApmProcessor::initialize(int p_sample_rate_hz, bool p_enable_noise_suppression, bool p_enable_agc2) {
    if (p_sample_rate_hz != 8000 && p_sample_rate_hz != 16000 &&
            p_sample_rate_hz != 32000 && p_sample_rate_hz != 48000) {
        return false;
    }

    webrtc::AudioProcessing::Config config;
    config.noise_suppression.enabled = p_enable_noise_suppression;
    config.gain_controller2.enabled = p_enable_agc2;
    config.gain_controller2.adaptive_digital.enabled = p_enable_agc2;
    impl->apm = webrtc::AudioProcessingBuilder().SetConfig(config).Create();
    if (!impl->apm || impl->apm->Initialize() != webrtc::AudioProcessing::kNoError) {
        impl->apm = nullptr;
        impl->sample_rate_hz = 0;
        return false;
    }
    impl->sample_rate_hz = p_sample_rate_hz;
    return true;
}

bool WebRtcApmProcessor::reset() {
    return impl->apm && impl->apm->Initialize() == webrtc::AudioProcessing::kNoError;
}

bool WebRtcApmProcessor::process_capture_10ms(float *p_mono_samples, size_t p_sample_count) {
    if (!impl->apm || !p_mono_samples || p_sample_count != static_cast<size_t>(impl->sample_rate_hz / 100)) {
        return false;
    }
    const webrtc::StreamConfig stream_config(impl->sample_rate_hz, 1);
    const float *input[] = { p_mono_samples };
    float *output[] = { p_mono_samples };
    return impl->apm->ProcessStream(input, stream_config, stream_config, output) == webrtc::AudioProcessing::kNoError;
}

bool WebRtcApmProcessor::process_render_10ms(const float *p_mono_samples, size_t p_sample_count) {
    if (!impl->apm || !p_mono_samples || p_sample_count != static_cast<size_t>(impl->sample_rate_hz / 100)) {
        return false;
    }
    const webrtc::StreamConfig stream_config(impl->sample_rate_hz, 1);
    const float *input[] = { p_mono_samples };
    std::vector<float> output_samples(p_sample_count);
    float *output[] = { output_samples.data() };
    return impl->apm->ProcessReverseStream(input, stream_config, stream_config, output) == webrtc::AudioProcessing::kNoError;
}

bool WebRtcApmProcessor::is_initialized() const {
    return impl->apm != nullptr;
}

} // namespace godot
