//
//  ZeroTTSONNXBridge.m
//  FreeBook
//
//  Thi hành cầu nối khai ở `ZeroTTSONNXBridge.h` bằng **C API** của ONNX Runtime.
//
//  Bốn quy tắc của C API đã kiểm ở `VieNeuONNXBridge.m` và giữ nguyên ở đây:
//  - `ORT_API2_STATUS` **không** thêm `const OrtApi*` vào đầu hàm ⇒ gọi `api->TenHam(...)`.
//  - Các hàm `Release*` sinh bằng `ORT_CLASS_RELEASE` trả **`void`** ⇒ không đưa vào `check(...)`.
//  - `CreateTensorWithDataAsOrtValue` **không copy** ⇒ buffer của bên gọi phải sống tới hết lượt `Run`.
//  - Tên output **hỏi thẳng session** (`SessionGetOutputName`), không hardcode: bản tham chiếu đọc output
//    theo **vị trí** nên không xác nhận được tên, mà `OrtApi::Run` lại bắt buộc truyền tên.
//
//  Tên **input** thì hardcode — chúng là hợp đồng đã ghi ở `docs/RUNTIME.md` của upstream và bản port JS
//  cũng hardcode y hệt. Sai tên input thì `Run` báo "missing input" ngay, nên không có rủi ro im lặng.
//

#import "ZeroTTSONNXBridge.h"

#import <onnxruntime/onnxruntime_c_api.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/// Chỉ số bốn graph, dùng để tra `outputNames` — khớp thứ tự trong `ZeroTTSORTCreate`.
enum {
    ZeroTTSGraphTextEncoder = 0,
    ZeroTTSGraphPrefixStep = 1,
    ZeroTTSGraphLocalFrameDecode = 2,
    ZeroTTSGraphCodecDecodeFull = 3,
    ZeroTTSGraphCount = 4
};

/// Hạng tối đa của một tensor trong pipeline này. `cross_kv`/`packed_kv` là 6 chiều, nên để 8 cho dư.
#define ZeroTTSMaxTensorRank 8
/// Số output tối đa một graph khai. Nhiều nhất là `text_encoder` với 4.
#define ZeroTTSMaxOutputs 8
/// Số input tối đa của một lượt gọi. `prefix_step` là graph nhiều input nhất với 10.
#define ZeroTTSMaxInputs 12

struct ZeroTTSORT {
    const OrtApi *api;
    OrtEnv *env;
    OrtMemoryInfo *memoryInfo;
    OrtAllocator *allocator;
    int32_t threadCount;
    OrtSession *sessions[ZeroTTSGraphCount];
    /// Tên output của từng graph, **theo đúng thứ tự session khai** — vì vị trí mới là thứ hợp đồng
    /// upstream dùng, không phải tên.
    char *outputNames[ZeroTTSGraphCount][ZeroTTSMaxOutputs];
    size_t outputCounts[ZeroTTSGraphCount];

