//
//  FreeBookBridgingHeader.h
//  Tàng Công Các
//
//  Bridging header duy nhất của target app (`SWIFT_OBJC_BRIDGING_HEADER` trong `project.yml`).
//  Chỉ gom các header C mà Swift cần thấy; mỗi phân hệ giữ header riêng của mình.
//
//  Sai đường dẫn ở đây là **mọi** file Swift hỏng biên dịch, không riêng phân hệ nào.
//

#ifndef FreeBookBridgingHeader_h
#define FreeBookBridgingHeader_h

// Cầu nối C API của ONNX Runtime cho engine VieNeu-TTS.
#include "../../Services/TTS/VieNeu/VieNeuONNXBridge.h"
// Cầu nối tổng quát (chỉ float32) — backend Core ML của trình đọc Nano ("Tăng tốc Core ML").
#include "../../Services/TTS/VieNeu/VieNeuONNXProbeBridge.h"
// TẠM (1.3.932): màn đo "Codec Turbo: AMX vs Neural Engine" — xoá cùng màn đo.
#include "../../Services/TTS/VieNeuTurbo/CodecBench/TurboCodecProbeBridge.h"

// libxml2 hệ thống cho XPath của nguồn Legado.
#include "../../Services/LegadoSource/Rule/LegadoLibXML2.h"

#endif /* FreeBookBridgingHeader_h */
