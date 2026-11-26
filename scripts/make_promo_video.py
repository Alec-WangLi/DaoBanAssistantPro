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


# 字幕：时间**相对本场开头**（秒）。一条别超 14 个字 —— 52px 两行以内看得完，
# 再长观众就不看了。改文案只动这里，不用重渲帧。
SCENE_CAPTIONS = {
    's1_calendar': [
        (0.3, 2.4, '这个月怎么倒，一眼看完'),
        (2.6, 4.8, '点哪天，底栏信息卡跟着换'),
    ],
    's8_templates': [
        (0.2, 3.5, '20 种倒班方式，挑一个最像的'),
    ],
    's2_stats': [
        (0.3, 2.2, '上了多少小时，它自己算'),
        (2.4, 4.3, '请假、加班、夜班分开统计'),
    ],
    's3_stats_year': [
        (0.2, 1.7, '年视图：哪个月最累'),
        (1.9, 3.3, '出勤表能导成 CSV'),
    ],
    's4_alarm': [
        (0.2, 1.9, '闹钟跟着排班自己走'),
        (2.1, 3.8, '一个班次能挂十条'),
    ],
    's5_ringing': [
        (0.2, 2.8, '锁屏、后台都会顶上来'),
    ],
    's6_todos': [
        (0.3, 2.2, '按班次重复，到点提醒'),
        (2.4, 4.5, '勾完自动归档'),
    ],
    's7_override': [
        (0.4, 2.4, '长按拖选一段日子'),
        (2.6, 4.8, '换班 / 请假 / 加班，只动这几天'),
    ],
    's9_font': [
        (0.3, 2.4, '字号四档，App 自己管'),
        (2.6, 5.3, '切到特大，日历当场重排'),
    ],
}

# 场次名（整场常驻在字幕上方那一行）。圆形序号让人一眼知道看到第几项。
SCENE_TITLES = {
    's1_calendar': '① 排班日历',
    's8_templates': '② 20 种倒班方式',
    's2_stats': '③ 统计 · 月度',
    's3_stats_year': '④ 统计 · 年度',
    's4_alarm': '⑤ 班次闹钟',
    's5_ringing': '⑥ 全屏响铃',
    's6_todos': '⑦ 待办日程',
    's7_override': '⑧ 换班 / 请假',
    's9_font': '⑨ 外观与字号',
}


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


def _ffmpeg(*args, cwd=None):
    cmd = ['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', *args]
    subprocess.run(cmd, check=True, cwd=cwd)


def _encode_image(path, seconds, out):
    """静帧 → 定长片段。`-t` 写在输入侧之前更稳妥，这里用输出侧限长即可。"""
    _ffmpeg('-loop', '1', '-framerate', str(FPS), '-i', str(path),
            '-t', f'{seconds}', '-vf', 'scale=%d:%d,format=yuv420p' % (W, H),
            '-c:v', 'libx264', '-preset', 'slow', '-crf', '19',
            '-r', str(FPS), str(out))


def _ass_ts(sec):
    cs = int(round(sec * 100))
    return f'{cs // 360000}:{(cs // 6000) % 60:02d}:{(cs // 100) % 60:02d}.{cs % 100:02d}'


def _ass_escape(text):
    return text.replace('\\', '\\\\').replace('{', '(').replace('}', ')')


def write_ass(scene, caps, duration):
    """一场戏一份 .ass，时间相对本场开头 —— 拼片是按场切的，全局时间码不用管。

    两行：上面一行是场次名（整场常驻，观众知道现在看的是什么），
    下面一行是随动作变化的说明。都不用方框底 —— 白字加黑描边在任何画面上都读得清，
    方框会把下面那条本来就窄的带子塞满。
    """
    head = """[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Kicker,Microsoft YaHei,34,&H00FF6C5B,&H00FFFFFF,&H00000000,&H00000000,-1,0,0,0,108,100,2,0,1,5,0,2,80,80,232,1
Style: Cap,Microsoft YaHei,52,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,-1,0,0,0,100,100,1,0,1,6,2,2,80,80,150,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    lines = [head]
    title = SCENE_TITLES.get(scene)
    if title:
        lines.append(f'Dialogue: 0,{_ass_ts(0.15)},{_ass_ts(duration - 0.1)},Kicker,,'
                     f'0,0,0,,{_ass_escape(title)}\n')
    for t0, t1, text in caps:
        lines.append(f'Dialogue: 0,{_ass_ts(t0)},{_ass_ts(t1)},Cap,,0,0,0,,'
                     f'{_ass_escape(text)}\n')
    path = WORK / 'captions' / f'{scene}.ass'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(lines), encoding='utf-8')
    return f'captions/{scene}.ass'


def _encode_frames(scene, out, captions=True):
    first = FRAMES / f'{scene}_0000.png'
    if not first.exists():
        sys.exit(f'缺少 {scene} 的帧：先跑 flutter test '
                 f'tool/promo/render_promo_video_test.dart --plain-name {scene}')

    if not captions:
        _ffmpeg('-framerate', str(FPS), '-i', f'frames/{scene}_%04d.png',
                '-vf', 'format=yuv420p',
                '-c:v', 'libx264', '-preset', 'slow', '-crf', '19',
                '-r', str(FPS), str(out), cwd=WORK)
        return

    # 画中画：模糊放大的自己当底，中间放清晰的画面，底下一条字幕带。
    # 为什么不直接满屏烧字幕：抖音 / 小红书自带的 UI 压在下 250px，
    # 满屏字幕不是被盖住，就是压住 App 自己的信息卡 —— 两条都不好看。
    chain = ('[0:v]scale=1080:1920:force_original_aspect_ratio=increase,'
             'crop=1080:1920,gblur=sigma=48,eq=brightness=-0.24:saturation=0.85[bg];'
             '[0:v]scale=842:1496[app];'
             '[bg][app]overlay=119:64[v0]')
    if captions and SCENE_CAPTIONS.get(scene):
        ass = write_ass(scene, SCENE_CAPTIONS[scene], _frame_count(scene) / FPS)
        chain += f';[v0]ass={ass}[v]'
        label = '[v]'
    else:
        label = '[v0]'

    _ffmpeg('-framerate', str(FPS), '-i', f'frames/{scene}_%04d.png',
            '-filter_complex', chain, '-map', label,
            '-c:v', 'libx264', '-preset', 'slow', '-crf', '19',
            '-r', str(FPS), '-pix_fmt', 'yuv420p', str(out), cwd=WORK)


def _frame_count(scene):
    return len(list(FRAMES.glob(f'{scene}_*.png')))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--scenes', default='',
                    help='只拼这几场（逗号分隔的场次名），调试用')
    ap.add_argument('--intro', type=float, default=2.0, help='片头秒数')
    ap.add_argument('--outro', type=float, default=3.0, help='片尾秒数')
    ap.add_argument('--no-cards', action='store_true', help='不拼片头片尾')
    ap.add_argument('--no-captions', action='store_true',
                    help='不烧字幕、也不做画中画（满屏原画，调试用）')
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
        _encode_frames(scene, out, captions=not args.no_captions)
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