    // MARK: - Trạng thái KV của lượt sinh hiện tại
    //
    // `packed_kv` và `full_valid` phình thêm một mục mỗi frame. Cấp phát **một lần** cho cả utterance ở
    // `ZeroTTSORTBeginSequence` rồi ghi tại chỗ — cấp lại mỗi frame là chỗ đốt thời gian lớn nhất mà bản
    // port JS đã chỉ ra.
    float *packedKv;
    int32_t packedKvCapacityElements;
    /// `T_past` hiện tại của `packed_kv` (số vị trí đã có trong cache).
    int32_t packedKvLength;
    uint8_t *fullValid;
    int32_t fullValidCapacityElements;
    int32_t fullValidLength;
    /// Hình dạng KV: `(layers, 2, batch, heads, T, headDim)`.
    int32_t kvLayers;
    int32_t kvHeads;
    int32_t kvHeadDim;
    int32_t kvBatch;
    /// Số vị trí của khối giọng (`V`). Lưu lại vì `prefix_step` phải dựng `new_pos` theo nó, mà nó không
    /// suy được từ shape nào của graph (graph khai chiều `T` là động).
    int32_t kvVoiceCount;
    /// Trần số frame đã cấp — dùng để báo lỗi rõ khi vượt, thay vì ghi tràn.
    int32_t kvMaxFrames;
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

static OrtValue *makeTensor(const OrtApi *api,
                            OrtMemoryInfo *memoryInfo,
                            const void *data,
                            size_t byteCount,
                            const int64_t *shape,
                            size_t rank,
                            ONNXTensorElementDataType type,
                            char **errorMessage) {
    OrtValue *value = NULL;
    // `p_data` là `void*` không const; bỏ const ở đây an toàn vì ORT chỉ đọc dữ liệu này khi chạy.
    if (check(api->CreateTensorWithDataAsOrtValue(memoryInfo, (void *)data, byteCount,
                                                  shape, rank, type, &value),
              api, errorMessage) != 0) {
        return NULL;
    }
    return value;
}

/// Đọc shape + số phần tử của một `OrtValue`.
static int32_t readShape(const OrtApi *api, OrtValue *value,
                         int64_t *dimensions, int32_t *outRank, int64_t *outCount,
                         char **errorMessage) {
    OrtTensorTypeAndShapeInfo *info = NULL;
    if (check(api->GetTensorTypeAndShape(value, &info), api, errorMessage) != 0) return -1;

    size_t rank = 0;
    if (check(api->GetDimensionsCount(info, &rank), api, errorMessage) != 0) {
        api->ReleaseTensorTypeAndShapeInfo(info);
        return -1;
    }
    if (rank > ZeroTTSMaxTensorRank) rank = ZeroTTSMaxTensorRank;
    memset(dimensions, 0, sizeof(int64_t) * ZeroTTSMaxTensorRank);
    if (rank > 0 && check(api->GetDimensions(info, dimensions, rank), api, errorMessage) != 0) {
        api->ReleaseTensorTypeAndShapeInfo(info);
        return -1;
    }
    api->ReleaseTensorTypeAndShapeInfo(info);

    int64_t count = 1;
    for (size_t index = 0; index < rank; index++) {
        count *= (dimensions[index] > 0 ? dimensions[index] : 1);
    }
    if (outRank != NULL) *outRank = (int32_t)rank;
    if (outCount != NULL) *outCount = count;
    return 0;
}

/// Copy một output float32 vào buffer do bên gọi cấp, kèm shape thật (tuỳ chọn).
static int32_t copyFloatsInto(const OrtApi *api, OrtValue *value,
                              float *outBuffer, int32_t capacity, int32_t *outCount,
                              int64_t *outShape, int32_t shapeCapacity, int32_t *outRank,
                              char **errorMessage) {
    int64_t dimensions[ZeroTTSMaxTensorRank] = {0};
    int32_t rank = 0;
    int64_t count = 0;
    if (readShape(api, value, dimensions, &rank, &count, errorMessage) != 0) return -1;

    if (outRank != NULL) *outRank = rank;
    if (outShape != NULL) {
        int32_t copied = 0;
        for (int32_t index = 0; index < rank && copied < shapeCapacity; index++) {
            outShape[copied++] = dimensions[index];
        }
    }
    if (count > (int64_t)capacity) {
        setError(errorMessage, "buffer ra quá nhỏ cho output của graph");
        return -1;
    }

    void *raw = NULL;
    if (check(api->GetTensorMutableData(value, &raw), api, errorMessage) != 0) return -1;
    if (count > 0) memcpy(outBuffer, raw, (size_t)count * sizeof(float));
    if (outCount != NULL) *outCount = (int32_t)count;
    return 0;
}

/// Copy một output 1 byte/phần tử (bool) vào buffer do bên gọi cấp.
static int32_t copyBytesInto(const OrtApi *api, OrtValue *value,
                             uint8_t *outBuffer, int32_t capacity, int32_t *outCount,
                             char **errorMessage) {
    int64_t dimensions[ZeroTTSMaxTensorRank] = {0};
    int32_t rank = 0;
    int64_t count = 0;
    if (readShape(api, value, dimensions, &rank, &count, errorMessage) != 0) return -1;
    if (count > (int64_t)capacity) {
        setError(errorMessage, "buffer ra quá nhỏ cho tensor bool của graph");
        return -1;
    }
    void *raw = NULL;
    if (check(api->GetTensorMutableData(value, &raw), api, errorMessage) != 0) return -1;
    if (count > 0) memcpy(outBuffer, raw, (size_t)count);
    if (outCount != NULL) *outCount = (int32_t)count;
    return 0;
}

/// Copy một output int64 vào buffer do bên gọi cấp.
static int32_t copyInt64Into(const OrtApi *api, OrtValue *value,
                             int64_t *outBuffer, int32_t capacity, int32_t *outCount,
                             char **errorMessage) {
    int64_t dimensions[ZeroTTSMaxTensorRank] = {0};
    int32_t rank = 0;
    int64_t count = 0;
    if (readShape(api, value, dimensions, &rank, &count, errorMessage) != 0) return -1;
    if (count > (int64_t)capacity) {
        setError(errorMessage, "buffer ra quá nhỏ cho tensor int64 của graph");
        return -1;
    }
    void *raw = NULL;
    if (check(api->GetTensorMutableData(value, &raw), api, errorMessage) != 0) return -1;
    if (count > 0) memcpy(outBuffer, raw, (size_t)count * sizeof(int64_t));
    if (outCount != NULL) *outCount = (int32_t)count;
    return 0;
}

/// `hidden` là `(B, T, D)`; vòng lặp chỉ cần **vị trí cuối**. `prefix_step` trả cả khối nên phải cắt.
static int32_t copyLastPosition(const OrtApi *api, OrtValue *value,
                                float *outBuffer, int32_t batch, int32_t dModel,
                                char **errorMessage) {
    int64_t dimensions[ZeroTTSMaxTensorRank] = {0};
    int32_t rank = 0;
    int64_t count = 0;
    if (readShape(api, value, dimensions, &rank, &count, errorMessage) != 0) return -1;

    void *raw = NULL;
    if (check(api->GetTensorMutableData(value, &raw), api, errorMessage) != 0) return -1;

    if (rank == 2) {
        if (count > (int64_t)batch * (int64_t)dModel) {
            setError(errorMessage, "hidden trả về lớn hơn (batch, dModel)");
            return -1;
        }
        memcpy(outBuffer, raw, (size_t)count * sizeof(float));
        return 0;
    }
    if (rank != 3) {
        setError(errorMessage, "hidden phải có hạng 2 hoặc 3");
        return -1;
    }

    const int32_t length = (int32_t)dimensions[1];
    const int32_t width = (int32_t)dimensions[2];
    if (width != dModel || length <= 0) {
        setError(errorMessage, "hidden có chiều không khớp dModel");
        return -1;
    }
    const float *source = (const float *)raw;
    for (int32_t b = 0; b < batch; b++) {
        const float *row = source + ((size_t)b * (size_t)length + (size_t)(length - 1)) * (size_t)width;
        memcpy(outBuffer + (size_t)b * (size_t)dModel, row, (size_t)dModel * sizeof(float));
    }
    return 0;
}

/// Nạp một graph, đọc **tên output theo thứ tự khai** và lưu vào `context`.
static OrtSession *createSession(const OrtApi *api,
                                 const OrtEnv *env,
                                 const OrtSessionOptions *options,
                                 const char *directory,
                                 const char *name,
                                 int graphIndex,
                                 ZeroTTSORT *context,
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
    if (outputCount > ZeroTTSMaxOutputs) {
        setError(errorMessage, "graph khai nhiều output hơn dự kiến");
        api->ReleaseSession(session);
        return NULL;
    }
    for (size_t index = 0; index < outputCount; index++) {
        char *outputName = NULL;
        if (check(api->SessionGetOutputName(session, index, context->allocator, &outputName),
                  api, errorMessage) != 0) {
            for (size_t inner = 0; inner < index; inner++) {
                context->allocator->Free(context->allocator, context->outputNames[graphIndex][inner]);
                context->outputNames[graphIndex][inner] = NULL;
            }
            api->ReleaseSession(session);
            return NULL;
        }
        context->outputNames[graphIndex][index] = outputName;
    }
    context->outputCounts[graphIndex] = outputCount;
    return session;
}

/// Đọc shape khai của một input **theo tên**. Trả `0` khi tìm thấy.
///
/// Dùng để **hỏi model** thay vì suy shape từ `config.json` — bài học đã trả giá ở engine VieNeu
/// (`VieNeuONNXBridge.h:17-20`). Chiều nào model khai là động (`-1`) thì trả về `-1` và bên gọi phải tự
/// quyết.
static int32_t readInputShape(const OrtApi *api, OrtSession *session, OrtAllocator *allocator,
                              const char *wanted, int64_t *dimensions, int32_t *outRank,
                              char **errorMessage) {
    size_t inputCount = 0;
    if (check(api->SessionGetInputCount(session, &inputCount), api, errorMessage) != 0) return -1;

    for (size_t index = 0; index < inputCount; index++) {
        char *name = NULL;
        if (check(api->SessionGetInputName(session, index, allocator, &name), api, errorMessage) != 0) return -1;
        const int matches = (strcmp(name, wanted) == 0);
        allocator->Free(allocator, name);
        if (!matches) continue;

        OrtTypeInfo *typeInfo = NULL;
        if (check(api->SessionGetInputTypeInfo(session, index, &typeInfo), api, errorMessage) != 0) return -1;
        const OrtTensorTypeAndShapeInfo *shapeInfo = NULL;
        if (check(api->CastTypeInfoToTensorInfo(typeInfo, &shapeInfo), api, errorMessage) != 0) {
            api->ReleaseTypeInfo(typeInfo);
            setError(errorMessage, "input không phải tensor");
            return -1;
        }
        size_t rank = 0;
        if (check(api->GetDimensionsCount(shapeInfo, &rank), api, errorMessage) != 0) {
            api->ReleaseTypeInfo(typeInfo);
            return -1;
        }
        if (rank > ZeroTTSMaxTensorRank) rank = ZeroTTSMaxTensorRank;
        memset(dimensions, 0, sizeof(int64_t) * ZeroTTSMaxTensorRank);
        if (rank > 0 && check(api->GetDimensions(shapeInfo, dimensions, rank), api, errorMessage) != 0) {
            api->ReleaseTypeInfo(typeInfo);
            return -1;
        }
        api->ReleaseTypeInfo(typeInfo);
        if (outRank != NULL) *outRank = (int32_t)rank;
        return 0;
    }
    setError(errorMessage, "không tìm thấy input theo tên");
    return -1;
}

/// `Run` với **mọi** output của session, theo đúng thứ tự khai — vì hợp đồng upstream đọc theo vị trí.
static int32_t runAllOutputs(const OrtApi *api, ZeroTTSORT *context, int graphIndex,
                             const char *const *inputNames, const OrtValue *const *inputs, size_t inputCount,
                             OrtValue **outputs, char **errorMessage) {
    if (check(api->Run(context->sessions[graphIndex], NULL,
                       inputNames, inputs, inputCount,
                       (const char *const *)context->outputNames[graphIndex],
                       context->outputCounts[graphIndex], outputs),
              api, errorMessage) != 0) {
        return -1;
    }
    return 0;
}

static void releaseOutputs(const OrtApi *api, ZeroTTSORT *context, int graphIndex, OrtValue **outputs) {
    for (size_t index = 0; index < context->outputCounts[graphIndex]; index++) {
        if (outputs[index] != NULL) {
            api->ReleaseValue(outputs[index]);
            outputs[index] = NULL;
        }
    }
}

#pragma mark - Vòng đời

ZeroTTSORT *ZeroTTSORTCreate(const char *modelDirectory,
                             int32_t threadCount,
                             ZeroTTSORTShapes *outShapes,
                             char **errorMessage) {
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

    ZeroTTSORT *context = calloc(1, sizeof(ZeroTTSORT));
    if (context == NULL) {
        setError(errorMessage, "calloc failed");
        return NULL;
    }
    context->api = api;

    if (check(api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "FreeBookZeroTTS", &context->env),
              api, errorMessage) != 0) {
        ZeroTTSORTDestroy(context);
        return NULL;
    }
    if (check(api->CreateCpuMemoryInfo(OrtDeviceAllocator, OrtMemTypeDefault, &context->memoryInfo),
              api, errorMessage) != 0) {
        ZeroTTSORTDestroy(context);
        return NULL;
    }
    if (check(api->GetAllocatorWithDefaultOptions(&context->allocator), api, errorMessage) != 0) {
        ZeroTTSORTDestroy(context);
        return NULL;
    }

