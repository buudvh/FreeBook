#!/usr/bin/env bash
# Dựng audio.cpp (ggml, Apache-2.0) cho iOS arm64 thành `AudioCpp.xcframework` — dynamic framework có module map,
# để Swift `import AudioCpp` gọi thẳng C API (`include/audiocpp.h`). Chỉ biên dịch family `vieneu_v3_turbo`, chỉ CPU.
#
# Vì sao dynamic framework, không phải thư viện tĩnh: target C API của audio.cpp là SHARED và tự giới hạn symbol
# xuất ra còn `audiocpp_*` (`src/capi/audiocpp.symbols`) ⇒ ggml / sentencepiece / cJSON nằm gọn bên trong, không
# đụng symbol nào của app. Thư viện tĩnh thì phải gom hàng chục `.a` và tự lo trùng tên.
#
# Vì sao chỉ CPU: iOS không cho app chạy nền dùng GPU, mà TTS phải đọc được khi khoá màn hình.
#
# Biến môi trường (đều có mặc định):
#   AUDIOCPP_REF   tag/nhánh audio.cpp (mặc định đọc Scripts/ci/audiocpp_ref.txt)
#   OUT_DIR        nơi đặt AudioCpp.xcframework (mặc định Vendor/AudioCpp — project.yml trỏ vào đây)
#   WORK_DIR       thư mục tạm (mặc định build/audiocpp-ios)
#   ARM_ARCH       cờ -march cho kernel ggml (mặc định armv8.2-a+dotprod+fp16 = A13 trở lên)
set -euo pipefail

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIOCPP_REF="${AUDIOCPP_REF:-$(tr -d '[:space:]' < "$CI_DIR/audiocpp_ref.txt")}"
OUT_DIR="${OUT_DIR:-Vendor/AudioCpp}"
WORK_DIR="${WORK_DIR:-build/audiocpp-ios}"
ARM_ARCH="${ARM_ARCH:-armv8.2-a+dotprod+fp16}"
DEPLOYMENT_TARGET="17.0"
JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"

SRC="$WORK_DIR/src"
BUILD="$WORK_DIR/build"
STAGE="$WORK_DIR/stage"
FW="$STAGE/AudioCpp.framework"

echo "▶ audio.cpp $AUDIOCPP_REF → $OUT_DIR (iOS $DEPLOYMENT_TARGET arm64, $ARM_ARCH)"
rm -rf "$WORK_DIR" "$OUT_DIR/AudioCpp.xcframework"
mkdir -p "$WORK_DIR" "$OUT_DIR"

git clone --depth 1 --branch "$AUDIOCPP_REF" --recurse-submodules --shallow-submodules \
  https://github.com/0xShug0/audio.cpp.git "$SRC"
AUDIOCPP_SHA="$(git -C "$SRC" rev-parse HEAD)"
echo "audio.cpp commit: $AUDIOCPP_SHA"

# Bản vá của app (Scripts/ci/audiocpp_patches/), kiểm ở job parity của audiocpp-ios.yml
# (Scripts/ci/audiocpp_parity_macos.sh):
# - vieneu_prefill_gallocr: bước nạp prompt của Turbo tái sử dụng bộ nhớ trung gian (cùng mã âm thanh với bản gốc);
# - vieneu_codec_blas: codec giải mã qua Accelerate khi session option `vieneu_v3_turbo.codec_blas` bật (mặc định tắt);
# - vieneu_prefill_blas: bước nạp prompt qua Accelerate khi `vieneu_v3_turbo.prefill_blas` bật (mặc định tắt);
# - vieneu_threadpool: giữ một threadpool ggml suốt session khi `vieneu_v3_turbo.threadpool_poll` có (mặc định tắt);
# - vieneu_acoustic_repack: trọng số q8_0 của bộ giải mã âm học vào bộ đệm CPU_REPACK khi
#   `vieneu_v3_turbo.acoustic_repack` bật (mặc định tắt);
# - capi_log_file: hàm C `audiocpp_set_log_file` để app bật bộ đếm giờ có sẵn của audio.cpp;
# - capi_abort_file: hàm C `audiocpp_set_abort_file` — câu báo GGML_ASSERT / exception chưa bắt ghi ra file trước abort.
python3 "$CI_DIR/audiocpp_patches/vieneu_prefill_gallocr.py" "$SRC"
python3 "$CI_DIR/audiocpp_patches/vieneu_codec_blas.py" "$SRC"
python3 "$CI_DIR/audiocpp_patches/vieneu_prefill_blas.py" "$SRC"
python3 "$CI_DIR/audiocpp_patches/vieneu_threadpool.py" "$SRC"
python3 "$CI_DIR/audiocpp_patches/vieneu_acoustic_repack.py" "$SRC"
python3 "$CI_DIR/audiocpp_patches/capi_log_file.py" "$SRC"
python3 "$CI_DIR/audiocpp_patches/capi_abort_file.py" "$SRC"

