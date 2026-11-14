//
//  TurboCodecProbeBridge.m
//  Tàng Công Các
//
//  Hiện thực `TurboCodecProbeBridge.h` — TẠM, xoá cùng màn đo codec Turbo. Khuôn theo `VieNeuONNXProbeBridge.m`.
//

#import "TurboCodecProbeBridge.h"

#import <onnxruntime/onnxruntime_c_api.h>

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

struct TurboCodecProbe {
    const OrtApi *api;
    OrtEnv *env;
    OrtMemoryInfo *memoryInfo;
    OrtSession *session;
};

static void codecSetError(char **out, const char *message) {
    if (out == NULL) return;
    *out = strdup(message != NULL ? message : "ONNX Runtime: lỗi không rõ");
}

static int codecFailed(const OrtApi *api, OrtStatus *status, char **errorMessage) {
    if (status == NULL) return 0;
    codecSetError(errorMessage, api->GetErrorMessage(status));
    api->ReleaseStatus(status);
    return 1;
}

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
                                       char **errorMessage) {
    const OrtApiBase *base = OrtGetApiBase();
    const OrtApi *api = base != NULL ? base->GetApi(ORT_API_VERSION) : NULL;
    if (api == NULL || modelPath == NULL || weightName == NULL || weightPath == NULL) {
        codecSetError(errorMessage, "không lấy được OrtApi hoặc thiếu đường dẫn");
        return NULL;
    }
    TurboCodecProbe *probe = calloc(1, sizeof(TurboCodecProbe));
    if (probe == NULL) {
        codecSetError(errorMessage, "calloc thất bại");
        return NULL;
    }
    probe->api = api;
    if (codecFailed(api, api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "TangCongCacTurboCodecProbe", &probe->env), errorMessage)
        || codecFailed(api, api->CreateCpuMemoryInfo(OrtDeviceAllocator, OrtMemTypeDefault, &probe->memoryInfo),
                       errorMessage)) {
        TurboCodecProbeDestroy(probe);
        return NULL;
    }

    OrtSessionOptions *options = NULL;
    if (codecFailed(api, api->CreateSessionOptions(&options), errorMessage)) {
        TurboCodecProbeDestroy(probe);
        return NULL;
    }
    int captureLog = logPath != NULL && logPath[0] != '\0';
    OrtStatus *status = api->SetIntraOpNumThreads(options, threads > 0 ? threads : 1);
    if (status == NULL) status = api->AddSessionConfigEntry(options, "session.intra_op.allow_spinning", "0");
    if (status == NULL) status = api->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL);
    if (status == NULL && captureLog) status = api->SetSessionLogSeverityLevel(options, ORT_LOGGING_LEVEL_INFO);
    if (status == NULL && codeLength > 0) status = api->AddFreeDimensionOverrideByName(options, "batch", 1);
    if (status == NULL && codeLength > 0) status = api->AddFreeDimensionOverrideByName(options, "code_length", codeLength);
    if (status == NULL && provider != NULL && strcmp(provider, "CPU") != 0) {
        status = api->SessionOptionsAppendExecutionProvider(options, provider, keys, values,
                                                            (size_t)(optionCount > 0 ? optionCount : 0));
    }

    // Trọng số external data nạp từ bộ nhớ: mmap chỉ đọc, ORT chép vào graph trong CreateSession rồi gỡ map.
    void *mapped = NULL;
    size_t mappedLength = 0;
    if (status == NULL) {
        int file = open(weightPath, O_RDONLY);
        struct stat info;
        if (file < 0 || fstat(file, &info) != 0 || info.st_size <= 0) {
            if (file >= 0) close(file);
            api->ReleaseSessionOptions(options);
            codecSetError(errorMessage, "không mở được file trọng số");
            TurboCodecProbeDestroy(probe);
            return NULL;
        }
        mappedLength = (size_t)info.st_size;
        mapped = mmap(NULL, mappedLength, PROT_READ, MAP_PRIVATE, file, 0);
        close(file);
        if (mapped == MAP_FAILED) {
            api->ReleaseSessionOptions(options);
            codecSetError(errorMessage, "mmap file trọng số thất bại");
            TurboCodecProbeDestroy(probe);
            return NULL;
        }
        const ORTCHAR_T *names[1] = { (const ORTCHAR_T *)weightName };
        char *buffers[1] = { (char *)mapped };
        size_t lengths[1] = { mappedLength };
        status = api->AddExternalInitializersFromFilesInMemory(options, names, buffers, lengths, 1);
    }
    if (codecFailed(api, status, errorMessage)) {
        if (mapped != NULL && mapped != MAP_FAILED) munmap(mapped, mappedLength);
        api->ReleaseSessionOptions(options);
        TurboCodecProbeDestroy(probe);
        return NULL;
    }

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
    if (mapped != NULL && mapped != MAP_FAILED) munmap(mapped, mappedLength);
    if (codecFailed(api, status, errorMessage)) {
        TurboCodecProbeDestroy(probe);
        return NULL;
    }
    return probe;
}