    OrtSessionOptions *options = NULL;
    if (check(api->CreateSessionOptions(&options), api, errorMessage) != 0) {
        ZeroTTSORTDestroy(context);
        return NULL;
    }
    check(api->SetIntraOpNumThreads(options, threadCount), api, errorMessage);
    check(api->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL), api, errorMessage);
    context->threadCount = threadCount;

    static const char *fileNames[ZeroTTSGraphCount] = {
        "text_encoder.onnx",
        "prefix_step.onnx",
        "local_frame_decode.onnx",
        "moss_audio_tokenizer_decode_full.onnx"
    };
    for (int index = 0; index < ZeroTTSGraphCount; index++) {
        context->sessions[index] =
            createSession(api, context->env, options, modelDirectory, fileNames[index], index, context, errorMessage);
    }
    api->ReleaseSessionOptions(options);

    for (int index = 0; index < ZeroTTSGraphCount; index++) {
        if (context->sessions[index] == NULL) {
            ZeroTTSORTDestroy(context);
            return NULL;
        }
    }

    if (outShapes != NULL) {
        memset(outShapes, 0, sizeof(ZeroTTSORTShapes));
        int64_t dimensions[ZeroTTSMaxTensorRank] = {0};
        int32_t rank = 0;
        // `seen_mask` khai `(1, K, C)` — hai chiều cuối là hằng số của model.
        if (readInputShape(api, context->sessions[ZeroTTSGraphLocalFrameDecode], context->allocator,
                           "seen_mask", dimensions, &rank, NULL) == 0 && rank == 3) {
            if (dimensions[1] > 0) outShapes->codebooks = (int32_t)dimensions[1];
            if (dimensions[2] > 0) outShapes->codebookSize = (int32_t)dimensions[2];
        }
        if (readInputShape(api, context->sessions[ZeroTTSGraphLocalFrameDecode], context->allocator,
                           "global_hidden", dimensions, &rank, NULL) == 0 && rank == 2) {
            if (dimensions[1] > 0) outShapes->dModel = (int32_t)dimensions[1];
        }
        // `packed_kv` khai `(layers, 2, B, heads, T, headDim)` — B và T là chiều động.
        if (readInputShape(api, context->sessions[ZeroTTSGraphPrefixStep], context->allocator,
                           "packed_kv", dimensions, &rank, NULL) == 0 && rank == 6) {
            if (dimensions[0] > 0) outShapes->layers = (int32_t)dimensions[0];
            if (dimensions[3] > 0) outShapes->heads = (int32_t)dimensions[3];
            if (dimensions[5] > 0) outShapes->headDim = (int32_t)dimensions[5];
        }
    }
    return context;
}

