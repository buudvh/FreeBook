//
//  VieNeuONNXProbeBridge.m
//  Tàng Công Các
//
//  Hiện thực `VieNeuONNXProbeBridge.h` — xem doc ở header. Chỉ dùng cho phép thử P1 ở màn thử VieNeu Turbo.
//

#import "VieNeuONNXProbeBridge.h"

#import <onnxruntime/onnxruntime_c_api.h>

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

/// Một file trọng số đã `mmap` (chỉ đọc) — sống tới khi tạo session xong.
typedef struct {
    void *base;
    size_t length;
} ProbeMappedFile;

static void probeUnmapAll(ProbeMappedFile *files, int32_t count) {
    if (files == NULL) return;
    for (int32_t index = 0; index < count; index++) {
        if (files[index].base != NULL && files[index].base != MAP_FAILED) munmap(files[index].base, files[index].length);
    }
    free(files);
}

struct VieNeuORTProbeSession {
    const OrtApi *api;
    OrtEnv *env;
    OrtMemoryInfo *memoryInfo;
    OrtSession *session;
    int32_t inputCount;
    int32_t outputCount;
    char **inputNames;
    char **outputNames;
};

static void probeSetError(char **out, const char *message) {
    if (out == NULL) return;
    *out = strdup(message != NULL ? message : "ONNX Runtime: lỗi không rõ");
}

/// `status` khác NULL ⇒ ghi lỗi, giải phóng status, trả 1.
static int probeFailed(const OrtApi *api, OrtStatus *status, char **errorMessage) {
    if (status == NULL) return 0;
    probeSetError(errorMessage, api->GetErrorMessage(status));
    api->ReleaseStatus(status);
    return 1;
}

static char **probeCopyNames(const OrtApi *api, OrtSession *session, int input, int32_t *outCount,
                             char **errorMessage) {
    size_t count = 0;
    OrtStatus *status = input ? api->SessionGetInputCount(session, &count) : api->SessionGetOutputCount(session, &count);
    if (probeFailed(api, status, errorMessage)) return NULL;
    OrtAllocator *allocator = NULL;
    if (probeFailed(api, api->GetAllocatorWithDefaultOptions(&allocator), errorMessage)) return NULL;
    char **names = calloc(count > 0 ? count : 1, sizeof(char *));
    if (names == NULL) {
        probeSetError(errorMessage, "calloc thất bại");
        return NULL;
    }
    for (size_t index = 0; index < count; index++) {
        char *name = NULL;
        status = input ? api->SessionGetInputName(session, index, allocator, &name)
                       : api->SessionGetOutputName(session, index, allocator, &name);
        if (probeFailed(api, status, errorMessage)) {
            for (size_t inner = 0; inner < index; inner++) free(names[inner]);
            free(names);
            return NULL;
        }
        names[index] = strdup(name);
        api->AllocatorFree(allocator, name);
    }
    *outCount = (int32_t)count;
    return names;
}

