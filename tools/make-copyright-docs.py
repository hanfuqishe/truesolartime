# -*- coding: utf-8 -*-
"""
生成软件著作权登记要交的两份材料（中国版权保护中心）：

  1. 《真太阳时时钟 V1.0 源程序》  —— 前 30 页 + 后 30 页，每页 50 行
  2. 《真太阳时时钟 V1.0 软件说明书》—— 功能与操作说明，约 20 页

规范依据（中心对源程序与文档的通用要求）：
  * 源程序、文档各取前 30 页、后 30 页（不足 60 页的全交）；
  * 源程序每页不少于 50 行（末页除外），页眉或页脚须标注软件名称、版本号、页码；
  * 文档每页不少于 30 行（有图的页可少于此数）；
  * 页码连续编号。

用法：
    python tools/make-copyright-docs.py                # 只生成 docx
    python tools/make-copyright-docs.py --pdf           # 再调 Word 转 PDF（Windows + Office）

输出目录：docs/software-copyright/
"""

from __future__ import annotations

import argparse
import io
import os
import subprocess
import sys
from glob import glob

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt

SOFTWARE = "真太阳时时钟"
VERSION = "V1.0"
OUT_DIR = os.path.join("docs", "software-copyright")

LINES_PER_PAGE = 50
PAGES_EACH_SIDE = 30
PREAMBLE_LINES = 0  # 源程序不额外加说明页，避免多占一页

# 源程序的呈现顺序：核心算法 → 数据 → 表现 → 平台接入 → 其它平台实现。
# 只影响“前 30 页/后 30 页”取到哪段代码，不影响内容完整性。
ORDER_HINTS = [
    ("android/app/src/main/java/com/realsuntime/solartime/core/", 0),
    ("android/app/src/main/java/com/realsuntime/solartime/time/", 1),
    ("android/app/src/main/java/com/realsuntime/solartime/solar/", 2),
    ("android/app/src/main/java/com/realsuntime/solartime/data/", 3),
    ("android/app/src/main/java/com/realsuntime/solartime/ui/", 4),
    ("android/app/src/main/java/com/realsuntime/solartime/widget/", 5),
    ("android/app/src/main/java/com/realsuntime/solartime/map/", 6),
    ("android/app/src/main/java/com/realsuntime/solartime/location/", 7),
    ("android/app/src/main/java/com/realsuntime/solartime/city/", 8),
    ("android/app/src/main/java/com/realsuntime/solartime/weather/", 9),
    ("android/app/src/main/java/com/realsuntime/solartime/", 10),
    ("harmony/entry/src/main/ets/core/", 11),
    ("harmony/entry/src/main/ets/services/", 12),
    ("harmony/entry/src/main/ets/pages/", 13),
    ("harmony/entry/src/main/ets/", 14),
    ("ios/", 15),
]


def read_text(path: str) -> str:
    with io.open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def collect_sources() -> list[str]:
    files: list[str] = []
    for pattern in ("android/app/src/main/java/**/*.kt", "harmony/entry/src/main/ets/**/*.ets", "ios/**/*.swift"):
        files.extend(glob(pattern, recursive=True))
    # 测试代码不进源程序文本（中心要的是可运行的实现，测试会稀释核心逻辑）
    files = [
        f
        for f in files
        if not any(seg in f.replace("\\", "/") for seg in ("/test/", "/androidTest/", "/Tests/", "UITests"))
    ]

    def rank(path: str) -> tuple[int, str]:
        norm = path.replace("\\", "/")
        for prefix, order in ORDER_HINTS:
            if norm.startswith(prefix):
                return (order, norm)
        return (99, norm)

    return sorted(files, key=rank)


def build_listing(files: list[str]) -> list[str]:
    """把源文件拼成逐行的清单，文件之间插入分隔行（也算行数，故取整页时同样计入）。"""
    lines: list[str] = []
    for path in files:
        norm = path.replace("\\", "/")
        lines.append("// " + "=" * 74)
        lines.append("// 文件：" + norm)
        lines.append("// " + "=" * 74)
        for raw in read_text(path).split("\n"):
            lines.append(raw.rstrip("\r"))
        lines.append("")
    return lines