# sentencepiece (vendored) gọi `set_xcode_property` khi CMAKE_SYSTEM_NAME=iOS nhưng macro đó chỉ có trong bộ
# ios.toolchain.cmake riêng của nó (mình không dùng) ⇒ khai macro rỗng; nó chỉ gắn bundle id cho các tool CLI
# `spm_*` mà mình không build.
COMPAT="$(cd "$WORK_DIR" && pwd)/ios_compat.cmake"
cat > "$COMPAT" <<'EOF'
if (NOT COMMAND set_xcode_property)
  macro(set_xcode_property TARGET XCODE_PROPERTY XCODE_VALUE XCODE_RELVERSION)
  endmacro()
endif()
EOF

# OpenMP: Apple clang không có ⇒ tắt (ggml dùng pool pthread của nó).
# NATIVE_CPU: đang cross-compile, không dò được máy đích ⇒ tắt, cấp cờ ARM tường minh qua GGML_CPU_ARM_ARCH.
# BLAS: bật, nhà cung cấp Apple = Accelerate (framework hệ thống, AMX trên A13+). Chỉ codec MOSS dùng tới, và chỉ khi
# session option `vieneu_v3_turbo.codec_blas` bật (bản vá vieneu_codec_blas); tắt thì graph y hệt bản không BLAS.
cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PROJECT_INCLUDE="$COMPAT" \
  -DAUDIOCPP_VERSION="$AUDIOCPP_REF" \
  -DAUDIOCPP_BUILD_C_API=ON \
  -DAUDIOCPP_DEPLOYMENT_BUILD=ON \
  -DAUDIOCPP_MODEL_SET=custom \
  -DAUDIOCPP_MODELS=vieneu_v3_turbo \
  -DENGINE_ENABLE_METAL=OFF \
  -DENGINE_ENABLE_CUDA=OFF \
  -DENGINE_ENABLE_HIP=OFF \
  -DENGINE_ENABLE_VULKAN=OFF \
  -DENGINE_ENABLE_WEBGPU=OFF \
  -DENGINE_ENABLE_SYCL=OFF \
  -DENGINE_ENABLE_OPENMP=OFF \
  -DENGINE_ENABLE_NATIVE_CPU=OFF \
  -DENGINE_ENABLE_CPU_ALL_VARIANTS=OFF \
  -DGGML_CPU_ARM_ARCH="$ARM_ARCH" \
  -DGGML_BLAS=ON \
  -DGGML_BLAS_VENDOR=Apple

cmake --build "$BUILD" --target audiocpp -j "$JOBS"

DYLIB="$(find "$BUILD" -name 'libaudiocpp*.dylib' -type f | head -n 1)"
if [ -z "$DYLIB" ]; then
  echo "::error::Không thấy libaudiocpp*.dylib sau khi build"
  find "$BUILD" -maxdepth 3 \( -name '*.dylib' -o -name '*.a' \) | head -n 40
  exit 1
