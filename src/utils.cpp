#include "utils.h"

#include <godot_cpp/variant/utility_functions.hpp>

#ifdef WINDOWS_ENABLED
char *Utils::utf8toMbcs(char const *aUtf8string)
{
    wchar_t const *lUtf16string;
    lUtf16string = utf8to16(aUtf8string);
    return utf16toMbcs(lUtf16string);
}

char *Utils::mbcsTo8(char const *aMbcsString)
{
    wchar_t const *lUtf16string;
    lUtf16string = mbcsTo16(aMbcsString);
    return utf16to8(lUtf16string);
}

wchar_t *Utils::mbcsTo16(char const *aMbcsString)
{
    static wchar_t *lMbcsString = NULL;
    int32_t lSize;

    free(lMbcsString);
    if (!aMbcsString)
    {
        lMbcsString = NULL;
        return NULL;
    }
    lSize = MultiByteToWideChar(CP_ACP, MB_ERR_INVALID_CHARS,
                                aMbcsString, -1, NULL, 0);
    if (lSize)
    {
        lMbcsString = (wchar_t *)malloc(lSize * sizeof(wchar_t));
        lSize = MultiByteToWideChar(CP_ACP, 0, aMbcsString, -1, lMbcsString, lSize);
    }
    else
        wcscpy_s(lMbcsString, 1, L"");
    return lMbcsString;
}

wchar_t *Utils::utf8to16(char const *aUtf8string)
{
    static wchar_t *lUtf16string = NULL;
    int32_t lSize;

    free(lUtf16string);
    if (!aUtf8string)
    {
        lUtf16string = NULL;
        return NULL;
    }
    lSize = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                aUtf8string, -1, NULL, 0);
    if (lSize)
    {
        lUtf16string = (wchar_t *)malloc(lSize * sizeof(wchar_t));
        lSize = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                    aUtf8string, -1, lUtf16string, lSize);
        return lUtf16string;
    }
    else
    {
        /* let's try mbcs anyway */
        lUtf16string = NULL;
        return mbcsTo16(aUtf8string);
    }
}

char *Utils::utf16toMbcs(wchar_t const *aUtf16string)
{
    static char *lMbcsString = NULL;
    int32_t lSize;

    free(lMbcsString);
    if (!aUtf16string)
    {
        lMbcsString = NULL;
        return NULL;
    }
    lSize = WideCharToMultiByte(CP_ACP, 0,
                                aUtf16string, -1, NULL, 0, NULL, NULL);
    if (lSize)
    {
        lMbcsString = (char *)malloc(lSize);
        lSize = WideCharToMultiByte(CP_ACP, 0, aUtf16string, -1, lMbcsString, lSize, NULL, NULL);
    }
    else
        strcpy_s(lMbcsString, 1, "");
    return lMbcsString;
}

char *Utils::utf16to8(wchar_t const *aUtf16string)
{
    static char *lUtf8string = NULL;
    int32_t lSize;

    free(lUtf8string);
    if (!aUtf16string)
    {
        lUtf8string = NULL;
        return NULL;
    }
    lSize = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                aUtf16string, -1, NULL, 0, NULL, NULL);
    if (lSize)
    {
        lUtf8string = (char *)malloc(lSize);
        lSize = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, aUtf16string, -1, lUtf8string, lSize, NULL, NULL);
    }
    else
        strcpy_s(lUtf8string, 1, "");
    return lUtf8string;
}
#endif // WINDOWS_ENABLED
