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
//    lượt `Run`. Ở đây mọi tensor được tạo, dùng và giải phóng trong cùng một hàm nên bảo đảm được.
//  - Dữ liệu output do ORT cấp phát nên căn chỉnh chuẩn ⇒ `memcpy` thẳng vào mảng float là an toàn.
//

#import "VieNeuONNXBridge.h"

#import <onnxruntime/onnxruntime_c_api.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct VieNeuORT {
    const OrtApi *api;
    OrtEnv *env;
    OrtMemoryInfo *memoryInfo;
    OrtSession *textEncoder;
    OrtSession *durationPredictor;
    OrtSession *vectorEstimator;
    OrtSession *codecDecoder;
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

static OrtSession *createSession(const OrtApi *api,
                                 const OrtEnv *env,
                                 const OrtSessionOptions *options,
                                 const char *directory,
                                 const char *name,
                                 char **errorMessage) {
    char path[4096];
    snprintf(path, sizeof(path), "%s/%s", directory, name);
    OrtSession *session = NULL;
    if (check(api->CreateSession(env, path, options, &session), api, errorMessage) != 0) return NULL;
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
static float *copyFloats(const OrtApi *api, OrtValue *value, int32_t *outCount, char **errorMessage) {
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

    OrtSessionOptions *options = NULL;
    if (check(api->CreateSessionOptions(&options), api, errorMessage) != 0) {
        VieNeuORTDestroy(context);
        return NULL;
    }
    check(api->SetIntraOpNumThreads(options, threadCount), api, errorMessage);
    check(api->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL), api, errorMessage);

    context->textEncoder = createSession(api, context->env, options, modelDirectory, "text_encoder.onnx", errorMessage);
    context->durationPredictor = createSession(api, context->env, options, modelDirectory, "duration_predictor.onnx", errorMessage);
    context->vectorEstimator = createSession(api, context->env, options, modelDirectory, "vector_estimator.onnx", errorMessage);
    context->codecDecoder = createSession(api, context->env, options, modelDirectory, "codec_decoder.onnx", errorMessage);
    api->ReleaseSessionOptions(options);

    if (context->textEncoder == NULL || context->durationPredictor == NULL ||
        context->vectorEstimator == NULL || context->codecDecoder == NULL) {
        VieNeuORTDestroy(context);
        return NULL;
    }
    return context;
}

void VieNeuORTDestroy(VieNeuORT *context) {
    if (context == NULL) return;
    const OrtApi *api = context->api;
    if (api != NULL) {
        if (context->textEncoder != NULL) api->ReleaseSession(context->textEncoder);
        if (context->durationPredictor != NULL) api->ReleaseSession(context->durationPredictor);
        if (context->vectorEstimator != NULL) api->ReleaseSession(context->vectorEstimator);
        if (context->codecDecoder != NULL) api->ReleaseSession(context->codecDecoder);
        if (context->memoryInfo != NULL) api->ReleaseMemoryInfo(context->memoryInfo);
        if (context->env != NULL) api->ReleaseEnv(context->env);
    }
    free(context);
}

void VieNeuORTFreeErrorMessage(char *errorMessage) {
    free(errorMessage);
}

#pragma mark - Bốn bước pipeline

float *VieNeuORTRunTextEncoder(VieNeuORT *context,
                               const int64_t *ids, int32_t length,
                               const float *style, int32_t styleRows, int32_t styleColumns,
                               int32_t *outCount, char **errorMessage) {
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
    OrtValue *output = runSession(api, context->textEncoder, names, inputs, 2, "ctx", errorMessage);

    api->ReleaseValue(idsValue);
    api->ReleaseValue(styleValue);
    if (output == NULL) return NULL;

    float *result = copyFloats(api, output, outCount, errorMessage);
    api->ReleaseValue(output);
    return result;
}

