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

struct VieNeuORT {
    const OrtApi *api;
    OrtEnv *env;
    OrtMemoryInfo *memoryInfo;
    OrtAllocator *allocator;
    OrtSession *sessions[VieNeuGraphCount];
    /// Tên output **đọc từ chính session** (`SessionGetOutputName`), không hardcode.
    ///
    /// Bản tham chiếu Python lấy output theo **chỉ số** (`run(None, {...})[0]`) nên không xác nhận được
    /// tên, mà `OrtApi::Run` của C API lại **bắt buộc** truyền tên. Đoán tên là mở đường cho một lỗi
    /// runtime chỉ nổ trên máy người dùng — nên hỏi thẳng session.
    char *outputNames[VieNeuGraphCount];

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
static int32_t copyFloatsInto(const OrtApi *api,
                              OrtValue *value,
                              float *outBuffer,
                              int32_t capacity,
                              int64_t *outCount,
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

VieNeuORT *VieNeuORTCreate(const char *modelDirectory, int32_t threadCount, char **errorMessage) {
    if (modelDirectory == NULL) {
        setError(errorMessage, "modelDirectory is NULL");
        return NULL;
    }
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

    if (check(api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "FreeBookVieNeu", &context->env),
              api, errorMessage) != 0) {
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
        // Tên output do allocator mặc định của ORT cấp phát ⇒ phải trả lại bằng chính allocator đó.
        if (context->allocator != NULL) {
            for (int index = 0; index < VieNeuGraphCount; index++) {
                if (context->outputNames[index] != NULL) {
                    context->allocator->Free(context->allocator, context->outputNames[index]);
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

    int32_t status = copyFloatsInto(api, output, outBuffer, outCapacity, outCount, context, errorMessage);
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

    int32_t status = copyFloatsInto(api, output, outBuffer, outCapacity, outCount, context, errorMessage);
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
