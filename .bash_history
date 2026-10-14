marker = """  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.flushHeaders();
  const emit = (o: object) => res.write(`data: ${JSON.stringify(o)}\\n\\n`);

  try {
    saveMessage(sid, 'user', message);
    for (let r = 0; r < rounds; r++) {"""

replacement = """  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.flushHeaders();
  const emit = (o: object) => res.write(`data: ${JSON.stringify(o)}\\n\\n`);

  // verify llama is up before starting the loop
  try {
    const h = await fetch('http://127.0.0.1:8081/health', { signal: AbortSignal.timeout(2000) });
    if (!h.ok) throw new Error('llama not ready');
  } catch {
    emit({ type: 'error', message: 'llama-server not ready — run: notbots-make up' });
    res.end();
    return;
  }

  try {
    saveMessage(sid, 'user', message);
    for (let r = 0; r < rounds; r++) {"""

if marker in s:
    s = s.replace(marker, replacement)
    p.write_text(s)
    print("loop route guard added")
else:
    print("marker not found — route may differ; check src/agent.ts")
PYEOF

grep -c "llama-server not ready" src/agent.ts
notbots-make down
sleep 2
notbots-make up
sleep 5
notbots status
notbots new
notbots swarm "reverse a string" --roles coder,reviewer --rounds 1
notbots-make up
notbots new
notbots swarm "reverse a string" --roles coder,reviewer --rounds 1
cat > ~/monolith/data/.paths << 'EOF'
LLAMA_SERVER="/data/data/com.termux/files/home/monolith/llama.cpp/build/bin/llama-server"
LLAMA_CLI="/data/data/com.termux/files/home/monolith/llama.cpp/build/bin/llama-cli"
MODEL="/data/data/com.termux/files/home/monolith/models/qwen.gguf"
EOF

cat ~/monolith/data/.paths
ls -la ~/monolith/llama.cpp/build/bin/llama-server ~/monolith/models/qwen.gguf
cat ~/monolith/scripts/llm-server.sh
cat > ~/monolith/scripts/llm-server.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
[ -f data/.paths ] && source data/.paths

[ -z "$LLAMA_SERVER" ] && { echo "LLAMA_SERVER empty in data/.paths"; exit 1; }
[ -z "$MODEL" ] && { echo "MODEL empty in data/.paths"; exit 1; }
[ ! -x "$LLAMA_SERVER" ] && { echo "not executable: $LLAMA_SERVER"; exit 1; }
[ ! -f "$MODEL" ] && { echo "not found: $MODEL"; exit 1; }

echo "🧠 llama-server: $(basename $MODEL)"
exec "$LLAMA_SERVER" -m "$MODEL" --host 127.0.0.1 --port 8081 \
    -c 4096 -t "$(nproc)" --parallel 1 > logs/llama.log 2>&1
EOF

chmod +x ~/monolith/scripts/llm-server.sh
cd ~/monolith
mkdir -p logs
bash scripts/llm-server.sh &
sleep 20
curl -s http://127.0.0.1:8081/health
echo ""
tail -10 logs/llama.log
python3 << 'PYEOF'
import pathlib
p = pathlib.Path.home() / "monolith" / "scripts" / "wire.sh"
s = p.read_text()

# replace the .paths write block with a safe version that validates before writing
old_start = s.find('cat > .paths <<')
if old_start == -1:
    old_start = s.find('cat > data/.paths <<')

if old_start >= 0:
    old_end = s.find('PATHSEOF', old_start) + len('PATHSEOF')
    old_end = s.find('\n', old_end)
    new_block = '''# write .paths ONLY if both real values found
if [ -n "$LLAMA_SERVER" ] && [ -n "$MODEL" ] && [ -x "$LLAMA_SERVER" ] && [ -f "$MODEL" ] && [ "$(stat -c%s "$MODEL" 2>/dev/null)" -gt 50000000 ]; then
    cat > data/.paths << PATHSEOF
LLAMA_SERVER="$LLAMA_SERVER"
LLAMA_CLI="${LLAMA_SERVER%/*}/llama-cli"
MODEL="$MODEL"
PATHSEOF
    ln -sf data/.paths .paths
    echo "✅ wrote data/.paths"
else
    echo "⚠  keeping existing .paths (missing or invalid binary/model)"
fi
'''
    s = s[:old_start] + new_block + s[old_end:]
    p.write_text(s)
    print("wire.sh patched")
