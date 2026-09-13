#!/usr/bin/env bash
# Monitor GitHub Actions run 34600319950 until completion.
RUN_ID=34600319950
API="https://api.github.com/repos/buudvh/FreeBook/actions/runs/${RUN_ID}"
MAX_ITER=50
SLEEP=60

for ((i=1;i<=MAX_ITER;i++)); do
  ts=$(date +%H:%M:%S)
  status=$(curl -s -H "Accept: application/vnd.github+json" "$API" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('status'),d.get('conclusion'))")
  echo "poll $i @ $ts -> $status"
  if [[ "$status" == *"completed"* ]]; then
    echo "=== RUN COMPLETE ==="
    curl -s -H "Accept: application/vnd.github+json" "$API" | python3 -c "import sys,json;d=json.load(sys.stdin);print('status:',d.get('status'));print('conclusion:',d.get('conclusion'));print('url:',d.get('html_url'))"
    echo "=== JOB / STEP BREAKDOWN ==="
    curl -s -H "Accept: application/vnd.github+json" "${API}/jobs" | python3 -c "import sys,json;d=json.load(sys.stdin);[print('JOB:',j['name'],'|',j['status'],'|',j['conclusion']) or [print('   -',s['name'],'|',s['status'],'|',s['conclusion']) for s in j['steps']] for j in d.get('jobs',[])]"
    exit 0
  fi
  sleep $SLEEP
done
echo "=== MONITOR TIMED OUT (run still in_progress after $((MAX_ITER*SLEEP))s) ==="
exit 1
