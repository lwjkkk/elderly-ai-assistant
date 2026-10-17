#!/usr/bin/env bash
set -Eeuo pipefail
APP=/root/silver_agent_backend
PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE=elderly-ai-backend
cd "$APP"
test -x venv/bin/python
systemctl cat "$SERVICE.service" >/dev/null
BACKUP="$APP/deploy_backups/media_$(date +%Y%m%d_%H%M%S)"
FILES=(api/messages.py core/speech_transcription.py api/users.py api/vitals.py api/reports.py api/consults.py core/consult_summary.py db/models.py db/schemas.py db/database.py)
for item in "${FILES[@]}"; do
  mkdir -p "$BACKUP/$(dirname "$item")"
  if [ -f "$item" ]; then cp "$item" "$BACKUP/$item"; fi
done

rollback() {
  trap - ERR
  echo "更新失败，恢复备份：$BACKUP"
  for item in "${FILES[@]}"; do
    if [ -f "$BACKUP/$item" ]; then cp "$BACKUP/$item" "$item"; else rm -f "$item"; fi
  done
  systemctl restart "$SERVICE" || true
  journalctl -u "$SERVICE" -n 30 --no-pager || true
  exit 1
}
trap rollback ERR
cp "$PACKAGE_ROOT/api/messages.py" api/messages.py
cp "$PACKAGE_ROOT/core/speech_transcription.py" core/speech_transcription.py
cp "$PACKAGE_ROOT/core/consult_summary.py" core/consult_summary.py
cp "$PACKAGE_ROOT/api/consults.py" api/consults.py

# 只在原接口文件中补充删除路由，保留云端原有的其他业务配置。
venv/bin/python - "$PACKAGE_ROOT" <<'PY'
import ast, pathlib, sys
source_root = pathlib.Path(sys.argv[1])
for filename, function in [('api/users.py', 'delete_avatar'),
                            ('api/vitals.py', 'delete_vital'),
                            ('api/reports.py', 'delete_report')]:
    target = pathlib.Path(filename)
    original = target.read_text(encoding='utf-8')
    if any(isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == function
           for n in ast.parse(original).body):
        continue
    source = (source_root / filename).read_text(encoding='utf-8')
    node = next(n for n in ast.parse(source).body
                if isinstance(n, ast.FunctionDef) and n.name == function)
    start = min([node.lineno] + [d.lineno for d in node.decorator_list]) - 1
    addition = '\n'.join(source.splitlines()[start:node.end_lineno])
    updated = original + '\n\n' + addition + '\n'
    ast.parse(updated)
    target.write_text(updated, encoding='utf-8')
# Only extend the consultation models; retain cloud-specific database settings.
fields = {'transcript', 'summary', 'summary_status', 'summary_error'}
for filename, classname in [('db/models.py', 'ConsultRecord'), ('db/schemas.py', 'ConsultOut')]:
    target = pathlib.Path(filename)
    original = target.read_text(encoding='utf-8')
    tree = ast.parse(original)
    cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == classname)
    def name(n):
        if isinstance(n, ast.AnnAssign): return n.target.id
        if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name): return n.targets[0].id
        return ''
    existing = {name(n) for n in cls.body}
    source = (source_root / filename).read_text(encoding='utf-8')
    source_cls = next(n for n in ast.parse(source).body if isinstance(n, ast.ClassDef) and n.name == classname)
    additions = ['\n'.join(source.splitlines()[n.lineno-1:n.end_lineno])
                 for n in source_cls.body if name(n) in fields - existing]
    lines = original.splitlines()
    lines[cls.end_lineno:cls.end_lineno] = additions
    updated = '\n'.join(lines) + '\n'
    ast.parse(updated)
    target.write_text(updated, encoding='utf-8')
target = pathlib.Path('db/database.py')
original = target.read_text(encoding='utf-8')
if 'ALTER TABLE consult_records ADD COLUMN' not in original:
    function = next(n for n in ast.parse(original).body if isinstance(n, ast.FunctionDef) and n.name == 'init_db')
    lines = original.splitlines()
    additions = ["    for column, sql_type in [('transcript', 'TEXT'), ('summary', 'TEXT'), ('summary_status', 'VARCHAR(20)'), ('summary_error', 'VARCHAR(200)')]:",
                 "        _add_column_if_missing('consult_records', column, f'ALTER TABLE consult_records ADD COLUMN {column} {sql_type}')"]
    lines[function.end_lineno:function.end_lineno] = additions
    updated = '\n'.join(lines) + '\n'
    ast.parse(updated)
    target.write_text(updated, encoding='utf-8')
PY

venv/bin/python -c 'from api.messages import router; from core.speech_transcription import transcribe_audio; from api.users import router; from api.vitals import router; from api.reports import router; from api.consults import router'
systemctl restart "$SERVICE"
for attempt in $(seq 1 20); do
  if curl --fail --silent --max-time 3 http://127.0.0.1:8000/openapi.json >"$BACKUP/openapi.json"; then
    if venv/bin/python - "$BACKUP/openapi.json" <<'PY'
import json, sys
paths = json.load(open(sys.argv[1]))['paths']
required = {
    '/api/consults/{consult_id}/summarize': 'post',
    '/api/consults/{consult_id}/summary': 'get',
    '/api/messages/{binding_id}/audio': 'post',
    '/api/messages/{binding_id}/{message_id}/transcribe': 'post',
    '/api/messages/{binding_id}/{message_id}': 'delete',
    '/api/users/avatar': 'delete', '/api/vitals/{vital_id}': 'delete',
    '/api/reports/{report_id}': 'delete', '/api/consults/{consult_id}': 'delete',
}
assert all(method in paths.get(path, {}) for path, method in required.items())
PY
    then
      systemctl is-active --quiet "$SERVICE"
      trap - ERR
      echo "更新成功：家人语音和图片持久化、按需转文字、本人上传记录删除、咨询录音 AI 摘要接口已上线。"
      echo "备份位置：$BACKUP"
      systemctl status "$SERVICE" --no-pager
      exit 0
    fi
  fi
  sleep 2
done
false