MAX_PAGE_EM = 52.0  # 一行能放的「em 数」：可用宽 482pt / 字号 9pt ≈ 53.5em，取 52 留余量
#   ASCII 按 0.6em、中文按 1.0em 累计 → 纯英文约 86 字符、纯中文约 52 字，再长就续行，避免 Word 自动折行


def _em(ch: str) -> float:
    code = ord(ch)
    if code < 128:
        return 0.6
    return 1.0


def wrap_display(text: str) -> list[str]:
    """把过长的源码行拆成若干「显示行」，避免 Word 自动折行破坏每页 50 行。"""
    text = text.replace("\t", "    ")
    if not text:
        return [" "]
    out: list[str] = []
    cur: list[str] = []
    width = 0.0
    for ch in text:
        w = _em(ch)
        if width + w > MAX_PAGE_EM and cur:
            out.append("".join(cur))
            cur = [ch]
            width = w
        else:
            cur.append(ch)
            width += w
    if cur:
        out.append("".join(cur))
    return out


def to_display_lines(lines: list[str]) -> list[str]:
    result: list[str] = []
    for line in lines:
        result.extend(wrap_display(line))
    return result


def set_run_font(run, ascii_font: str = "Consolas", cjk_font: str = "宋体", size_pt: float = 9.0) -> None:
    run.font.size = Pt(size_pt)
    run.font.name = ascii_font
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.append(rfonts)
    rfonts.set(qn("w:ascii"), ascii_font)
    rfonts.set(qn("w:hAnsi"), ascii_font)
    rfonts.set(qn("w:eastAsia"), cjk_font)


def add_page_field(paragraph) -> None:
    run = paragraph.add_run()
    for instr, kind in (("begin", "fldChar"), ("PAGE", "instrText"), ("end", "fldChar")):
        if kind == "fldChar":
            el = OxmlElement("w:fldChar")
            el.set(qn("w:fldCharType"), instr)
        else:
            el = OxmlElement("w:instrText")
            el.set(qn("xml:space"), "preserve")
            el.text = " PAGE "
        run._element.append(el)
    set_run_font(run, "宋体", "宋体", 9.0)


def setup_page(section) -> None:
    section.page_width = Cm(21.0)
    section.page_height = Cm(29.7)
    section.top_margin = Cm(2.0)
    section.bottom_margin = Cm(1.8)
    section.left_margin = Cm(2.0)
    section.right_margin = Cm(2.0)
    section.header_distance = Cm(1.0)
    section.footer_distance = Cm(0.9)


def set_header(section, text: str) -> None:
    section.header.is_linked_to_previous = False
    para = section.header.paragraphs[0]
    para.text = ""
    para.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = para.add_run(text)
    set_run_font(run, "宋体", "宋体", 9.0)
    bold = run.font
    bold.bold = True


def set_footer(section, prefix: str = "第 ", suffix: str = " 页") -> None:
    section.footer.is_linked_to_previous = False
    para = section.footer.paragraphs[0]
    para.text = ""
    para.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r1 = para.add_run(prefix)
    set_run_font(r1, "宋体", "宋体", 9.0)
    add_page_field(para)
    r2 = para.add_run(suffix)
    set_run_font(r2, "宋体", "宋体", 9.0)


def add_code_page(doc, lines: list[str], first: bool, break_after: bool = False) -> None:
    """写一页代码：固定 50 行；分页符挂在最后一行段落末尾（不额外占行）。"""
    for i, text in enumerate(lines):
        para = doc.add_paragraph()
        pf = para.paragraph_format
        pf.space_before = Pt(0)
        pf.space_after = Pt(0)
        pf.line_spacing = Pt(13)
        para.alignment = WD_ALIGN_PARAGRAPH.LEFT
        expanded = text.replace("\t", "    ")
        run = para.add_run(expanded if expanded else " ")
        set_run_font(run, "Consolas", "宋体", 9.0)
        if break_after and i == len(lines) - 1:
            run.add_break(WD_BREAK.PAGE)


