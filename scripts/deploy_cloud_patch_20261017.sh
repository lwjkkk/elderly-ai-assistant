#!/usr/bin/env bash
set -Eeuo pipefail

APP=/root/silver_agent_backend
SERVICE=elderly-ai-backend
PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test -f "$PACKAGE_ROOT/api/medication_recognition.py"
cd "$APP"
test -x venv/bin/python
BACKUP="$APP/deploy_backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP/api"
cp main.py "$BACKUP/main.py"
cp api/bind.py "$BACKUP/api/bind.py"
if [ -f api/medication_recognition.py ]; then
  cp api/medication_recognition.py "$BACKUP/api/medication_recognition.py"
fi

rollback() {
  trap - ERR
  echo "更新失败，正在恢复原文件：$BACKUP"
  cp "$BACKUP/main.py" main.py
  cp "$BACKUP/api/bind.py" api/bind.py
  if [ -f "$BACKUP/api/medication_recognition.py" ]; then
    cp "$BACKUP/api/medication_recognition.py" api/medication_recognition.py
  else
    rm -f api/medication_recognition.py
  fi
  systemctl restart "$SERVICE" || true
  journalctl -u "$SERVICE" -n 35 --no-pager || true
  exit 1
}
trap rollback ERR

cp "$PACKAGE_ROOT/api/medication_recognition.py" "$BACKUP/medication_recognition.new.py"
venv/bin/python - "$BACKUP/medication_recognition.new.py" <<'PY'
import ast, pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
ast.parse(source)
if '/recognize-instructions' not in source:
    raise RuntimeError('下载内容不是预期接口')
main = pathlib.Path('main.py').read_text()
if 'from api.medication_recognition import router as medication_recognition_router' not in main:
    anchor = 'from api.meds import router as meds_router'
    if anchor not in main:
        raise RuntimeError('云端 main.py 结构不同，请保留备份并人工检查')
    main = main.replace(anchor, anchor + '\nfrom api.medication_recognition import router as medication_recognition_router', 1)
if 'app.include_router(medication_recognition_router)' not in main:
    main += '\napp.include_router(medication_recognition_router)\n'
binding = pathlib.Path('api/bind.py').read_text()
if '"other_avatar"' not in binding and "'other_avatar'" not in binding:
    lines = binding.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if '"other_nickname":' in line or "'other_nickname':" in line:
            indent = line[:len(line) - len(line.lstrip())]
            lines.insert(index + 1, indent + '"other_avatar": other.avatar_url if other else None,\n')
            break
    else:
        raise RuntimeError('云端绑定接口结构不同，请人工检查')
    binding = ''.join(lines)
ast.parse(main)
ast.parse(binding)
pathlib.Path('main.py').write_text(main)
pathlib.Path('api/bind.py').write_text(binding)
pathlib.Path('api/medication_recognition.py').write_text(source)
PY

# 导入校验不会启动服务；缺失依赖时立即恢复，不影响现有进程。
venv/bin/python -c 'from api.medication_recognition import router; from api.bind import router as binding_router'

if ! systemctl cat "$SERVICE.service" >/dev/null 2>&1; then
  cat >"/etc/systemd/system/$SERVICE.service" <<'UNIT'
[Unit]
Description=Elderly AI Assistant Backend
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/silver_agent_backend
ExecStart=/root/silver_agent_backend/venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
fi
systemctl daemon-reload
systemctl stop "$SERVICE" || true

# 兼容之前的 nohup 部署，只停止当前项目的 uvicorn 进程。
venv/bin/python - <<'PY'
import os, pathlib, signal, time
target = pathlib.Path.cwd().resolve()
for proc in pathlib.Path('/proc').iterdir():
    if not proc.name.isdigit():
        continue
    try:
        args = (proc / 'cmdline').read_bytes().split(b'\0')
        if b'uvicorn' in args and b'main:app' in args and (proc / 'cwd').resolve() == target:
            os.kill(int(proc.name), signal.SIGTERM)
    except (OSError, ProcessLookupError):
        pass
time.sleep(2)
PY
systemctl enable "$SERVICE"
systemctl start "$SERVICE"

for attempt in $(seq 1 20); do
  if curl --fail --silent --max-time 3 http://127.0.0.1:8000/openapi.json >"$BACKUP/openapi.json"; then
    if venv/bin/python -c 'import json,sys; paths=json.load(open(sys.argv[1]))["paths"]; assert "/api/meds/recognize-instructions" in paths' "$BACKUP/openapi.json"; then
      systemctl is-active --quiet "$SERVICE"
      trap - ERR
      echo "更新成功：说明书识别接口已上线，绑定列表已支持真实头像。"
      echo "原文件备份：$BACKUP"
      systemctl status "$SERVICE" --no-pager
      exit 0
    fi
  fi
  sleep 2
done
false
