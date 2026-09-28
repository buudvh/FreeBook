//
//  VieNeuONNXBridge.h
//  FreeBook
//
//  Cầu nối **C API** của ONNX Runtime cho engine VieNeu-TTS.
//
//  Vì sao phải có file C này thay vì gọi thẳng từ Swift: module C của ORT (`onnxruntime`) **không**
//  import được từ target app — product SPM `onnxruntime` chỉ trỏ tới target ObjC `OnnxRuntimeBindings`,
//  và umbrella header `onnxruntime.h` không `#import` header C API. Còn lớp ObjC thì **không tạo được
//  tensor bool**: `ctx_mask` của `duration_predictor`/`vector_estimator` khai `elem_type = 9 = BOOL`
//  (node duy nhất dùng nó là `Not`, mà `Not` của ONNX chỉ nhận bool), trong khi
//  `ORTTensorElementDataType` không có case `Bool` ở mọi bản ORT còn dùng được.
//
//  Bốn hàm dưới đây bám đúng bốn bước của pipeline, nên không cần một API tensor tổng quát.
//  Mọi mảng trả về là **float32 do `malloc` cấp phát** — bên gọi phải `free`.
//

#ifndef VieNeuONNXBridge_h
#define VieNeuONNXBridge_h

#include <stddef.h>
#include <stdint.h>

/// Ngữ cảnh ORT: giữ `OrtEnv`, `OrtMemoryInfo` và 4 `OrtSession`.
typedef struct VieNeuORT VieNeuORT;

/// Tạo ngữ cảnh và nạp 4 graph từ `modelDirectory`.
/// Trả `NULL` khi lỗi; `*errorMessage` (nếu khác NULL) nhận chuỗi do `malloc` cấp phát.
VieNeuORT *VieNeuORTCreate(const char *modelDirectory, int32_t threadCount, char **errorMessage);

/// Giải phóng ngữ cảnh cùng mọi session bên trong.
void VieNeuORTDestroy(VieNeuORT *context);

/// `text_encoder(ids, style)` → `ctx` phẳng theo hàng, `style` có `styleRows × styleColumns`.
/// `*outCount` nhận số phần tử; trả mảng do `malloc` cấp phát, hoặc `NULL` khi lỗi.
float *VieNeuORTRunTextEncoder(VieNeuORT *context,
                               const int64_t *ids, int32_t length,
                               const float *style, int32_t styleRows, int32_t styleColumns,
                               int32_t *outCount, char **errorMessage);

/// `duration_predictor(ctx, ctx_mask, spk)` → một số vô hướng (`log_s`).
/// `mask` là mảng **bool 1 byte/phần tử** — đây chính là kiểu mà lớp ObjC không tạo được.
int32_t VieNeuORTRunDurationPredictor(VieNeuORT *context,
                                      const float *context_, int32_t length, int32_t dim,
                                      const uint8_t *mask,
                                      const float *speaker, int32_t speakerCount,
                                      float *outValue, char **errorMessage);

/// `vector_estimator(x, t, ctx, ctx_mask, spk, style)` → velocity, cùng shape với `x`.
float *VieNeuORTRunVectorEstimator(VieNeuORT *context,
                                   const float *latent, int32_t latentChannels, int32_t frames,
                                   float time,
                                   const float *context_, int32_t length, int32_t dim,
                                   const uint8_t *mask,
                                   const float *speaker, int32_t speakerCount,
                                   const float *style, int32_t styleRows, int32_t styleColumns,
                                   int32_t *outCount, char **errorMessage);

/// `codec_decoder(x)` → PCM float32. Số mẫu **không** suy được từ công thức nên đọc từ shape thật.
float *VieNeuORTRunCodecDecoder(VieNeuORT *context,
                                const float *latent, int32_t latentChannels, int32_t frames,
                                int32_t *outCount, char **errorMessage);

/// Giải phóng chuỗi lỗi do các hàm trên cấp phát.
void VieNeuORTFreeErrorMessage(char *errorMessage);

#endif /* VieNeuONNXBridge_h */