VieNeuORTProbeSession *VieNeuORTProbeCreate(const char *modelPath,
                                            const char *provider,
                                            const char *const *keys,
                                            const char *const *values,
                                            int32_t optionCount,
                                            int32_t threads,
                                            const char *logPath,
                                            const char *const *weightNames,
                                            const char *const *weightPaths,
                                            int32_t weightCount,
                                            char **errorMessage) {
    const OrtApiBase *base = OrtGetApiBase();
    const OrtApi *api = base != NULL ? base->GetApi(ORT_API_VERSION) : NULL;
    if (api == NULL || modelPath == NULL) {
        probeSetError(errorMessage, "không lấy được OrtApi hoặc thiếu đường dẫn model");
        return NULL;
    }
    VieNeuORTProbeSession *probe = calloc(1, sizeof(VieNeuORTProbeSession));
    if (probe == NULL) {
        probeSetError(errorMessage, "calloc thất bại");
        return NULL;
    }
    probe->api = api;
    // `CreateEnv` trả lại môi trường dùng chung của tiến trình nếu đã có (engine Nano / Piper tạo trước).
    if (probeFailed(api, api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "TangCongCacVieNeuProbe", &probe->env), errorMessage)
        || probeFailed(api, api->CreateCpuMemoryInfo(OrtDeviceAllocator, OrtMemTypeDefault, &probe->memoryInfo),
                       errorMessage)) {
        VieNeuORTProbeDestroy(probe);
        return NULL;
    }

    OrtSessionOptions *options = NULL;
    if (probeFailed(api, api->CreateSessionOptions(&options), errorMessage)) {
        VieNeuORTProbeDestroy(probe);
        return NULL;
    }
    int captureLog = logPath != NULL && logPath[0] != '\0';
    // Khoá riêng của app `fb.graph_optimization` (P2b-0) — bóc ra, không đưa cho EP (EP gặp khoá lạ là báo lỗi).
    // "disable" ⇒ ORT_DISABLE_ALL: không chạy `MatMulAddFusion` (mức 1, mọi EP) ⇒ Core ML EP không chuyển vị trọng số
    // Linear thành hằng nằm trong chương trình `model.mil`, trọng số vào `weight.bin`.
    GraphOptimizationLevel optimization = ORT_ENABLE_ALL;
    int32_t providerCount = 0;
    const char **providerKeys = calloc((size_t)(optionCount > 0 ? optionCount : 1), sizeof(char *));
    const char **providerValues = calloc((size_t)(optionCount > 0 ? optionCount : 1), sizeof(char *));
    if (providerKeys == NULL || providerValues == NULL) {
        free(providerKeys);
        free(providerValues);
        api->ReleaseSessionOptions(options);
        probeSetError(errorMessage, "calloc thất bại");
        VieNeuORTProbeDestroy(probe);
        return NULL;
    }
    for (int32_t index = 0; index < optionCount; index++) {
        if (keys[index] != NULL && strcmp(keys[index], "fb.graph_optimization") == 0) {
            const char *value = values[index] != NULL ? values[index] : "";
            if (strcmp(value, "disable") == 0) optimization = ORT_DISABLE_ALL;
            else if (strcmp(value, "basic") == 0) optimization = ORT_ENABLE_BASIC;
            else if (strcmp(value, "extended") == 0) optimization = ORT_ENABLE_EXTENDED;
            continue;
        }
        providerKeys[providerCount] = keys[index];
        providerValues[providerCount] = values[index];
        providerCount++;
    }
    OrtStatus *status = api->SetIntraOpNumThreads(options, threads > 0 ? threads : 1);
    if (status == NULL) status = api->AddSessionConfigEntry(options, "session.intra_op.allow_spinning", "0");
    if (status == NULL) status = api->SetSessionGraphOptimizationLevel(options, optimization);
    if (status == NULL && captureLog) status = api->SetSessionLogSeverityLevel(options, ORT_LOGGING_LEVEL_INFO);
    if (status == NULL && provider != NULL && strcmp(provider, "CPU") != 0) {
        status = api->SessionOptionsAppendExecutionProvider(options, provider, providerKeys, providerValues,
                                                            (size_t)providerCount);
    }
    free(providerKeys);
    free(providerValues);
    // Trọng số external data nạp từ bộ nhớ (P1b): mmap từng file, đưa con trỏ cho ORT; ORT chép vào graph trong
    // `CreateSession` nên gỡ map ngay sau đó.
    ProbeMappedFile *mapped = NULL;
    if (status == NULL && weightCount > 0) {
        mapped = calloc((size_t)weightCount, sizeof(ProbeMappedFile));
        char **buffers = calloc((size_t)weightCount, sizeof(char *));
        size_t *lengths = calloc((size_t)weightCount, sizeof(size_t));
        if (mapped == NULL || buffers == NULL || lengths == NULL) {
            free(buffers);
            free(lengths);
            probeUnmapAll(mapped, weightCount);
            api->ReleaseSessionOptions(options);
            probeSetError(errorMessage, "calloc thất bại");
            VieNeuORTProbeDestroy(probe);
            return NULL;
        }
        for (int32_t index = 0; index < weightCount; index++) {
            int file = open(weightPaths[index], O_RDONLY);
            struct stat info;
            if (file < 0 || fstat(file, &info) != 0 || info.st_size <= 0) {
                if (file >= 0) close(file);
                free(buffers);
                free(lengths);
                probeUnmapAll(mapped, weightCount);
                api->ReleaseSessionOptions(options);
                probeSetError(errorMessage, "không mở được file trọng số");
                VieNeuORTProbeDestroy(probe);
                return NULL;
            }
            mapped[index].length = (size_t)info.st_size;
            mapped[index].base = mmap(NULL, mapped[index].length, PROT_READ, MAP_PRIVATE, file, 0);
            close(file);
            if (mapped[index].base == MAP_FAILED) {
                mapped[index].base = NULL;
                free(buffers);
                free(lengths);
                probeUnmapAll(mapped, weightCount);
                api->ReleaseSessionOptions(options);
                probeSetError(errorMessage, "mmap file trọng số thất bại");
                VieNeuORTProbeDestroy(probe);
                return NULL;
            }
            buffers[index] = (char *)mapped[index].base;
            lengths[index] = mapped[index].length;
        }
        status = api->AddExternalInitializersFromFilesInMemory(options, (const ORTCHAR_T *const *)weightNames,
                                                               (char *const *)buffers, lengths, (size_t)weightCount);
        free(buffers);
        free(lengths);
    }
    if (probeFailed(api, status, errorMessage)) {
        probeUnmapAll(mapped, weightCount);
        api->ReleaseSessionOptions(options);
        VieNeuORTProbeDestroy(probe);
        return NULL;
    }

    // Bắt stderr trong lúc tạo session: ORT ghi bảng chia partition của EP ra đó. Hỏng thì bỏ qua, không chặn.
    int savedStderr = -1;
    int logFile = -1;
    if (captureLog) {
        fflush(stderr);
        logFile = open(logPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (logFile >= 0) {
            savedStderr = dup(STDERR_FILENO);
            if (savedStderr < 0 || dup2(logFile, STDERR_FILENO) < 0) {
                if (savedStderr >= 0) close(savedStderr);
                savedStderr = -1;
            }
        }
    }
    status = api->CreateSession(probe->env, modelPath, options, &probe->session);
    if (savedStderr >= 0) {
        fflush(stderr);
        dup2(savedStderr, STDERR_FILENO);
        close(savedStderr);
    }
    if (logFile >= 0) close(logFile);
    api->ReleaseSessionOptions(options);
    probeUnmapAll(mapped, weightCount);
    if (probeFailed(api, status, errorMessage)) {
        VieNeuORTProbeDestroy(probe);
        return NULL;
    }

    probe->inputNames = probeCopyNames(api, probe->session, 1, &probe->inputCount, errorMessage);
    if (probe->inputNames == NULL) {
        VieNeuORTProbeDestroy(probe);
        return NULL;
    }
    probe->outputNames = probeCopyNames(api, probe->session, 0, &probe->outputCount, errorMessage);
    if (probe->outputNames == NULL) {
        VieNeuORTProbeDestroy(probe);
        return NULL;
    }
    return probe;
}

