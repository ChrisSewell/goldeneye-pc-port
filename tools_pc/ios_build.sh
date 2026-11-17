#!/usr/bin/env bash
# The iOS app: tools_pc/ios_build.sh [sim|device] [lib|app|run|data]
#
#   sim      arm64 simulator build (default)
#   device   arm64 device build, signed with ios/Config/Local.xcconfig
#   lib      SDL2 and the game as static libraries: build-ios/<sdk>/lib
#   app      lib, then xcodegen + xcodebuild (default):
#            build-ios/<sdk>/GoldenEye 007.app
#   run      app, then install and launch on the booted simulator (or
#            SIM="<name or udid>"), muted
#   GE_BUNDLE_DATA=1 puts data/ inside the app instead (an install over the air)
#   data     copy data/ (your ROM and its converted files, docs/building.md
#            steps 2 and 4) into the app's Documents/data on the simulator;
#            for a device, DEVICE=<udid> uses devicectl
#
# Before the first build: the assets extracted from your US ROM
# (docs/building.md step 2: ./scripts/extract_baserom.u.sh), and for `data`
# the sidecars (step 4). SDL2's source is fetched into build-ios/ once.
# Requires Xcode, CMake, Ninja, XcodeGen, Python 3.
#
# The app holds the game's code and your ROM's data: for your own devices
# only. Never distribute it.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "ios_build: $*" >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || fail "the iOS build runs on macOS"

target=${1:-sim}
step=${2:-app}
case "$target" in sim|device) ;; *) fail "usage: $0 [sim|device] [lib|app|run|data]" ;; esac
case "$step" in lib|app|run|data) ;; *) fail "usage: $0 [sim|device] [lib|app|run|data]" ;; esac
[ "$step" = run ] && [ "$target" = device ] && fail "run: simulator only; install on a device with devicectl"

sdk=$([ "$target" = sim ] && echo iphonesimulator || echo iphoneos)
romid=${ROMID:-ntsc-final}
out="$repo/build-ios"
build="$out/$sdk"
lib="$build/lib"
app_name="GoldenEye 007"

