#pragma once

#ifdef WINDOWS_ENABLED

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

#if !defined(WC_ERR_INVALID_CHARS)
/* undefined prior to Vista, so not yet in MINGW header file */
#define WC_ERR_INVALID_CHARS 0x00000000 /* 0x00000080 for MINGW maybe ? */
#endif

#endif // WINDOWS_ENABLED

class Utils
{
public:
#ifdef WINDOWS_ENABLED
    static char *utf8toMbcs(char const *aUtf8string);
    static char *mbcsTo8(char const *aMbcsString);

    static char *utf16toMbcs(wchar_t const *aUtf16string);
    static wchar_t *mbcsTo16(char const *aMbcsString);
    static wchar_t *utf8to16(char const *aUtf8string);
    static char *utf16to8(wchar_t const *aUtf16string);
#endif // WINDOWS_ENABLED
};
