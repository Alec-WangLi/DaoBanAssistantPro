# 把 app/tool/promo 渲染出来的逐帧素材拼成**功能演示视频**（抖音 / 小红书 / B 站）。
#
#   # 1) 先出帧（每场一条用例，可以只重跑改过的那场）
#   toolchain/flutter/bin/flutter test tool/promo/render_promo_video_test.dart
#   toolchain/flutter/bin/flutter test tool/promo/render_promo_video_test.dart --plain-name 待办
#
#   # 2) 再拼片
#   python scripts/make_promo_video.py
#   python scripts/make_promo_video.py --scenes s6_todos,s9_font   # 只拼几场试看
#
# 产物：dist/video/daoban-shiftassistantpro-v<版本>-demo-1080x1920.mp4
#   —— **无音轨**。BGM 与口播由用户后期自己贴，所以这里既不加音乐也不烧字幕；
#      分镜时间码与建议口播写在 docs/promo/video-script-v0.14.0.md。
#
# 为什么不用真机录屏：录屏有通知栏、有误触、有手指入画，而且改一个界面就得重录。
# 工装每一条交互都写在代码里，重跑一次就是同一支片（与 README 动图同一套思路）。
import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FRAMES = ROOT / 'app' / 'build' / 'promo-video' / 'frames'
WORK = ROOT / 'app' / 'build' / 'promo-video'
CARDS = WORK / 'cards'
SEGMENTS = WORK / 'segments'
OUT_DIR = ROOT / 'dist' / 'video'

W, H = 1080, 1920
FPS = 30

ACCENT = (91, 108, 255)
ACCENT_D = (44, 34, 130)
WHITE = (255, 255, 255)
SOFT = (216, 221, 255)

# 场次顺序 = 成片顺序。名字必须与 render_promo_video_test.dart 里的 `scene:` 一致。
SCENES = [
    ('s1_calendar', '排班日历'),
    ('s8_templates', '20 种倒班方式'),
    ('s2_stats', '统计 · 月'),
    ('s3_stats_year', '统计 · 年'),
    ('s4_alarm', '班次闹钟'),
    ('s5_ringing', '全屏响铃'),
    ('s6_todos', '待办日程'),
    ('s7_override', '换班 / 请假'),
    ('s9_font', '字号四档'),
]


def _font(name, size):
    try:
        return ImageFont.truetype(f'C:/Windows/Fonts/{name}', size)
    except OSError:
        return ImageFont.load_default()


def _gradient(w, h, c1, c2):
    ys, xs = np.mgrid[0:h, 0:w]
    t = np.clip(xs / max(1, w - 1) * 0.6 + ys / max(1, h - 1) * 0.4, 0, 1)
    arr = np.zeros((h, w, 3), np.float64)
    for i in range(3):
        arr[:, :, i] = c1[i] + (c2[i] - c1[i]) * t
    return Image.fromarray(arr.astype(np.uint8), 'RGB')


def _center(d, text, font, y, fill):
    d.text(((W - d.textlength(text, font=font)) / 2, y), text, font=font, fill=fill)


def intro_card():
    """片头：品牌渐变 + 标题。两秒，够观众看清名字就走。"""
    img = _gradient(W, H, ACCENT, ACCENT_D)
    d = ImageDraw.Draw(img)
    _center(d, '倒班助手 Pro', _font('msyhbd.ttc', 132), 620, WHITE)
    _center(d, '排班日历 · 班次闹钟 · 待办日程', _font('msyh.ttc', 62), 806, SOFT)
    _center(d, '为倒班的人做的一套 App', _font('msyh.ttc', 52), 930, (196, 204, 255))
    return img


def outro_card():
    """片尾：四条承诺 + 搜索词。

    刻意**不写网址**：抖音与小红书都把站外导流判成营销，轻则限流重则违规，
    所以这里只留「搜什么」。GitHub 仓库名同时也是 App 名，搜得到。
    """
    img = _gradient(W, H, ACCENT_D, ACCENT)
    d = ImageDraw.Draw(img)
    _center(d, '你的排班，只在你手机里', _font('msyhbd.ttc', 96), 520, WHITE)
    lines = ['无账号', '无广告', '无后端', '纯本地离线']
    f = _font('msyh.ttc', 66)
    y = 760
    for line in lines:
        _center(d, line, f, y, SOFT)
        y += 104
    _center(d, 'GitHub / 酷安 搜索：倒班助手Pro', _font('msyh.ttc', 54), 1290, WHITE)
    _center(d, '仅支持 Android 8.0 及以上', _font('msyh.ttc', 44), 1400, (186, 194, 255))
    return img


