"""把 Android 的 VectorDrawable 天气图标转成鸿蒙可用的 SVG。

Android 的 widget 图标在 res/drawable/ic_wx_*.xml，用的是 VectorDrawable；
鸿蒙的资源只认 SVG/PNG，这里把 pathData / fillColor / stroke* 逐项翻译过去。

用法：python Tools/gen-wx-icons.py
"""

import os
import re
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, '..', 'android', 'app', 'src', 'main', 'res', 'drawable')
DST = os.path.join(ROOT, 'entry', 'src', 'main', 'resources', 'base', 'media')

ANDROID = '{http://schemas.android.com/apk/res/android}'


def color(value, key):
    """#AARRGGBB / #RRGGBB / #ARGB / #RGB → (attrs dict)"""
    if not value:
        return {}
    value = value.strip().lstrip('#')
    if len(value) == 3:
        value = ''.join(c * 2 for c in value)
        alpha, rgb = 'FF', value
    elif len(value) == 4:
        value = ''.join(c * 2 for c in value)
        alpha, rgb = value[0:2], value[2:]
    elif len(value) == 6:
        alpha, rgb = 'FF', value
    elif len(value) == 8:
        alpha, rgb = value[0:2], value[2:]
    else:
        return {}
    result = {key: '#' + rgb.upper()}
    if alpha.upper() != 'FF':
        result[key + '-opacity'] = round(int(alpha, 16) / 255, 3)
    return result


def path_attrs(node):
    attrs = {}
    d = node.get(ANDROID + 'pathData')
    if d:
        attrs['d'] = d
    fill = node.get(ANDROID + 'fillColor')
    if fill:
        attrs.update(color(fill, 'fill'))
    else:
        attrs['fill'] = 'none'
    stroke = node.get(ANDROID + 'strokeColor')
    if stroke:
        attrs.update(color(stroke, 'stroke'))
        width = node.get(ANDROID + 'strokeWidth')
        if width:
            attrs['stroke-width'] = width
        cap = node.get(ANDROID + 'strokeLineCap')
        if cap:
            attrs['stroke-linecap'] = cap
        join = node.get(ANDROID + 'strokeLineJoin')
        if join:
            attrs['stroke-linejoin'] = join
    if node.get(ANDROID + 'fillAlpha'):
        pass
    rule = node.get(ANDROID + 'fillType')
    if rule == 'evenOdd':
        attrs['fill-rule'] = 'evenodd'
    return attrs


def emit(node, indent):
    tag = node.tag.rsplit('}', 1)[-1]
    pad = '  ' * indent
    if tag == 'path':
        attrs = path_attrs(node)
        body = ' '.join(f'{k}="{v}"' for k, v in attrs.items())
        return [f'{pad}<path {body}/>']
    if tag == 'group':
        parts = []
        tx = node.get(ANDROID + 'translateX', '0')
        ty = node.get(ANDROID + 'translateY', '0')
        sx = node.get(ANDROID + 'scaleX', '1')
        sy = node.get(ANDROID + 'scaleY', '1')
        rot = node.get(ANDROID + 'rotation', '0')
        px = node.get(ANDROID + 'pivotX')
        py = node.get(ANDROID + 'pivotY')
        transform = f'translate({tx} {ty})'
        if sx != '1' or sy != '1':
            transform += f' scale({sx} {sy})'
        if rot != '0':
            if px and py:
                transform += f' rotate({rot} {px} {py})'
            else:
                transform += f' rotate({rot})'
        parts.append(f'{pad}<g transform="{transform}">')
        for child in node:
            parts.extend(emit(child, indent + 1))
        parts.append(f'{pad}</g>')
        return parts
    return []


def convert(name):
    src = os.path.join(SRC, name + '.xml')
    tree = ET.parse(src)
    root = tree.getroot()
    width = root.get(ANDROID + 'viewportWidth', '24')
    height = root.get(ANDROID + 'viewportHeight', '24')
    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">'
    ]
    for child in root:
        lines.extend(emit(child, 1))
    lines.append('</svg>')
    target = os.path.join(DST, 'wx_' + name[len('ic_wx_'):] + '.svg')
    with open(target, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    return os.path.basename(target)


def main():
    count = 0
    for entry in sorted(os.listdir(SRC)):
        if re.fullmatch(r'ic_wx_[a-z_]+\.xml', entry):
            print('wrote', convert(entry[:-4]))
            count += 1
    print(f'{count} icon(s) converted')


if __name__ == '__main__':
    main()
