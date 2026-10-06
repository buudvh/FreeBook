//
//  ZeroTTSONNXBridge.h
//  FreeBook
//
//  Cầu nối **C API** của ONNX Runtime cho spike khảo sát ZeroTTS.
//
//  ## Vì sao lại thêm một cầu nữa thay vì dùng `VieNeuONNXBridge`
//  Cầu VieNeu là API **chuyên dụng theo từng bước graph của VieNeu** (`VieNeuONNXBridge.h:14`): mỗi hàm
//  nhận đúng bộ tham số của một graph và bốn hàm đó không dùng được cho graph nào khác. ZeroTTS cần một
//  bộ input khác hẳn — nhiều tensor hỗn hợp dtype, một `seen_mask` bool **sửa tại chỗ** giữa các frame, và
//  một KV cache phình dần theo từng frame — nên nó có cầu riêng. Cái dùng lại được là **khuôn kỹ thuật**:
//  `CreateTensorWithDataAsOrtValue` không copy, tensor bool phải đi qua C API, và tên input/output **hỏi
//  thẳng session** chứ không đoán.
//
//  ## Ba khác biệt dtype/trục phải nhớ (đọc từ `docs/RUNTIME.md` của upstream)
//  - Ba graph TTS nhận **int64**; graph codec nhận **int32**. Lẫn hai thứ này thì `Run` báo lỗi kiểu.
//  - Trục code của codec là **time-major** `(B, T, K)` còn vòng sinh của TTS tạo `(B, K, T)` ⇒
//    `ZeroTTSORTRunCodecDecodeFull` tự chuyển vị.
//  - `cross_kv` phải sống suốt utterance: `text_encoder` tính một lần rồi **mọi** `prefix_step` nhận lại
//    cùng buffer đó.
//
//  ## Trạng thái KV nằm trong ngữ cảnh
//  `packed_kv` và `full_valid` phình thêm một mục mỗi frame, nên chúng được cấp phát **một lần** trong
//  `ZeroTTSORTBeginSequence` và ghi tại chỗ ở mỗi `ZeroTTSORTRunPrefixFrame`. Hệ quả: **một ngữ cảnh chỉ
//  phục vụ được một lượt sinh tại một thời điểm** — bên gọi phải tự khoá (engine bọc bằng `NSLock`).
//
//  ## Quy ước lỗi
//  Mọi hàm trả `0` khi thành công, `-1` khi lỗi. `*errorMessage` (nếu khác `NULL`) nhận chuỗi do `malloc`
//  cấp phát ⇒ bên gọi phải trả lại bằng `ZeroTTSORTFreeErrorMessage`.
//

#ifndef ZeroTTSONNXBridge_h
#define ZeroTTSONNXBridge_h

#include <stddef.h>
#include <stdint.h>

/// Ngữ cảnh ORT: `OrtEnv`, `OrtMemoryInfo`, `OrtAllocator`, bốn `OrtSession` và trạng thái KV của lượt
/// sinh hiện tại.
typedef struct ZeroTTSORT ZeroTTSORT;

/// Shape **đọc từ chính graph** lúc nạp, không lấy từ `config.json`.
///
/// Trường nào model khai là chiều động thì trả `0` — bên gọi phải tự đối chiếu với `config.json` và báo
/// lỗi nếu cả hai đều không biết. Đây đúng bài học đã trả giá ở engine VieNeu: dựng shape từ config rồi
/// `duration_predictor` báo `Got: 512 Expected: 256` (`VieNeuONNXBridge.h:17-20`).
typedef struct {
    int32_t codebooks;
    int32_t codebookSize;
    int32_t layers;
    int32_t heads;
    int32_t headDim;
    int32_t dModel;
} ZeroTTSORTShapes;

/// Tạo ngữ cảnh và nạp **bốn** graph từ `modelDirectory`.
///
/// Bốn file, đúng tên gốc của kho weights: `text_encoder.onnx`, `prefix_step.onnx`,
/// `local_frame_decode.onnx`, `moss_audio_tokenizer_decode_full.onnx`. File external data của codec
/// (`moss_audio_tokenizer_decode_shared.data`) phải nằm **cùng thư mục** — ORT tự tìm theo đường dẫn
/// tương đối ghi trong graph.
///
/// `outShapes` là tuỳ chọn (truyền `NULL` để bỏ qua). Trả `NULL` khi lỗi.
ZeroTTSORT *ZeroTTSORTCreate(const char *modelDirectory,
                             int32_t threadCount,
                             ZeroTTSORTShapes *outShapes,
                             char **errorMessage);

/// Giải phóng ngữ cảnh, mọi session và buffer trạng thái KV bên trong.
void ZeroTTSORTDestroy(ZeroTTSORT *context);

/// `text_encoder(text_ids, txt_lengths)` → `text_valid`, `soa_embed`, `cross_kv`.
///
/// Đọc output **theo vị trí** (0 = `text_states`, 1 = `text_valid`, 2 = `soa_embed`, 3 = `cross_kv`) vì
/// bản tham chiếu cũng đọc theo vị trí; tên của chúng khác nhau giữa các bản export. `text_states` bị bỏ
/// qua — `prefix_step` bản mới **không** nhận nó (nó nhận `cross_kv` đã chiếu sẵn).
///
/// `outTextValid` phải chứa được `batch * length` byte; `outSoaEmbed` chứa được `soaCapacity` float
/// (thực tế là `batch * dModel`).
///
/// `outCrossKv` là buffer do bên gọi cấp và **phải sống suốt utterance** — nó được truyền lại vào mọi
/// `prefix_step`. Shape thật của `cross_kv` trả ra `outCrossKvShape`/`outCrossKvRank`; bên gọi **phải**
/// dùng shape đó thay vì tự dựng.
int32_t ZeroTTSORTRunTextEncoder(ZeroTTSORT *context,
                                 const int64_t *ids, int32_t batch, int32_t length,
                                 uint8_t *outTextValid,
                                 float *outSoaEmbed, int32_t soaCapacity,
                                 float *outCrossKv, int32_t crossKvCapacity, int32_t *outCrossKvCount,
                                 int64_t *outCrossKvShape, int32_t shapeCapacity, int32_t *outCrossKvRank,
                                 char **errorMessage);