void TurboCodecProbeDestroy(TurboCodecProbe *probe) {
    if (probe == NULL) return;
    const OrtApi *api = probe->api;
    if (probe->session != NULL) api->ReleaseSession(probe->session);
    if (probe->memoryInfo != NULL) api->ReleaseMemoryInfo(probe->memoryInfo);
    if (probe->env != NULL) api->ReleaseEnv(probe->env);
    free(probe);
}

int32_t TurboCodecProbeDecode(TurboCodecProbe *probe,
                              const int32_t *codes,
                              int64_t frames,
                              int32_t realFrames,
                              float **audio,
                              int64_t *channels,
                              int64_t *samples,
                              char **errorMessage) {
    *audio = NULL;
    *channels = 0;
    *samples = 0;
    if (probe == NULL || probe->session == NULL || codes == NULL || frames <= 0) {
        codecSetError(errorMessage, "session rỗng hoặc thiếu mã");
        return -1;
    }
    const OrtApi *api = probe->api;
    OrtValue *inputs[2] = { NULL, NULL };
    OrtValue *outputs[2] = { NULL, NULL };
    int32_t length = realFrames;
    int64_t codeShape[3] = { 1, frames, 16 };
    int64_t lengthShape[1] = { 1 };
    const char *inputNames[2] = { "audio_codes", "audio_code_lengths" };
    const char *outputNames[2] = { "audio", "audio_lengths" };
    int32_t result = -1;

    if (codecFailed(api, api->CreateTensorWithDataAsOrtValue(probe->memoryInfo, (void *)codes,
                                                             (size_t)(frames * 16) * sizeof(int32_t), codeShape, 3,
                                                             ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32, &inputs[0]),
                    errorMessage)
        || codecFailed(api, api->CreateTensorWithDataAsOrtValue(probe->memoryInfo, &length, sizeof(int32_t),
                                                                lengthShape, 1, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32,
                                                                &inputs[1]),
                       errorMessage)) {
        goto done;
    }
    if (codecFailed(api, api->Run(probe->session, NULL, inputNames, (const OrtValue *const *)inputs, 2,
                                  outputNames, 2, outputs), errorMessage)) {
        goto done;
    }

    {
        OrtTensorTypeAndShapeInfo *info = NULL;
        int64_t shape[3] = { 0, 0, 0 };
        size_t rank = 0;
        if (codecFailed(api, api->GetTensorTypeAndShape(outputs[0], &info), errorMessage)) goto done;
        OrtStatus *status = api->GetDimensionsCount(info, &rank);
        if (status == NULL && rank != 3) {
            api->ReleaseTensorTypeAndShapeInfo(info);
            codecSetError(errorMessage, "output audio không phải 3 chiều");
            goto done;
        }
        if (status == NULL) status = api->GetDimensions(info, shape, 3);
        api->ReleaseTensorTypeAndShapeInfo(info);
        if (codecFailed(api, status, errorMessage)) goto done;

        float *data = NULL;
        int32_t *lengths = NULL;
        if (codecFailed(api, api->GetTensorMutableData(outputs[0], (void **)&data), errorMessage)
            || codecFailed(api, api->GetTensorMutableData(outputs[1], (void **)&lengths), errorMessage)) {
            goto done;
        }
        int64_t channelCount = shape[1];
        int64_t total = shape[2];
        int64_t kept = lengths != NULL && lengths[0] > 0 && lengths[0] < total ? lengths[0] : total;
        float *copy = malloc((size_t)(channelCount * kept) * sizeof(float) + sizeof(float));
        if (copy == NULL) {
            codecSetError(errorMessage, "malloc thất bại");
            goto done;
        }
        for (int64_t channel = 0; channel < channelCount; channel++) {
            memcpy(copy + channel * kept, data + channel * total, (size_t)kept * sizeof(float));
        }
        *audio = copy;
        *channels = channelCount;
        *samples = kept;
        result = 0;
    }

done:
    for (int index = 0; index < 2; index++) {
        if (inputs[index] != NULL) api->ReleaseValue(inputs[index]);
        if (outputs[index] != NULL) api->ReleaseValue(outputs[index]);
    }
    return result;
}

void TurboCodecProbeFreeString(char *message) {
    free(message);
}