else:
    print("no .paths write found in wire.sh — manual inspection needed")
PYEOF

grep -A6 "keeping existing" ~/monolith/scripts/wire.sh | head -10
notbots-make down
sleep 2
notbots-make up
sleep 30
notbots status
exit
cat > ~/monolith/scripts/seek.sh << 'SEEK_EOF'
#!/bin/bash
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
R=$PWD
echo "seeking issues in $R"
echo "─────────────────────────────────────"
ISSUES=0
note() { echo "  $1"; }
issue() { echo "  ❌ $1"; ISSUES=$((ISSUES+1)); }
warn() { echo "  ⚠  $1"; }

# 1. files
echo ""
echo "1. files"
[ -f Makefile ] || issue "Makefile missing"
[ -f bin/notbots ] || issue "bin/notbots missing"
[ -f src/agent.ts ] || issue "src/agent.ts missing"
[ -f package.json ] || issue "package.json missing"
[ -f tsconfig.json ] || issue "tsconfig.json missing"
[ -f scripts/run.sh ] || issue "scripts/run.sh missing"
[ -f scripts/stop.sh ] || issue "scripts/stop.sh missing"
[ -f scripts/llm-server.sh ] || issue "scripts/llm-server.sh missing"
[ -f scripts/swarm.sh ] || issue "scripts/swarm.sh missing"
[ -f scripts/manifest.sh ] || issue "scripts/manifest.sh missing"
[ -f data/.paths ] || issue "data/.paths missing"
[ -f config/.env ] || issue "config/.env missing"
[ -d node_modules ] || issue "node_modules missing — run npm install"
[ -d manifests ] || warn "manifests/ missing (empty is ok)"
[ $ISSUES -eq 0 ] && note "all required files present"

# 2. package.json
echo ""
echo "2. package.json"
if jq -e '.type == "module"' package.json >/dev/null 2>&1; then
    note "type=module ok"
else
    issue "type=module missing — agent.ts won't run"
fi
for pkg in express dotenv @google/generative-ai; do
    [ -d "node_modules/$pkg" ] && note "$pkg ok" || issue "$pkg not installed"
done

# 3. paths
echo ""
echo "3. data/.paths"
if [ -f data/.paths ]; then
    source data/.paths
    [ -n "$LLAMA_SERVER" ] && [ -x "$LLAMA_SERVER" ] \
        && note "LLAMA_SERVER ok" \
        || issue "LLAMA_SERVER empty or not executable: '$LLAMA_SERVER'"
    [ -n "$MODEL" ] && [ -f "$MODEL" ] \
        && note "MODEL ok" \
        || issue "MODEL empty or missing: '$MODEL'"
    if [ -f "$MODEL" ]; then
        SZ=$(stat -c%s "$MODEL" 2>/dev/null || echo 0)
        if [ "$SZ" -lt 50000000 ]; then
            issue "MODEL is only $((SZ/1024))K — likely a vocab file, not a real model"
        else
            note "MODEL size ok ($((SZ/1024/1024))MB)"
        fi
    fi
fi

# 4. scripts — correct cd and content
echo ""
echo "4. scripts"
for f in scripts/run.sh scripts/stop.sh scripts/llm-server.sh scripts/swarm.sh scripts/manifest.sh; do
    [ -f "$f" ] || continue
    head2=$(sed -n '2p' "$f")
    echo "$head2" | grep -q 'readlink -f' \
        && note "$(basename $f) cd-safe" \
        || warn "$(basename $f) not cd-safe: $head2"
    bash -n "$f" 2>/dev/null \
        && note "$(basename $f) syntax ok" \
        || issue "$(basename $f) syntax error"
