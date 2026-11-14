//
//  TurboCodecProbeBridge.h
//  Tàng Công Các
//
//  **TẠM — màn đo "Codec Turbo: AMX vs Neural Engine"** (hướng 3 của báo cáo tối ưu Turbo §18, 1.3.932). Xoá cùng màn
//  đo khi có kết luận.
//
//  Cầu C API của ONNX Runtime cho graph codec MOSS chính thức (`moss_audio_tokenizer_decode_full.onnx`, HF
//  OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX): vào `audio_codes [1, T, 16] int32` + `audio_code_lengths [1] int32`,
//  ra `audio [1, kênh, mẫu] float` + `audio_lengths [1] int32`. Khác `VieNeuONNXProbeBridge.h` (chỉ float32): ở đây
//  có int32 và cố định chiều động lúc tạo session (`AddFreeDimensionOverrideByName`) để Core ML EP thấy shape tĩnh.
//

#ifndef TurboCodecProbeBridge_h
#define TurboCodecProbeBridge_h

#include <stdint.h>

typedef struct TurboCodecProbe TurboCodecProbe;

/// Tạo session.
/// - `provider`: `"CPU"` hoặc `"CoreML"`; `keys` / `values` / `optionCount` là tuỳ chọn của EP (bỏ qua với `"CPU"`).
/// - `codeLength` > 0 ⇒ cố định `batch = 1`, `code_length = codeLength` (bucket); 0 ⇒ để shape động.
/// - `weightName` / `weightPath`: file external data nạp vào bộ nhớ (`AddExternalInitializersFromFilesInMemory`, né
///   lỗi đường dẫn external data của Core ML EP ORT 1.24.2). `weightName` = chuỗi `location` trong graph.
/// - `logPath` khác rỗng ⇒ log INFO, stderr chuyển vào file đó trong lúc tạo session (bảng chia partition của EP).
TurboCodecProbe *TurboCodecProbeCreate(const char *modelPath,
                                       const char *provider,
                                       const char *const *keys,
                                       const char *const *values,
                                       int32_t optionCount,
                                       int32_t threads,
                                       int64_t codeLength,
                                       const char *weightName,
                                       const char *weightPath,
                                       const char *logPath,
                                       char **errorMessage);

void TurboCodecProbeDestroy(TurboCodecProbe *probe);

/// Giải mã một đoạn. `codes` xếp theo khung (`frames × 16`, khung trước), đã độn tới `frames` (= bucket khi có);
/// `realFrames` = số khung thật (đưa vào `audio_code_lengths`). Ra: `*audio` (`malloc`, bên gọi `free`) xếp **theo
/// kênh** (`channels × samples`), đã cắt theo `audio_lengths`. Trả 0 khi thành công.
int32_t TurboCodecProbeDecode(TurboCodecProbe *probe,
                              const int32_t *codes,
                              int64_t frames,
                              int32_t realFrames,
                              float **audio,
                              int64_t *channels,
                              int64_t *samples,
                              char **errorMessage);

void TurboCodecProbeFreeString(char *message);

#endif /* TurboCodecProbeBridge_h */
