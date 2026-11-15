#include <SHA256DispatchProbe.h>

#include <crypto/sha256.h>

#include <string>

const char* SHA256DispatchProbeSelectedImplementation(void)
{
    try {
        static const std::string name = SHA256AutoDetect();
        return name.c_str();
    } catch (...) {
        // An extern "C" boundary must never leak C++ exceptions into Swift.
        return "unknown";
    }
}
