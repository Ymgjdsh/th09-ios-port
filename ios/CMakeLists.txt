cmake_minimum_required(VERSION 3.24)

# Configure with Xcode and -DCMAKE_SYSTEM_NAME=iOS (see build_ios.sh).
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "Minimum supported iOS version")
project(th09_native VERSION 0.1.2 LANGUAGES C CXX OBJC OBJCXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    message(FATAL_ERROR "This target is an iOS app. Use ios/build_ios.sh on macOS.")
endif()
string(TOLOWER "${CMAKE_OSX_SYSROOT}" TH09_SDK_LOWER)
if(TH09_SDK_LOWER MATCHES "iphonesimulator")
    set(TH09_SUPPORTED_PLATFORM "iPhoneSimulator")
else()
    set(TH09_SUPPORTED_PLATFORM "iPhoneOS")
endif()

get_filename_component(TH09_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(TH09_DEPS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/deps" CACHE PATH
    "Dependency root containing SDL (release-3.2.24) and SDL_ttf (release-3.2.2)")
set(TH09_ASSET_DIR "${CMAKE_CURRENT_SOURCE_DIR}/assets" CACHE PATH
    "Read-only game resource tree bundled under assets/")
set(TH09_ICON_CATALOG "${CMAKE_CURRENT_SOURCE_DIR}/app-icon/Assets.xcassets" CACHE PATH
    "Private icon catalog extracted from the original Japanese executable")
set(TH09_BUNDLE_IDENTIFIER "org.th09.native" CACHE STRING "App bundle identifier")
option(TH09_IOS_SMOKE "Build the separate diagnostics app; never a distributable game" OFF)
set(TH09_BUILD_FLAVOR "game")
set(TH09_APP_NAME "東方花映塚")
if(TH09_IOS_SMOKE)
    set(TH09_BUNDLE_IDENTIFIER "org.th09.native.smoke")
    set(TH09_BUILD_FLAVOR "diagnostics")
    set(TH09_APP_NAME "TH09 Diagnostics")
endif()
option(TH09_ENABLE_CODE_SIGNING "Let Xcode sign the app using local signing settings" OFF)
set(TH09_DEVELOPMENT_TEAM "" CACHE STRING "Optional Apple development team identifier")

foreach(dependency SDL SDL_ttf)
    if(NOT EXISTS "${TH09_DEPS_DIR}/${dependency}/CMakeLists.txt")
        message(FATAL_ERROR
            "Missing ${TH09_DEPS_DIR}/${dependency}/CMakeLists.txt. Provision the pinned local dependencies first.")
    endif()
endforeach()
if(NOT IS_DIRECTORY "${TH09_ASSET_DIR}")
    message(FATAL_ERROR "Missing game resources: ${TH09_ASSET_DIR}. Set TH09_ASSET_DIR to the asset tree.")
endif()
if(NOT EXISTS "${TH09_ICON_CATALOG}/AppIcon.appiconset/Contents.json")
    message(FATAL_ERROR "Missing original app icon. Run ios/tools/extract_icon.py --exe /path/to/th09.exe first.")
endif()

# Dependencies remain local: configuration never downloads game assets or code.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SDL_INSTALL OFF CACHE BOOL "" FORCE)
# TH09 renders directly through GLES3. Do not require newer Metal SDK enums
# from unused SDL GPU backends when building with the iOS 16 / Xcode 14 SDK.
set(SDL_GPU OFF CACHE BOOL "" FORCE)
set(SDL_RENDER_GPU OFF CACHE BOOL "" FORCE)
set(SDL_METAL OFF CACHE BOOL "" FORCE)
set(SDL_RENDER_METAL OFF CACHE BOOL "" FORCE)
set(SDLTTF_VENDORED ON CACHE BOOL "" FORCE)
set(SDLTTF_HARFBUZZ OFF CACHE BOOL "" FORCE)
set(SDLTTF_FREETYPE ON CACHE BOOL "" FORCE)
set(SDLTTF_PLUTOSVG OFF CACHE BOOL "" FORCE)
set(SDLTTF_SAMPLES OFF CACHE BOOL "" FORCE)
set(SDLTTF_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory("${TH09_DEPS_DIR}/SDL" "${CMAKE_BINARY_DIR}/deps/SDL" EXCLUDE_FROM_ALL)
add_subdirectory("${TH09_DEPS_DIR}/SDL_ttf" "${CMAKE_BINARY_DIR}/deps/SDL_ttf" EXCLUDE_FROM_ALL)

file(GLOB TH09_GAME_SOURCES CONFIGURE_DEPENDS "${TH09_ROOT}/th09_web/cpp/game/*.cpp")
file(GLOB TH09_PLATFORM_SOURCES CONFIGURE_DEPENDS "${TH09_ROOT}/th09_web/cpp/sdl/*.cpp")
file(GLOB_RECURSE TH09_FINGERPRINT_FILES CONFIGURE_DEPENDS
    "${TH09_ROOT}/th09_web/cpp/*.cpp" "${TH09_ROOT}/th09_web/cpp/*.hpp"
    "${TH09_ROOT}/th09_web/cpp/*.inc" "${TH09_ROOT}/portable/*.cpp"
    "${TH09_ROOT}/portable/*.hpp" "${TH09_ROOT}/portable/*.h"
    "${TH09_ROOT}/portable/*.inc" "${CMAKE_CURRENT_SOURCE_DIR}/*.mm"
    "${CMAKE_CURRENT_SOURCE_DIR}/Smoke.hpp" "${CMAKE_CURRENT_SOURCE_DIR}/Diagnostics.hpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/Joystick.hpp")
list(APPEND TH09_FINGERPRINT_FILES "${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt" "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist")
list(SORT TH09_FINGERPRINT_FILES)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${TH09_FINGERPRINT_FILES})
set(fingerprint_input "")
foreach(source IN LISTS TH09_FINGERPRINT_FILES)
    file(SHA256 "${source}" source_hash)
    file(RELATIVE_PATH source_name "${TH09_ROOT}" "${source}")
    string(APPEND fingerprint_input "${source_name}:${source_hash}\n")
endforeach()
string(SHA256 TH09_SOURCE_FINGERPRINT "${fingerprint_input}")
file(GLOB_RECURSE TH09_ASSET_FILES CONFIGURE_DEPENDS LIST_DIRECTORIES FALSE "${TH09_ASSET_DIR}/*")
if(NOT TH09_GAME_SOURCES OR NOT TH09_PLATFORM_SOURCES OR NOT TH09_ASSET_FILES)
    message(FATAL_ERROR "The game source tree or the bundled asset tree is empty.")
endif()

# Keep relative resource paths intact; runtime reads the app bundle and writes
# saves only to Documents. No resource is copied to a writable cache at launch.
foreach(asset IN LISTS TH09_ASSET_FILES)
    file(RELATIVE_PATH relative_asset "${TH09_ASSET_DIR}" "${asset}")
    get_filename_component(relative_directory "${relative_asset}" DIRECTORY)
    set_source_files_properties("${asset}" PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources/assets/${relative_directory}")
endforeach()

set(TH09_NOTICES "${CMAKE_CURRENT_BINARY_DIR}/ThirdPartyNotices.txt")
file(WRITE "${TH09_NOTICES}" "TH09 native iOS\n\nstb_image / stb_vorbis by Sean Barrett: public domain option.\nShared touch policy adapted from eagler-th07 Touch.cpp (CC0).\n\n")
foreach(notice
    "${TH09_DEPS_DIR}/SDL/LICENSE.txt"
    "${TH09_DEPS_DIR}/SDL_ttf/LICENSE.txt"
    "${TH09_DEPS_DIR}/SDL_ttf/external/freetype/docs/FTL.TXT"
    "${TH09_ROOT}/portable/sdl/third_party/miniaudio.LICENSE"
    "${TH09_ROOT}/th09_web/cpp/licenses/th08-reference-MIT.txt")
    file(READ "${notice}" notice_text)
    get_filename_component(notice_name "${notice}" NAME)
    file(APPEND "${TH09_NOTICES}" "===== ${notice_name} =====\n${notice_text}\n\n")
endforeach()
set_source_files_properties("${TH09_NOTICES}" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)

add_executable(th09 MACOSX_BUNDLE
    Main.mm
    "${TH09_ICON_CATALOG}"
    "${TH09_NOTICES}"
    ${TH09_GAME_SOURCES}
    ${TH09_PLATFORM_SOURCES}
    "${TH09_ROOT}/portable/sdl/Renderer.cpp"
    ${TH09_ASSET_FILES})
set_source_files_properties("${TH09_ICON_CATALOG}" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
target_compile_features(th09 PRIVATE cxx_std_17)
target_include_directories(th09 PRIVATE
    "${TH09_ROOT}/th09_web/cpp"
    "${TH09_ROOT}/portable")
target_compile_definitions(th09 PRIVATE
    TH09_NATIVE_IOS=1 TH_NATIVE_PLATFORM=1 TH09_DEVELOPMENT_HARNESS=0)
if(TH09_IOS_SMOKE)
    target_compile_definitions(th09 PRIVATE TH09_IOS_SMOKE=1)
endif()
target_compile_options(th09 PRIVATE
    $<$<COMPILE_LANGUAGE:CXX,OBJCXX>:-ffp-contract=off>
    $<$<COMPILE_LANGUAGE:CXX,OBJCXX>:-fno-fast-math>
    $<$<COMPILE_LANGUAGE:CXX,OBJCXX>:-fno-strict-aliasing>
    $<$<COMPILE_LANGUAGE:CXX,OBJCXX>:-fno-exceptions>
    $<$<COMPILE_LANGUAGE:CXX,OBJCXX>:-fno-rtti>)
set_source_files_properties(Main.mm PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
target_link_libraries(th09 PRIVATE
    SDL3::SDL3-static SDL3_ttf::SDL3_ttf-static
    "-framework UIKit" "-framework Foundation" "-framework QuartzCore"
    "-framework OpenGLES" "-framework AudioToolbox" "-framework AVFoundation")

set_target_properties(th09 PROPERTIES
    OUTPUT_NAME "th09"
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO
    OBJCXX_STANDARD 17
    OBJCXX_STANDARD_REQUIRED YES
    OBJCXX_EXTENSIONS NO
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
    MACOSX_BUNDLE_BUNDLE_NAME "${TH09_APP_NAME}"
    MACOSX_BUNDLE_GUI_IDENTIFIER "${TH09_BUNDLE_IDENTIFIER}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.2"
    MACOSX_BUNDLE_BUNDLE_VERSION "3"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${TH09_BUNDLE_IDENTIFIER}"
    XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "${CMAKE_OSX_DEPLOYMENT_TARGET}"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
    XCODE_ATTRIBUTE_ENABLE_BITCODE NO
    XCODE_ATTRIBUTE_GCC_FAST_MATH NO
    XCODE_ATTRIBUTE_GCC_ENABLE_CPP_EXCEPTIONS NO
    XCODE_ATTRIBUTE_GCC_ENABLE_CPP_RTTI NO
    XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE NO)
set_target_properties(th09 PROPERTIES XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME AppIcon)
if(TH09_ENABLE_CODE_SIGNING)
    set_target_properties(th09 PROPERTIES XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic)
    if(TH09_DEVELOPMENT_TEAM)
        set_target_properties(th09 PROPERTIES XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${TH09_DEVELOPMENT_TEAM}")
    endif()
else()
    set_target_properties(th09 PROPERTIES
        XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO
        XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED NO
        XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "")
endif()
