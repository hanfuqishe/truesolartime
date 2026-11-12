"""把 Android 版的图标同步成鸿蒙版的启动图标。

图标只有一份设计稿：design/icon-512.png（与 Android 的 ic_launcher 同一张图）。
这里直接复制到 AppScope 与 entry 的 media 目录，不另行绘制，避免两端图标不一致。

用法：python Tools/gen-icons.py
"""

import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "design" / "icon-512.png"
TARGETS = (
    ROOT / "AppScope/resources/base/media/app_icon.png",
    ROOT / "entry/src/main/resources/base/media/app_icon.png",
)


def main():
    if not SOURCE.exists():
        raise SystemExit(f"missing source icon: {SOURCE}")
    for target in TARGETS:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(SOURCE, target)
        print(f"wrote {target} ({target.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
