#include "register_types.h"

#include "audio_effect_opus_chunked.h"
#include "audio_stream_opus_chunked.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>


using namespace godot;

void initialize_two_voip_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    ClassDB::register_class<AudioEffectOpusChunked>();
    ClassDB::register_class<AudioEffectOpusChunkedInstance>();

    ClassDB::register_class<AudioStreamOpusChunked>();
    ClassDB::register_class<AudioStreamPlaybackOpusChunked>();
}

void uninitialize_two_voip_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {
// Initialization.
GDExtensionBool GDE_EXPORT two_voip_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

    init_obj.register_initializer(initialize_two_voip_module);
    init_obj.register_terminator(uninitialize_two_voip_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

    return init_obj.init();
}
}

