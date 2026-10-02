//
//  VieNeuONNXBridge.m
//  FreeBook
//
//  Thi hành cầu nối khai ở `VieNeuONNXBridge.h` bằng **C API** của ONNX Runtime.
//
//  Chi tiết C API đã tra từ `onnxruntime_c_api.h` (v1.24.2) và **phải** giữ đúng:
//  - `ORT_API2_STATUS` KHÔNG thêm tham số `const OrtApi*` vào đầu hàm ⇒ gọi `api->TenHam(...)`.
//  - Các hàm `Release*` sinh bằng `ORT_CLASS_RELEASE` trả **`void`**, không phải `OrtStatus*` ⇒ không
//    được đưa vào `check(...)`.
//  - `CreateTensorWithDataAsOrtValue` **không copy** dữ liệu ⇒ buffer của bên gọi phải sống tới hết
//    lượt `Run`. Với tensor **input**, hàm nào tạo tensor trong chính nó thì bảo đảm được (tạo → `Run`
//    → giải phóng trong cùng một hàm). **Ngoại lệ có kiểm soát duy nhất**: tensor cache của nhánh vô
//    điều kiện trong `VieNeuORTRunVectorEstimatorUnconditioned` — sống lâu hơn một hàm, nên ai tạo
//    cache (`VieNeuORTResetVectorCache`) phải bảo đảm buffer nguồn còn sống và ai huỷ ngữ cảnh
//    (`VieNeuORTDestroy`) phải giải phóng tensor cache. Xem doc của hai hàm đó.
//  - Dữ liệu output do ORT cấp phát nên căn chỉnh chuẩn ⇒ `memcpy` thẳng vào mảng float là an toàn.
//

#import "VieNeuONNXBridge.h"

#import <onnxruntime/onnxruntime_c_api.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/// Chỉ số 4 graph, dùng để tra `outputNames` — khớp thứ tự trong `VieNeuORTCreate`.
enum {
    VieNeuGraphTextEncoder = 0,
    VieNeuGraphDurationPredictor = 1,
    VieNeuGraphVectorEstimator = 2,
    VieNeuGraphCodecDecoder = 3,
    VieNeuGraphCount = 4
};

/// Chỉ số 3 graph **clone giọng** — nạp rời bằng `VieNeuORTLoadCloneGraphs`, không nằm trong
/// `VieNeuGraphCount` (xem doc ở header).
enum {
    VieNeuCloneGraphSpeakerEncoder = 0,
    VieNeuCloneGraphCodecEncoder = 1,
    VieNeuCloneGraphReferenceEncoder = 2,
    VieNeuCloneGraphCount = 3
};

/// Số input tối đa của một graph clone. Hiện chỉ `reference_encoder` cần 2 (`ref` + `ref_mask`);
/// `speaker_encoder`/`codec_encoder` mỗi graph 1 input. Khai thành hằng để vòng lặp nạp/giải phóng
/// không phải hardcode con số 2 ở nhiều chỗ.
#define VieNeuCloneMaxInputs 2

struct VieNeuORT {
    const OrtApi *api;
    OrtEnv *env;
    OrtMemoryInfo *memoryInfo;
    OrtAllocator *allocator;
    /// Số luồng intra-op đã dùng cho 4 graph chính; giữ lại để graph clone dùng **cùng** cấu hình.
    int32_t threadCount;
    OrtSession *sessions[VieNeuGraphCount];
    /// Tên output **đọc từ chính session** (`SessionGetOutputName`), không hardcode.
    ///
    /// Bản tham chiếu Python lấy output theo **chỉ số** (`run(None, {...})[0]`) nên không xác nhận được
    /// tên, mà `OrtApi::Run` của C API lại **bắt buộc** truyền tên. Đoán tên là mở đường cho một lỗi
    /// runtime chỉ nổ trên máy người dùng — nên hỏi thẳng session.
    char *outputNames[VieNeuGraphCount];

    /// 3 graph clone — **`NULL` cho tới khi `VieNeuORTLoadCloneGraphs` thành công**.
    ///
    /// Khai riêng thay vì nới `VieNeuGraphCount` lên 7: `VieNeuORTCreate` tạo session **eager** cho cả
    /// `VieNeuGraphCount` file, nên nới con số đó biến gói clone thành điều kiện sống còn của engine.
    OrtSession *cloneSessions[VieNeuCloneGraphCount];
    /// Tên output của graph clone, đọc từ chính session (`SessionGetOutputName`) — cùng lý do như
    /// `outputNames`: tên input/output của graph clone **khác** 4 graph cũ và không được đoán.
    char *cloneOutputNames[VieNeuCloneGraphCount];
    /// Tên input của graph clone, đọc từ session (`SessionGetInputName`) lúc nạp — **theo đúng thứ tự
    /// chỉ số của graph**.
    ///
    /// `speaker_encoder` nhận `"input"`, `codec_encoder` nhận `"wav"`, `reference_encoder` nhận
    /// `"ref"` + `"ref_mask"` — ba tên khác nhau và số input khác nhau, nên hardcode là mở đường cho
    /// lỗi chỉ nổ trên máy người dùng. Chiều thứ hai là chỉ số input (tối đa `VieNeuCloneMaxInputs`),
    /// phần tử thừa để `NULL`.
    char *cloneInputNames[VieNeuCloneGraphCount][VieNeuCloneMaxInputs];
    /// Số input mỗi graph clone khai (dùng để phát hiện graph lạ cần nhiều input hơn dự kiến).
    int32_t cloneInputCounts[VieNeuCloneGraphCount];

    // MARK: - Bộ đếm churn (chỉ để chẩn đoán, không ảnh hưởng kết quả số học)
    //
    // Đo "công việc phụ trợ" mà vòng Euler `vector_estimator` sinh ra mỗi chunk: số `OrtValue` tạo/giải
    // phóng và số byte output bị copy. Cố ý **không** suy từ RTF: `Run` chiếm ~98% thời gian nên một
    // lượt tối ưu cấp phát/copy có thể **không** làm RTF đổi chút nào, mà vẫn là đòn bẩy nhiệt thật.
    // Chỉ đọc khi bật log (`VieNeuORTChurnSnapshot`).
    int64_t tensorCreates;
    int64_t tensorReleases;
    int64_t copiedBytes;

    /// Tensor cache cho nhánh **vô điều kiện** của CFG (`ctx`/`ctx_mask`/`spk`/`style`).
    ///
    /// Bốn tensor này **loop-invariant**: cùng giá trị cho mọi bước Euler của mọi chunk (chúng đến từ
    /// `null_spk`/`null_style`/nhánh null, không phụ thuộc giọng hay văn bản). Tạo lại 4 tensor × 8 bước
    /// mỗi chunk là bookkeeping ORT thuần tuý. Cache lại ⇒ bỏ ~32/96 `makeTensor` mỗi chunk.
    ///
    /// **Vòng đời là trách nhiệm của bên gọi**: `CreateTensorWithDataAsOrtValue` không copy, nên buffer
    /// nguồn phải sống ≥ vòng đời tensor. `VieNeuORTResetVectorCache` huỷ cache khi buffer đổi;
    /// `VieNeuORTDestroy` giải phóng nốt.
    OrtValue *cachedNullContext;
    OrtValue *cachedNullMask;
    OrtValue *cachedNullSpeaker;
    OrtValue *cachedNullStyle;
};

#pragma mark - Tiện ích

static void setError(char **out, const char *message) {
    if (out == NULL) return;
    *out = strdup(message != NULL ? message : "unknown error");
}

