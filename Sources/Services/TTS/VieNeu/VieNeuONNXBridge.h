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

/// Tuỳ chọn khi dựng ngữ cảnh — dùng cho **thí nghiệm CoreML EP** (1.3.466).
///
/// Truyền `NULL` cho `VieNeuORTCreateWithRunOptions` = hành vi cũ (CPU, log mức WARNING).
typedef struct VieNeuORTRunOptions {
    /// `1` ⇒ đăng ký CoreML EP cho **cả 4** session. Lỗi đăng ký ⇒ hàm tạo trả `NULL` (bên gọi tự
    /// quay về CPU) — cố ý **không** im lặng chạy tiếp trên CPU, vì như vậy số đo thí nghiệm vô nghĩa.
    int32_t useCoreML;
    /// `1` ⇒ `ORT_LOGGING_LEVEL_VERBOSE`. Cần cho `ProfileComputePlan` của CoreML EP (ORT ghi ra từng
    /// toán tử chạy trên ANE/GPU/CPU kèm thời gian ước lượng).
    int32_t verboseLog;
    /// Thư mục cache của CoreML EP. **Bắt buộc** khi `useCoreML`: không có cache thì CoreML **biên dịch
    /// lại** subgraph mỗi lần mở session. Bên gọi phải bảo đảm thư mục tồn tại.
    const char *coreMLCacheDirectory;
} VieNeuORTRunOptions;

/// Callback nhận log của ONNX Runtime (thay vì để ORT ghi thẳng ra stderr như mặc định).
///
/// Cần thiết vì `[VieNeuPerf]` **không** thấy được log bên trong ORT: cảnh báo "node không hỗ trợ",
/// lý do CoreML EP từ chối một toán tử, và bảng phân bổ ANE/GPU/CPU của `ProfileComputePlan` đều đi
/// qua logger của ORT.
///
/// Dùng **con trỏ hàm C** (không phải block ObjC) để không phụ thuộc việc target bật ARC hay không —
/// Swift truyền được hàm toàn cục không capture vào đây.
typedef void (*VieNeuORTLogCallback)(int32_t severity, const char *message, void *context);

/// Đăng ký callback log. Truyền `callback == NULL` để gỡ.
///
/// `context` được trả nguyên lại cho callback. ORT gọi callback **từ luồng đang chạy `Run`** nên bên
/// nhận phải rẻ và không được ném ngoại lệ.
void VieNeuORTSetLogCallback(VieNeuORTLogCallback callback, void *context);

/// Như `VieNeuORTCreate` nhưng có tuỳ chọn EP/log. `runOptions == NULL` ⇒ giống hệt `VieNeuORTCreate`.
///
/// Tách hàm thay vì đổi chữ ký `VieNeuORTCreate`: giữ nguyên mọi caller cũ, và làm rõ rằng đường
/// thí nghiệm là **tuỳ chọn**.
VieNeuORT *VieNeuORTCreateWithRunOptions(const char *modelDirectory, int32_t threadCount,
                                         const VieNeuORTRunOptions *runOptions, char **errorMessage);

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

/// Như `VieNeuORTRunVectorEstimator` nhưng ghi kết quả vào **buffer do bên gọi cấp** ⇒ bỏ `malloc` và
/// một tầng `memcpy`. Đây là hình dạng mà đường Reader dùng (16 lượt/chunk — chỗ phát sinh churn).
///
/// `outCapacity` là số **phần tử `float`** buffer chứa được (thường `latentChannels × frames`); trả `-1`
/// nếu buffer không đủ. Trả `0` khi thành công, `-1` khi lỗi.
int32_t VieNeuORTRunVectorEstimatorInto(VieNeuORT *context,
                                        const float *latent, int32_t latentChannels, int32_t frames,
                                        float time,
                                        const float *context_, const int64_t *contextShape, int32_t contextRank,
                                        const uint8_t *mask,
                                        const float *speaker, int32_t speakerCount,
                                        const float *style, int32_t styleRows, int32_t styleColumns,
                                        float *outBuffer, int32_t outCapacity,
                                        int32_t *outCount, char **errorMessage);