done

# 5. CLI syntax
echo ""
echo "5. bin/notbots"
if bash -n bin/notbots 2>/dev/null; then
    note "syntax ok"
    # detect duplicate mark() or stacked functions
    N=$(grep -c '^mark()' bin/notbots)
    [ "$N" -gt 1 ] && issue "duplicate mark() functions ($N)" || note "no duplicate functions"
    grep -q '^status()' bin/notbots && note "status() present" || warn "no status() function"
else
    issue "syntax error in bin/notbots"
    bash -n bin/notbots 2>&1 | head -3 | sed 's/^/    /'
fi

# 6. install
echo ""
echo "6. global install"
[ -f "$PREFIX/bin/notbots" ] && note "$PREFIX/bin/notbots ok" || warn "not installed globally"
[ -f "$PREFIX/bin/notbots-make" ] && note "$PREFIX/bin/notbots-make ok" || warn "notbots-make not installed"

# 7. processes
echo ""
echo "7. processes"
if curl -s --max-time 1 http://127.0.0.1:8080/health >/dev/null 2>&1; then
    note "agent :8080 up"
    H=$(curl -s http://127.0.0.1:8080/health)
    DB=$(echo "$H" | jq -r '.db')
    [ "$DB" = "connected" ] && note "db connected" || issue "db not connected: $DB"
else
    warn "agent :8080 down"
fi
if curl -s --max-time 1 http://127.0.0.1:8081/health >/dev/null 2>&1; then
    note "llama :8081 up"
else
    warn "llama :8081 down"
fi

# 8. stale pid
echo ""
echo "8. runtime state"
if [ -f data/.agent.pid ]; then
    PID=$(cat data/.agent.pid)
    kill -0 "$PID" 2>/dev/null && note "pid $PID alive" || warn "stale pid $PID"
fi
[ -f data/.session ] && note "session: $(cut -c1-8 data/.session)" || warn "no session file"

# 9. logs — look for errors
echo ""
echo "9. recent log errors"
if [ -f logs/agent.log ]; then
    ERRS=$(grep -cE 'Error|error:|throw|TypeError|SyntaxError' logs/agent.log 2>/dev/null || echo 0)
    [ "$ERRS" -gt 0 ] && warn "$ERRS error lines in agent.log" || note "agent.log clean"
fi
if [ -f logs/llama.log ]; then
    ERRS=$(grep -cE 'error|Error' logs/llama.log 2>/dev/null || echo 0)
    [ "$ERRS" -gt 0 ] && warn "$ERRS error lines in llama.log" || note "llama.log clean"
fi

# 10. endpoint routes — test each
echo ""
echo "10. endpoint routes"
if curl -s --max-time 1 http://127.0.0.1:8080/health >/dev/null 2>&1; then
    SID=$(cat data/.session 2>/dev/null)
    for path in "/health" "/v1/sessions" "/v1/manifests"; do
        code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:8080$path")
        [ "$code" = "200" ] && note "GET $path → $code" || issue "GET $path → $code"
    done
    if [ -n "$SID" ]; then
        code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:8080/v1/session/$SID")
        [ "$code" = "200" ] && note "GET /v1/session/<id> → $code" || issue "GET /v1/session/<id> → $code"
        # loop route only exists if swarm is wired
        code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:8080/v1/session/$SID/loop" \
               -H 'Content-Type: application/json' -d '{"message":"ping","roles":["a","b"],"rounds":1}')
        [ "$code" = "200" ] && note "POST /v1/session/<id>/loop → $code" || warn "POST /v1/session/<id>/loop → $code (may not exist)"
    fi
fi

# 11. manifests
echo ""
echo "11. manifests"
if [ -d manifests ] && [ "$(ls -1 manifests/*.json 2>/dev/null | wc -l)" -gt 0 ]; then
    for m in manifests/*.json; do
        jq -e . "$m" >/dev/null 2>&1 && note "$(basename $m) valid" || issue "$(basename $m) invalid JSON"
    done
else
    warn "no manifest files"
fi

echo ""
echo "─────────────────────────────────────"
[ "$ISSUES" -eq 0 ] && echo "✅ no blocking issues" || echo "❌ $ISSUES issue(s) found"
exit $ISSUES
SEEK_EOF

chmod +x ~/monolith/scripts/seek.sh
bash ~/monolith/scripts/seek.sh
cd ~/monolith
python3 << 'PYEOF'
import pathlib
p = pathlib.Path("src/agent.ts")
s = p.read_text()

if "'/v1/manifests'" not in s:
    route = '''

// ── manifests listing ──
import type { Request as R2, Response as Re2 } from 'express';
app.get('/v1/manifests', (_req: R2, res: Re2) => {
  const dir = path.join(ROOT, 'manifests');
  if (!fs.existsSync(dir)) { res.json([]); return; }
  const names = fs.readdirSync(dir)
    .filter(f => f.endsWith('.json'))
    .map(f => f.replace(/\\.manifest\\.json$/, '').replace(/\\.json$/, ''));
  res.json(names);
});
'''
    s = s.rstrip() + route
    p.write_text(s)
    print("route added")
else:
    print("already present")
PYEOF

grep -c "'/v1/manifests'" src/agent.ts
cd ~/monolith
mkdir -p manifests
cat > manifests/main.manifest.json << 'EOF'
{
  "name": "main",
  "prompt": "{{input}}",
  "rounds": 2,
  "roles": [
    { "name": "coder",    "system": "You write code. Output only code blocks." },
    { "name": "reviewer", "system": "You find flaws. Bullets only." },
    { "name": "tester",   "system": "You write tests. Code blocks only." }
  ]
}
EOF

cat > manifests/code_review.json << 'EOF'
{
  "name": "code_review",
  "prompt": "Review this code and produce a fix:\n\n{{input}}",
  "rounds": 1,
  "roles": [
    { "name": "reader", "system": "Describe what the code does. 3 bullets." },
    { "name": "critic", "system": "List flaws. Bullets only." },
    { "name": "fixer",  "system": "Output corrected code. Code block only." }
  ]
}
EOF

cat > manifests/research.json << 'EOF'
{
  "name": "research",
  "prompt": "Briefly research:\n\n{{input}}",
  "rounds": 1,
  "roles": [
    { "name": "scout",   "system": "List facts. 5 bullets max." },
    { "name": "analyst", "system": "Find patterns. 3 bullets." },
    { "name": "writer",  "system": "Summarize in 3 sentences." }
  ]
}
EOF

ls manifests/
sed -i 's|ERRS=$(grep -cE .*|| echo 0)|ERRS=$(grep -cE "Error\|error:\|throw\|TypeError\|SyntaxError" logs/agent.log 2>/dev/null \| head -1)|' ~/monolith/scripts/seek.sh 2>/dev/null
# safer: direct rewrite of just those two lines
python3 << 'PYEOF'
import pathlib
p = pathlib.Path.home() / "monolith" / "scripts" / "seek.sh"
s = p.read_text()

# fix agent.log error count
s = s.replace(
  "ERRS=$(grep -cE 'Error|error:|throw|TypeError|SyntaxError' logs/agent.log 2>/dev/null || echo 0)",
  "ERRS=$(grep -cE 'Error|error:|throw|TypeError|SyntaxError' logs/agent.log 2>/dev/null | head -1)\n    [ -z \"$ERRS\" ] && ERRS=0"
)
# fix llama.log error count
s = s.replace(
  "ERRS=$(grep -cE 'error|Error' logs/llama.log 2>/dev/null || echo 0)",
  "ERRS=$(grep -cE 'error|Error' logs/llama.log 2>/dev/null | head -1)\n    [ -z \"$ERRS\" ] && ERRS=0"
)
p.write_text(s)
print("seek.sh patched")
PYEOF

notbots-make restart
sleep 20
notbots-make seek
cd
cd ~/monolith
python3 << 'PYEOF'
import pathlib
p = pathlib.Path("Makefile")
s = p.read_text()
if "\nseek:" not in s:
    s = s.rstrip() + "\n\nseek: ; @bash scripts/seek.sh\n"
    p.write_text(s)
    print("seek target added")
else:
    print("already present")
PYEOF

grep -n "^seek:" Makefile
vd
cd
cd ~/monolith
python3 << 'PYEOF'
import pathlib
p = pathlib.Path("src/agent.ts")
s = p.read_text()
if "'/v1/manifests'" not in s:
    route = '''

// ── manifests listing ──
app.get('/v1/manifests', (_req: Request, res: Response) => {
  const dir = path.join(ROOT, 'manifests');
  if (!fs.existsSync(dir)) { res.json([]); return; }
  const names = fs.readdirSync(dir)
    .filter(f => f.endsWith('.json'))
    .map(f => f.replace(/\\.manifest\\.json$/, '').replace(/\\.json$/, ''));
  res.json(names);
});
'''
    s = s.rstrip() + route
    p.write_text(s)
    print("route added")
else:
    print("already present")
PYEOF

grep -c "'/v1/manifests'" src/agent.ts
notbots-make restart
sleep 20
notbots-make seek
cd
cat > scripts/dist.sh << 'DIST_EOF'
#!/bin/bash
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
set -e

OUT="dist/notbots-v1"
rm -rf "$OUT"
mkdir -p "$OUT"/{bin,models,manifests,soul,config,data/db,logs,scripts}

echo "▶ 1/6 bundle + SEA"
npm install -D esbuild --quiet
mkdir -p dist
npx esbuild src/agent.ts --bundle --platform=node --format=cjs \
  --outfile=dist/bundle.cjs --external:node:*

cat > dist/sea-config.json << CONF
{
  "main": "dist/bundle.cjs",
  "output": "$OUT/bin/notbots-agent",
  "disableExperimentalSEAWarning": true,
  "useCodeCache": true
}
CONF
node --build-sea dist/sea-config.json

echo "▶ 2/6 copy llama-server"
[ -x llama.cpp/build/bin/llama-server ] && \
  cp llama.cpp/build/bin/llama-server "$OUT/bin/" || \
  echo "  ⚠  llama-server missing"

echo "▶ 3/6 copy model"
[ -f models/qwen.gguf ] && \
  cp models/qwen.gguf "$OUT/models/" || \
  echo "  ⚠  model missing"

echo "▶ 4/6 copy config"
cp manifests/*.json "$OUT/manifests/" 2>/dev/null || true
cp soul/*.md "$OUT/soul/" 2>/dev/null || true
cp config/.env "$OUT/config/" 2>/dev/null || true
cp scripts/*.sh "$OUT/scripts/" 2>/dev/null || true
cp scripts/llm-server.sh "$OUT/scripts/" 2>/dev/null || true

echo "▶ 5/6 CLI wrapper"
cat > "$OUT/bin/notbots" << 'WRAP'
#!/bin/bash
R="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
cd "$R"
[ -f data/.paths ] || cat > data/.paths << P
LLAMA_SERVER="$R/bin/llama-server"
MODEL="$R/models/qwen.gguf"
P
exec "$R/bin/notbots-agent" "$@"
WRAP
chmod +x "$OUT/bin/notbots"

echo "▶ 6/6 done"
du -sh "$OUT"
find "$OUT" -maxdepth 2 -type f | sort
DIST_EOF

chmod +x scripts/dist.sh
# add to Makefile
cat >> Makefile << 'EOF'

dist: ; @bash scripts/dist.sh
EOF