static int check(OrtStatus *status, const OrtApi *api, char **errorMessage) {
    if (status == NULL) return 0;
    const char *message = api->GetErrorMessage(status);
    setError(errorMessage, message);
    api->ReleaseStatus(status);
    return -1;
}

#pragma mark - Log của ONNX Runtime (1.3.466)

/// Callback do tầng Swift đăng ký. `NULL` ⇒ không đụng gì (ORT vẫn ghi ra stderr như trước).
static VieNeuORTLogCallback vieNeuLogCallback = NULL;
static void *vieNeuLogContext = NULL;

/// Cầu nối đúng chữ ký `OrtLoggingFunction` (6 tham số) sang callback 2 tham số của tầng trên.
///
/// ORT gọi hàm này **từ luồng đang chạy `Run`** ⇒ chỉ được làm việc rẻ, và phải chịu được việc
/// `message` là `NULL`.
static void vieNeuORTLogTrampoline(void *param, OrtLoggingLevel severity, const char *category,
                                   const char *logid, const char *code_location, const char *message) {
    (void)param; (void)category; (void)logid; (void)code_location;
    VieNeuORTLogCallback callback = vieNeuLogCallback;
    if (callback == NULL || message == NULL) return;
    callback((int32_t)severity, message, vieNeuLogContext);
}

void VieNeuORTSetLogCallback(VieNeuORTLogCallback callback, void *context) {
    vieNeuLogCallback = callback;
    vieNeuLogContext = context;
}

#pragma mark - CoreML EP (1.3.466)

/// Đăng ký CoreML EP cho `options` theo `runOptions`.
///
/// Dùng `SessionOptionsAppendExecutionProvider` (API key/value, **có từ ORT 1.12**) chứ **không** dùng
/// `OrtSessionOptionsAppendExecutionProvider_CoreML` (chỉ nhận cờ): API cũ **không** đặt được
/// `ModelCacheDirectory` lẫn `ProfileComputePlan`, mà thiếu cache thì CoreML **biên dịch lại subgraph
/// mỗi lần mở session**, còn thiếu profile thì không biết toán tử nào chạy trên thiết bị nào.
///
/// Trả `-1` khi lỗi (bên gọi phải coi là thất bại, **không** im lặng chạy tiếp trên CPU).
static int32_t appendCoreMLProvider(const OrtApi *api, OrtSessionOptions *options,
                                    const VieNeuORTRunOptions *runOptions, char **errorMessage) {
    const char *keys[5];
    const char *values[5];
    size_t count = 0;

    // MLProgram (Core ML 5+, iOS 15+): bắt buộc cho các op hiện đại của graph này
    // (LayerNormalization / Gelu / Erf / ReduceMean) mà định dạng NeuralNetwork không có.
    keys[count] = "ModelFormat";          values[count++] = "MLProgram";
    // ⚠️ **CHẨN ĐOÁN (1.3.468)** — tạm đổi sang `CPUOnly` để tách nguyên nhân tiếng nhiễu:
    // CoreML chạy trên CPU là đường **không mất độ chính xác** (fp32), nên:
    //   * audio **đúng** ⇒ thủ phạm là fp16/ANE (CoreML trên ANE/GPU tính fp16 ⇒ latent lệch ⇒ nhiễu);
    //   * audio **vẫn nhiễu** ⇒ lỗi ở semantics/phân mảnh của EP, không liên quan độ chính xác.
    // Giá trị cũ là `CPUAndNeuralEngine` (1.3.466–1.3.467) — đo được **tiếng nhiễu** với `rtf` 0,64–0,93
    // trong khi CPU thường (ORT) chỉ 0,26–0,44. Đổi tuỳ chọn ⇒ **phải đổi hậu tố thư mục cache** (Luật 22).
    keys[count] = "MLComputeUnits";       values[count++] = "CPUOnly";
    keys[count] = "ModelCacheDirectory";  values[count++] = runOptions->coreMLCacheDirectory;
    // Bảng phân bổ ANE/GPU/CPU theo từng toán tử — nguồn sự thật duy nhất cho câu hỏi "EP có ăn không".
    keys[count] = "ProfileComputePlan";   values[count++] = "1";
    // ⚠️ **BẮT BUỘC = 1** (sửa ở 1.3.467, đo trên máy thật): để `0` (cho phép shape động) thì CoreML EP
    // **chia `vector_estimator` thành 33+ partition**, mỗi partition là một `.mlmodel` biên dịch riêng
    // (`CoreMLCache/<hash>/3_dynamic_mlprogram` … `33_dynamic_mlprogram`), và **sinh thêm partition mới ở
    // mỗi lượt chạy**. Hệ quả đo được: trong 25 giây đọc không có **một** dòng `[VieNeuPerf]` nào, chỉ có
    // `[NghiEnergy] Underrun` ⇒ **hoàn toàn không phát ra tiếng**.
    // Đặt `1` ⇒ EP chỉ nhận node có shape tĩnh; `L` (độ dài phoneme) và `T` (số frame) của model này đổi
    // mỗi đoạn nên EP sẽ nhận **rất ít** node — lợi ích gần như bằng 0, nhưng **không còn bão biên dịch**.
    // Đây là bước kiểm chứng trước khi quyết định bỏ hẳn EP (xem `Docs/Reports/walkthrough-1.3.467.md`).
    keys[count] = "RequireStaticInputShapes"; values[count++] = "1";

    if (check(api->SessionOptionsAppendExecutionProvider(options, "CoreML", keys, values, count),
              api, errorMessage) != 0) {
        return -1;
    }
    return 0;
}

/// Nạp một graph và **hỏi thẳng session tên output của nó**.
///
/// `outputNames` là mảng trong `VieNeuORT`; tên do ORT cấp phát bằng allocator mặc định nên phải giải
/// phóng bằng chính allocator đó (`VieNeuORTDestroy`).
static OrtSession *createSession(const OrtApi *api,
                                 const OrtEnv *env,
                                 const OrtSessionOptions *options,
                                 const char *directory,
                                 const char *name,
                                 int graphIndex,
                                 VieNeuORT *context,
                                 char **errorMessage) {
    char path[4096];
    snprintf(path, sizeof(path), "%s/%s", directory, name);
    OrtSession *session = NULL;
    if (check(api->CreateSession(env, path, options, &session), api, errorMessage) != 0) return NULL;

    size_t outputCount = 0;
    if (check(api->SessionGetOutputCount(session, &outputCount), api, errorMessage) != 0 || outputCount == 0) {
        setError(errorMessage, "graph không có output");
        api->ReleaseSession(session);
        return NULL;
    }
    char *outputName = NULL;
    if (check(api->SessionGetOutputName(session, 0, context->allocator, &outputName), api, errorMessage) != 0) {
        api->ReleaseSession(session);
        return NULL;
    }
    context->outputNames[graphIndex] = outputName;
    return session;
}

/// Trả một chuỗi do allocator mặc định của ORT cấp phát về cho chính allocator đó.
static void freeSessionString(VieNeuORT *context, char *name) {
    if (name != NULL && context->allocator != NULL) {
        context->allocator->Free(context->allocator, name);
    }
}

