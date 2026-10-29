#pragma once

#include <cstddef>

namespace godot {

class WebRtcApmProcessor {
public:
    static WebRtcApmProcessor *create(int p_sample_rate_hz, bool p_enable_noise_suppression, bool p_enable_agc2);
    ~WebRtcApmProcessor();

    WebRtcApmProcessor(const WebRtcApmProcessor &) = delete;
    WebRtcApmProcessor &operator=(const WebRtcApmProcessor &) = delete;

    bool reset();
    bool process_capture_10ms(float *p_mono_samples, size_t p_sample_count);
    bool process_render_10ms(const float *p_mono_samples, size_t p_sample_count);
    bool is_initialized() const;

private:
    WebRtcApmProcessor();
    bool initialize(int p_sample_rate_hz, bool p_enable_noise_suppression, bool p_enable_agc2);

    struct Impl;
    Impl *impl = nullptr;
};

} // namespace godot
