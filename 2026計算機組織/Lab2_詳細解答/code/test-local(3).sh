#!/usr/bin/env bash
# Local feedback only. Reads the two current assembly files without a commit.
set -euo pipefail

expected_digest='sha256:f0ff938b7c554c1d021d5e91e31dfcbaeb810b88892dec6c0c404fac530b42db'
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
error() { printf 'ERROR：%s\n' "$*" >&2; exit 2; }
trap 'error "測試工具遇到非預期錯誤（第 ${LINENO} 行）；請保留上方訊息並聯絡助教。"' ERR

[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 && -f /.dockerenv ]] ||
    error '請在 Lab 0 的課程容器內執行。'
for executable in git sudo python3; do
    command -v "$executable" >/dev/null 2>&1 || error "找不到 $executable。"
done
[[ -x /opt/lab2-grader/grade-one && -f /opt/lab2-tools/lab2-tools-lock.json ]] ||
    error '本機測試工具尚未安裝，請先執行 ./setup-local-test.sh。'
[[ -d "$repo_root/.git" ]] || error '請在你自己的 Lab 2 作業 repo 內執行。'
[[ "$repo_root" == /home/ubuntu/workspace/* ]] || error '作業須位於課程容器的工作區。'

python3 - "$expected_digest" <<'PY' || error '批改工具版本與課程正式版本不符。'
import json, pathlib, sys
try:
    lock = json.loads(pathlib.Path('/opt/lab2-tools/lab2-tools-lock.json').read_text())
    if lock['grader_image'] != 'ghcr.io/computer-organization-at-ncku-ee/co-lab2-grader-v2@' + sys.argv[1]:
        raise ValueError('unexpected grader version')
except (OSError, ValueError, KeyError, TypeError):
    raise SystemExit(1)
PY

# HEAD is only a reproducible test seed. The grader reads saved working files.
commit="$(git -C "$repo_root" rev-parse --verify HEAD 2>/dev/null)" ||
    error '作業 repo 沒有可用的 commit。'
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || error '無法取得有效的測試種子。'

temporary="$(sudo mktemp -d /tmp/lab2-self-test.XXXXXXXX)" ||
    error '無法建立批改暫存資料夾。'
[[ "$temporary" =~ ^/tmp/lab2-self-test\.[A-Za-z0-9]{8}$ ]] ||
    error '批改暫存路徑異常。'
trap 'sudo rm -r -- "$temporary"' EXIT

printf '正在測試目前已儲存的兩份組合語言程式，請稍候。\n'
if ! sudo env \
    PATH='/opt/riscv-gnu-toolchain/bin:/usr/local/bin:/usr/bin:/bin' \
    LAB2_WORKER_USER=lab2worker \
    LAB2_GRADER_IMAGE_DIGEST="$expected_digest" \
    /opt/lab2-grader/grade-one \
    --submission "$repo_root" \
    --owner local \
    --commit "$commit" \
    --manifest lab2-v1 \
    --output-dir "$temporary" >/dev/null; then
    error '批改器執行失敗，請把上方訊息提供給助教。'
fi
sudo chown "$(id -u):$(id -g)" "$temporary" "$temporary/grade.json" "$temporary/audit.json" ||
    error '批改器未產生完整結果。'
chmod 0700 "$temporary"
chmod 0600 "$temporary/grade.json" "$temporary/audit.json"

if python3 - "$temporary/grade.json" "$temporary/audit.json" "$expected_digest" <<'PY'
import json, pathlib, sys
try:
    grade = json.loads(pathlib.Path(sys.argv[1]).read_text())
    audit = json.loads(pathlib.Path(sys.argv[2]).read_text())
    rows = grade['rows']
    expected_ids = ['C01', 'C02'] + [f'M{i:02d}' for i in range(1, 22)] + [f'S{i:02d}' for i in range(1, 21)]
    score = grade['score']
    valid = (
        grade['schema'] == 'ncku-co/lab2-grade/v1'
        and audit['schema'] == 'ncku-co/lab2-audit/v1'
        and audit['infrastructure_error'] is False
        and audit['grader']['image_digest'] == sys.argv[3]
        and grade['manifest']['version'] == 'lab2-v1'
        and [row['id'] for row in rows] == expected_ids
        and sum(row['max_score'] for row in rows) == 100
        and sum(row['score'] for row in rows) == score
        and grade['max_score'] == 100
        and type(score) is int and 0 <= score <= 100
        and all(
            type(row['score']) is int and type(row['max_score']) is int
            and 0 <= row['score'] <= row['max_score']
            and type(row['passed']) is bool
            and row['passed'] == (row['score'] == row['max_score'])
            for row in rows
        )
    )
    if not valid:
        raise ValueError('批改結果格式、配分或工具版本不符')
    if score == 100:
        if not all(row['passed'] for row in rows):
            raise ValueError('100 分結果仍含失敗測試列')
        print('PASS：本機測試全部通過（100/100）。')
    else:
        first = next(row for row in rows if not row['passed'])
        message = first['message'].replace('\n', ' ').replace('\r', ' ')[:240]
        print(f'FAIL：本機測試未全通過（{score}/100）。')
        print(f"第一項失敗：{first['id']} {first['reason']} — {message}")
        raise SystemExit(1)
except (OSError, KeyError, TypeError, ValueError, IndexError, StopIteration) as exc:
    print(f'ERROR：無法確認批改結果：{exc}', file=sys.stderr)
    raise SystemExit(2)
PY
then
    exit 0
else
    exit $?
fi