/// Như `createSession` nhưng cho **graph clone**: đọc **cả** tên output **và mọi tên input** từ session.
///
/// Khác `createSession` ở hai điểm, cả hai đều bắt nguồn từ C4 ("hỏi model, đừng đoán"):
/// - Ghi vào `cloneSessions`/`cloneOutputNames`/`cloneInputNames` thay vì mảng 4 graph chính.
/// - Đọc tên input: `speaker_encoder` nhận `"input"`, `codec_encoder` nhận `"wav"`,
///   `reference_encoder` nhận `"ref"` + `"ref_mask"` — ba tên và hai số lượng input khác nhau.
///
/// **Chỉ gán vào `context` khi đã lấy đủ** tên: nếu lỗi giữa đường thì mọi chuỗi đã lấy được trả lại
/// ngay, `context` không giữ trạng thái dở dang ⇒ `VieNeuORTLoadCloneGraphs` gọi lại được sạch sẽ.
static OrtSession *createCloneSession(const OrtApi *api,
                                      const OrtEnv *env,
                                      const OrtSessionOptions *options,
                                      const char *directory,
                                      const char *name,
                                      int graphIndex,
                                      VieNeuORT *context,
                                      char **errorMessage) {
    char path[4096];
    snprintf(path, sizeof(path), "%s/%s", directory, name);
    OrtSession *session = NULL;
    if (check(api->CreateSession(env, path, options, &session), api, errorMessage) != 0) return NULL;

    char *outputName = NULL;
    char *inputNames[VieNeuCloneMaxInputs] = {NULL};
    size_t inputCount = 0;

    size_t outputCount = 0;
    if (check(api->SessionGetOutputCount(session, &outputCount), api, errorMessage) != 0 || outputCount == 0) {
        setError(errorMessage, "graph clone không có output");
        goto fail;
    }
    if (check(api->SessionGetOutputName(session, 0, context->allocator, &outputName), api, errorMessage) != 0) {
        goto fail;
    }

    if (check(api->SessionGetInputCount(session, &inputCount), api, errorMessage) != 0 || inputCount == 0) {
        setError(errorMessage, "graph clone không có input");
        goto fail;
    }
    if (inputCount > VieNeuCloneMaxInputs) {
        setError(errorMessage, "graph clone khai nhiều input hơn dự kiến");
        goto fail;
    }
    for (size_t index = 0; index < inputCount; index++) {
        if (check(api->SessionGetInputName(session, index, context->allocator, &inputNames[index]),
                  api, errorMessage) != 0) {
            goto fail;
        }
    }

    context->cloneOutputNames[graphIndex] = outputName;
    for (size_t index = 0; index < VieNeuCloneMaxInputs; index++) {
        context->cloneInputNames[graphIndex][index] = inputNames[index];
    }
    context->cloneInputCounts[graphIndex] = (int32_t)inputCount;
    return session;

fail:
    freeSessionString(context, outputName);
    for (size_t index = 0; index < VieNeuCloneMaxInputs; index++) {
        freeSessionString(context, inputNames[index]);
    }
    api->ReleaseSession(session);
    return NULL;
}

static OrtValue *makeTensor(const OrtApi *api,
                            OrtMemoryInfo *memoryInfo,
                            const void *data,
                            size_t byteCount,
                            const int64_t *shape,
                            size_t rank,
                            ONNXTensorElementDataType type,
                            char **errorMessage) {
    OrtValue *value = NULL;
    // `p_data` là `void*` không const; ép bỏ const ở đây là an toàn vì ORT chỉ đọc dữ liệu này khi chạy.
    if (check(api->CreateTensorWithDataAsOrtValue(memoryInfo, (void *)data, byteCount,
                                                  shape, rank, type, &value),
              api, errorMessage) != 0) {
        return NULL;
    }
    return value;
}

/// `makeTensor` có đếm churn — dùng cho đường `vector_estimator` (16 lượt/chunk). Đường khác gọi thẳng
/// `makeTensor` vì chạy 1 lần/chunk nên không phải chỗ churn (và đếm chúng chỉ làm nhiễu con số).
static OrtValue *makeTensorCounted(const OrtApi *api,
                                   VieNeuORT *context,
                                   const void *data,
                                   size_t byteCount,
                                   const int64_t *shape,
                                   size_t rank,
                                   ONNXTensorElementDataType type,
                                   char **errorMessage) {
    OrtValue *value = makeTensor(api, context->memoryInfo, data, byteCount, shape, rank, type, errorMessage);
    if (value != NULL) context->tensorCreates += 1;
    return value;
}

static OrtValue *runSession(const OrtApi *api,
                            OrtSession *session,
                            const char *const *inputNames,
                            const OrtValue *const *inputs,
                            size_t inputCount,
                            const char *outputName,
                            char **errorMessage) {
    OrtValue *output = NULL;
    const char *outputNames[1] = {outputName};
    if (check(api->Run(session, NULL, inputNames, inputs, inputCount, outputNames, 1, &output),
              api, errorMessage) != 0) {
        return NULL;
    }
    return output;
}

/// Sao chép tensor float32 của `value` ra một mảng `malloc`. Số phần tử **đọc từ shape thật**, không
/// suy từ công thức — `codec_decoder` trả độ dài PCM mà không hàm nào đoán được.
static float *copyFloats(const OrtApi *api,
                         OrtValue *value,
                         int32_t *outCount,
                         int64_t *outShape,
                         int32_t shapeCapacity,
                         int32_t *outRank,
                         char **errorMessage) {
    OrtTensorTypeAndShapeInfo *info = NULL;
    if (check(api->GetTensorTypeAndShape(value, &info), api, errorMessage) != 0) return NULL;

    size_t rank = 0;
    if (check(api->GetDimensionsCount(info, &rank), api, errorMessage) != 0) {
        api->ReleaseTensorTypeAndShapeInfo(info);
        return NULL;
    }
    if (rank > 8) rank = 8;
    int64_t dimensions[8] = {0};
    if (rank > 0 && check(api->GetDimensions(info, dimensions, rank), api, errorMessage) != 0) {
        api->ReleaseTensorTypeAndShapeInfo(info);
        return NULL;
    }
    api->ReleaseTensorTypeAndShapeInfo(info);

    if (outRank != NULL) *outRank = (int32_t)rank;
    if (outShape != NULL) {
        int32_t copied = 0;
        for (size_t index = 0; index < rank && copied < shapeCapacity; index++) {
            outShape[copied++] = dimensions[index];
        }
    }

    size_t count = 1;
    for (size_t index = 0; index < rank; index++) {
        count *= (size_t)(dimensions[index] > 0 ? dimensions[index] : 1);
    }

    void *raw = NULL;
    if (check(api->GetTensorMutableData(value, &raw), api, errorMessage) != 0) return NULL;

    float *result = malloc(count * sizeof(float));
    if (result == NULL) {
        setError(errorMessage, "malloc failed");
        return NULL;
    }
    memcpy(result, raw, count * sizeof(float));
    if (outCount != NULL) *outCount = (int32_t)count;
    return result;
}

