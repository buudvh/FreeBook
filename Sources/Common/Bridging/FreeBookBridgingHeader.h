//
//  FreeBookBridgingHeader.h
//  FreeBook
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

// libxml2 hệ thống cho XPath của nguồn Legado.
#include "../../Services/LegadoSource/Rule/LegadoLibXML2.h"

#endif /* FreeBookBridgingHeader_h */
