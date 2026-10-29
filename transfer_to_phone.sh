#!/bin/bash
# Transfer laptop-built libil2cpp.so + conversion output to phone.
# Run from laptop with phone connected via USB (adb).
#
# The app skips the (long) native compile when it finds a prebuilt engine:
#   build/libil2cpp.so            the compiled arm64 engine
#   build/data/                   conversion output (global-metadata.dat + Resources)
#   build/asm/                    the staged assemblies (our patches/shims)
#   build/packages/               the compiled patches (harmless; skipped anyway)
# It then only installs the engine, builds the player image and retargets
# content -- no ~20+ minute compile.

set -e

PKG=com.jakobkhansen.silksong
CACHE=/mnt/Lapeace/.cache/silksong

ASM=$CACHE/build/asm
DATA=$CACHE/build/data
PKGS=$CACHE/build/packages
CPP=$CACHE/build/cpp
SO=$CACHE/native/root/libil2cpp.so

# The folder the app is told holds the Linux game depot. Written so the user
# does not have to re-pick it after a reinstall.
DEPOT_PATH='/storage/emulated/0/Download/Received from PC/Leavy-proLaptop/Silksong/Hollow Knight Silksong'

echo "=== verifying laptop artifacts ==="
[ -d "$ASM" ] || { echo "asm/ missing"; exit 1; }
[ -f "$ASM/SilksongPatches.dll" ] || { echo "asm/SilksongPatches.dll missing"; exit 1; }
[ -f "$ASM/BepInEx.dll" ] || { echo "asm/BepInEx.dll missing"; exit 1; }
[ -f "$ASM/0Harmony.dll" ] || { echo "asm/0Harmony.dll missing"; exit 1; }
[ -d "$CPP" ] || { echo "cpp/ missing"; exit 1; }
[ -f "$DATA/Metadata/global-metadata.dat" ] || { echo "metadata missing"; exit 1; }
[ -f "$SO" ] || { echo "libil2cpp.so missing"; exit 1; }

# Roslyn (the C# compiler the app fetches from NuGet on first run)
ROSLYN_SRC="$CACHE/unity/roslyn/tasks/netcore/bincore"
[ -f "$ROSLYN_SRC/csc.dll" ] || { echo "Roslyn csc.dll missing"; exit 1; }
[ -f "$ROSLYN_SRC/Microsoft.CodeAnalysis.dll" ] || { echo "Roslyn Microsoft.CodeAnalysis.dll missing"; exit 1; }

# Verify adb + phone
adb devices | grep -q "device$" || { echo "No phone connected (adb devices)"; exit 1; }
adb shell "pm list packages | grep $PKG" | grep -q "$PKG" || { echo "App not installed on phone"; exit 1; }

# The app's external files dir, exactly as getExternalFilesDir(null) resolves it.
# /sdcard is a legacy symlink to /storage/emulated/0, so use the canonical path.
EXT=/storage/emulated/0/Android/data/$PKG/files

echo
echo "=== pushing to phone ==="
# Push to a public temp dir first (works on all Android versions)
adb shell "rm -rf /storage/emulated/0/Download/silksong_transfer"
adb shell "mkdir -p /storage/emulated/0/Download/silksong_transfer"
adb push "$ASM" /storage/emulated/0/Download/silksong_transfer/asm >/dev/null
adb push "$DATA" /storage/emulated/0/Download/silksong_transfer/data >/dev/null
adb push "$PKGS" /storage/emulated/0/Download/silksong_transfer/packages >/dev/null
adb push "$CPP" /storage/emulated/0/Download/silksong_transfer/cpp >/dev/null
adb push "$ROSLYN_SRC" /storage/emulated/0/Download/silksong_transfer/roslyn >/dev/null
adb push "$SO" /storage/emulated/0/Download/silksong_transfer/libil2cpp.so >/dev/null

echo "=== moving into app's build dir (needs app installed) ==="
adb shell "
  mkdir -p $EXT/build/asm
  mkdir -p $EXT/build/data
  mkdir -p $EXT/build/packages
  mkdir -p $EXT/build/cpp
  mkdir -p $EXT/build/roslyn
  cp -r /storage/emulated/0/Download/silksong_transfer/asm/* $EXT/build/asm/
  cp -r /storage/emulated/0/Download/silksong_transfer/data/* $EXT/build/data/
  cp -r /storage/emulated/0/Download/silksong_transfer/packages/* $EXT/build/packages/
  cp -r /storage/emulated/0/Download/silksong_transfer/cpp/* $EXT/build/cpp/
  cp -r /storage/emulated/0/Download/silksong_transfer/roslyn/* $EXT/build/roslyn/
  cp /storage/emulated/0/Download/silksong_transfer/libil2cpp.so $EXT/build/libil2cpp.so
  echo 'done'
"

echo "=== writing depot path (so the app finds the game) ==="
adb shell "printf '%s' '$DEPOT_PATH' > $EXT/depot-path.txt"

echo
echo "=== verifying on phone ==="
adb shell "ls -la $EXT/build/ | grep -E 'asm|data|packages|libil2cpp'"
adb shell "ls $EXT/build/asm/ | grep -E 'SilksongPatches|BepInEx|0Harmony'"
adb shell "head -c 16 $EXT/build/data/Metadata/global-metadata.dat | xxd -p"
adb shell "ls -la $EXT/build/libil2cpp.so"
adb shell "cat $EXT/depot-path.txt"

echo
echo "=== DONE ==="
echo "On the phone, open the Silksong Android app and press 'Start porting'."
echo "It will detect the prebuilt engine and skip the long native compile."
echo "Only installing the engine, building the player image and retargeting"
echo "content will run (a few minutes)."