/// Như `copyFloats` nhưng **ghi thẳng vào buffer do bên gọi cấp** ⇒ bỏ được `malloc` + một tầng `memcpy`.
///
/// Dùng cho `vector_estimator` (16 lượt/chunk — chỗ churn thật). Bên gọi **phải** biết trước số phần tử
/// (ở đây là `latentChannels × frames`, khớp shape output vì velocity cùng shape với `x`); nếu buffer
/// nhỏ hơn số thật thì trả lỗi chứ **không** ghi tràn.
///
/// Trả `0` khi thành công, `-1` khi lỗi. `copiedBytes` cộng dồn để đo churn.
///
/// `outShape`/`shapeCapacity`/`outRank` là **tuỳ chọn** (truyền `NULL`/`0`/`NULL` khi bên gọi đã biết
/// shape) — `codec_encoder` cần chúng vì số kênh và số frame của latent **không** suy được từ công thức.
static int32_t copyFloatsInto(const OrtApi *api,
                              OrtValue *value,
                              float *outBuffer,
                              int32_t capacity,
                              int32_t *outCount,
                              int64_t *outShape,
                              int32_t shapeCapacity,
                              int32_t *outRank,
                              VieNeuORT *context,
                              char **errorMessage) {
    OrtTensorTypeAndShapeInfo *info = NULL;
    if (check(api->GetTensorTypeAndShape(value, &info), api, errorMessage) != 0) return -1;

    size_t rank = 0;
    if (check(api->GetDimensionsCount(info, &rank), api, errorMessage) != 0) {
        api->ReleaseTensorTypeAndShapeInfo(info);
        return -1;
    }
    if (rank > 8) rank = 8;
    int64_t dimensions[8] = {0};
    if (rank > 0 && check(api->GetDimensions(info, dimensions, rank), api, errorMessage) != 0) {
        api->ReleaseTensorTypeAndShapeInfo(info);
        return -1;
    }
    api->ReleaseTensorTypeAndShapeInfo(info);

    if (outRank != NULL) *outRank = (int32_t)rank;
    if (outShape != NULL) {
        int32_t copied = 0;
        for (size_t index = 0; index < rank && copied < shapeCapacity; index++) {
            outShape[copied++] = dimensions[index];
        }
    }

    size_t count = 1;
    for (size_t index = 0; index < rank; index++) {
        count *= (size_t)(dimensions[index] > 0 ? dimensions[index] : 1);
    }
    if ((int64_t)count > (int64_t)capacity) {
        setError(errorMessage, "buffer ra quá nhỏ cho output của graph");
        return -1;
    }

    void *raw = NULL;
    if (check(api->GetTensorMutableData(value, &raw), api, errorMessage) != 0) return -1;

    memcpy(outBuffer, raw, count * sizeof(float));
    if (context != NULL) context->copiedBytes += (int64_t)(count * sizeof(float));
    if (outCount != NULL) *outCount = (int32_t)count;
    return 0;
}

#pragma mark - Vòng đời

/// Nạp 3 graph clone bằng một `OrtSessionOptions` **đã có**.
///
/// Tách khỏi `VieNeuORTLoadCloneGraphs` (hàm tự dựng options) để `VieNeuORTCreateCloneOnly` dùng lại
/// đúng bộ options của khung ngữ cảnh thay vì tạo bộ thứ hai.
static int32_t loadCloneGraphsWithOptions(VieNeuORT *context, const char *modelDirectory,
                                          const OrtSessionOptions *options, char **errorMessage);

/// Dựng phần **khung** của ngữ cảnh: `OrtEnv`, `OrtMemoryInfo`, `OrtAllocator` và một
/// `OrtSessionOptions` đã đặt số luồng + mức tối ưu (**và CoreML EP nếu `runOptions->useCoreML`**).
/// **Chưa** mở session nào.
///
/// Tách ra vì có **hai** kiểu ngữ cảnh dùng chung phần khung này:
/// - `VieNeuORTCreate` / `VieNeuORTCreateWithRunOptions` — đủ 4 graph chính (đường tổng hợp).
/// - `VieNeuORTCreateCloneOnly` — chỉ 3 graph clone (đường tạo giọng).
///
/// `runOptions == NULL` ⇒ CPU + log mặc định, đúng hành vi trước 1.3.466.
///
/// `*outOptions` thuộc bên gọi: giải phóng bằng `ReleaseSessionOptions` sau khi mở xong session. Truyền
/// `NULL` được nếu bên gọi tự lo options (khi đó options dựng ở đây bị giải phóng luôn).
static VieNeuORT *createBaseContext(int32_t threadCount,
                                    const VieNeuORTRunOptions *runOptions,
                                    OrtSessionOptions **outOptions,
                                    char **errorMessage) {
    const OrtApiBase *base = OrtGetApiBase();
    if (base == NULL) {
        setError(errorMessage, "OrtGetApiBase returned NULL");
        return NULL;
    }
    const OrtApi *api = base->GetApi(ORT_API_VERSION);
    if (api == NULL) {
        setError(errorMessage, "GetApi returned NULL");
        return NULL;
    }

    VieNeuORT *context = calloc(1, sizeof(VieNeuORT));
    if (context == NULL) {
        setError(errorMessage, "calloc failed");
        return NULL;
    }
    context->api = api;

    // Đường thí nghiệm CoreML bật logger tuỳ biến để tầng Swift thấy được log của ORT; mọi đường khác
    // giữ nguyên `CreateEnv` (ghi ra stderr) như trước 1.3.466.
    const int32_t wantsLog = (runOptions != NULL) && (runOptions->verboseLog || runOptions->useCoreML);
    const OrtLoggingLevel level = (runOptions != NULL && runOptions->verboseLog)
        ? ORT_LOGGING_LEVEL_VERBOSE : ORT_LOGGING_LEVEL_WARNING;
    OrtStatus *envStatus = wantsLog
        ? api->CreateEnvWithCustomLogger(vieNeuORTLogTrampoline, NULL, level, "FreeBookVieNeu", &context->env)
        : api->CreateEnv(level, "FreeBookVieNeu", &context->env);
    if (check(envStatus, api, errorMessage) != 0) {
        VieNeuORTDestroy(context);
        return NULL;
    }
    if (check(api->CreateCpuMemoryInfo(OrtDeviceAllocator, OrtMemTypeDefault, &context->memoryInfo),
              api, errorMessage) != 0) {
        VieNeuORTDestroy(context);
        return NULL;
    }

    if (check(api->GetAllocatorWithDefaultOptions(&context->allocator), api, errorMessage) != 0) {
        VieNeuORTDestroy(context);
        return NULL;
    }

    OrtSessionOptions *options = NULL;
    if (check(api->CreateSessionOptions(&options), api, errorMessage) != 0) {
        VieNeuORTDestroy(context);
        return NULL;
    }
    check(api->SetIntraOpNumThreads(options, threadCount), api, errorMessage);
    check(api->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL), api, errorMessage);
    context->threadCount = threadCount;

    if (runOptions != NULL && runOptions->useCoreML) {
        if (appendCoreMLProvider(api, options, runOptions, errorMessage) != 0) {
            // Cố ý KHÔNG im lặng chạy tiếp trên CPU: như vậy số đo thí nghiệm sẽ vô nghĩa vì người dùng
            // tưởng đang chạy ANE. Bên gọi (Swift) tự quyết định quay về CPU.
            VieNeuORTDestroy(context);
            return NULL;
        }
    }

    if (outOptions != NULL) {
        *outOptions = options;
    } else {
        api->ReleaseSessionOptions(options);
    }
    return context;
}

/// Dựng ngữ cảnh **đủ 4 graph chính**. `runOptions == NULL` ⇒ CPU, log mặc định (đường cũ).
static VieNeuORT *createMainContext(const char *modelDirectory, int32_t threadCount,
                                    const VieNeuORTRunOptions *runOptions, char **errorMessage) {
    if (modelDirectory == NULL) {
        setError(errorMessage, "modelDirectory is NULL");
        return NULL;
    }
    OrtSessionOptions *options = NULL;
    VieNeuORT *context = createBaseContext(threadCount, runOptions, &options, errorMessage);
    if (context == NULL) return NULL;
    const OrtApi *api = context->api;

    context->sessions[VieNeuGraphTextEncoder] =
        createSession(api, context->env, options, modelDirectory, "text_encoder.onnx", VieNeuGraphTextEncoder, context, errorMessage);
    context->sessions[VieNeuGraphDurationPredictor] =
        createSession(api, context->env, options, modelDirectory, "duration_predictor.onnx", VieNeuGraphDurationPredictor, context, errorMessage);
    context->sessions[VieNeuGraphVectorEstimator] =
        createSession(api, context->env, options, modelDirectory, "vector_estimator.onnx", VieNeuGraphVectorEstimator, context, errorMessage);
    context->sessions[VieNeuGraphCodecDecoder] =
        createSession(api, context->env, options, modelDirectory, "codec_decoder.onnx", VieNeuGraphCodecDecoder, context, errorMessage);
    api->ReleaseSessionOptions(options);

    for (int index = 0; index < VieNeuGraphCount; index++) {
        if (context->sessions[index] == NULL) {
            VieNeuORTDestroy(context);
            return NULL;
        }
    }
    return context;
}