/// Nhánh **vô điều kiện** của CFG: bốn tensor `ctx`/`ctx_mask`/`spk`/`style` là loop-invariant nên
/// **cache** trong `VieNeuORT` — dựng một lần cho nhiều bước Euler thay vì mỗi bước.
///
/// **Vòng đời buffer là trách nhiệm của bên gọi**: `CreateTensorWithDataAsOrtValue` không copy nên
/// `nullContext_`/`nullMask`/`nullSpeaker`/`nullStyle` phải sống tới khi gọi `VieNeuORTResetVectorCache`
/// (engine gọi ngay khi `prepareLocked` thay các mảng đó). `VieNeuORTDestroy` cũng giải phóng cache.
int32_t VieNeuORTRunVectorEstimatorUnconditionedInto(VieNeuORT *context,
                                                     const float *latent, int32_t latentChannels, int32_t frames,
                                                     float time,
                                                     const float *nullContext_, int64_t ctxElementCount,
                                                     const int64_t *ctxShape, int32_t ctxRank,
                                                     const uint8_t *nullMask, int32_t maskLength,
                                                     const float *nullSpeaker, int32_t speakerCount,
                                                     const float *nullStyle, int32_t styleRows, int32_t styleColumns,
                                                     float *outBuffer, int32_t outCapacity,
                                                     int32_t *outCount, char **errorMessage);

/// Huỷ tensor cache của nhánh vô điều kiện. **Bắt buộc** gọi khi buffer nguồn (mảng null của engine)
/// sắp bị thay hoặc giải phóng, nếu không tensor cache sẽ trỏ vào bộ nhớ đã chết.
void VieNeuORTResetVectorCache(VieNeuORT *context);

/// Đọc bộ đếm churn tích luỹ (số `OrtValue` tạo/giải phóng, số byte output đã copy). Chỉ để chẩn đoán.
/// Bất kỳ tham số nào `NULL` thì bỏ qua.
void VieNeuORTChurnSnapshot(VieNeuORT *context, int64_t *outCreates, int64_t *outReleases, int64_t *outCopiedBytes);

/// Đưa bộ đếm churn về 0 — gọi đầu mỗi lượt tổng hợp để con số ứng với đúng lượt đó.
void VieNeuORTResetChurnCounters(VieNeuORT *context);

/// `codec_decoder(x)` → PCM float32. Số mẫu **không** suy được từ công thức nên đọc từ shape thật.
float *VieNeuORTRunCodecDecoder(VieNeuORT *context,
                                const float *latent, int32_t latentChannels, int32_t frames,
                                int32_t *outCount, char **errorMessage);

/// Giải phóng chuỗi lỗi do các hàm trên cấp phát.
void VieNeuORTFreeErrorMessage(char *errorMessage);

#pragma mark - Graph clone giọng (tuỳ chọn, ~100 MB)

/// Tạo ngữ cảnh **chỉ có 3 graph clone**, **không** nạp 4 graph chính.
///
/// Vì sao cần một hàm tạo riêng thay vì `VieNeuORTCreate` + `VieNeuORTLoadCloneGraphs`: luồng tạo giọng
/// không có quyền đụng vào engine đang chạy (`VieNeuTTSEngine` giữ ngữ cảnh của nó ở mức `private`, và
/// plan C2 cấm sửa file đó), nên nó phải tự mở ngữ cảnh. Dùng `VieNeuORTCreate` thì ngữ cảnh đó nạp
/// thêm cả 4 graph chính (~280 MB) trong khi chỉ cần 3 graph clone (~91 MB) — đỉnh bộ nhớ lúc tạo giọng
/// sẽ gấp đôi vô ích.
///
/// Ngữ cảnh trả về **không dùng được** cho `VieNeuORTRunTextEncoder` và các hàm 4 bước khác (session
/// `NULL` ⇒ `Run` lỗi). Nó chỉ phục vụ `VieNeuORTHasCloneGraphs` và ba hàm `…RunSpeakerEncoder` /
/// `…RunCodecEncoder` / `…RunReferenceEncoder`.
///
/// Trả `NULL` khi lỗi; `*errorMessage` (nếu khác NULL) nhận chuỗi do `malloc` cấp phát.
VieNeuORT *VieNeuORTCreateCloneOnly(const char *modelDirectory, int32_t threadCount, char **errorMessage);

