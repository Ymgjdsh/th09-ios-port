#pragma once
#include <string>
#include <SDL3/SDL.h>
namespace th09::sdl {
// The Web build keeps its mounted virtual paths. Native builds resolve the
// same logical paths against a read-only bundle and a writable save directory.
inline std::string resource_root, save_root;
inline std::string platform_path(const char* name) {
    const std::string path=name?name:"";
#if defined(TH09_NATIVE_IOS)
    if(path=="/save")return save_root;
    if(path.rfind("/save/",0)==0)return save_root+path.substr(5);
    if(!path.empty()&&path[0]=='/')return resource_root+path;
#endif
    return path;
}
}