VieNeuORT *VieNeuORTCreate(const char *modelDirectory, int32_t threadCount, char **errorMessage) {
    return createMainContext(modelDirectory, threadCount, NULL, errorMessage);
}

VieNeuORT *VieNeuORTCreateWithRunOptions(const char *modelDirectory, int32_t threadCount,
                                         const VieNeuORTRunOptions *runOptions, char **errorMessage) {
    return createMainContext(modelDirectory, threadCount, runOptions, errorMessage);
}

VieNeuORT *VieNeuORTCreateCloneOnly(const char *modelDirectory, int32_t threadCount, char **errorMessage) {
    if (modelDirectory == NULL) {
        setError(errorMessage, "modelDirectory is NULL");
        return NULL;
    }
    OrtSessionOptions *options = NULL;
    // `NULL` runOptions: đường nhân bản giọng **không** dùng CoreML EP — 3 graph clone không nằm trên
    // đường nóng (xem plan 1.3.466), và nạp thêm EP ở đây chỉ tăng rủi ro cho luồng tạo giọng.
    VieNeuORT *context = createBaseContext(threadCount, NULL, &options, errorMessage);
    if (context == NULL) return NULL;

    // Dùng **cùng** options với khung (số luồng + mức tối ưu) thay vì để `VieNeuORTLoadCloneGraphs` dựng
    // bộ thứ hai — cùng cấu hình nên không có lý do gì để tạo hai lần.
    int32_t status = loadCloneGraphsWithOptions(context, modelDirectory, options, errorMessage);
    context->api->ReleaseSessionOptions(options);
    if (status != 0) {
        VieNeuORTDestroy(context);
        return NULL;
    }
    return context;
}

void VieNeuORTDestroy(VieNeuORT *context) {
    if (context == NULL) return;
    const OrtApi *api = context->api;
    if (api != NULL) {
        // Tensor cache của nhánh vô điều kiện sống lâu hơn một hàm ⇒ phải giải phóng ở đây, không như
        // tensor tạo-trong-hàm (những cái đó đã tự `ReleaseValue` trước khi hàm trả về).
        VieNeuORTResetVectorCache(context);
        for (int index = 0; index < VieNeuGraphCount; index++) {
            if (context->sessions[index] != NULL) api->ReleaseSession(context->sessions[index]);
        }
        // Vòng lặp **riêng** cho graph clone: chúng có thể chưa từng được nạp (`NULL`), và nới
        // `VieNeuGraphCount` để gộp chung sẽ làm `VieNeuORTCreate` đòi đủ 7 file.
        for (int index = 0; index < VieNeuCloneGraphCount; index++) {
            if (context->cloneSessions[index] != NULL) api->ReleaseSession(context->cloneSessions[index]);
        }
        // Tên output do allocator mặc định của ORT cấp phát ⇒ phải trả lại bằng chính allocator đó.
        if (context->allocator != NULL) {
            for (int index = 0; index < VieNeuGraphCount; index++) {
                if (context->outputNames[index] != NULL) {
                    context->allocator->Free(context->allocator, context->outputNames[index]);
                }
            }
            for (int index = 0; index < VieNeuCloneGraphCount; index++) {
                if (context->cloneOutputNames[index] != NULL) {
                    context->allocator->Free(context->allocator, context->cloneOutputNames[index]);
                }
                for (int slot = 0; slot < VieNeuCloneMaxInputs; slot++) {
                    if (context->cloneInputNames[index][slot] != NULL) {
                        context->allocator->Free(context->allocator, context->cloneInputNames[index][slot]);
                    }
                }
            }
        }
        if (context->memoryInfo != NULL) api->ReleaseMemoryInfo(context->memoryInfo);
        if (context->env != NULL) api->ReleaseEnv(context->env);
    }
    free(context);
}

void VieNeuORTResetVectorCache(VieNeuORT *context) {
    if (context == NULL) return;
    const OrtApi *api = context->api;
    if (api == NULL) return;
    if (context->cachedNullContext != NULL) { api->ReleaseValue(context->cachedNullContext); context->cachedNullContext = NULL; }
    if (context->cachedNullMask != NULL)    { api->ReleaseValue(context->cachedNullMask);    context->cachedNullMask = NULL; }
    if (context->cachedNullSpeaker != NULL) { api->ReleaseValue(context->cachedNullSpeaker); context->cachedNullSpeaker = NULL; }
    if (context->cachedNullStyle != NULL)   { api->ReleaseValue(context->cachedNullStyle);   context->cachedNullStyle = NULL; }
}

void VieNeuORTChurnSnapshot(VieNeuORT *context, int64_t *outCreates, int64_t *outReleases, int64_t *outCopiedBytes) {
    if (context == NULL) return;
    if (outCreates != NULL) *outCreates = context->tensorCreates;
    if (outReleases != NULL) *outReleases = context->tensorReleases;
    if (outCopiedBytes != NULL) *outCopiedBytes = context->copiedBytes;
}

void VieNeuORTResetChurnCounters(VieNeuORT *context) {
    if (context == NULL) return;
    context->tensorCreates = 0;
    context->tensorReleases = 0;
    context->copiedBytes = 0;
}

void VieNeuORTFreeErrorMessage(char *errorMessage) {
    free(errorMessage);
}

#pragma mark - Bốn bước pipeline

float *VieNeuORTRunTextEncoder(VieNeuORT *context,
                               const int64_t *ids, int32_t length,
                               const float *style, int32_t styleRows, int32_t styleColumns,
                               int32_t *outCount,
                               int64_t *outShape, int32_t shapeCapacity, int32_t *outRank,
                               char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return NULL;
    }
    const OrtApi *api = context->api;
    const int64_t idsShape[2] = {1, length};
    const int64_t styleShape[3] = {1, styleRows, styleColumns};

    OrtValue *idsValue = makeTensor(api, context->memoryInfo, ids,
                                    (size_t)length * sizeof(int64_t), idsShape, 2,
                                    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, errorMessage);
    if (idsValue == NULL) return NULL;
    OrtValue *styleValue = makeTensor(api, context->memoryInfo, style,
                                      (size_t)(styleRows * styleColumns) * sizeof(float), styleShape, 3,
                                      ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    if (styleValue == NULL) {
        api->ReleaseValue(idsValue);
        return NULL;
    }

    const char *names[2] = {"ids", "style"};
    const OrtValue *inputs[2] = {idsValue, styleValue};
    OrtValue *output = runSession(api, context->sessions[VieNeuGraphTextEncoder], names, inputs, 2, context->outputNames[VieNeuGraphTextEncoder], errorMessage);

    api->ReleaseValue(idsValue);
    api->ReleaseValue(styleValue);
    if (output == NULL) return NULL;

    float *result = copyFloats(api, output, outCount, outShape, shapeCapacity, outRank, errorMessage);
    api->ReleaseValue(output);
    return result;
}