void VieNeuORTProbeDestroy(VieNeuORTProbeSession *probe) {
    if (probe == NULL) return;
    const OrtApi *api = probe->api;
    if (probe->session != NULL) api->ReleaseSession(probe->session);
    if (probe->memoryInfo != NULL) api->ReleaseMemoryInfo(probe->memoryInfo);
    if (probe->env != NULL) api->ReleaseEnv(probe->env);
    if (probe->inputNames != NULL) {
        for (int32_t index = 0; index < probe->inputCount; index++) free(probe->inputNames[index]);
        free(probe->inputNames);
    }
    if (probe->outputNames != NULL) {
        for (int32_t index = 0; index < probe->outputCount; index++) free(probe->outputNames[index]);
        free(probe->outputNames);
    }
    free(probe);
}

int32_t VieNeuORTProbeInputCount(const VieNeuORTProbeSession *probe) {
    return probe != NULL ? probe->inputCount : 0;
}

int32_t VieNeuORTProbeOutputCount(const VieNeuORTProbeSession *probe) {
    return probe != NULL ? probe->outputCount : 0;
}

const char *VieNeuORTProbeInputName(const VieNeuORTProbeSession *probe, int32_t index) {
    if (probe == NULL || index < 0 || index >= probe->inputCount) return "";
    return probe->inputNames[index];
}

const char *VieNeuORTProbeOutputName(const VieNeuORTProbeSession *probe, int32_t index) {
    if (probe == NULL || index < 0 || index >= probe->outputCount) return "";
    return probe->outputNames[index];
}