/// Cấp phát lại trạng thái KV cho một lượt sinh mới.
///
/// `maxFrames` là **trần số frame audio**; `packed_kv` được cấp đủ cho `voiceCount + 1 + maxFrames` vị
/// trí nên **không** phải cấp lại giữa chừng (cấp lại mỗi frame là chỗ đốt thời gian lớn nhất của bản
/// port JS). Gọi hàm này trước mỗi utterance.
///
/// `codebooks` (`K`) **không** phải số frame: `frame_codes` của `prefix_step` khai `(B, T, K)` — chiều
/// cuối là số codebook. Nhầm nó với số frame sẽ ra đúng lỗi
/// `Got invalid dimensions for input: frame_codes … index: 2 Got: 1 Expected: 16`.
int32_t ZeroTTSORTBeginSequence(ZeroTTSORT *context,
                                int32_t batch, int32_t voiceCount, int32_t maxFrames,
                                int32_t codebooks,
                                int32_t layers, int32_t heads, int32_t headDim,
                                char **errorMessage);

/// Bước **cold start** của `prefix_step`: nạp khối `[voice ‖ soa]`.
///
/// `externalEmbed` là `(batch, voiceCount + 1, dModel)` đã ghép sẵn ở phía Swift; `soaEmbed` là
/// `(batch, dModel)` từ `text_encoder`. Trạng thái KV trong ngữ cảnh được ghi mới hoàn toàn.
/// `outHidden` nhận `(batch, dModel)` — chỉ **vị trí cuối** của output `hidden`, vì đó là thứ duy nhất
/// vòng lặp dùng.
int32_t ZeroTTSORTRunPrefixInit(ZeroTTSORT *context,
                                const float *externalEmbed,
                                const float *soaEmbed,
                                const float *crossKv, int32_t crossKvCount,
                                const int64_t *crossKvShape, int32_t crossKvRank,
                                const uint8_t *textValid, int32_t textValidCount,
                                float *outHidden,
                                char **errorMessage);

/// Bước **một frame** của `prefix_step`.
///
/// `frameCodes` là `(batch, codebooks)` int64 vừa lấy từ `ZeroTTSORTRunLocalFrameDecode`.
/// `new_pos` được dựng bên trong theo đúng công thức của upstream: khối giọng giữ `0 … voiceCount-1`,
/// `<soa>` ở `voiceCount`, frame `t` ở `voiceCount + 1 + t`. Sai một đơn vị ở đây **không** báo lỗi — nó
/// chỉ làm lệch mọi vị trí RoPE và audio nghe như một checkpoint tồi.
int32_t ZeroTTSORTRunPrefixFrame(ZeroTTSORT *context,
                                 const int64_t *frameCodes,
                                 int32_t frameIndex, int32_t voiceCount,
                                 const float *crossKv, int32_t crossKvCount,
                                 const int64_t *crossKvShape, int32_t crossKvRank,
                                 const uint8_t *textValid, int32_t textValidCount,
                                 float *outHidden,
                                 char **errorMessage);

/// `local_frame_decode(global_hidden, …)` → `is_eoa` và `codes` của **một** frame.
///
/// `seen_mask` là `(1, codebooks, codebookSize)` bool và bị **sửa tại chỗ** ở đây (đánh dấu code vừa lấy
/// cho từng codebook) — graph không mang được state dài biến thiên, nên lịch sử phạt lặp nằm ở bên gọi.
/// Bên gọi **phải** tự reset nó về toàn `0` đầu mỗi utterance.
///
/// `ctrlRandomU` là 1 float, `audioRandomU` là `codebooks` float — đây là các lá phiếu ngẫu nhiên của bộ
/// sampler, do bên gọi cấp, nên cùng seed ⇒ cùng kết quả.
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
                                      char **errorMessage);

/// `decode_full(audio_codes, audio_code_lengths)` → PCM mono float32.
///
/// `codesKT` là `(codebooks, frames)` int32 theo bố cục vòng sinh trả ra; hàm tự chuyển vị sang `(1, T, K)`
/// mà graph codec yêu cầu. Output `(1, channels, T_audio)` được lấy **trung bình kênh** thành mono, và số
/// mẫu thật đọc từ output `audio_lengths` (không suy từ công thức).
int32_t ZeroTTSORTRunCodecDecodeFull(ZeroTTSORT *context,
                                     const int32_t *codesKT, int32_t codebooks, int32_t frames,
                                     float *outPcm, int32_t pcmCapacity, int32_t *outPcmCount,
                                     char **errorMessage);

/// Giải phóng chuỗi lỗi do các hàm trên cấp phát.
void ZeroTTSORTFreeErrorMessage(char *errorMessage);

#endif /* ZeroTTSONNXBridge_h */