int32_t VieNeuORTRunDurationPredictor(VieNeuORT *context,
                                      const float *context_, const int64_t *contextShape, int32_t contextRank,
                                      const uint8_t *mask,
                                      const float *speaker, int32_t speakerCount,
                                      float *outValue, char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return -1;
    }
    if (contextShape == NULL || contextRank < 2) {
        setError(errorMessage, "ctx shape không hợp lệ");
        return -1;
    }
    const OrtApi *api = context->api;
    // Số token lấy từ shape THẬT của ctx; `mask` phải cùng số token đó.
    const int32_t length = (int32_t)contextShape[1];
    int64_t contextElementCount = 1;
    for (int32_t index = 0; index < contextRank; index++) contextElementCount *= contextShape[index];
    const int64_t maskShape[2] = {1, length};
    const int64_t speakerShape[2] = {1, speakerCount};

    OrtValue *contextValue = makeTensor(api, context->memoryInfo, context_,
                                        (size_t)contextElementCount * sizeof(float),
                                        contextShape, (size_t)contextRank,
                                        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    if (contextValue == NULL) return -1;
    // `ctx_mask` là **bool** — một byte mỗi phần tử. Đây chính là tensor mà lớp ObjC không tạo được.
    OrtValue *maskValue = makeTensor(api, context->memoryInfo, mask,
                                     (size_t)length * sizeof(uint8_t), maskShape, 2,
                                     ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    if (maskValue == NULL) {
        api->ReleaseValue(contextValue);
        return -1;
    }
    OrtValue *speakerValue = makeTensor(api, context->memoryInfo, speaker,
                                        (size_t)speakerCount * sizeof(float), speakerShape, 2,
                                        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    if (speakerValue == NULL) {
        api->ReleaseValue(contextValue);
        api->ReleaseValue(maskValue);
        return -1;
    }

    const char *names[3] = {"ctx", "ctx_mask", "spk"};
    const OrtValue *inputs[3] = {contextValue, maskValue, speakerValue};
    OrtValue *output = runSession(api, context->sessions[VieNeuGraphDurationPredictor], names, inputs, 3, context->outputNames[VieNeuGraphDurationPredictor], errorMessage);

    api->ReleaseValue(contextValue);
    api->ReleaseValue(maskValue);
    api->ReleaseValue(speakerValue);
    if (output == NULL) return -1;

    int32_t count = 0;
    float *values = copyFloats(api, output, &count, NULL, 0, NULL, errorMessage);
    api->ReleaseValue(output);
    if (values == NULL) return -1;
    if (count < 1) {
        free(values);
        setError(errorMessage, "duration_predictor returned no element");
        return -1;
    }
    *outValue = values[0];
    free(values);
    return 0;
}

int32_t VieNeuORTRunVectorEstimatorInto(VieNeuORT *context,
                                        const float *latent, int32_t latentChannels, int32_t frames,
                                        float time,
                                        const float *context_, const int64_t *contextShape, int32_t contextRank,
                                        const uint8_t *mask,
                                        const float *speaker, int32_t speakerCount,
                                        const float *style, int32_t styleRows, int32_t styleColumns,
                                        float *outBuffer, int32_t outCapacity,
                                        int32_t *outCount, char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return -1;
    }
    if (outBuffer == NULL) {
        setError(errorMessage, "outBuffer is NULL");
        return -1;
    }
    if (contextShape == NULL || contextRank < 2) {
        setError(errorMessage, "ctx shape không hợp lệ");
        return -1;
    }
    const OrtApi *api = context->api;
    const int32_t length = (int32_t)contextShape[1];
    int64_t contextElementCount = 1;
    for (int32_t index = 0; index < contextRank; index++) contextElementCount *= contextShape[index];
    const int64_t latentShape[3] = {1, latentChannels, frames};
    const int64_t timeShape[1] = {1};
    const int64_t maskShape[2] = {1, length};
    const int64_t speakerShape[2] = {1, speakerCount};
    const int64_t styleShape[3] = {1, styleRows, styleColumns};

    OrtValue *latentValue = makeTensorCounted(api, context, latent,
                                              (size_t)(latentChannels * frames) * sizeof(float), latentShape, 3,
                                              ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    if (latentValue == NULL) return -1;
    OrtValue *timeValue = makeTensorCounted(api, context, &time, sizeof(float), timeShape, 1,
                                            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    OrtValue *contextValue = makeTensorCounted(api, context, context_,
                                               (size_t)contextElementCount * sizeof(float),
                                               contextShape, (size_t)contextRank,
                                               ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    OrtValue *maskValue = makeTensorCounted(api, context, mask,
                                            (size_t)length * sizeof(uint8_t), maskShape, 2,
                                            ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    OrtValue *speakerValue = makeTensorCounted(api, context, speaker,
                                               (size_t)speakerCount * sizeof(float), speakerShape, 2,
                                               ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    OrtValue *styleValue = makeTensorCounted(api, context, style,
                                             (size_t)(styleRows * styleColumns) * sizeof(float), styleShape, 3,
                                             ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);

    OrtValue *values[6] = {latentValue, timeValue, contextValue, maskValue, speakerValue, styleValue};
    for (size_t index = 0; index < 6; index++) {
        if (values[index] == NULL) {
            for (size_t inner = 0; inner < 6; inner++) {
                if (values[inner] != NULL) { api->ReleaseValue(values[inner]); context->tensorReleases += 1; }
            }
            return -1;
        }
    }

    const char *names[6] = {"x", "t", "ctx", "ctx_mask", "spk", "style"};
    const OrtValue *inputs[6] = {latentValue, timeValue, contextValue, maskValue, speakerValue, styleValue};
    OrtValue *output = runSession(api, context->sessions[VieNeuGraphVectorEstimator], names, inputs, 6, context->outputNames[VieNeuGraphVectorEstimator], errorMessage);

    for (size_t index = 0; index < 6; index++) { api->ReleaseValue(values[index]); context->tensorReleases += 1; }
    if (output == NULL) return -1;

    int32_t status = copyFloatsInto(api, output, outBuffer, outCapacity, outCount,
                                    NULL, 0, NULL, context, errorMessage);
    api->ReleaseValue(output);
    return status;
}

int32_t VieNeuORTRunVectorEstimatorUnconditionedInto(VieNeuORT *context,
                                                     const float *latent, int32_t latentChannels, int32_t frames,
                                                     float time,
                                                     const float *nullContext_, int64_t ctxElementCount,
                                                     const int64_t *ctxShape, int32_t ctxRank,
                                                     const uint8_t *nullMask, int32_t maskLength,
                                                     const float *nullSpeaker, int32_t speakerCount,
                                                     const float *nullStyle, int32_t styleRows, int32_t styleColumns,
                                                     float *outBuffer, int32_t outCapacity,
                                                     int32_t *outCount, char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return -1;
    }
    if (outBuffer == NULL) {
        setError(errorMessage, "outBuffer is NULL");
        return -1;
    }
    if (ctxShape == NULL || ctxRank < 2) {
        setError(errorMessage, "ctx shape không hợp lệ");
        return -1;
    }
    const OrtApi *api = context->api;
    const int64_t latentShape[3] = {1, latentChannels, frames};
    const int64_t timeShape[1] = {1};
    const int64_t maskShape[2] = {1, maskLength};
    const int64_t speakerShape[2] = {1, speakerCount};
    const int64_t styleShape[3] = {1, styleRows, styleColumns};

    // Hai tensor **đổi mỗi bước** phải tạo mới; bốn tensor còn lại là loop-invariant ⇒ dựng cache một lần.
    OrtValue *latentValue = makeTensorCounted(api, context, latent,
                                              (size_t)(latentChannels * frames) * sizeof(float), latentShape, 3,
                                              ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    if (latentValue == NULL) return -1;
    OrtValue *timeValue = makeTensorCounted(api, context, &time, sizeof(float), timeShape, 1,
                                            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    if (timeValue == NULL) {
        api->ReleaseValue(latentValue); context->tensorReleases += 1;
        return -1;
    }

    // Cache dựng từ **buffer thật của nhánh null** (không phải `x`). `CreateTensorWithDataAsOrtValue`
    // không copy ⇒ buffer đó (`nullContext`/`nullMask`/`nullSpeaker`/`nullStyle`) phải sống tới
    // `VieNeuORTResetVectorCache`; engine gọi reset ngay khi `prepareLocked` thay mảng.
    if (context->cachedNullContext == NULL) {
        context->cachedNullContext = makeTensorCounted(api, context, nullContext_,
                                                       (size_t)ctxElementCount * sizeof(float),
                                                       ctxShape, (size_t)ctxRank,
                                                       ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    }
    if (context->cachedNullMask == NULL) {
        context->cachedNullMask = makeTensorCounted(api, context, nullMask,
                                                    (size_t)maskLength * sizeof(uint8_t), maskShape, 2,
                                                    ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    }
    if (context->cachedNullSpeaker == NULL) {
        context->cachedNullSpeaker = makeTensorCounted(api, context, nullSpeaker,
                                                       (size_t)speakerCount * sizeof(float), speakerShape, 2,
                                                       ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    }
    if (context->cachedNullStyle == NULL) {
        context->cachedNullStyle = makeTensorCounted(api, context, nullStyle,
                                                     (size_t)(styleRows * styleColumns) * sizeof(float), styleShape, 3,
                                                     ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    }

    if (context->cachedNullContext == NULL || context->cachedNullMask == NULL
        || context->cachedNullSpeaker == NULL || context->cachedNullStyle == NULL) {
        api->ReleaseValue(latentValue); context->tensorReleases += 1;
        api->ReleaseValue(timeValue); context->tensorReleases += 1;
        return -1;
    }

    const char *names[6] = {"x", "t", "ctx", "ctx_mask", "spk", "style"};
    const OrtValue *inputs[6] = {
        latentValue, timeValue,
        context->cachedNullContext, context->cachedNullMask,
        context->cachedNullSpeaker, context->cachedNullStyle
    };
    OrtValue *output = runSession(api, context->sessions[VieNeuGraphVectorEstimator], names, inputs, 6, context->outputNames[VieNeuGraphVectorEstimator], errorMessage);

    api->ReleaseValue(latentValue); context->tensorReleases += 1;
    api->ReleaseValue(timeValue); context->tensorReleases += 1;
    if (output == NULL) return -1;

    int32_t status = copyFloatsInto(api, output, outBuffer, outCapacity, outCount,
                                    NULL, 0, NULL, context, errorMessage);
    api->ReleaseValue(output);
    return status;
}

float *VieNeuORTRunVectorEstimator(VieNeuORT *context,
                                   const float *latent, int32_t latentChannels, int32_t frames,
                                   float time,
                                   const float *context_, const int64_t *contextShape, int32_t contextRank,
                                   const uint8_t *mask,
                                   const float *speaker, int32_t speakerCount,
                                   const float *style, int32_t styleRows, int32_t styleColumns,
                                   int32_t *outCount, char **errorMessage) {
    // Vỏ giữ hợp đồng cũ cho bên gọi chưa chuyển sang biến thể ghi-vào-buffer. Đường Reader dùng bản
    // `…Into` để bỏ được `malloc` + một tầng `memcpy`.
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return NULL;
    }
    if (contextShape == NULL || contextRank < 2) {
        setError(errorMessage, "ctx shape không hợp lệ");
        return NULL;
    }
    int64_t total = (int64_t)latentChannels * (int64_t)frames;
    if (total <= 0) {
        setError(errorMessage, "kích thước latent không hợp lệ");
        return NULL;
    }
    float *result = malloc((size_t)total * sizeof(float));
    if (result == NULL) {
        setError(errorMessage, "malloc failed");
        return NULL;
    }
    int32_t count = 0;
    if (VieNeuORTRunVectorEstimatorInto(context, latent, latentChannels, frames, time,
                                        context_, contextShape, contextRank, mask,
                                        speaker, speakerCount, style, styleRows, styleColumns,
                                        result, (int32_t)total, &count, errorMessage) != 0) {
        free(result);
        return NULL;
    }
    if (outCount != NULL) *outCount = count;
    return result;
}


float *VieNeuORTRunCodecDecoder(VieNeuORT *context,
                                const float *latent, int32_t latentChannels, int32_t frames,
                                int32_t *outCount, char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return NULL;
    }
    const OrtApi *api = context->api;
    const int64_t latentShape[3] = {1, latentChannels, frames};

    OrtValue *latentValue = makeTensor(api, context->memoryInfo, latent,
                                       (size_t)(latentChannels * frames) * sizeof(float), latentShape, 3,
                                       ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    if (latentValue == NULL) return NULL;

    const char *names[1] = {"x"};
    const OrtValue *inputs[1] = {latentValue};
    OrtValue *output = runSession(api, context->sessions[VieNeuGraphCodecDecoder], names, inputs, 1, context->outputNames[VieNeuGraphCodecDecoder], errorMessage);

    api->ReleaseValue(latentValue);
    if (output == NULL) return NULL;

    float *result = copyFloats(api, output, outCount, NULL, 0, NULL, errorMessage);
    api->ReleaseValue(output);
    return result;
}

#pragma mark - Graph clone giọng

int32_t VieNeuORTLoadCloneGraphs(VieNeuORT *context, const char *modelDirectory, char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return -1;
    }
    if (modelDirectory == NULL) {
        setError(errorMessage, "modelDirectory is NULL");
        return -1;
    }
    // Gọi lại lần hai là no-op: nếu đã đủ 3 graph thì không mở session trùng.
    if (VieNeuORTHasCloneGraphs(context)) return 0;

    const OrtApi *api = context->api;
    // Dùng **cùng** cấu hình luồng/tối ưu với 4 graph chính (`context->threadCount` đã lưu ở
    // `VieNeuORTCreate`) — gói clone không được tự ý chạy khác số luồng.
    OrtSessionOptions *options = NULL;
    if (check(api->CreateSessionOptions(&options), api, errorMessage) != 0) return -1;
    check(api->SetIntraOpNumThreads(options, context->threadCount), api, errorMessage);
    check(api->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL), api, errorMessage);

    int32_t status = loadCloneGraphsWithOptions(context, modelDirectory, options, errorMessage);
    api->ReleaseSessionOptions(options);
    return status;
}

static int32_t loadCloneGraphsWithOptions(VieNeuORT *context, const char *modelDirectory,
                                          const OrtSessionOptions *options, char **errorMessage) {
    const OrtApi *api = context->api;
    static const char *fileNames[VieNeuCloneGraphCount] = {
        "speaker_encoder.onnx", "codec_encoder.onnx", "reference_encoder.onnx"
    };

    for (int index = 0; index < VieNeuCloneGraphCount; index++) {
        context->cloneSessions[index] =
            createCloneSession(api, context->env, options, modelDirectory, fileNames[index], index,
                               context, errorMessage);
        if (context->cloneSessions[index] != NULL) continue;

        // Hợp đồng ở header: lỗi ⇒ **không** giữ session nào, để gọi lại được sau khi người dùng tải
        // nốt gói. Giải phóng cả những graph đã nạp thành công ở các vòng trước (kể cả tên đã đọc).
        for (int inner = 0; inner < VieNeuCloneGraphCount; inner++) {
            if (context->cloneSessions[inner] != NULL) {
                api->ReleaseSession(context->cloneSessions[inner]);
                context->cloneSessions[inner] = NULL;
            }
            freeSessionString(context, context->cloneOutputNames[inner]);
            context->cloneOutputNames[inner] = NULL;
            for (int slot = 0; slot < VieNeuCloneMaxInputs; slot++) {
                freeSessionString(context, context->cloneInputNames[inner][slot]);
                context->cloneInputNames[inner][slot] = NULL;
            }
            context->cloneInputCounts[inner] = 0;
        }
        return -1;
    }
    return 0;
}

int32_t VieNeuORTHasCloneGraphs(const VieNeuORT *context) {
    if (context == NULL) return 0;
    for (int index = 0; index < VieNeuCloneGraphCount; index++) {
        if (context->cloneSessions[index] == NULL) return 0;
    }
    return 1;
}

int32_t VieNeuORTRunSpeakerEncoder(VieNeuORT *context,
                                   const float *fbank, int32_t frames, int32_t melBins,
                                   float *outBuffer, int32_t outCapacity, int32_t *outCount,
                                   char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return -1;
    }
    if (!VieNeuORTHasCloneGraphs(context)) {
        setError(errorMessage, "chưa nạp gói graph clone");
        return -1;
    }
    if (outBuffer == NULL) {
        setError(errorMessage, "outBuffer is NULL");
        return -1;
    }
    if (frames <= 0 || melBins <= 0) {
        setError(errorMessage, "kích thước fbank không hợp lệ");
        return -1;
    }
    const OrtApi *api = context->api;
    const int graph = VieNeuCloneGraphSpeakerEncoder;
    // Input `[batch, sequence_length, 80]` — bên gọi đã trừ trung bình theo bin trước khi vào đây.
    const int64_t shape[3] = {1, frames, melBins};

    OrtValue *input = makeTensor(api, context->memoryInfo, fbank,
                                 (size_t)(frames * melBins) * sizeof(float), shape, 3,
                                 ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    if (input == NULL) return -1;

    const char *names[1] = {context->cloneInputNames[graph][0]};
    const OrtValue *inputs[1] = {input};
    OrtValue *output = runSession(api, context->cloneSessions[graph], names, inputs, 1,
                                  context->cloneOutputNames[graph], errorMessage);
    api->ReleaseValue(input);
    if (output == NULL) return -1;

    // Số phần tử thật (192) đọc từ shape graph, không hardcode `EMBED_DIM`.
    int32_t count = 0;
    int32_t status = copyFloatsInto(api, output, outBuffer, outCapacity, &count,
                                    NULL, 0, NULL, context, errorMessage);
    api->ReleaseValue(output);
    if (status == 0 && outCount != NULL) *outCount = count;
    return status;
}

int32_t VieNeuORTRunCodecEncoder(VieNeuORT *context,
                                 const float *pcm, int32_t sampleCount,
                                 float *outBuffer, int32_t outCapacity,
                                 int64_t *outShape, int32_t shapeCapacity, int32_t *outRank,
                                 int32_t *outCount, char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return -1;
    }
    if (!VieNeuORTHasCloneGraphs(context)) {
        setError(errorMessage, "chưa nạp gói graph clone");
        return -1;
    }
    if (outBuffer == NULL) {
        setError(errorMessage, "outBuffer is NULL");
        return -1;
    }
    if (sampleCount <= 0) {
        setError(errorMessage, "độ dài waveform không hợp lệ");
        return -1;
    }
    const OrtApi *api = context->api;
    const int graph = VieNeuCloneGraphCodecEncoder;
    // `wav` là `[1, 1, N]` — waveform mono 24 kHz.
    const int64_t shape[3] = {1, 1, sampleCount};

    OrtValue *input = makeTensor(api, context->memoryInfo, pcm,
                                 (size_t)sampleCount * sizeof(float), shape, 3,
                                 ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    if (input == NULL) return -1;

    const char *names[1] = {context->cloneInputNames[graph][0]};
    const OrtValue *inputs[1] = {input};
    OrtValue *output = runSession(api, context->cloneSessions[graph], names, inputs, 1,
                                  context->cloneOutputNames[graph], errorMessage);
    api->ReleaseValue(input);
    if (output == NULL) return -1;

    // Số kênh (24) và số frame của latent **không** suy được từ công thức ⇒ bắt buộc trả shape thật
    // cho bên gọi (`outShape`/`outRank`), đúng hợp đồng ở header.
    int32_t count = 0;
    int32_t status = copyFloatsInto(api, output, outBuffer, outCapacity, &count,
                                    outShape, shapeCapacity, outRank, context, errorMessage);
    api->ReleaseValue(output);
    if (status == 0 && outCount != NULL) *outCount = count;
    return status;
}

int32_t VieNeuORTRunReferenceEncoder(VieNeuORT *context,
                                     const float *latent, int32_t channels, int32_t frames,
                                     float *outBuffer, int32_t outCapacity, int32_t *outCount,
                                     char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return -1;
    }
    if (!VieNeuORTHasCloneGraphs(context)) {
        setError(errorMessage, "chưa nạp gói graph clone");
        return -1;
    }
    if (outBuffer == NULL) {
        setError(errorMessage, "outBuffer is NULL");
        return -1;
    }
    if (channels <= 0 || frames <= 0) {
        setError(errorMessage, "kích thước latent không hợp lệ");
        return -1;
    }
    const OrtApi *api = context->api;
    const int graph = VieNeuCloneGraphReferenceEncoder;
    // `reference_encoder` là graph clone **duy nhất** cần 2 input; thiếu `ref_mask` thì `Run` sẽ báo
    // lỗi khó hiểu, nên chặn sớm bằng thông báo rõ.
    if (context->cloneInputCounts[graph] < 2) {
        setError(errorMessage, "reference_encoder thiếu input ref_mask");
        return -1;
    }
    const int64_t refShape[3] = {1, channels, frames};
    const int64_t maskShape[2] = {1, frames};

    // `ref_mask = np.ones((1, T), bool)` của upstream: mọi phần tử `true`. Tự dựng ở đây thay vì bắt
    // bên gọi truyền vào — không có tham số nào để hoá trị, vì nó luôn toàn `1`.
    uint8_t *mask = malloc((size_t)frames);
    if (mask == NULL) {
        setError(errorMessage, "malloc failed");
        return -1;
    }
    memset(mask, 1, (size_t)frames);

    OrtValue *refValue = makeTensor(api, context->memoryInfo, latent,
                                    (size_t)(channels * frames) * sizeof(float), refShape, 3,
                                    ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    if (refValue == NULL) {
        free(mask);
        return -1;
    }
    OrtValue *maskValue = makeTensor(api, context->memoryInfo, mask,
                                     (size_t)frames * sizeof(uint8_t), maskShape, 2,
                                     ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    if (maskValue == NULL) {
        api->ReleaseValue(refValue);
        free(mask);
        return -1;
    }

    const char *names[2] = {context->cloneInputNames[graph][0], context->cloneInputNames[graph][1]};
    const OrtValue *inputs[2] = {refValue, maskValue};
    OrtValue *output = runSession(api, context->cloneSessions[graph], names, inputs, 2,
                                  context->cloneOutputNames[graph], errorMessage);

    // `CreateTensorWithDataAsOrtValue` không copy ⇒ `mask` chỉ được giải phóng **sau** `Run`.
    api->ReleaseValue(refValue);
    api->ReleaseValue(maskValue);
    free(mask);
    if (output == NULL) return -1;

    int32_t count = 0;
    int32_t status = copyFloatsInto(api, output, outBuffer, outCapacity, &count,
                                    NULL, 0, NULL, context, errorMessage);
    api->ReleaseValue(output);
    if (status == 0 && outCount != NULL) *outCount = count;
    return status;
}