int32_t VieNeuORTProbeRun(VieNeuORTProbeSession *probe,
                          const float *const *inputs,
                          const int64_t *shapes,
                          const int32_t *ranks,
                          float **outputs,
                          int64_t *outputCounts,
                          int64_t *outputShapes,
                          int32_t *outputRanks,
                          char **errorMessage) {
    if (probe == NULL || probe->session == NULL) {
        probeSetError(errorMessage, "session rỗng");
        return -1;
    }
    const OrtApi *api = probe->api;
    for (int32_t index = 0; index < probe->outputCount; index++) {
        outputs[index] = NULL;
        outputCounts[index] = 0;
        outputRanks[index] = 0;
    }
    OrtValue **inputValues = calloc(probe->inputCount > 0 ? probe->inputCount : 1, sizeof(OrtValue *));
    OrtValue **outputValues = calloc(probe->outputCount > 0 ? probe->outputCount : 1, sizeof(OrtValue *));
    int32_t result = -1;
    if (inputValues == NULL || outputValues == NULL) {
        probeSetError(errorMessage, "calloc thất bại");
        goto done;
    }

    const int64_t *shape = shapes;
    for (int32_t index = 0; index < probe->inputCount; index++) {
        int64_t count = 1;
        for (int32_t axis = 0; axis < ranks[index]; axis++) count *= shape[axis];
        OrtStatus *status = api->CreateTensorWithDataAsOrtValue(probe->memoryInfo, (void *)inputs[index],
                                                                (size_t)count * sizeof(float), shape,
                                                                (size_t)ranks[index],
                                                                ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
                                                                &inputValues[index]);
        if (probeFailed(api, status, errorMessage)) goto done;
        shape += ranks[index];
    }

    if (probeFailed(api, api->Run(probe->session, NULL,
                                  (const char *const *)probe->inputNames, (const OrtValue *const *)inputValues,
                                  (size_t)probe->inputCount,
                                  (const char *const *)probe->outputNames, (size_t)probe->outputCount,
                                  outputValues), errorMessage)) {
        goto done;
    }

    for (int32_t index = 0; index < probe->outputCount; index++) {
        OrtTensorTypeAndShapeInfo *info = NULL;
        size_t elementCount = 0;
        float *data = NULL;
        size_t rank = 0;
        if (probeFailed(api, api->GetTensorTypeAndShape(outputValues[index], &info), errorMessage)) goto done;
        OrtStatus *status = api->GetTensorShapeElementCount(info, &elementCount);
        if (status == NULL) status = api->GetDimensionsCount(info, &rank);
        if (status == NULL && rank > VIENEU_PROBE_MAX_RANK) {
            api->ReleaseTensorTypeAndShapeInfo(info);
            probeSetError(errorMessage, "output quá nhiều chiều");
            goto done;
        }
        if (status == NULL) status = api->GetDimensions(info, outputShapes + (size_t)index * VIENEU_PROBE_MAX_RANK, rank);
        api->ReleaseTensorTypeAndShapeInfo(info);
        if (probeFailed(api, status, errorMessage)) goto done;
        outputRanks[index] = (int32_t)rank;
        if (probeFailed(api, api->GetTensorMutableData(outputValues[index], (void **)&data), errorMessage)) goto done;
        outputs[index] = malloc(elementCount > 0 ? elementCount * sizeof(float) : sizeof(float));
        if (outputs[index] == NULL) {
            probeSetError(errorMessage, "malloc thất bại");
            goto done;
        }
        if (elementCount > 0) memcpy(outputs[index], data, elementCount * sizeof(float));
        outputCounts[index] = (int64_t)elementCount;
    }
    result = 0;

done:
    if (inputValues != NULL) {
        for (int32_t index = 0; index < probe->inputCount; index++) {
            if (inputValues[index] != NULL) api->ReleaseValue(inputValues[index]);
        }
        free(inputValues);
    }
    if (outputValues != NULL) {
        for (int32_t index = 0; index < probe->outputCount; index++) {
            if (outputValues[index] != NULL) api->ReleaseValue(outputValues[index]);
        }
        free(outputValues);
    }
    if (result != 0) {
        for (int32_t index = 0; index < probe->outputCount; index++) {
            free(outputs[index]);
            outputs[index] = NULL;
            outputCounts[index] = 0;
        }
    }
    return result;
}

void VieNeuORTProbeFreeString(char *message) {
    free(message);
}
