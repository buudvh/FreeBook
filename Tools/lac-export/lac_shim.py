"""LAC 2.1.2 gọi `paddle.fluid`, đã bị gỡ từ paddle 2.6 ⇒ trỏ `paddle.fluid` sang `paddle.base` (cùng API cũ)."""
import sys

import paddle
import paddle.base as base

sys.modules["paddle.fluid"] = base
sys.modules["paddle.fluid.core"] = base.core
paddle.fluid = base