if [ "$step" = data ]; then
    [ -d "$repo/data" ] || fail "no data/ folder (docs/building.md step 4)"
    ls "$repo"/data/*.z64 >/dev/null 2>&1 || fail "no ROM in data/"
    [ -d "$repo/data/pcmodels-$romid" ] && [ -d "$repo/data/pccg-$romid" ] \
        || fail "no converted files in data/ (docs/building.md step 4)"
    plist="$build/$app_name.app/Info.plist"
    [ -f "$plist" ] || fail "build the app first"
    bundle="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$plist")"
    files=("$repo"/data/*.z64 "$repo/data/pcmodels-$romid" "$repo/data/pccg-$romid")
    [ -f "$repo/data/ge007.eep" ] && files+=("$repo/data/ge007.eep")
    if [ "$target" = sim ]; then
        docs="$(xcrun simctl get_app_container "${SIM:-booted}" "$bundle" data)/Documents"
        mkdir -p "$docs/data"
        cp -R "${files[@]}" "$docs/data/"
        echo "  copied to $docs/data"
    else
        [ -n "${DEVICE:-}" ] || fail "DEVICE=<udid> (xcrun devicectl list devices)"
        for f in "${files[@]}"; do
            name="$(basename "$f")"
            if [ -d "$f" ]; then
                for g in "$f"/*; do
                    xcrun devicectl device copy to --device "$DEVICE" --domain-type appDataContainer \
                        --domain-identifier "$bundle" --source "$g" \
                        --destination "Documents/data/$name/$(basename "$g")"
                done
            else
                xcrun devicectl device copy to --device "$DEVICE" --domain-type appDataContainer \
                    --domain-identifier "$bundle" --source "$f" --destination "Documents/data/$name"
            fi
        done
    fi
    exit 0
fi

command -v cmake >/dev/null || fail "no cmake: brew install cmake"
command -v ninja >/dev/null || fail "no ninja: brew install ninja"
command -v xcodegen >/dev/null || [ "$step" = lib ] || fail "no xcodegen: brew install xcodegen"
py="$(command -v python3)" || fail "no python3"
sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"

# SDL2, from source, static.
sdl_ver=2.32.10
sdl_src="${GE_SDL_DIR:-$out/SDL2-$sdl_ver}"
if [ ! -f "$sdl_src/CMakeLists.txt" ]; then
    mkdir -p "$out"
    echo "== fetching SDL2 $sdl_ver"
    curl -fsSL "https://github.com/libsdl-org/SDL/releases/download/release-$sdl_ver/SDL2-$sdl_ver.tar.gz" \
        | tar -xz -C "$out"
fi
sdl_prefix="$build/sdl"
if [ ! -f "$sdl_prefix/lib/libSDL2.a" ]; then
    echo "== SDL2 ($sdk)"
    cmake -S "$sdl_src" -B "$build/sdl-build" -G Ninja \
        -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
        -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF \
        -DCMAKE_INSTALL_PREFIX="$sdl_prefix"
    cmake --build "$build/sdl-build"
    cmake --install "$build/sdl-build"
fi

# The game, as libge007.a (CMakeLists.txt, GE007_IOS).
echo "== game ($sdk, $romid)"
cmake -S "$repo" -B "$build/game" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_BUILD_TYPE=Release -DROMID="$romid" -UPORT_ADDR_BASE \
    -DSDL2_INCLUDE_DIR="$sdl_prefix/include/SDL2" -DSDL2_LIBRARY="$sdl_prefix/lib/libSDL2.a" \
    -DZLIB_INCLUDE_DIR="$sdk_path/usr/include" -DZLIB_LIBRARY="$sdk_path/usr/lib/libz.tbd" \
    -DPython3_EXECUTABLE="$py"
cmake --build "$build/game" --target ge007
mkdir -p "$lib"
cp "$build/game/libge007.a" "$sdl_prefix/lib/libSDL2.a" "$sdl_prefix/lib/libSDL2main.a" "$lib/"
echo "  libraries: ${lib#$repo/}"
[ "$step" = lib ] && exit 0

echo "== app ($sdk)"
# GE_BUNDLE_DATA=1: put data/ (ROM, converted files) inside the app, for an
# install over the air to your own phone. Such an app holds your ROM: never
# share it.
staged="$repo/ios/BundledData"
rm -rf "$staged"
if [ "${GE_BUNDLE_DATA:-0}" = 1 ]; then
    ls "$repo"/data/*.z64 >/dev/null 2>&1 || fail "GE_BUNDLE_DATA: no ROM in data/"
    [ -d "$repo/data/pcmodels-$romid" ] && [ -d "$repo/data/pccg-$romid" ] \
        || fail "GE_BUNDLE_DATA: no converted files in data/ (docs/building.md step 4)"
    mkdir -p "$staged"
    cp -R "$repo"/data/*.z64 "$repo/data/pcmodels-$romid" "$repo/data/pccg-$romid" "$staged/"
    echo "  data inside the app (GE_BUNDLE_DATA=1)"
fi
(cd "$repo/ios" && xcodegen generate --quiet)
derived="$build/xcode"
dest=$([ "$target" = sim ] && echo "generic/platform=iOS Simulator" || echo "generic/platform=iOS")
# GE_XCODEBUILD_ARGS: e.g. -allowProvisioningUpdates and the App Store
# Connect API key flags for a device build without Xcode signed in.
xcodebuild -project "$repo/ios/GoldenEye.xcodeproj" -scheme GoldenEye \
    -configuration Release -destination "$dest" -derivedDataPath "$derived" -quiet \
    ${GE_XCODEBUILD_ARGS:-} build
built="$(find "$derived/Build/Products" -maxdepth 2 -name "$app_name.app" | head -1)"
[ -d "$built" ] || fail "no app after the build (see xcodebuild's output above)"
rm -rf "$build/$app_name.app"
cp -R "$built" "$build/"
echo "  app: ${build#$repo/}/$app_name.app"
[ "$step" = run ] || exit 0

echo "== simulator (muted)"
sim="${SIM:-booted}"
[ "$sim" != booted ] && { xcrun simctl boot "$sim" 2>/dev/null || true; }
bundle="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$build/$app_name.app/Info.plist")"
xcrun simctl install "$sim" "$build/$app_name.app"
SIMCTL_CHILD_SDL_AUDIODRIVER=dummy xcrun simctl launch --console-pty "$sim" "$bundle"