def _ffmpeg(*args):
    cmd = ['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', *args]
    subprocess.run(cmd, check=True)


def _encode_image(path, seconds, out):
    """静帧 → 定长片段。`-t` 写在输入侧之前更稳妥，这里用输出侧限长即可。"""
    _ffmpeg('-loop', '1', '-framerate', str(FPS), '-i', str(path),
            '-t', f'{seconds}', '-vf', 'scale=%d:%d,format=yuv420p' % (W, H),
            '-c:v', 'libx264', '-preset', 'slow', '-crf', '19',
            '-r', str(FPS), str(out))


def _encode_frames(scene, out):
    first = FRAMES / f'{scene}_0000.png'
    if not first.exists():
        sys.exit(f'缺少 {scene} 的帧：先跑 flutter test '
                 f'tool/promo/render_promo_video_test.dart --plain-name {scene}')
    _ffmpeg('-framerate', str(FPS), '-i', str(FRAMES / f'{scene}_%04d.png'),
            '-vf', 'format=yuv420p',
            '-c:v', 'libx264', '-preset', 'slow', '-crf', '19',
            '-r', str(FPS), str(out))


def _frame_count(scene):
    return len(list(FRAMES.glob(f'{scene}_*.png')))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--scenes', default='',
                    help='只拼这几场（逗号分隔的场次名），调试用')
    ap.add_argument('--intro', type=float, default=2.0, help='片头秒数')
    ap.add_argument('--outro', type=float, default=3.0, help='片尾秒数')
    ap.add_argument('--no-cards', action='store_true', help='不拼片头片尾')
    args = ap.parse_args()

    if not shutil.which('ffmpeg'):
        sys.exit('找不到 ffmpeg，先装 FFmpeg 6.1+ 并放进 PATH')

    SCENES[:] = [s for s in SCENES
                 if not args.scenes or s[0] in args.scenes.split(',')]
    if not SCENES:
        sys.exit('--scenes 一个都没匹配上，检查场次名')

    CARDS.mkdir(parents=True, exist_ok=True)
    SEGMENTS.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    parts = []
    if not args.no_cards:
        intro_card().save(CARDS / 'intro.png')
        _encode_image(CARDS / 'intro.png', args.intro, SEGMENTS / '00_intro.mp4')
        parts.append(SEGMENTS / '00_intro.mp4')

    total = args.intro if not args.no_cards else 0.0
    for idx, (scene, title) in enumerate(SCENES, start=1):
        out = SEGMENTS / f'{idx:02d}_{scene}.mp4'
        _encode_frames(scene, out)
        parts.append(out)
        n = _frame_count(scene)
        secs = n / FPS
        total += secs
        print(f'  {scene:14s} {n:5d} 帧  {secs:5.2f}s  {title}')

    if not args.no_cards:
        outro_card().save(CARDS / 'outro.png')
        _encode_image(CARDS / 'outro.png', args.outro, SEGMENTS / '99_outro.mp4')
        parts.append(SEGMENTS / '99_outro.mp4')
        total += args.outro

    lst = SEGMENTS / 'concat.txt'
    lst.write_text(''.join(f"file '{p.as_posix()}'\n" for p in parts),
                   encoding='utf-8')

    version = _version()
    out = OUT_DIR / f'daoban-shiftassistantpro-v{version}-demo-1080x1920.mp4'
    _ffmpeg('-f', 'concat', '-safe', '0', '-i', str(lst),
            '-c', 'copy', '-movflags', '+faststart', str(out))

    size_mb = out.stat().st_size / 1024 / 1024
    print(f'\n{out.relative_to(ROOT)}  {total:.1f}s  {size_mb:.1f} MB  无音轨')


def _version():
    """版本号只认 pubspec 一处（与 app_info.dart 由用例把关一致）。"""
    text = (ROOT / 'app' / 'pubspec.yaml').read_text(encoding='utf-8')
    m = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', text, re.M)
    return m.group(1) if m else 'dev'


if __name__ == '__main__':
    os.chdir(ROOT)
    main()