def chunk50(lines: list[str]) -> list[list[str]]:
    return [lines[i : i + LINES_PER_PAGE] for i in range(0, len(lines), LINES_PER_PAGE)]


def build_source_docx(files: list[str], listing: list[str]) -> str:
    need = PAGES_EACH_SIDE * LINES_PER_PAGE
    # 先按显示宽度换行，再按「显示行」切片：否则被折开的行会让某页超过 50 行、
    # 页数变成 61/63，提交时会被判格式不合规。
    display = to_display_lines(listing)
    head = display[:need]
    tail = display[-need:] if len(display) > need else []

    doc = Document()

    sec1 = doc.sections[0]
    setup_page(sec1)
    set_header(sec1, f"{SOFTWARE} {VERSION}  源程序（前 {PAGES_EACH_SIDE} 页 + 后 {PAGES_EACH_SIDE} 页）")
    set_footer(sec1)

    pages_all = chunk50(head) + (chunk50(tail) if tail else [])
    for index, page in enumerate(pages_all):
        add_code_page(
            doc,
            page,
            first=(index == 0),
            break_after=(index < len(pages_all) - 1),
        )

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, f"{SOFTWARE}-{VERSION}-源程序.docx")
    doc.save(path)
    print(f"  源程序：{path}")
    print(f"    源文件 {len(files)} 个，清单 {len(listing)} 行；取前 {len(head)} 行 + 后 {len(tail)} 行")
    return path


