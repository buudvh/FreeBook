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
//  **Shape của `ctx` do `text_encoder` quyết định, không do `config.json`.** `VieNeuORTRunTextEncoder`
//  trả shape thật ra `outShape`/`outRank`, và hai hàm sau **bắt buộc** nhận lại đúng shape đó. Bản đầu
//  tự dựng `[1, L, dim]` với `dim = 512` lấy từ `config.json` nên `duration_predictor` báo
//  `Got: 512 Expected: 256` — chiều thật của `ctx` là `style_dim` (256), còn `dim` là chiều khác.
//

#ifndef VieNeuONNXBridge_h
#define VieNeuONNXBridge_h

#include <stddef.h>
#include <stdint.h>

/// Ngữ cảnh ORT: giữ `OrtEnv`, `OrtMemoryInfo`, `OrtAllocator` và 4 `OrtSession`.
typedef struct VieNeuORT VieNeuORT;

/// Tạo ngữ cảnh và nạp 4 graph từ `modelDirectory`.
/// Trả `NULL` khi lỗi; `*errorMessage` (nếu khác NULL) nhận chuỗi do `malloc` cấp phát.
VieNeuORT *VieNeuORTCreate(const char *modelDirectory, int32_t threadCount, char **errorMessage);

/// Giải phóng ngữ cảnh cùng mọi session bên trong.
void VieNeuORTDestroy(VieNeuORT *context);

/// `text_encoder(ids, style)` → `ctx` phẳng theo hàng.
///
/// `outShape` là buffer do bên gọi cấp phát, `shapeCapacity` là số chiều tối đa nó chứa được;
/// `outRank` nhận số chiều thật. Trả mảng do `malloc` cấp phát, hoặc `NULL` khi lỗi.
float *VieNeuORTRunTextEncoder(VieNeuORT *context,
                               const int64_t *ids, int32_t length,
                               const float *style, int32_t styleRows, int32_t styleColumns,
                               int32_t *outCount,
                               int64_t *outShape, int32_t shapeCapacity, int32_t *outRank,
                               char **errorMessage);

/// `duration_predictor(ctx, ctx_mask, spk)` → một số vô hướng (`log_s`).
///
/// `contextShape`/`contextRank` là shape **đã lấy từ** `VieNeuORTRunTextEncoder`; số token suy từ
/// `contextShape[1]`. `mask` là mảng **bool 1 byte/phần tử** — kiểu mà lớp ObjC không tạo được.
int32_t VieNeuORTRunDurationPredictor(VieNeuORT *context,
                                      const float *context_, const int64_t *contextShape, int32_t contextRank,
                                      const uint8_t *mask,
                                      const float *speaker, int32_t speakerCount,
                                      float *outValue, char **errorMessage);

/// `vector_estimator(x, t, ctx, ctx_mask, spk, style)` → velocity, cùng shape với `x`.
float *VieNeuORTRunVectorEstimator(VieNeuORT *context,
                                   const float *latent, int32_t latentChannels, int32_t frames,
                                   float time,
                                   const float *context_, const int64_t *contextShape, int32_t contextRank,
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