void ZeroTTSORTDestroy(ZeroTTSORT *context) {
    if (context == NULL) return;
    const OrtApi *api = context->api;
    if (api != NULL) {
        for (int index = 0; index < ZeroTTSGraphCount; index++) {
            if (context->sessions[index] != NULL) api->ReleaseSession(context->sessions[index]);
        }
        if (context->allocator != NULL) {
            for (int index = 0; index < ZeroTTSGraphCount; index++) {
                for (size_t slot = 0; slot < context->outputCounts[index]; slot++) {
                    if (context->outputNames[index][slot] != NULL) {
                        context->allocator->Free(context->allocator, context->outputNames[index][slot]);
                    }
                }
            }
        }
        if (context->memoryInfo != NULL) api->ReleaseMemoryInfo(context->memoryInfo);
        if (context->env != NULL) api->ReleaseEnv(context->env);
    }
    free(context->packedKv);
    free(context->fullValid);
    free(context);
}

void ZeroTTSORTFreeErrorMessage(char *errorMessage) {
    free(errorMessage);
}

#pragma mark - text_encoder

int32_t ZeroTTSORTRunTextEncoder(ZeroTTSORT *context,
                                 const int64_t *ids, int32_t batch, int32_t length,
                                 uint8_t *outTextValid,
                                 float *outSoaEmbed, int32_t soaCapacity,
                                 float *outCrossKv, int32_t crossKvCapacity, int32_t *outCrossKvCount,
                                 int64_t *outCrossKvShape, int32_t shapeCapacity, int32_t *outCrossKvRank,
                                 char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return -1;
    }
    if (batch <= 0 || length <= 0) {
        setError(errorMessage, "kích thước text_ids không hợp lệ");
        return -1;
    }
    const OrtApi *api = context->api;
    const int graph = ZeroTTSGraphTextEncoder;
    if (context->outputCounts[graph] < 4) {
        setError(errorMessage, "text_encoder phải trả 4 output (text_states, text_valid, soa_embed, cross_kv)");
        return -1;
    }

    // `txt_lengths` của upstream luôn bằng độ dài thật của từng hàng trong batch.
    int64_t *lengths = malloc((size_t)batch * sizeof(int64_t));
    if (lengths == NULL) {
        setError(errorMessage, "malloc failed");
        return -1;
    }
    for (int32_t index = 0; index < batch; index++) lengths[index] = length;

    const int64_t idsShape[2] = {batch, length};
    const int64_t lengthsShape[1] = {batch};

    OrtValue *idsValue = makeTensor(api, context->memoryInfo, ids,
                                    (size_t)batch * (size_t)length * sizeof(int64_t), idsShape, 2,
                                    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, errorMessage);
    OrtValue *lengthsValue = makeTensor(api, context->memoryInfo, lengths,
                                        (size_t)batch * sizeof(int64_t), lengthsShape, 1,
                                        ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, errorMessage);
    if (idsValue == NULL || lengthsValue == NULL) {
        if (idsValue != NULL) api->ReleaseValue(idsValue);
        if (lengthsValue != NULL) api->ReleaseValue(lengthsValue);
        free(lengths);
        return -1;
    }

    const char *names[2] = {"text_ids", "txt_lengths"};
    const OrtValue *inputs[2] = {idsValue, lengthsValue};
    OrtValue *outputs[ZeroTTSMaxOutputs] = {NULL};
    const int32_t status = runAllOutputs(api, context, graph, names, inputs, 2, outputs, errorMessage);

    api->ReleaseValue(idsValue);
    api->ReleaseValue(lengthsValue);
    free(lengths);
    if (status != 0) {
        releaseOutputs(api, context, graph, outputs);
        return -1;
    }

    int32_t result = 0;
    // Vị trí 0 là `text_states` — cố ý bỏ qua: graph bản này **không** đưa nó cho `prefix_step` nữa (nó
    // nhận `cross_kv` đã chiếu sẵn), nên `text_states` chỉ còn để soi.
    if (copyBytesInto(api, outputs[1], outTextValid, batch * length, NULL, errorMessage) != 0) result = -1;
    if (result == 0 && copyFloatsInto(api, outputs[2], outSoaEmbed, soaCapacity, NULL,
                                      NULL, 0, NULL, errorMessage) != 0) result = -1;
    if (result == 0 && copyFloatsInto(api, outputs[3], outCrossKv, crossKvCapacity, outCrossKvCount,
                                      outCrossKvShape, shapeCapacity, outCrossKvRank, errorMessage) != 0) result = -1;

    releaseOutputs(api, context, graph, outputs);
    return result;
}

#pragma mark - prefix_step

int32_t ZeroTTSORTBeginSequence(ZeroTTSORT *context,
                                int32_t batch, int32_t voiceCount, int32_t maxFrames,
                                int32_t layers, int32_t heads, int32_t headDim,
                                char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return -1;
    }
    if (batch <= 0 || voiceCount <= 0 || maxFrames <= 0 || layers <= 0 || heads <= 0 || headDim <= 0) {
        setError(errorMessage, "tham số cấp phát KV không hợp lệ");
        return -1;
    }
    const int64_t positions = (int64_t)voiceCount + 1 + maxFrames;
    const int64_t kvElements = (int64_t)layers * 2 * batch * heads * positions * headDim;
    const int64_t validElements = (int64_t)batch * positions;
    if (kvElements > (int64_t)INT32_MAX || validElements > (int64_t)INT32_MAX) {
        setError(errorMessage, "KV cache vượt quá 2^31 phần tử — giảm maxFrames");
        return -1;
    }

    float *newPackedKv = malloc((size_t)kvElements * sizeof(float));
    uint8_t *newFullValid = malloc((size_t)validElements);
    if (newPackedKv == NULL || newFullValid == NULL) {
        free(newPackedKv);
        free(newFullValid);
        setError(errorMessage, "malloc failed");
        return -1;
    }
    memset(newPackedKv, 0, (size_t)kvElements * sizeof(float));
    memset(newFullValid, 0, (size_t)validElements);

    free(context->packedKv);
    free(context->fullValid);
    context->packedKv = newPackedKv;
    context->fullValid = newFullValid;
    context->packedKvCapacityElements = (int32_t)kvElements;
    context->fullValidCapacityElements = (int32_t)validElements;
    context->packedKvLength = 0;
    context->fullValidLength = 0;
    context->kvLayers = layers;
    context->kvHeads = heads;
    context->kvHeadDim = headDim;
    context->kvBatch = batch;
    context->kvVoiceCount = voiceCount;
    context->kvMaxFrames = maxFrames;
    return 0;
}