MANUAL = [
    ("一、软件概述", [
        f"{SOFTWARE}是一款以「真太阳时」为核心的时间显示工具。日常使用的钟表走的是平太阳时，"
        "把每天长度视为恒定；而真太阳时以太阳经过当地子午线的时刻为正午，逐日修正两类偏差："
        "一是经度与时区中央经线的差异，二是地球轨道偏心率与黄赤交角造成的均时差。",
        "因此同一瞬间，不同经度看到的真太阳时并不相同；同一地点，真太阳时与平太阳时的差值在一年中"
        "也会在约 -14 分到 +16 分之间往复。软件把这些修正实时算出来并与标准时间并列显示，"
        "帮助用户理解「当地此刻真正的太阳时间」。",
        "除时间本身，软件还提供当地日出日落与太阳高度角、按真太阳时划分的十二时辰、逐时天气，"
        "以及可放到桌面的卡片组件。软件支持 Android、HarmonyOS 与 iOS 三个平台，"
        "三端共用同一套计算口径与验证用例。",
    ]),
    ("二、运行环境与权限", [
        "（一）运行环境",
        "Android：Android 7.0（API 24）及以上版本；HarmonyOS：HarmonyOS 5.0 及以上版本；"
        "iOS：iOS 16 及以上版本。屏幕分辨率与密度不限，界面按可用宽高自适应。",
        "（二）网络与定位",
        "联网用于获取逐时天气与地图底图；定位用于确定用户当前经度与时区，从而计算真太阳时。"
        "用户可拒绝定位，此时可手动选择城市，或在无定位状态下仅显示标准时间。",
        "（三）权限说明",
        "软件仅申请与功能直接相关的权限：网络访问（必需）、定位（可选）。"
        "不申请通讯录、短信、通话记录、相册等与功能无关的权限，也不接入第三方广告或统计组件。",
    ]),
    ("三、界面总览", [
        "主界面自上而下依次为标题区、时间主卡片、太阳位置卡片、逐时天气与位置地图。"
        "整页可上下滚动查看；标题区右侧齿轮进入设置。",
        "时间主卡片左侧为标准时间（含秒），右侧为当地真太阳时；中间竖线为两栏分隔线。"
        "卡片下方是日期与天气摘要，再往下是时间轴与逐时天气行。",
        ("img", "docs/store-shots/redmi-248-normal.png", "图 1  主界面（亮色主题）"),
        ("img", "docs/store-shots/nova6-dark-theme.jpg", "图 2  主界面（暗色主题）"),
        "设置页自上而下为：主题、桌面卡片、诊断、关于计算、地图数据来源。"
        "其中「关于计算」写明了真太阳时的计算口径，便于用户理解与开发者核对。",
        ("img", "docs/store-shots/redmi-settings-no-calib.png", "图 3  设置页（桌面卡片与诊断入口）"),
    ]),
    ("四、功能说明", [
        "（一）真太阳时显示",
        "主卡片右侧显示按当地经度与当日均时差修正后的真太阳时，时、分、秒与左侧标准时间同步推进。"
        "秒位由系统计时器驱动，每秒在整秒边界更新一次，避免与「时:分」错位。",
        "（二）十二时辰",
        "按真太阳时刻划分时辰：子时自 23:00 起，每两小时一个时辰。卡片上显示当前时辰名称，"
        "如「午时」「未时」。",
        "（三）太阳位置",
        "以圆形示意图表示太阳在一个昼夜中的运行：实线半圆表示白昼、虚线半圆表示夜间，"
        "横线表示地平线；标注日出、日落、上中天时刻与太阳当前高度角，并用圆点标出太阳当前位置。",
        "（四）逐时天气",
        "显示当前及随后若干小时的天气图标与气温，数据来自公开气象接口。无网络或无缓存时该行自动降级，"
        "不显示错误占位。",
        "（五）位置地图",
        "显示当前坐标与底图。境内使用高德矢量瓦片，境外自动切换至 Esri 街道图；"
        "支持双指缩放与双击放大，用户手动缩放后不再自动切换底图来源，避免缩放级别被刷新覆盖。",
        "（六）桌面卡片",
        "可添加到桌面的卡片组件，样式与主界面一致，含标准时间、真太阳时、时间轴、逐时天气与时辰。"
        "卡片尺寸随桌面格子自适应：空间不足时收起时间轴或逐时行，保证不裁切、不重叠。",
        "（七）提醒设置",
        "可分别开启关键时间提醒（日出、日落、上中天等）与时辰交接提示，提示音走系统通知音频通道，"
        "不打断正在播放的音乐。",
        "（八）主题与显示",
        "主题支持「自动」「亮色」「暗色」三档：自动模式按当地日出日落切换。"
        "卡片与主界面共用同一套配色与字体。",
        "（九）诊断与卡片尺寸校准",
        "设置页「查看诊断信息」会生成一份只读快照（版本、机型、密度、卡片构建参数、天气与地图状态），"
        "可一键复制。若桌面卡片布局明显异常，可在诊断页展开「卡片布局不对？校准卡片尺寸」，"
        "让卡片临时显示横向与纵向刻度尺，读出真实宽高后填入，保存即按该尺寸排版；"
        "填写错误可点击「恢复自动」回到自动估算。",
    ]),
    ("五、操作说明", [
        "1. 首次启动：授予（或拒绝）定位权限。允许定位时自动计算当地真太阳时；拒绝时可手动选择城市。",
        "2. 查看太阳位置与天气：在主界面向上滑动，即可看到太阳位置卡片与逐时天气行。",
        "3. 缩放地图：在地图区域用双指开合缩放，或双击放大一级。",
        "4. 添加桌面卡片：进入设置，点击「添加到桌面」，按系统提示放置卡片。",
        "5. 切换主题：设置 → 主题，选择「自动」「亮色」或「暗色」。",
        "6. 开启提醒：设置 → 提醒，分别开关关键时间提醒与时辰交接提示。",
        "7. 反馈问题：设置 → 查看诊断信息 → 「复制全部」，把内容粘贴给开发者。",
        "8. 校准卡片：设置 → 查看诊断信息 → 「卡片布局不对？校准卡片尺寸」→ 点「刻度」→"
        "回桌面读出宽高 → 填入并「保存并刷新」；如需还原，点「恢复自动」。",
    ]),
    ("六、技术特点", [
        "1. 计算口径统一：真太阳时采用时差方程叠加经度修正的标准近似，三端共用同一实现与测试用例，"
        "避免同一地点在不同平台显示不同时间。",
        "2. 离线可用：无网络时标准时间与真太阳时照常显示，天气与地图按降级策略处理，不阻塞主功能。",
        "3. 卡片自绘：桌面卡片的时间轴与圆点按像素绘制位图，并限制位图体积，"
        "保证不同屏幕密度下几何一致且不超出系统对组件图片的大小限制。",
        "4. 布局自适应：卡片按桌面实际上报的宽高估算可用空间，空间不足时按优先级收起次要行，"
        "而不是整体缩放导致文字过小。",
        "5. 隐私友好：不采集个人身份信息，不申请无关权限，不接入广告与统计 SDK。",
    ]),
    ("七、隐私与数据说明", [
        "软件不收集可识别个人身份的信息。定位数据仅在本机用于计算真太阳时与天气，"
        "不会上传或与他人共享；天气与地图请求只携带计算所需的经纬度与瓦片坐标。",
        "软件不创建账号、不提供用户发布内容的功能，因此不涉及内容审核与用户信息存储。",
    ]),
    ("八、常见问题", [
        "问：真太阳时与北京时间为什么会差十几分钟？",
        "答：北京时间以东经 120° 为标准，若所在地经度不是 120°，每差 1° 就要修正 4 分钟；"
        "此外还有均时差（地球轨道偏心率与黄赤交角造成），一年中在约 -14 分到 +16 分之间变化。"
        "两者相加即为真太阳时与标准时间的差。",
        "问：为什么有的机型卡片上不显示时间轴？",
        "答：时间轴占一行高度。桌面给的格子较矮时，软件会按优先级收起时间轴以保证其余内容不被裁切；"
        "把卡片拉高即可恢复。",
        "问：没有定位权限还能用吗？",
        "答：可以。此时可手动选择城市确定经度，或仅显示标准时间。",
        "问：离线时天气和地图怎么办？",
        "答：显示上一次缓存的数据；无缓存时该区域留空，不影响时间显示。",
    ]),
    ("九、版本与维护信息", [
        f"软件名称：{SOFTWARE}",
        f"版本号：{VERSION}",
        "开发语言：Kotlin（Android）、ArkTS（HarmonyOS）、Swift（iOS）",
        "程序规模：源程序合计约 4.5 万行；本文档另附源程序前 30 页与后 30 页，每页 50 行。",
        "维护方式：随系统版本与气象、地图服务接口变化持续更新；界面与计算逻辑的变更会同步更新本文档。",
    ]),
]



