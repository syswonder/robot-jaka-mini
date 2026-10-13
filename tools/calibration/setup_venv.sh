#!/usr/bin/env bash
# 建标定工具自己的 venv：tools/calibration/.venv
#
# 为什么独立 venv：工具跑在宿主上（不经 ROS/robonix），依赖 pyorbbecsdk/opencv 等
# 宿主包；仓库根的 .venv 是给 rbnx codegen 用的（numpy 1.23/grpcio 钉死），不能混。
# 已有 venv 就复用，不删。
#
# 必须 Python 3.10：臂包里的 jkrc.so 是 3.10 构建的扩展；PATH 上的 python3 可能是
# 别的版本（本机是 pyenv 3.11 shim），所以显式解析一个 3.10 解释器。
set -euo pipefail

TOOL="$(cd "$(dirname "$0")" && pwd)"       # tools/calibration
VENV="${CALIB_VENV:-$TOOL/.venv}"

PY=""
for candidate in /usr/bin/python3.10 "$(command -v python3.10 || true)" "$(command -v python3 || true)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ] && \
       "$candidate" -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 10) else 1)' 2>/dev/null; then
        PY="$candidate"
        break
    fi
done
if [ -z "$PY" ]; then
    echo "error: 找不到 Python 3.10（jkrc.so 是 3.10 扩展，不能换版本）" >&2
    echo "       装一个：sudo apt install python3.10 python3.10-venv" >&2
    exit 1
fi
echo "[setup] 解释器：$PY（$("$PY" -V 2>&1)）"

if [ -x "$VENV/bin/python" ]; then
    echo "[setup] 复用已有环境 → $VENV"
else
    echo "[setup] 建 venv → $VENV"
    "$PY" -m venv "$VENV"
fi

echo "[setup] 装依赖（$TOOL/requirements.txt）"
"$VENV/bin/pip" install -q -r "$TOOL/requirements.txt"

echo "[setup] 自测"
cd "$TOOL"
"$VENV/bin/python" - <<'PY'
import importlib.metadata
import cv2, numpy, scipy, pyorbbecsdk  # noqa: F401
print("[setup]   numpy", numpy.__version__, "| opencv", cv2.__version__,
      "| flask", importlib.metadata.version("flask"))
# 臂包探测 + 经包内加载器载入 jkrc（不动硬件）
import calib_arm  # noqa: F401
print("[setup]   臂包 OK")
PY

echo "[setup] 完成。跑法见 $TOOL/README.md"