/// Nạp **3 graph clone** (`speaker_encoder` / `codec_encoder` / `reference_encoder`) từ `modelDirectory`.
///
/// Cố ý **không** gọi trong `VieNeuORTCreate`: 4 graph chính được tạo **eager**, thiếu một file là
/// `VieNeuORTCreate` trả `NULL` ⇒ engine chết cho cả người chỉ dùng giọng preset. Gói clone chỉ cần khi
/// người dùng thực sự tạo giọng, nên nó phải nạp rời và **không** ảnh hưởng `isReady`/`missingNames`.
///
/// Gọi lại được nhiều lần (lần thứ hai là no-op). Trả `0` khi đủ 3 graph, `-1` khi thiếu file hoặc lỗi
/// (khi đó không session nào bị giữ lại — gọi lại được sau khi tải xong).
int32_t VieNeuORTLoadCloneGraphs(VieNeuORT *context, const char *modelDirectory, char **errorMessage);

/// `1` nếu cả 3 graph clone đã nạp.
int32_t VieNeuORTHasCloneGraphs(const VieNeuORT *context);

/// `speaker_encoder(input)` → x-vector.
///
/// `fbank` là ma trận **row-major** `frames × melBins` **đã trừ trung bình theo bin** (mean-norm) — đúng
/// thứ tự phần tử của input `[1, frames, melBins]`. Số phần tử thật của output đọc từ shape graph (192).
/// Trả `0` khi thành công, `-1` khi lỗi hoặc buffer không đủ.
int32_t VieNeuORTRunSpeakerEncoder(VieNeuORT *context,
                                   const float *fbank, int32_t frames, int32_t melBins,
                                   float *outBuffer, int32_t outCapacity, int32_t *outCount,
                                   char **errorMessage);

/// `codec_encoder(wav)` → latent **chưa gộp nhóm** (`latentDim` = 24 kênh).
///
/// `pcm` là waveform mono float ở 24 kHz (`sampleCount` mẫu). Shape output thật trả ra
/// `outShape`/`outRank` — bên gọi **phải** dùng nó để biết số kênh và số frame, không đoán.
int32_t VieNeuORTRunCodecEncoder(VieNeuORT *context,
                                 const float *pcm, int32_t sampleCount,
                                 float *outBuffer, int32_t outCapacity,
                                 int64_t *outShape, int32_t shapeCapacity, int32_t *outRank,
                                 int32_t *outCount, char **errorMessage);

/// `reference_encoder(ref, ref_mask)` → style tokens.
///
/// `latent` là latent **đã gộp nhóm** (`channels` = `latentDim × group` = 144), `frames` là số frame
/// **sau khi cắt**. `ref_mask` do hàm này tự dựng toàn `true` — đúng `ref_mask = np.ones((1, T), bool)`
/// của upstream, và vì mọi phần tử đều `true` nên không cần tham số hoá.
int32_t VieNeuORTRunReferenceEncoder(VieNeuORT *context,
                                     const float *latent, int32_t channels, int32_t frames,
                                     float *outBuffer, int32_t outCapacity, int32_t *outCount,
                                     char **errorMessage);

#endif /* VieNeuONNXBridge_h */
