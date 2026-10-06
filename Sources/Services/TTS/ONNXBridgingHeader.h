//
//  ONNXBridgingHeader.h
//  FreeBook
//
//  Umbrella cho `SWIFT_OBJC_BRIDGING_HEADER` khai ở `project.yml`.
//
//  XcodeGen chỉ cho khai **một** file bridging header, mà repo đã có hai cầu nối C cho hai engine TTS
//  khác nhau. Thay vì nhét `#include` của ZeroTTS vào cuối `VieNeuONNXBridge.h` (làm lẫn hai engine trong
//  một file, và file đó là của VieNeu), tách hẳn một umbrella — thêm engine thứ ba sau này chỉ là thêm một
//  dòng ở đây.
//
//  Đường dẫn trong ngoặc kép được giải theo thư mục của **chính file này**, nên hai dòng dưới trỏ đúng
//  tới hai cầu nối mà không cần include path nào thêm.
//

#ifndef ONNXBridgingHeader_h
#define ONNXBridgingHeader_h

#import "VieNeu/VieNeuONNXBridge.h"
#import "ZeroTTS/ZeroTTSONNXBridge.h"

#endif /* ONNXBridgingHeader_h */