fi
echo "dylib: $DYLIB ($(du -h "$DYLIB" | cut -f1))"

# ---- Đóng gói framework ----------------------------------------------------------------------------------------
rm -rf "$STAGE"
mkdir -p "$FW/Headers" "$FW/Modules"
cp "$DYLIB" "$FW/AudioCpp"
install_name_tool -id "@rpath/AudioCpp.framework/AudioCpp" "$FW/AudioCpp"
# Bỏ symbol gỡ lỗi cục bộ (giữ symbol xuất `audiocpp_*`).
xcrun strip -x -S "$FW/AudioCpp"
cp "$SRC/include/audiocpp.h" "$FW/Headers/audiocpp.h"
cp "$SRC/LICENSE" "$FW/LICENSE-audio.cpp.txt"

cat > "$FW/Modules/module.modulemap" <<'EOF'
framework module AudioCpp {
  umbrella header "audiocpp.h"
  export *
  module * { export * }
}
EOF

cat > "$FW/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>AudioCpp</string>
  <key>CFBundleIdentifier</key><string>org.audiocpp.AudioCpp</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>AudioCpp</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>${AUDIOCPP_REF#v}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>MinimumOSVersion</key><string>${DEPLOYMENT_TARGET}</string>
  <key>AudioCppCommit</key><string>${AUDIOCPP_SHA}</string>
</dict>
</plist>
EOF

echo "Phụ thuộc của AudioCpp:"
otool -L "$FW/AudioCpp"
if otool -L "$FW/AudioCpp" | tail -n +2 | grep -v -E '/usr/lib/|/System/Library/|@rpath/AudioCpp.framework' ; then
  echo "::error::AudioCpp còn phụ thuộc dylib ngoài hệ thống (liệt kê ở trên) — framework sẽ không nạp được trên máy"
  exit 1
fi
echo "Symbol audiocpp_* xuất ra: $(nm -gU "$FW/AudioCpp" | grep -c ' _audiocpp_' || true)"
# App gọi hàm của bản vá capi_log_file / capi_abort_file — thiếu symbol thì app link hỏng, chặn ngay ở đây cho rõ lỗi.
for symbol in audiocpp_set_log_file audiocpp_set_abort_file; do
  if ! nm -gU "$FW/AudioCpp" | grep -q " _${symbol}\$"; then
    echo "::error::AudioCpp không xuất $symbol (bản vá Scripts/ci/audiocpp_patches/)"
    exit 1
  fi
done

# ---- Kiểm nhanh: Swift import + link được cho iOS ---------------------------------------------------------------
SMOKE="$WORK_DIR/smoke"
mkdir -p "$SMOKE"
cat > "$SMOKE/main.swift" <<'EOF'
import AudioCpp
let abi = audiocpp_abi_version()
print("audio.cpp ABI \(abi >> 16).\((abi >> 8) & 0xff).\(abi & 0xff)")
var registry: OpaquePointer?
_ = audiocpp_registry_create(nil, &registry)
audiocpp_registry_free(registry)
_ = audiocpp_set_log_file(nil)
_ = audiocpp_set_abort_file(nil)
EOF
xcrun -sdk iphoneos swiftc -target "arm64-apple-ios${DEPLOYMENT_TARGET}" \
  -F "$STAGE" -framework AudioCpp \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks \
  "$SMOKE/main.swift" -o "$SMOKE/smoke"
echo "✓ Swift import AudioCpp + link iOS OK"

# ---- xcframework -------------------------------------------------------------------------------------------------
xcodebuild -create-xcframework -framework "$FW" -output "$OUT_DIR/AudioCpp.xcframework"
echo "$AUDIOCPP_REF $AUDIOCPP_SHA $ARM_ARCH" > "$OUT_DIR/STAMP"
du -sh "$OUT_DIR/AudioCpp.xcframework"
echo "✓ $OUT_DIR/AudioCpp.xcframework"
