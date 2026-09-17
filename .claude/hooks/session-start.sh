#!/bin/bash
# HIJ 대시보드 — 세션 시작 시 기기 간 인계 상태 브리핑.
#
# 이 저장소는 빌드 도구·패키지 의존성·테스트가 없는 단일 파일 정적 HTML 앱이라
# 설치할 것이 없다. 대신 데스크탑1·데스크탑2·핸드폰을 오가며 작업할 때 가장 흔한
# 사고(푸시 안 된 변경을 다른 기기에서 못 봄, 오래된 브랜치 위에서 작업 시작)를
# 막기 위해 현재 git 상태를 세션 시작 시점에 보여준다.
#
# 원격(claude.ai/code)뿐 아니라 로컬 터미널 세션에서도 동작한다 — 기기 간 인계가
# 목적이므로 CLAUDE_CODE_REMOTE로 제한하지 않는다.

set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || exit 0
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

echo "=== HIJ 대시보드 · 작업 인계 상태 ==="

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
echo "브랜치: $branch"

# 원격 최신 상태를 반영해 ahead/behind를 계산한다 (네트워크 없으면 조용히 건너뜀).
git fetch --quiet origin "$branch" 2>/dev/null

upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
if [ -n "$upstream" ]; then
  counts=$(git rev-list --left-right --count "$upstream"...HEAD 2>/dev/null || echo "0	0")
  behind=$(echo "$counts" | cut -f1)
  ahead=$(echo "$counts" | cut -f2)
  if [ "$ahead" != "0" ]; then
    echo "⚠ 푸시 안 된 커밋 $ahead개 — 푸시 전까지 다른 기기에서 보이지 않음"
  fi
  if [ "$behind" != "0" ]; then
    echo "⚠ 원격이 $behind개 앞섬 — 다른 기기의 작업분. 시작 전 git pull 필요"
  fi
  [ "$ahead" = "0" ] && [ "$behind" = "0" ] && echo "원격과 동기화됨 ($upstream)"
else
  echo "⚠ 원격 추적 브랜치 없음 — 첫 푸시는 git push -u origin $branch"
fi

dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$dirty" != "0" ]; then
  echo "⚠ 커밋 안 된 변경 $dirty건:"
  git status --short 2>/dev/null | head -10
fi

last=$(git log -1 --format='%h  %ad  %s' --date=format:'%Y-%m-%d %H:%M' 2>/dev/null || true)
[ -n "$last" ] && echo "마지막 커밋: $last"

# 아카이브본이 정규본과 갈라진 상태인지 확인 — 실수로 구버전을 고치는 것을 막는다.
archive="HIJ_AI_자동화_진행현황.html"
if [ -f "$archive" ] && [ -f index.html ] && ! cmp -s "$archive" index.html; then
  echo "참고: $archive 는 구버전 아카이브. 수정은 index.html 에만."
fi

echo "=== 데이터는 브라우저 localStorage 저장 = 기기별로 분리됨. 영구 보존은 시드 커밋 ==="
exit 0