/// Lấy `hidden` của vị trí cuối và ghi `packed_kv`/`full_valid` mới vào trạng thái ngữ cảnh.
///
/// Dùng chung cho cả cold start và frame step: hai lượt chỉ khác bộ input, còn phần đọc output thì y hệt.
static int32_t harvestPrefixOutputs(ZeroTTSORT *context, OrtValue **outputs,
                                    float *outHidden, int32_t dModel, int32_t expectedPositions,
                                    char **errorMessage) {
    const OrtApi *api = context->api;

    if (copyLastPosition(api, outputs[0], outHidden, context->kvBatch, dModel, errorMessage) != 0) {
        return -1;
    }

    // `packed_kv` mới: `(layers, 2, batch, heads, T_new, headDim)` — phải khớp đúng hình dạng đã cấp.
    int64_t dimensions[ZeroTTSMaxTensorRank] = {0};
    int32_t rank = 0;
    int64_t count = 0;
    if (readShape(api, outputs[1], dimensions, &rank, &count, errorMessage) != 0) return -1;
    if (rank != 6) {
        setError(errorMessage, "packed_kv trả về không phải hạng 6");
        return -1;
    }
    if (dimensions[0] != context->kvLayers || dimensions[1] != 2
        || dimensions[2] != context->kvBatch || dimensions[3] != context->kvHeads
        || dimensions[5] != context->kvHeadDim) {
        setError(errorMessage, "packed_kv trả về lệch hình dạng đã cấp");
        return -1;
    }
    if (dimensions[4] != expectedPositions) {
        setError(errorMessage, "packed_kv trả về số vị trí khác dự kiến");
        return -1;
    }
    if (count > (int64_t)context->packedKvCapacityElements) {
        setError(errorMessage, "packed_kv vượt sức chứa đã cấp — tăng maxFrames");
        return -1;
    }
    void *kvRaw = NULL;
    if (check(api->GetTensorMutableData(outputs[1], &kvRaw), api, errorMessage) != 0) return -1;
    memcpy(context->packedKv, kvRaw, (size_t)count * sizeof(float));
    context->packedKvLength = (int32_t)dimensions[4];

    // `full_valid`: `(batch, T_new)` bool.
    int32_t validCount = 0;
    if (copyBytesInto(api, outputs[2], context->fullValid, context->fullValidCapacityElements,
                      &validCount, errorMessage) != 0) {
        return -1;
    }
    if (validCount != expectedPositions * context->kvBatch) {
        setError(errorMessage, "full_valid trả về số phần tử khác dự kiến");
        return -1;
    }
    context->fullValidLength = validCount;
    return 0;
}