def _shrink_for_doc(path: str, target_px: int = 900) -> str:
    """截图先压到 ~900px 宽再嵌入：原图 3000px/数 MB 会让文档体积失控。"""
    try:
        from PIL import Image  # type: ignore
    except Exception:
        return path
    try:
        out_dir = os.path.join(OUT_DIR, ".cache")
        os.makedirs(out_dir, exist_ok=True)
        img = Image.open(path).convert("RGB")
        if img.width > target_px:
            ratio = target_px / float(img.width)
            img = img.resize((target_px, int(img.height * ratio)), Image.LANCZOS)
        out = os.path.join(out_dir, os.path.basename(path).rsplit(".", 1)[0] + f"-{target_px}.jpg")
        img.save(out, "JPEG", quality=82, optimize=True)
        return out
    except Exception:
        return path



def _pic_width_cm(path: str) -> float:
    """按长宽比选插入宽度：竖版手机截图（>1.8）用 5.4cm，其余 7.2cm。"""
    try:
        from PIL import Image  # type: ignore
        with Image.open(path) as im:
            ratio = im.height / float(im.width)
        return 5.4 if ratio > 1.8 else 7.2
    except Exception:
        return 6.5


def build_manual_docx() -> str:
    doc = Document()
    sec = doc.sections[0]
    setup_page(sec)
    set_header(sec, f"{SOFTWARE} {VERSION}  软件说明书")
    set_footer(sec)

    title = doc.add_paragraph()
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = title.add_run(SOFTWARE)
    set_run_font(run, "宋体", "黑体", 22.0)
    run.font.bold = True

    sub = doc.add_paragraph()
    sub.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = sub.add_run(f"软件说明书（{VERSION}）")
    set_run_font(run, "宋体", "宋体", 14.0)

    doc.add_paragraph()

    for heading, paragraphs in MANUAL:
        hp = doc.add_paragraph()
        hp.paragraph_format.space_before = Pt(10)
        hp.paragraph_format.space_after = Pt(4)
        run = hp.add_run(heading)
        set_run_font(run, "宋体", "黑体", 13.0)
        run.font.bold = True

        for text in paragraphs:
            if isinstance(text, tuple) and text[0] == "img":
                _, img_path, caption = text
                if os.path.exists(img_path):
                    pic_para = doc.add_paragraph()
                    pic_para.alignment = WD_ALIGN_PARAGRAPH.CENTER
                    pic_para.paragraph_format.space_before = Pt(6)
                    pic_para.paragraph_format.space_after = Pt(2)
                    shot = _shrink_for_doc(img_path)
                    pic_para.add_run().add_picture(shot, width=Cm(_pic_width_cm(shot)))
                    cap_para = doc.add_paragraph()
                    cap_para.alignment = WD_ALIGN_PARAGRAPH.CENTER
                    cap_para.paragraph_format.space_after = Pt(8)
                    cap_run = cap_para.add_run(caption)
                    set_run_font(cap_run, "宋体", "宋体", 9.5)
                continue
            para = doc.add_paragraph()
            pf = para.paragraph_format
            pf.space_before = Pt(0)
            pf.space_after = Pt(2)
            pf.line_spacing = Pt(22)
            pf.first_line_indent = Pt(24)
            run = para.add_run(text)
            set_run_font(run, "宋体", "宋体", 11.0)

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, f"{SOFTWARE}-{VERSION}-软件说明书.docx")
    doc.save(path)
    print(f"  说明书：{path}")
    return path


