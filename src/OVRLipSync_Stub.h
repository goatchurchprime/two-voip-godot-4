/*******************************************************************************
 * Filename    :   OVRLipSync.h
 * Content     :   Low-level interface to OVRLipSync library
 * Created     :   Oct 19th, 2015
 * Copyright   :   Copyright Facebook Technologies, LLC and its affiliates.
 *                 All rights reserved.
 *
 * Licensed under the Oculus Audio SDK License Version 3.3 (the "License");
 * you may not use the Oculus Audio SDK except in compliance with the License,
 * which is provided at the time of installation or download, or which
 * otherwise accompanies this software in either electronic or hard copy form.
 *
 * You may obtain a copy of the License at
 *
 * https://developer.oculus.com/licenses/audio-3.3/
 *
 * Unless required by applicable law or agreed to in writing, the Oculus Audio SDK
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 ******************************************************************************/
#ifndef OVR_LipSync_H
#define OVR_LipSync_H

#include <stdint.h>

/**
 * \file OVRLipsync.h
 * \brief Oculus LipSync native interface
 */

/// OVRLipSync library major version
#define OVR_LIPSYNC_MAJOR_VERSION 1
/// OVRLipSync library minor version
#define OVR_LIPSYNC_MINOR_VERSION 61
/// OVRLipSync library patch version
#define OVR_LIPSYNC_PATCH_VERSION 0

/// Result type used by the OVRLipSync API
/// Success is zero, while all error types are non-zero values.

typedef enum {
  ovrLipSyncSuccess = 0,
  // ERRORS
  /// An unknown error has occurred
  ovrLipSyncError_Unknown = -2200,
  /// Unable to create a context
  ovrLipSyncError_CannotCreateContext = -2201,
  /// An invalid parameter, e.g. NULL pointer or out of range
  ovrLipSyncError_InvalidParam = -2202,
  /// An unsupported sample rate was declared
  ovrLipSyncError_BadSampleRate = -2203,
  /// The DLL or shared library could not be found
  ovrLipSyncError_MissingDLL = -2204,
  /// Mismatched versions between header and libs
  ovrLipSyncError_BadVersion = -2205,
  /// An undefined function
  ovrLipSyncError_UndefinedFunction = -2206
} ovrLipSyncResult;

/// Audio buffer data type
typedef enum {
  /// Signed 16-bit integer mono audio stream
  ovrLipSyncAudioDataType_S16_Mono,
  /// Signed 16-bit integer stereo audio stream
  ovrLipSyncAudioDataType_S16_Stereo,
  /// Signed 32-bit float mono data type
  ovrLipSyncAudioDataType_F32_Mono,
  /// Signed 32-bit float stereo data type
  ovrLipSyncAudioDataType_F32_Stereo,
} ovrLipSyncAudioDataType;

/// Visemes
///
/// \see struct ovrLipSyncFrame
typedef enum {
  /// Silent viseme
  ovrLipSyncViseme_sil,
  /// PP viseme (corresponds to p,b,m phonemes in worlds like \a put , \a bat, \a mat)
  ovrLipSyncViseme_PP,
  /// FF viseme (corrseponds to f,v phonemes in the worlds like \a fat, \a vat)
  ovrLipSyncViseme_FF,
  /// TH viseme (corresponds to th phoneme in words like \a think, \a that)
  ovrLipSyncViseme_TH,
  /// DD viseme (corresponds to t,d phonemes in words like \a tip or \a doll)
  ovrLipSyncViseme_DD,
  /// kk viseme (corresponds to k,g phonemes in words like \a call or \a gas)
  ovrLipSyncViseme_kk,
  /// CH viseme (corresponds to tS,dZ,S phonemes in words like \a chair, \a join, \a she)
  ovrLipSyncViseme_CH,
  /// SS viseme (corresponds to s,z phonemes in words like \a sir or \a zeal)
  ovrLipSyncViseme_SS,
  /// nn viseme (corresponds to n,l phonemes in worlds like \a lot or \a not)
  ovrLipSyncViseme_nn,
  /// RR viseme (corresponds to r phoneme in worlds like \a red)
  ovrLipSyncViseme_RR,
  /// aa viseme (corresponds to A: phoneme in worlds like \a car)
  ovrLipSyncViseme_aa,
  /// E viseme (corresponds to e phoneme in worlds like \a bed)
  ovrLipSyncViseme_E,
  /// I viseme (corresponds to ih phoneme in worlds like \a tip)
  ovrLipSyncViseme_ih,
  /// O viseme (corresponds to oh phoneme in worlds like \a toe)
  ovrLipSyncViseme_oh,
  /// U viseme (corresponds to ou phoneme in worlds like \a book)
  ovrLipSyncViseme_ou,

  /// Total number of visemes
  ovrLipSyncViseme_Count
} ovrLipSyncViseme;

/// Laughter types
///
/// \see struct ovrLipSyncFrame
typedef enum { ovrLipSyncLaughterCategory_Count } ovrLipSyncLaughterCategory;