int32_t ZeroTTSORTRunPrefixInit(ZeroTTSORT *context,
                                const float *externalEmbed,
                                const float *soaEmbed,
                                const float *crossKv, int32_t crossKvCount,
                                const int64_t *crossKvShape, int32_t crossKvRank,
                                const uint8_t *textValid, int32_t textValidCount,
                                float *outHidden,
                                char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return -1;
    }
    if (context->packedKv == NULL) {
        setError(errorMessage, "chưa gọi ZeroTTSORTBeginSequence");
        return -1;
    }
    if (crossKvShape == NULL || crossKvRank != 6) {
        setError(errorMessage, "cross_kv phải có hạng 6");
        return -1;
    }
    const OrtApi *api = context->api;
    const int graph = ZeroTTSGraphPrefixStep;
    if (context->outputCounts[graph] < 3) {
        setError(errorMessage, "prefix_step phải trả 3 output (hidden, packed_kv, full_valid)");
        return -1;
    }

    const int32_t batch = context->kvBatch;
    const int32_t voiceCount = context->kvVoiceCount;
    // `L` và `dModel` đọc từ chính shape của cross_kv: `(layers, 2, batch, heads, L, headDim)`.
    const int32_t textLength = (int32_t)crossKvShape[4];
    const int32_t dModel = (int32_t)crossKvShape[3] * (int32_t)crossKvShape[5];
    if (textLength <= 0 || dModel <= 0) {
        setError(errorMessage, "cross_kv có chiều không hợp lệ");
        return -1;
    }
    if (textValidCount != batch * textLength) {
        setError(errorMessage, "text_valid không khớp (batch, L) của cross_kv");
        return -1;
    }

    const int32_t positions = voiceCount + 1;
    const int64_t externalShape[3] = {batch, positions, dModel};
    const int64_t positionShape[2] = {batch, positions};
    const int64_t frameCodeShape[3] = {batch, positions, 1};
    const int64_t emptyKvShape[6] = {context->kvLayers, 2, batch, context->kvHeads, 0, context->kvHeadDim};
    const int64_t emptyValidShape[2] = {batch, 0};
    const int64_t textValidShape[2] = {batch, textLength};

    // `frame_codes` của cold start là **toàn 0** (đúng upstream), nên cấp một mảng 0 đúng kích thước.
    const int32_t codeCount = batch * positions;
    int64_t *frameCodes = calloc((size_t)codeCount, sizeof(int64_t));
    int64_t *positions64 = malloc((size_t)(batch * positions) * sizeof(int64_t));
    uint8_t *useExternal = malloc((size_t)(batch * positions));
    uint8_t *newValid = malloc((size_t)(batch * positions));
    uint8_t *bidirectional = malloc((size_t)(batch * positions));
    if (frameCodes == NULL || positions64 == NULL || useExternal == NULL
        || newValid == NULL || bidirectional == NULL) {
        free(frameCodes); free(positions64); free(useExternal); free(newValid); free(bidirectional);
        setError(errorMessage, "malloc failed");
        return -1;
    }
    memset(useExternal, 1, (size_t)(batch * positions));
    memset(newValid, 1, (size_t)(batch * positions));
    memset(bidirectional, 0, (size_t)(batch * positions));
    for (int32_t b = 0; b < batch; b++) {
        for (int32_t t = 0; t < positions; t++) {
            const int32_t offset = b * positions + t;
            positions64[offset] = t;
            // Khối giọng đọc **hai chiều**; `<soa>` ở cuối khối là mốc chuyển sang một chiều.
            if (t < voiceCount) bidirectional[offset] = 1;
        }
    }

    OrtValue *values[ZeroTTSMaxInputs] = {NULL};
    values[0] = makeTensor(api, context->memoryInfo, externalEmbed,
                           (size_t)(batch * positions * dModel) * sizeof(float), externalShape, 3,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    values[1] = makeTensor(api, context->memoryInfo, useExternal,
                           (size_t)(batch * positions), positionShape, 2,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    values[2] = makeTensor(api, context->memoryInfo, frameCodes,
                           (size_t)codeCount * sizeof(int64_t), frameCodeShape, 3,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, errorMessage);
    values[3] = makeTensor(api, context->memoryInfo, positions64,
                           (size_t)(batch * positions) * sizeof(int64_t), positionShape, 2,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, errorMessage);
    values[4] = makeTensor(api, context->memoryInfo, newValid,
                           (size_t)(batch * positions), positionShape, 2,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    // KV rỗng: con trỏ vẫn phải hợp lệ dù độ dài 0 (`CreateTensorWithDataAsOrtValue` từ chối `NULL`).
    values[5] = makeTensor(api, context->memoryInfo, context->packedKv, 0, emptyKvShape, 6,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    values[6] = makeTensor(api, context->memoryInfo, bidirectional,
                           (size_t)(batch * positions), positionShape, 2,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    values[7] = makeTensor(api, context->memoryInfo, context->fullValid, 0, emptyValidShape, 2,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    values[8] = makeTensor(api, context->memoryInfo, crossKv,
                           (size_t)crossKvCount * sizeof(float), crossKvShape, (size_t)crossKvRank,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    values[9] = makeTensor(api, context->memoryInfo, textValid,
                           (size_t)textValidCount, textValidShape, 2,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    for (size_t index = 0; index < 10; index++) {
        if (values[index] != NULL) continue;
        for (size_t inner = 0; inner < 10; inner++) {
            if (values[inner] != NULL) api->ReleaseValue(values[inner]);
        }
        free(frameCodes); free(positions64); free(useExternal); free(newValid); free(bidirectional);
        return -1;
    }

    const char *names[10] = {
        "external_embed", "use_external_embed", "frame_codes", "new_pos", "new_valid",
        "packed_kv", "new_bidirectional", "past_valid", "cross_kv", "text_valid"
    };
    const OrtValue *inputs[10] = {
        values[0], values[1], values[2], values[3], values[4],
        values[5], values[6], values[7], values[8], values[9]
    };
    OrtValue *outputs[ZeroTTSMaxOutputs] = {NULL};
    const int32_t status = runAllOutputs(api, context, graph, names, inputs, 10, outputs, errorMessage);

    for (size_t index = 0; index < 10; index++) api->ReleaseValue(values[index]);
    free(frameCodes); free(positions64); free(useExternal); free(newValid); free(bidirectional);
    if (status != 0) {
        releaseOutputs(api, context, graph, outputs);
        return -1;
    }

    const int32_t result = harvestPrefixOutputs(context, outputs, outHidden, dModel, positions, errorMessage);
    releaseOutputs(api, context, graph, outputs);
    return result;
}

int32_t ZeroTTSORTRunPrefixFrame(ZeroTTSORT *context,
                                 const int64_t *frameCodes,
                                 int32_t frameIndex, int32_t voiceCount,
                                 const float *crossKv, int32_t crossKvCount,
                                 const int64_t *crossKvShape, int32_t crossKvRank,
                                 const uint8_t *textValid, int32_t textValidCount,
                                 float *outHidden,
                                 char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return -1;
    }
    if (context->packedKv == NULL || context->packedKvLength <= 0) {
        setError(errorMessage, "chưa chạy ZeroTTSORTRunPrefixInit");
        return -1;
    }
    if (crossKvShape == NULL || crossKvRank != 6) {
        setError(errorMessage, "cross_kv phải có hạng 6");
        return -1;
    }
    const OrtApi *api = context->api;
    const int graph = ZeroTTSGraphPrefixStep;

    const int32_t batch = context->kvBatch;
    const int32_t textLength = (int32_t)crossKvShape[4];
    const int32_t dModel = (int32_t)crossKvShape[3] * (int32_t)crossKvShape[5];
    const int32_t positions = context->packedKvLength;
    if (textValidCount != batch * textLength) {
        setError(errorMessage, "text_valid không khớp (batch, L) của cross_kv");
        return -1;
    }
    if (positions + 1 > context->kvVoiceCount + 1 + context->kvMaxFrames) {
        setError(errorMessage, "vượt trần maxFrames đã cấp cho KV");
        return -1;
    }

    const int64_t externalShape[3] = {batch, 1, dModel};
    const int64_t singleShape[2] = {batch, 1};
    const int64_t frameCodeShape[3] = {batch, 1, 1};
    const int64_t kvShape[6] = {context->kvLayers, 2, batch, context->kvHeads, positions, context->kvHeadDim};
    const int64_t pastValidShape[2] = {batch, positions};
    const int64_t textValidShape[2] = {batch, textLength};

    // `external_embed` của frame step là **toàn 0** và `use_external_embed` toàn `false`.
    const int64_t kvElementCount = (int64_t)context->kvLayers * 2 * batch
        * context->kvHeads * positions * context->kvHeadDim;
    float *external = calloc((size_t)(batch * dModel), sizeof(float));
    int64_t *positions64 = malloc((size_t)batch * sizeof(int64_t));
    uint8_t *useExternal = calloc((size_t)batch, 1);
    uint8_t *newValid = malloc((size_t)batch);
    uint8_t *bidirectional = calloc((size_t)batch, 1);
    if (external == NULL || positions64 == NULL || useExternal == NULL
        || newValid == NULL || bidirectional == NULL) {
        free(external); free(positions64); free(useExternal); free(newValid); free(bidirectional);
        setError(errorMessage, "malloc failed");
        return -1;
    }
    memset(newValid, 1, (size_t)batch);
    for (int32_t b = 0; b < batch; b++) {
        // Vị trí: khối giọng giữ `0 … voiceCount-1`, `<soa>` ở `voiceCount`, frame `t` ở `voiceCount+1+t`.
        positions64[b] = (int64_t)voiceCount + 1 + frameIndex;
    }

    OrtValue *values[ZeroTTSMaxInputs] = {NULL};
    values[0] = makeTensor(api, context->memoryInfo, external,
                           (size_t)(batch * dModel) * sizeof(float), externalShape, 3,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    values[1] = makeTensor(api, context->memoryInfo, useExternal, (size_t)batch, singleShape, 2,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    values[2] = makeTensor(api, context->memoryInfo, frameCodes,
                           (size_t)batch * sizeof(int64_t), frameCodeShape, 3,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, errorMessage);
    values[3] = makeTensor(api, context->memoryInfo, positions64,
                           (size_t)batch * sizeof(int64_t), singleShape, 2,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, errorMessage);
    values[4] = makeTensor(api, context->memoryInfo, newValid, (size_t)batch, singleShape, 2,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    values[5] = makeTensor(api, context->memoryInfo, context->packedKv,
                           (size_t)kvElementCount * sizeof(float), kvShape, 6,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    values[6] = makeTensor(api, context->memoryInfo, bidirectional, (size_t)batch, singleShape, 2,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    values[7] = makeTensor(api, context->memoryInfo, context->fullValid,
                           (size_t)(batch * positions), pastValidShape, 2,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    values[8] = makeTensor(api, context->memoryInfo, crossKv,
                           (size_t)crossKvCount * sizeof(float), crossKvShape, (size_t)crossKvRank,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    values[9] = makeTensor(api, context->memoryInfo, textValid, (size_t)textValidCount, textValidShape, 2,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    for (size_t index = 0; index < 10; index++) {
        if (values[index] != NULL) continue;
        for (size_t inner = 0; inner < 10; inner++) {
            if (values[inner] != NULL) api->ReleaseValue(values[inner]);
        }
        free(external); free(positions64); free(useExternal); free(newValid); free(bidirectional);
        return -1;
    }

    const char *names[10] = {
        "external_embed", "use_external_embed", "frame_codes", "new_pos", "new_valid",
        "packed_kv", "new_bidirectional", "past_valid", "cross_kv", "text_valid"
    };
    const OrtValue *inputs[10] = {
        values[0], values[1], values[2], values[3], values[4],
        values[5], values[6], values[7], values[8], values[9]
    };
    OrtValue *outputs[ZeroTTSMaxOutputs] = {NULL};
    const int32_t status = runAllOutputs(api, context, graph, names, inputs, 10, outputs, errorMessage);

    for (size_t index = 0; index < 10; index++) api->ReleaseValue(values[index]);
    free(external); free(positions64); free(useExternal); free(newValid); free(bidirectional);
    if (status != 0) {
        releaseOutputs(api, context, graph, outputs);
        return -1;
    }

    const int32_t result = harvestPrefixOutputs(context, outputs, outHidden, dModel, positions + 1, errorMessage);
    releaseOutputs(api, context, graph, outputs);
    return result;
}

#pragma mark - local_frame_decode

int32_t ZeroTTSORTRunLocalFrameDecode(ZeroTTSORT *context,
                                      const float *hidden, int32_t batch, int32_t dModel,
                                      int32_t forbidEoa,
                                      float textTemperature, int64_t textTopK,
                                      float audioTemperature, int64_t audioTopK,
                                      float audioTopp, float audioRepetitionPenalty, float cfgScale,
                                      uint8_t *seenMask, int32_t seenMaskCount,
                                      const float *ctrlRandomU,
                                      const float *audioRandomU, int32_t audioRandomCount,
                                      uint8_t *outIsEoa,
                                      int64_t *outCodes, int32_t codesCapacity, int32_t *outCodesCount,
                                      char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return -1;
    }
    const OrtApi *api = context->api;
    const int graph = ZeroTTSGraphLocalFrameDecode;
    if (context->outputCounts[graph] < 2) {
        setError(errorMessage, "local_frame_decode phải trả 2 output (is_eoa, codes)");
        return -1;
    }

    // Số codebook lấy từ chính `audio_random_u` (`(1, K)`), rồi suy codebook size từ kích thước
    // `seen_mask` — nhờ vậy hàm này không cần bên gọi truyền K/C riêng.
    const int32_t codebooks = audioRandomCount;
    const int32_t codebookSize = codebooks > 0 ? seenMaskCount / codebooks : 0;
    if (codebooks <= 0 || codebookSize <= 0 || codebooks * codebookSize != seenMaskCount) {
        setError(errorMessage, "kích thước seen_mask không khớp số codebook");
        return -1;
    }

    const int64_t hiddenShape[2] = {batch, dModel};
    const int64_t singleShape[1] = {1};
    const int64_t randomShape[2] = {1, audioRandomCount};
    const int64_t seenShape[3] = {1, codebooks, codebookSize};

    const uint8_t forbid = forbidEoa ? 1 : 0;
    const int64_t textTopkValue = textTopK;
    const int64_t audioTopkValue = audioTopK;

    OrtValue *values[ZeroTTSMaxInputs] = {NULL};
    values[0] = makeTensor(api, context->memoryInfo, hidden,
                           (size_t)(batch * dModel) * sizeof(float), hiddenShape, 2,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    values[1] = makeTensor(api, context->memoryInfo, &forbid, sizeof(uint8_t), singleShape, 1,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    values[2] = makeTensor(api, context->memoryInfo, &textTemperature, sizeof(float), singleShape, 1,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    values[3] = makeTensor(api, context->memoryInfo, &textTopkValue, sizeof(int64_t), singleShape, 1,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, errorMessage);
    values[4] = makeTensor(api, context->memoryInfo, &audioTemperature, sizeof(float), singleShape, 1,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    values[5] = makeTensor(api, context->memoryInfo, &audioTopkValue, sizeof(int64_t), singleShape, 1,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, errorMessage);
    values[6] = makeTensor(api, context->memoryInfo, &audioTopp, sizeof(float), singleShape, 1,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    values[7] = makeTensor(api, context->memoryInfo, &audioRepetitionPenalty, sizeof(float), singleShape, 1,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    values[8] = makeTensor(api, context->memoryInfo, seenMask, (size_t)seenMaskCount, seenShape, 3,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL, errorMessage);
    values[9] = makeTensor(api, context->memoryInfo, ctrlRandomU, sizeof(float), singleShape, 1,
                           ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    values[10] = makeTensor(api, context->memoryInfo, audioRandomU,
                            (size_t)audioRandomCount * sizeof(float), randomShape, 2,
                            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    values[11] = makeTensor(api, context->memoryInfo, &cfgScale, sizeof(float), singleShape, 1,
                            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, errorMessage);
    for (size_t index = 0; index < 12; index++) {
        if (values[index] != NULL) continue;
        for (size_t inner = 0; inner < 12; inner++) {
            if (values[inner] != NULL) api->ReleaseValue(values[inner]);
        }
        return -1;
    }

    const char *names[12] = {
        "global_hidden", "forbid_eoa", "text_temperature", "text_topk",
        "audio_temperature", "audio_topk", "audio_topp", "audio_repetition_penalty",
        "seen_mask", "ctrl_random_u", "audio_random_u", "cfg_scale"
    };
    const OrtValue *inputs[12] = {
        values[0], values[1], values[2], values[3], values[4], values[5],
        values[6], values[7], values[8], values[9], values[10], values[11]
    };
    OrtValue *outputs[ZeroTTSMaxOutputs] = {NULL};
    const int32_t status = runAllOutputs(api, context, graph, names, inputs, 12, outputs, errorMessage);

    for (size_t index = 0; index < 12; index++) api->ReleaseValue(values[index]);
    if (status != 0) {
        releaseOutputs(api, context, graph, outputs);
        return -1;
    }

    int32_t result = 0;
    int32_t codeCount = 0;
    if (copyBytesInto(api, outputs[0], outIsEoa, 1, NULL, errorMessage) != 0) result = -1;
    if (result == 0 && copyInt64Into(api, outputs[1], outCodes, codesCapacity, &codeCount, errorMessage) != 0) result = -1;
    releaseOutputs(api, context, graph, outputs);
    if (result != 0) return -1;

    // Lịch sử phạt lặp: graph không mang được state dài biến thiên, nên bên gọi phải tự đánh dấu — và phải
    // làm **sau** `Run`. Bản tham chiếu cũng vậy (`seenMask[c * C + codes[c]] = 1`).
    for (int32_t c = 0; c < codeCount && c < codebooks; c++) {
        const int64_t code = outCodes[c];
        if (code < 0 || code >= codebookSize) continue;
        seenMask[(size_t)c * (size_t)codebookSize + (size_t)code] = 1;
    }
    if (outCodesCount != NULL) *outCodesCount = codeCount;
    return 0;
}

#pragma mark - codec

int32_t ZeroTTSORTRunCodecDecodeFull(ZeroTTSORT *context,
                                     const int32_t *codesKT, int32_t codebooks, int32_t frames,
                                     float *outPcm, int32_t pcmCapacity, int32_t *outPcmCount,
                                     char **errorMessage) {
    if (context == NULL) {
        setError(errorMessage, "context is NULL");
        return -1;
    }
    if (codebooks <= 0 || frames <= 0) {
        setError(errorMessage, "kích thước codes không hợp lệ");
        return -1;
    }
    const OrtApi *api = context->api;
    const int graph = ZeroTTSGraphCodecDecodeFull;

    // Bố cục vòng sinh là `(K, T)`; graph codec đòi `(1, T, K)` ⇒ chuyển vị ở đây.
    int32_t *transposed = malloc((size_t)codebooks * (size_t)frames * sizeof(int32_t));
    if (transposed == NULL) {
        setError(errorMessage, "malloc failed");
        return -1;
    }
    for (int32_t k = 0; k < codebooks; k++) {
        for (int32_t t = 0; t < frames; t++) {
            transposed[(size_t)t * (size_t)codebooks + (size_t)k] = codesKT[(size_t)k * (size_t)frames + (size_t)t];
        }
    }
    const int32_t lengthValue = frames;
    const int64_t codesShape[3] = {1, frames, codebooks};
    const int64_t lengthShape[1] = {1};

    OrtValue *codesValue = makeTensor(api, context->memoryInfo, transposed,
                                      (size_t)codebooks * (size_t)frames * sizeof(int32_t), codesShape, 3,
                                      ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32, errorMessage);
    OrtValue *lengthValueTensor = makeTensor(api, context->memoryInfo, &lengthValue, sizeof(int32_t), lengthShape, 1,
                                             ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32, errorMessage);
    if (codesValue == NULL || lengthValueTensor == NULL) {
        if (codesValue != NULL) api->ReleaseValue(codesValue);
        if (lengthValueTensor != NULL) api->ReleaseValue(lengthValueTensor);
        free(transposed);
        return -1;
    }

    const char *names[2] = {"audio_codes", "audio_code_lengths"};
    const OrtValue *inputs[2] = {codesValue, lengthValueTensor};
    OrtValue *outputs[ZeroTTSMaxOutputs] = {NULL};
    const int32_t status = runAllOutputs(api, context, graph, names, inputs, 2, outputs, errorMessage);

    api->ReleaseValue(codesValue);
    api->ReleaseValue(lengthValueTensor);
    free(transposed);
    if (status != 0) {
        releaseOutputs(api, context, graph, outputs);
        return -1;
    }

    // Đọc output **theo hình dạng** chứ không theo tên: `audio` là hạng 3 `(1, channels, T_audio)`, còn
    // `audio_lengths` là hạng 1. Tên output khác nhau giữa các bản export nên tra theo tên là đoán.
    int foundAudio = -1;
    int foundLengths = -1;
    int64_t audioShape[ZeroTTSMaxTensorRank] = {0};
    for (size_t index = 0; index < context->outputCounts[graph]; index++) {
        int64_t dimensions[ZeroTTSMaxTensorRank] = {0};
        int32_t rank = 0;
        int64_t count = 0;
        if (readShape(api, outputs[index], dimensions, &rank, &count, errorMessage) != 0) {
            releaseOutputs(api, context, graph, outputs);
            return -1;
        }
        if (rank == 3 && foundAudio < 0) {
            foundAudio = (int)index;
            memcpy(audioShape, dimensions, sizeof(dimensions));
        } else if (rank == 1 && foundLengths < 0) {
            foundLengths = (int)index;
        }
    }
    if (foundAudio < 0 || foundLengths < 0) {
        setError(errorMessage, "codec không trả về cặp (audio, audio_lengths) như hợp đồng");
        releaseOutputs(api, context, graph, outputs);
        return -1;
    }

    int32_t sampleCount = 0;
    {
        void *raw = NULL;
        if (check(api->GetTensorMutableData(outputs[foundLengths], &raw), api, errorMessage) != 0) {
            releaseOutputs(api, context, graph, outputs);
            return -1;
        }
        sampleCount = *(const int32_t *)raw;
    }
    const int32_t channels = (int32_t)audioShape[1];
    const int32_t audioFrames = (int32_t)audioShape[2];
    if (sampleCount <= 0 || channels <= 0 || audioFrames <= 0 || sampleCount > audioFrames) {
        setError(errorMessage, "codec trả về độ dài audio không hợp lệ");
        releaseOutputs(api, context, graph, outputs);
        return -1;
    }
    if (sampleCount > pcmCapacity) {
        setError(errorMessage, "buffer PCM quá nhỏ cho output của codec");
        releaseOutputs(api, context, graph, outputs);
        return -1;
    }

    void *audioRaw = NULL;
    if (check(api->GetTensorMutableData(outputs[foundAudio], &audioRaw), api, errorMessage) != 0) {
        releaseOutputs(api, context, graph, outputs);
        return -1;
    }
    // `(1, channels, T_audio)` → mono bằng trung bình kênh, đúng `toMono` của bản port JS.
    const float *audio = (const float *)audioRaw;
    for (int32_t t = 0; t < sampleCount; t++) {
        float sum = 0;
        for (int32_t c = 0; c < channels; c++) {
            sum += audio[(size_t)c * (size_t)audioFrames + (size_t)t];
        }
        outPcm[t] = sum / (float)channels;
    }
    if (outPcmCount != NULL) *outPcmCount = sampleCount;

    releaseOutputs(api, context, graph, outputs);
    return 0;
}
