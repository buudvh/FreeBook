//
//  LegadoLibXML2.h
//  FreeBook
//
//  Header libxml2 hệ thống mà engine rule của nguồn Legado dùng (HTML parser + XPath).
//  Thư mục `$(SDKROOT)/usr/include/libxml2` phải nằm trong `HEADER_SEARCH_PATHS` (khai ở `project.yml`)
//  vì các header của libxml2 tự include nhau theo dạng `<libxml/...>`.
//
//  Cố ý không có đường thay thế: thiếu libxml2 phải là lỗi biên dịch, không phải XPath im lặng trả rỗng.
//

#ifndef LegadoLibXML2_h
#define LegadoLibXML2_h

#include <libxml/HTMLparser.h>
#include <libxml/tree.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>

#endif /* LegadoLibXML2_h */