int32_t VieNeuORTRunDurationPredictor(VieNeuORT *context,
                                      const float *context_, int32_t length, int32_t dim,
                                      const uint8_t *mask,
                                      const float *speaker, int32_t speakerCount,
                                      float *outValue, char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return -1;
    }
    const OrtApi *api = context->api;
    const int64_t contextShape[3] = {1, length, dim};
    const int64_t maskShape[2] = {1, length};
    const int64_t speakerShape[2] = {1, speakerCount};

    OrtValue *contextValue = makeTensor(api, context->memoryInfo, context_,
                                        (size_t)(length * dim) * sizeof(float), contextShape, 3,
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
    OrtValue *output = runSession(api, context->durationPredictor, names, inputs, 3, "out", errorMessage);

    api->ReleaseValue(contextValue);
    api->ReleaseValue(maskValue);
    api->ReleaseValue(speakerValue);
    if (output == NULL) return -1;

    int32_t count = 0;
    float *values = copyFloats(api, output, &count, errorMessage);
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

float *VieNeuORTRunVectorEstimator(VieNeuORT *context,
                                   const float *latent, int32_t latentChannels, int32_t frames,
                                   float time,
                                   const float *context_, int32_t length, int32_t dim,
                                   const uint8_t *mask,
                                   const float *speaker, int32_t speakerCount,
                                   const float *style, int32_t styleRows, int32_t styleColumns,
                                   int32_t *outCount, char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return NULL;
    }
    const OrtApi *api = context->api;
    const int64_t latentShape[3] = {1, latentChannels, frames};
    const int64_t timeShape[1] = {1};
    const int64_t contextShape[3] = {1, length, dim};
    const int64_t maskShape[2] = {1, length};
    const int64_t speakerShape[2] = {1, speakerCount};
    const int64_t styleShape[3] = {1, styleRows, styleColumns};

    OrtValue *latentValue = makeTensor(api, context->memoryInfo, latent,
                                       (size_t)(latentChannels * frames) * sizeof(float), latentShape, 3,
                                       ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    if (latentValue == NULL) return NULL;
    OrtValue *timeValue = makeTensor(api, context->memoryInfo, &time, sizeof(float), timeShape, 1,
                                     ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    OrtValue *contextValue = makeTensor(api, context->memoryInfo, context_,
                                        (size_t)(length * dim) * sizeof(float), contextShape, 3,
                                        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    OrtValue *maskValue = makeTensor(api, context->memoryInfo, mask,
                                     (size_t)length * sizeof(uint8_t), maskShape, 2,
                                     ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    OrtValue *speakerValue = makeTensor(api, context->memoryInfo, speaker,
                                        (size_t)speakerCount * sizeof(float), speakerShape, 2,
                                        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    OrtValue *styleValue = makeTensor(api, context->memoryInfo, style,
                                      (size_t)(styleRows * styleColumns) * sizeof(float), styleShape, 3,
                                      ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);

    OrtValue *values[6] = {latentValue, timeValue, contextValue, maskValue, speakerValue, styleValue};
    for (size_t index = 0; index < 6; index++) {
        if (values[index] == NULL) {
            for (size_t inner = 0; inner < 6; inner++) {
                if (values[inner] != NULL) api->ReleaseValue(values[inner]);
            }
            return NULL;
        }
    }

    const char *names[6] = {"x", "t", "ctx", "ctx_mask", "spk", "style"};
    const OrtValue *inputs[6] = {latentValue, timeValue, contextValue, maskValue, speakerValue, styleValue};
    OrtValue *output = runSession(api, context->vectorEstimator, names, inputs, 6, "out", errorMessage);

    for (size_t index = 0; index < 6; index++) api->ReleaseValue(values[index]);
    if (output == NULL) return NULL;

    float *result = copyFloats(api, output, outCount, errorMessage);
    api->ReleaseValue(output);
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
    OrtValue *output = runSession(api, context->codecDecoder, names, inputs, 1, "out", errorMessage);

    api->ReleaseValue(latentValue);
    if (output == NULL) return NULL;

    float *result = copyFloats(api, output, outCount, errorMessage);
    api->ReleaseValue(output);
    return result;
}