/// Supported signals to send to LipSync API
///
/// \see ovrLipSync_SendSignal
typedef enum {
  ovrLipSyncSignals_VisemeOn, ///< fully on  (1.0f)
  ovrLipSyncSignals_VisemeOff, ///< fully off (0.0f)
  ovrLipSyncSignals_VisemeAmount, ///< Set to a given amount (0 - 100)
  ovrLipSyncSignals_VisemeSmoothing, ///< Amount to set per frame to target (0 - 100)
  ovrLipSyncSignals_LaughterAmount, ///< Set to a given amount (0.0-1.0)
  ovrLipSyncSignals_Count
} ovrLipSyncSignals;

/// Context provider
///
/// \see ovrLipSync_CreateContext
typedef enum {
  ovrLipSyncContextProvider_Original,
  ovrLipSyncContextProvider_Enhanced,
  ovrLipSyncContextProvider_EnhancedWithLaughter
} ovrLipSyncContextProvider;

/// Current lipsync frame results
///
/// \see ovrLipSync_ProcessFrame
/// \see ovrLipSync_ProcessFrameInterleaved
typedef struct {
  int frameNumber; ///< count from start of recognition
  int frameDelay; ///< Frame delay in milliseconds
  float* visemes; ///< Pointer to Viseme array, sizeof ovrLipSyncViseme_Count
  unsigned int visemesLength; ///< Number of visemes in array

  /// Laughter score for the current audio frame
  float laughterScore;
  /// Per-laughter category score, sizeof ovrLipSyncLaughterCategory_Count
  float* laughterCategories;
  /// Number of laughter categories
  unsigned int laughterCategoriesLength; ///< Number of laughter categories
} ovrLipSyncFrame;

/// Opaque type def for LipSync context
typedef unsigned int ovrLipSyncContext;
/// Callback function type
typedef void (*ovrLipSyncCallback)(void* opaque, const ovrLipSyncFrame* pFrame, ovrLipSyncResult result);

inline ovrLipSyncResult ovrLipSync_Initialize(int sampleRate, int bufferSize) { return ovrLipSyncError_Unknown; };
inline ovrLipSyncResult ovrLipSync_InitializeEx(int sampleRate, int bufferSize, const char* path) { return ovrLipSyncError_Unknown; };
inline ovrLipSyncResult ovrLipSync_Shutdown(void) { return ovrLipSyncError_Unknown; };
inline const char* ovrLipSync_GetVersion(int* major, int* minor, int* patch) { return "stub"; };
inline ovrLipSyncResult ovrLipSync_CreateContext(
    ovrLipSyncContext* pContext,
    const ovrLipSyncContextProvider provider) { return ovrLipSyncError_Unknown; };
inline ovrLipSyncResult ovrLipSync_CreateContextEx(
    ovrLipSyncContext* pContext,
    const ovrLipSyncContextProvider provider,
    const int sampleRate,
    const bool enableAcceleration) { return ovrLipSyncError_Unknown; };
inline ovrLipSyncResult ovrLipSync_CreateContextWithModelFile(
    ovrLipSyncContext* context,
    const ovrLipSyncContextProvider provider,
    const char* modelPath,
    const int sampleRate,
    const bool enableAcceleration) { return ovrLipSyncError_Unknown; };
inline ovrLipSyncResult ovrLipSync_DestroyContext(ovrLipSyncContext context) { return ovrLipSyncError_Unknown; };
inline ovrLipSyncResult ovrLipSync_ResetContext(ovrLipSyncContext context) { return ovrLipSyncError_Unknown; };
inline ovrLipSyncResult ovrLipSync_SendSignal(
    ovrLipSyncContext context,
    const ovrLipSyncSignals signal,
    const int arg1,
    const int arg2) { return ovrLipSyncError_Unknown; };
inline ovrLipSyncResult ovrLipSync_ProcessFrame(
    ovrLipSyncContext context,
    const float* audioBuffer,
    ovrLipSyncFrame* pFrame) { return ovrLipSyncError_Unknown; };
inline ovrLipSyncResult ovrLipSync_ProcessFrameInterleaved(
    ovrLipSyncContext context,
    const float* audioBuffer,
    ovrLipSyncFrame* pFrame) { return ovrLipSyncError_Unknown; };
inline ovrLipSyncResult ovrLipSync_ProcessFrameEx(
    ovrLipSyncContext context,
    const void* audioBuffer,
    int sampleCount,
    ovrLipSyncAudioDataType dataType,
    ovrLipSyncFrame* pFrame) { return ovrLipSyncError_Unknown; };
inline ovrLipSyncResult ovrLipSync_ProcessFrameAsync(
    ovrLipSyncContext context,
    const void* audioBuffer,
    int sampleCount,
    ovrLipSyncAudioDataType dataType,
    ovrLipSyncCallback callback,
    void* opaque) { return ovrLipSyncError_Unknown; };

#endif // OVR_LipSync_H
