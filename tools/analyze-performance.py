"""Summarize a Chrome trace captured through the browser QA tools.

Usage: python tools/analyze-performance.py trace.json [--check]
Checks renderer main-frame CPU work against a 60 Hz frame budget. This is
not a GPU/Android FPS measurement and includes the trace instrumentation cost.
"""
import argparse
import json
from pathlib import Path


def summarize(path):
    data = json.loads(Path(path).read_text(encoding='utf-8'))
    events = data['traceEvents']
    renderers = {(e['pid'], e['tid']) for e in events
                 if e.get('name') == 'thread_name'
                 and e.get('args', {}).get('name') == 'CrRendererMain'}
    frames = sorted(e['dur'] / 1000 for e in events
                    if e.get('name') == 'ProxyMain::BeginMainFrame'
                    and 'dur' in e and (e['pid'], e['tid']) in renderers)
    if not frames:
        raise ValueError('No renderer frame durations found')
    metric = lambda name: {m['name']: m['value'] for m in data[name]['metrics']}
    before, after = metric('metricsBefore'), metric('metricsAfter')
    return {
        'frames': len(frames),
        'main_frame_p50_ms': round(frames[int((len(frames)-1)*.50)], 3),
        'main_frame_p95_ms': round(frames[int((len(frames)-1)*.95)], 3),
        'main_frame_max_ms': round(frames[-1], 3),
        'main_frames_over_16_67ms': sum(f > 1000/60 for f in frames),
        'main_frames_over_50ms': sum(f > 50 for f in frames),
        'main_frame_work_ms': round(sum(frames), 2),
        'task_work_ms': round((after['TaskDuration']-before['TaskDuration'])*1000, 2),
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('trace')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    result = summarize(args.trace)
    print(json.dumps(result, indent=2))
    if args.check:
        passed = result['main_frame_p95_ms'] <= 1000/60 and result['main_frames_over_50ms'] == 0
        print('PASS' if passed else 'FAIL: renderer main-frame work exceeds the smoothness budget')
        raise SystemExit(0 if passed else 1)
