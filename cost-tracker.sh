#!/bin/bash
# Cost tracker script - outputs JSON with all API costs
# Called by the SwiftUI widget periodically

SESSIONS_DIR="$HOME/.openclaw/agents/main/sessions"
CALLS_FILE="$HOME/.openclaw/voice-calls/calls.jsonl"

python3 -c "
import json, glob, os
from datetime import datetime, timezone

sessions_dir = '$SESSIONS_DIR'
calls_file = '$CALLS_FILE'

# --- Anthropic costs from session logs ---
total_cost = 0
today_cost = 0
model_costs = {}
daily_costs = {}
total_requests = 0
total_input = 0
total_output = 0
total_cache_read = 0

today = datetime.now(timezone.utc).strftime('%Y-%m-%d')

for f in glob.glob(sessions_dir + '/*.jsonl'):
    if '.deleted.' in f: continue
    try:
        with open(f) as fh:
            for line in fh:
                try:
                    d = json.loads(line.strip())
                    if d.get('type') == 'message':
                        msg = d.get('message', {})
                        u = msg.get('usage')
                        if not u: continue
                        cost = u.get('cost', {})
                        t = cost.get('total', 0)
                        total_cost += t
                        total_input += u.get('input', 0)
                        total_output += u.get('output', 0)
                        total_cache_read += u.get('cacheRead', 0)
                        total_requests += 1

                        ts = d.get('timestamp', '')[:10]
                        daily_costs[ts] = daily_costs.get(ts, 0) + t
                        if ts == today:
                            today_cost += t

                        model = d.get('model', msg.get('model', 'unknown'))
                        model_costs[model] = model_costs.get(model, 0) + t
                except:
                    pass
    except:
        pass

# --- Twilio costs (estimate: ~\$0.02/min for calls) ---
twilio_cost = 0
twilio_calls = 0
try:
    if os.path.exists(calls_file):
        with open(calls_file) as f:
            for line in f:
                try:
                    d = json.loads(line.strip())
                    dur = d.get('duration', 0)
                    if isinstance(dur, str):
                        dur = int(dur) if dur.isdigit() else 0
                    twilio_cost += max(1, dur / 60) * 0.02  # min 1 min per call
                    twilio_calls += 1
                except:
                    pass
except:
    pass

# --- Replicate costs (estimate: ~\$0.005/run for TTS) ---
replicate_runs = 0
replicate_cost = 0
tts_dir = os.path.expanduser('~/.openclaw/workspace/tts-output')
if os.path.exists(tts_dir):
    replicate_runs = len([f for f in os.listdir(tts_dir) if f.endswith('.wav') or f.endswith('.mp3')])
    replicate_cost = replicate_runs * 0.005

# --- Twilio phone number cost: \$1.15/mo ---
twilio_number_cost = 1.15

# --- Output ---
result = {
    'timestamp': datetime.now(timezone.utc).isoformat(),
    'anthropic': {
        'total': round(total_cost, 2),
        'today': round(today_cost, 2),
        'requests': total_requests,
        'input_tokens': total_input,
        'output_tokens': total_output,
        'cache_read_tokens': total_cache_read,
        'by_model': {k: round(v, 2) for k, v in sorted(model_costs.items(), key=lambda x: -x[1])},
        'by_day': {k: round(v, 2) for k, v in sorted(daily_costs.items())}
    },
    'twilio': {
        'total': round(twilio_cost + twilio_number_cost, 2),
        'calls': twilio_calls,
        'call_cost': round(twilio_cost, 2),
        'number_cost': twilio_number_cost
    },
    'replicate': {
        'total': round(replicate_cost, 2),
        'runs': replicate_runs
    },
    'grand_total': round(total_cost + twilio_cost + twilio_number_cost + replicate_cost, 2)
}

print(json.dumps(result, indent=2))
"
