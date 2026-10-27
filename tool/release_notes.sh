#!/usr/bin/env bash
# 릴리스 노트를 만든다: 이전 태그 이후의 커밋 제목 목록 + 비교 링크.
# release.yml에서 쓰고, 로컬에서도 미리 볼 수 있다.
#
#   tool/release_notes.sh v1.1.0 kim2214/ChzzkMultiviewer
set -euo pipefail

tag="$1"
repo="$2"

# 이 태그 바로 전의 태그. 첫 릴리스면 비어 있다.
# 정식 릴리스는 시험판(하이픈이 들어간 태그)을 건너뛰고 이전 정식 릴리스와 비교한다.
exclude=()
if [[ "$tag" != *-* ]]; then exclude=(--exclude '*-*'); fi
previous=$(git describe --tags --abbrev=0 "${exclude[@]}" "${tag}^" 2>/dev/null || true)
range="${previous:+${previous}..}${tag}"

echo "## 변경 사항"
echo
git log --no-merges --reverse --format='- %s (%h)' "$range"
echo
if [ -n "$previous" ]; then
  echo "**전체 비교**: https://github.com/${repo}/compare/${previous}...${tag}"
else
  echo "**전체 커밋**: https://github.com/${repo}/commits/${tag}"
fi
