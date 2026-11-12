//
//  VieNeuONNXProbeBridge.h
//  Tàng Công Các
//
//  Cầu nối C API **tổng quát, chỉ float32** của ONNX Runtime cho phép thử P1 "So EP cho Nano" (màn thử VieNeu
//  Turbo). Khác `VieNeuONNXBridge.h` (4 hàm bám đúng 4 bước pipeline, có tensor bool / int64): ở đây mọi graph của
//  gói tĩnh (`Scripts/vieneu_nano_static_export.py`) chỉ nhận và trả float32, nên một hàm chạy theo tên là đủ.
//
//  Không đụng đường đọc truyện: chỉ `VieNeuNanoEPProbe` gọi.
//

#ifndef VieNeuONNXProbeBridge_h
#define VieNeuONNXProbeBridge_h

#include <stdint.h>

/// Một `OrtSession` kèm tên input / output (giữ bản sao, sống tới `VieNeuORTProbeDestroy`).
typedef struct VieNeuORTProbeSession VieNeuORTProbeSession;

/// Tạo session từ `modelPath` (external data đọc tương đối theo thư mục của model).
/// - `provider`: `"CPU"`, `"CoreML"` hoặc `"XNNPACK"`; `keys` / `values` / `optionCount` là tuỳ chọn của EP
///   (bỏ qua với `"CPU"`), đưa thẳng vào `SessionOptionsAppendExecutionProvider`.
/// - `threads`: số luồng intra-op của session; spin luôn tắt, tối ưu graph `ORT_ENABLE_ALL`.
/// - `logPath` khác chuỗi rỗng ⇒ log của session ở mức INFO và **stderr được chuyển vào file đó** trong lúc tạo
///   session (ORT in bảng chia partition của EP ra stderr). Chỉ là chẩn đoán, có thể rỗng.
/// - `weightNames` / `weightPaths` / `weightCount` (P1b): file trọng số external data **nạp vào bộ nhớ** trước khi tạo
///   session (`AddExternalInitializersFromFilesInMemory`, `mmap` chỉ đọc, ORT chép thẳng vào graph rồi gỡ map). Né lỗi
///   của Core ML EP ORT 1.24.2: nó ghép `<đường dẫn file model>/<tên file trọng số>` ⇒ "Not a directory". `weightNames`
///   là đúng chuỗi `location` ghi trong graph (vd `ve_main.weights`). `weightCount` = 0 ⇒ đọc external data như cũ.
/// Trả `NULL` khi lỗi; `*errorMessage` nhận chuỗi `malloc` (giải phóng bằng `VieNeuORTProbeFreeString`).
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
                                            char **errorMessage);

void VieNeuORTProbeDestroy(VieNeuORTProbeSession *session);

int32_t VieNeuORTProbeInputCount(const VieNeuORTProbeSession *session);
int32_t VieNeuORTProbeOutputCount(const VieNeuORTProbeSession *session);
/// Tên thuộc session — không giải phóng.
const char *VieNeuORTProbeInputName(const VieNeuORTProbeSession *session, int32_t index);
const char *VieNeuORTProbeOutputName(const VieNeuORTProbeSession *session, int32_t index);

/// Số chiều tối đa của một output (`outputShapes` cấp `outputCount × VIENEU_PROBE_MAX_RANK` phần tử).
#define VIENEU_PROBE_MAX_RANK 8

/// Chạy một lượt. Input theo **đúng thứ tự** `VieNeuORTProbeInputName`: `inputs[i]` trỏ dữ liệu float32,
/// `shapes` nối liền các shape (`ranks[i]` phần tử cho input i). Mọi output được copy ra `outputs[o]` (`malloc`,
/// bên gọi `free`), `outputCounts[o]` = số phần tử, shape ở `outputShapes[o × VIENEU_PROBE_MAX_RANK …]` với
/// `outputRanks[o]` chiều. Trả 0 khi thành công; lỗi thì mọi `outputs[o]` là `NULL`.
int32_t VieNeuORTProbeRun(VieNeuORTProbeSession *session,
                          const float *const *inputs,
                          const int64_t *shapes,
                          const int32_t *ranks,
                          float **outputs,
                          int64_t *outputCounts,
                          int64_t *outputShapes,
                          int32_t *outputRanks,
                          char **errorMessage);

void VieNeuORTProbeFreeString(char *message);

#endif /* VieNeuONNXProbeBridge_h */
