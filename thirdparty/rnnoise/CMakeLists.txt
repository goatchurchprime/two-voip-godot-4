cmake_minimum_required(VERSION 3.14)
project(RnNoise LANGUAGES C)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(RNNOISE_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../rnnoise")

include(FetchContent)
FetchContent_Declare(
    rnnoise_model
    URL https://media.xiph.org/rnnoise/models/rnnoise_data-0b50c45.tar.gz
    URL_HASH SHA256=4ac81c5c0884ec4bd5907026aaae16209b7b76cd9d7f71af582094a2f98f4b43
)
FetchContent_MakeAvailable(rnnoise_model)

set(RNNOISE_SOURCES
    "${RNNOISE_SOURCE_DIR}/src/celt_lpc.c"
    "${RNNOISE_SOURCE_DIR}/src/denoise.c"
    "${RNNOISE_SOURCE_DIR}/src/kiss_fft.c"
    "${RNNOISE_SOURCE_DIR}/src/nnet.c"
    "${RNNOISE_SOURCE_DIR}/src/nnet_default.c"
    "${RNNOISE_SOURCE_DIR}/src/parse_lpcnet_weights.c"
    "${RNNOISE_SOURCE_DIR}/src/pitch.c"
    "${RNNOISE_SOURCE_DIR}/src/rnn.c"
    "${RNNOISE_SOURCE_DIR}/src/rnnoise_tables.c"
    "${rnnoise_model_SOURCE_DIR}/src/rnnoise_data.c"
)

add_library(RnNoise STATIC ${RNNOISE_SOURCES})

# Disable warnings from this external C dependency.
target_compile_options(RnNoise PRIVATE
    $<$<OR:$<C_COMPILER_ID:Clang>,$<C_COMPILER_ID:AppleClang>,$<C_COMPILER_ID:GNU>>:-w>
    $<$<C_COMPILER_ID:MSVC>:/w>
)

target_include_directories(RnNoise
    PUBLIC "${RNNOISE_SOURCE_DIR}/include"
    PRIVATE
        "${RNNOISE_SOURCE_DIR}/src"
        "${rnnoise_model_SOURCE_DIR}/src"
)
