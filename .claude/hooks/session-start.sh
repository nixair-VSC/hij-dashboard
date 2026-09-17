#!/bin/bash
# HIJ 대시보드 — 세션 시작 시 기기 간 인계 상태 브리핑 + 기기 환경 동기화.
#
# 목적: 데스크탑1·데스크탑2·핸드폰(클라우드 세션)을 오가며 작업할 때
#   (A) 오래된 상태 위에서 작업을 시작하거나 푸시를 빠뜨리는 사고를 막고,
#   (B) 각 기기의 설치 도구·디렉토리·파일 구성을 저장소에 기록해 서로 볼 수 있게 한다.
#
# 이 저장소는 빌드 도구·패키지 의존성·테스트가 없는 단일 파일 정적 HTML 앱이라
# 설치할 의존성은 없다. 대신 "이 기기에 무엇이 있는지"를 스냅샷으로 남긴다.
#
# 원격(claude.ai/code)뿐 아니라 로컬 터미널 세션에서도 동작한다 — 기기 간 동기화가
# 목적이므로 CLAUDE_CODE_REMOTE로 제한하지 않는다.
# 어떤 경우에도 세션 시작을 막지 않는다(항상 exit 0).

set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" 2>/dev/null || exit 0
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# ---------------------------------------------------------------- A. 인계 상태
echo "=== HIJ 대시보드 · 작업 인계 상태 ==="

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
echo "브랜치: $branch"

# 원격 최신 상태를 반영해 ahead/behind를 계산한다 (네트워크 없으면 조용히 건너뜀).
git fetch --quiet origin "$branch" 2>/dev/null

upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
if [ -n "$upstream" ]; then
  counts=$(git rev-list --left-right --count "$upstream"...HEAD 2>/dev/null || printf '0\t0')
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

dirty=$(git status --porcelain 2>/dev/null | grep -v '\.claude/devices/' | wc -l | tr -d ' ')
if [ "$dirty" != "0" ]; then
  echo "⚠ 커밋 안 된 변경 $dirty건:"
  git status --short 2>/dev/null | grep -v '\.claude/devices/' | head -10
fi

last=$(git log -1 --format='%h  %ad  %an  %s' --date=format:'%Y-%m-%d %H:%M' 2>/dev/null || true)
[ -n "$last" ] && echo "마지막 커밋: $last"

# 아카이브본이 정규본과 갈라진 상태인지 확인 — 실수로 구버전을 고치는 것을 막는다.
archive="HIJ_AI_자동화_진행현황.html"
if [ -f "$archive" ] && [ -f index.html ] && ! cmp -s "$archive" index.html; then
  echo "참고: $archive 는 구버전 아카이브. 수정은 index.html 에만."
fi

# ------------------------------------------------------- B. 기기 환경 스냅샷
# 각 기기가 자기 환경을 .claude/devices/<기기ID>.md 에 기록한다.
# 이 파일이 커밋되어야 다른 기기에서 보인다 — 훅은 쓰기만 하고 커밋하지 않는다
# (사용자 작업 중에 임의로 커밋을 만들지 않기 위해서).

if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  device_id="cloud-session"
else
  device_id=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)
fi
# 파일명에 안전한 문자만 남긴다.
device_id=$(echo "$device_id" | tr -cd 'A-Za-z0-9._-' | cut -c1-40)
[ -z "$device_id" ] && device_id="unknown"

mkdir -p .claude/devices 2>/dev/null
snapshot=".claude/devices/${device_id}.md"
previous=""
[ -f "$snapshot" ] && previous=$(cat "$snapshot" 2>/dev/null)

# 도구 버전 수집 — 없는 도구는 건너뛴다.
tool_lines=""
for tool in git python3 node npm php ruby; do
  if command -v "$tool" >/dev/null 2>&1; then
    ver=$("$tool" --version 2>&1 | head -1 | tr -d '\r')
    tool_lines="${tool_lines}- ${tool}: ${ver}"$'\n'
  fi
done

# 저장소 파일 인벤토리 — 추적 파일과 (이 기기에만 있는) 미추적 파일.
tracked=$(git -c core.quotepath=false ls-files 2>/dev/null | head -40)
untracked=$(git -c core.quotepath=false ls-files --others --exclude-standard 2>/dev/null \
            | grep -v '^\.claude/devices/' | head -20)

{
  echo "# 기기: ${device_id}"
  echo
  echo "세션 시작 시 자동 생성됨. 직접 편집하지 말 것."
  echo
  echo "## 환경"
  echo "- OS: $(uname -s 2>/dev/null) $(uname -r 2>/dev/null) ($(uname -m 2>/dev/null))"
  echo "- 저장소 경로: $(pwd)"
  echo "- 세션 종류: $([ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && echo '클라우드 (claude.ai/code)' || echo '로컬 CLI')"
  echo "- 마지막 확인: $(date '+%Y-%m-%d %H:%M %z' 2>/dev/null)"
  echo
  echo "## 설치된 도구"
  if [ -n "$tool_lines" ]; then printf '%s' "$tool_lines"; else echo "- (없음)"; fi
  echo
  echo "## 추적 파일"
  if [ -n "$tracked" ]; then echo "$tracked" | sed 's/^/- /'; else echo "- (없음)"; fi
  echo
  echo "## 이 기기에만 있는 미추적 파일"
  if [ -n "$untracked" ]; then
    echo "$untracked" | sed 's/^/- /'
    echo
    echo "⚠ 커밋하지 않으면 다른 기기에서 볼 수 없다."
  else
    echo "- (없음)"
  fi
} > "$snapshot" 2>/dev/null

# '마지막 확인' 시각만 바뀐 경우는 실질 변화가 아니므로 제외하고 비교한다.
strip_ts() { grep -v '^- 마지막 확인:' 2>/dev/null; }
if [ -n "$previous" ]; then
  if ! diff -q <(printf '%s' "$previous" | strip_ts) \
               <(cat "$snapshot" 2>/dev/null | strip_ts) >/dev/null 2>&1; then
    echo "이 기기($device_id)의 환경이 지난 세션과 달라졌다 — $snapshot 갱신됨. 커밋 대상."
  fi
else
  echo "이 기기($device_id) 환경을 새로 기록했다 — $snapshot. 커밋 대상."
fi

# 다른 기기들의 스냅샷을 요약해 보여준다.
others=$(ls .claude/devices/*.md 2>/dev/null | grep -v "/${device_id}\.md$")
if [ -n "$others" ]; then
  echo "다른 기기 기록:"
  for f in $others; do
    name=$(basename "$f" .md)
    seen=$(grep -m1 '^- 마지막 확인:' "$f" 2>/dev/null | sed 's/^- 마지막 확인: //')
    echo "  - ${name} (최종 ${seen:-?})"
  done
fi

echo "=== 데이터는 브라우저 localStorage 저장 = 기기별로 분리됨. 영구 보존은 시드 커밋 ==="
exit 0
