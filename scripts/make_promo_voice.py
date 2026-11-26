# 给功能演示视频配 AI 口播（Microsoft Edge 的在线 TTS，中文音色，不要 key）。
#
#   python scripts/make_promo_voice.py                 # 默认云希，出 3 条音色
#   python scripts/make_promo_voice.py --voice zh-CN-YunjianNeural
#   python scripts/make_promo_voice.py --list          # 看有哪些中文音色
#
# 依赖：pip install edge-tts（本机已装）；网络要能连 Microsoft 的 TTS 接口。
# 成片：dist/video/daoban-shiftassistantpro-v<版本>-demo-1080x1920-<音色>.mp4
#   —— 画面直接 copy，只多一条音轨；无 BGM（见文件末尾）。
#
# 为什么用 edge-tts：免费、不要 API key、中文音色接近商用（云希 / 云健 / 晓晓），
# 而 Azure 要订阅、火山/阿里云要实名和计费、GPT-SoVITS 一类本地模型要 GPU 和几十 GB。
# 代价是它走 Edge「大声朗读」的公开接口，不保证长期可用 —— 换引擎只改 `_synth`。
import asyncio
import subprocess
import sys
from pathlib import Path

import edge_tts

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts'))

from make_promo_video import FPS, SCENES, _frame_count  # noqa: E402

VIDEO_DIR = ROOT / 'dist' / 'video'
WORK = ROOT / 'app' / 'build' / 'promo-video' / 'voice'

INTRO = 2.0
OUTRO = 4.0

# 口播稿：键是场次名，值是 [(相对本场开头的秒数, 文本)]。
#
# 写的时候按「每秒约 4.2 个汉字」估，每条再留 0.7 秒尾音。**故意比字幕短**：
# 字幕回答「现在看的是哪一项」，口播回答「为什么这件事值得看」，
# 两边一模一样的话，听着像在朗读页面。
VOICEOVER = {
    's1_calendar': [(0.35, '这个月怎么倒，一眼看完。')],
    's8_templates': [(0.25, '二十种倒班方式，挑一个最像的。')],
    's2_stats': [(0.35, '上了多少小时，它自己算。')],
    's3_stats_year': [(0.25, '出勤表还能导成 CSV。')],
    's4_alarm': [(0.25, '闹钟跟着排班自己走。')],
    's5_ringing': [(0.25, '锁屏、后台都会顶上来。')],
    # 「锁屏、后台都会顶上来」比它那一场（3.0s）长，尾音会压进待办那场，
    # 所以这一条推到 0.95s 再说，别和上一句叠在一起。
    's6_todos': [(0.95, '交班开会，按班次自动出现。')],
    's7_override': [(0.35, '长按拖一段，就换好班了。')],
    's9_font': [(0.35, '字号四档，日历当场重排。')],
}
OUTRO_LINE = (40.9, '无账号，无广告，纯本地。')

VOICES = {
    'yunxi': ('zh-CN-YunxiNeural', '云希 · 男声，阳光'),
    'yunjian': ('zh-CN-YunjianNeural', '云健 · 男声，有力'),
    'xiaoxiao': ('zh-CN-XiaoxiaoNeural', '晓晓 · 女声，温和'),
}


def _probe(path):
    out = subprocess.run(
        ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
         '-of', 'default=nw=1:nk=1', str(path)],
        capture_output=True, text=True, check=True)
    return float(out.stdout.strip())


def _synth(text, voice, out):
    async def run():
        await edge_tts.Communicate(text, voice).save(str(out))
    asyncio.run(run())


def timeline():
    """每场戏在成片里的起点（秒）。必须与 make_promo_video.py 的拼片顺序一致。"""
    t = INTRO
    starts = {}
    for scene, _ in SCENES:
        starts[scene] = t
        t += _frame_count(scene) / FPS
    return starts, t + OUTRO


def build(voice_key, voice_id, total):
    clips = []  # (开始秒, 文件)
    for scene, lines in VOICEOVER.items():
        starts, _ = timeline()
        for i, (off, text) in enumerate(lines):
            path = WORK / voice_key / f'{scene}_{i}.mp3'
            path.parent.mkdir(parents=True, exist_ok=True)
            if not path.exists():
                _synth(text, voice_id, path)
            clips.append((starts[scene] + off, path, text))

    outro = WORK / voice_key / 'outro.mp3'
    if not outro.exists():
        _synth(OUTRO_LINE[1], voice_id, outro)
    clips.append((OUTRO_LINE[0], outro, OUTRO_LINE[1]))

    clips.sort(key=lambda c: c[0])

    # 逐条报「说到哪儿」，一条压到下一条头上就说明稿子太长，要改的是稿子不是速度。
    prev_end = 0.0
    for start, path, text in clips:
        dur = _probe(path)
        end = start + dur
        flag = ' ⚠️ 压到下一句' if start < prev_end - 0.05 else ''
        if end > total + 0.3:
            flag += f' ⚠️ 超出成片结尾 {end - total:.2f}s'
        print(f'  {start:6.2f}s → {end:6.2f}s  {text}{flag}')
        prev_end = end


def mix(voice_key, voice_id, video, total):
    clips = []
    starts, _ = timeline()
    for scene, lines in VOICEOVER.items():
        for i, (off, text) in enumerate(lines):
            clips.append((starts[scene] + off, WORK / voice_key / f'{scene}_{i}.mp3'))
    clips.append((OUTRO_LINE[0], WORK / voice_key / 'outro.mp3'))
    clips.sort(key=lambda c: c[0])

    inputs = ['-i', str(video)]
    for _, p in clips:
        inputs += ['-i', str(p)]

    parts, labels = [], []
    for idx, (start, _) in enumerate(clips, start=1):
        ms = int(round(start * 1000))
        parts.append(f'[{idx}:a]adelay={ms}|{ms},volume=1.0[a{idx}]')
        labels.append(f'[a{idx}]')
    chain = ';'.join(parts) + ';' + ''.join(labels) + \
        f'amix=inputs={len(labels)}:normalize=0,alimiter=limit=0.95[a]'

    out = VIDEO_DIR / f'{video.stem}-{voice_key}.mp4'
    subprocess.run(['ffmpeg', '-y', '-v', 'error', *inputs,
                    '-filter_complex', chain,
                    '-map', '0:v', '-map', '[a]',
                    '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-ac', '2',
                    # 不加 -shortest：句尾比画面短，加它会把片尾卡按最后一句截断，
                    # 三个音色出来的时长还各不相同。让画面长度说了算。
                    '-movflags', '+faststart', str(out)],
                   check=True)
    return out


def main():
    if '--list' in sys.argv:
        for k, (vid, desc) in VOICES.items():
            print(f'{k:10s} {vid:26s} {desc}')
        return

    video = next(VIDEO_DIR.glob('*demo-1080x1920.mp4'), None)
    if not video:
        sys.exit('找不到成片，先跑 python scripts/make_promo_video.py')

    _, total = timeline()

    picks = VOICES
    if '--voice' in sys.argv:
        key = sys.argv[sys.argv.index('--voice') + 1]
        if key not in VOICES:
            sys.exit(f'没有这个音色：{key}（--list 看全部）')
        picks = {key: VOICES[key]}

    print(f'成片 {video.name}  {total:.1f}s')
    for key, (vid, desc) in picks.items():
        print(f'\n== {desc}（{vid}）')
        build(key, vid, total)
        out = mix(key, vid, video, total)
        print(f'→ {out.relative_to(ROOT)}  '
              f'{out.stat().st_size / 1024 / 1024:.1f} MB')


if __name__ == '__main__':
    main()