def convert_to_pdf(docx_path: str) -> str:
    """用本机 Word 转 PDF（软著在线提交只收 PDF）。"""
    pdf_path = os.path.splitext(docx_path)[0] + ".pdf"
    docx_abs = os.path.abspath(docx_path)
    pdf_abs = os.path.abspath(pdf_path)
    ps = f"""
$ErrorActionPreference = 'Stop'
$word = New-Object -ComObject Word.Application
$word.Visible = $false
try {{
  $doc = $word.Documents.Open('{docx_abs}', $false, $true)
  $doc.SaveAs([ref]'{pdf_abs}', [ref]17)
  $pages = $doc.ComputeStatistics(2)
  $doc.Close($false)
  Write-Output "PAGES=$pages"
}} finally {{
  $word.Quit()
}}
"""
    script = os.path.join(OUT_DIR, "_topdf.ps1")
    with io.open(script, "w", encoding="utf-8-sig") as f:
        f.write(ps)
    out = subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script],
        capture_output=True,
        text=True,
    )
    os.remove(script)
    pages = ""
    for line in (out.stdout or "").splitlines():
        if line.startswith("PAGES="):
            pages = line.split("=", 1)[1].strip()
    if not os.path.exists(pdf_path):
        print("  !! PDF 转换失败：", (out.stderr or out.stdout or "")[:400])
        return ""
    size_kb = os.path.getsize(pdf_path) / 1024
    print(f"    PDF：{pdf_path}（{pages} 页，{size_kb:.0f} KB）")
    return pdf_path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdf", action="store_true", help="同时用 Word 转 PDF")
    args = parser.parse_args()

    files = collect_sources()
    if not files:
        print("未找到源文件（请在仓库根目录运行）")
        return 1
    listing = build_listing(files)
    print(f"源文件 {len(files)} 个，拼接后 {len(listing)} 行")

    source_docx = build_source_docx(files, listing)
    manual_docx = build_manual_docx()

    if args.pdf:
        print("转 PDF…")
        convert_to_pdf(source_docx)
        convert_to_pdf(manual_docx)

    print("完成。输出目录：", OUT_DIR)
    return 0


if __name__ == "__main__":
    sys.exit(main())
