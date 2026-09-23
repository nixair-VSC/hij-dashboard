#!/bin/bash
# 새 기기를 이 저장소의 기기 동기화에 등록한다.
#
# 사용법: 저장소 안에서  bash .claude/connect-device.sh
#
# 하는 일: 세션 시작 훅을 한 번 실행해 이 기기의 환경 스냅샷을 만들고,
# .claude/devices/ 변경분만 커밋해 푸시한다. 이 과정을 거쳐야 다른 기기에서
# 이 기기가 보인다.
#
# 소스 코드는 건드리지 않는다. .claude/devices/ 아래만 커밋한다.

set -uo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$root" ]; then
  echo "오류: git 저장소 안에서 실행해야 한다." >&2
  exit 1
fi
cd "$root" || exit 1

hook=".claude/hooks/session-start.sh"
if [ ! -f "$hook" ]; then
  echo "오류: $hook 이 없다. 이 설정이 들어간 브랜치를 체크아웃했는지 확인할 것." >&2
  exit 1
fi

echo "1) 이 기기의 환경을 기록한다..."
CLAUDE_PROJECT_DIR="$root" bash "$hook"
echo

echo "2) 기기 기록을 커밋한다..."
git add .claude/devices/ 2>/dev/null
if git diff --cached --quiet 2>/dev/null; then
  echo "   변경 없음 — 이미 등록되어 있다."
else
  git diff --cached --name-only | sed 's/^/   /'
  git commit -q -m "기기 등록: $(hostname -s 2>/dev/null || echo unknown)" || {
    echo "   커밋 실패." >&2; exit 1; }
  echo "   커밋 완료."
fi
echo

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
echo "3) 푸시한다 (브랜치: $branch)..."
if git push -u origin "$branch" 2>&1 | sed 's/^/   /'; then
  echo
  echo "완료. 이제 다른 기기에서도 이 기기가 보인다."
else
  echo
  echo "푸시 실패. 원격이 앞서 있으면 먼저 받아온 뒤 다시 실행할 것:" >&2
  echo "   git pull origin $branch && bash .claude/connect-device.sh" >&2
  exit 1
fi
