#!/bin/sh
set -eux
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 -fobjc-arc -fblocks -dynamiclib NativeMouseFix.m -framework Foundation -framework UIKit -framework QuartzCore -framework GameController -install_name @executable_path/NativeMouseFix.dylib -o NativeMouseFix.dylib
codesign -f -s - NativeMouseFix.dylib
file NativeMouseFix.dylib
