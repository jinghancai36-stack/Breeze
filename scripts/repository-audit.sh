#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

failed=0

tracked_risky_paths=$(git ls-files | awk '
  /(^|\/)(build|dist|DerivedData|artifacts)\// ||
  /\.(p12|cer|mobileprovision)$/ { print }
')
if [ -n "$tracked_risky_paths" ]; then
  printf 'Error: generated output or credential-shaped files are tracked:\n%s\n' "$tracked_risky_paths" >&2
  failed=1
fi

large_files=$(git ls-files -z | xargs -0 stat -f '%z %N' | awk '$1 > 1048576 {print $2}')
if [ -n "$large_files" ]; then
  printf 'Error: tracked files larger than 1 MiB require review:\n%s\n' "$large_files" >&2
  failed=1
fi

secret_pattern='(BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,})'
if git grep -I -l -E "$secret_pattern" -- . ':!scripts/repository-audit.sh' 2>/dev/null | grep -q .; then
  printf 'Error: the current tree contains a credential-like pattern. Review locally without posting the match.\n' >&2
  failed=1
fi

history_hit=0
for commit in $(git rev-list --all); do
  if git grep -I -l -E "$secret_pattern" "$commit" -- . ':!scripts/repository-audit.sh' 2>/dev/null | grep -q .; then
    history_hit=1
    break
  fi
done
if [ "$history_hit" -eq 1 ]; then
  printf 'Error: Git history contains a credential-like pattern. Review before publishing.\n' >&2
  failed=1
fi

if git log --all --format='%ae' | awk '
  NF && $0 !~ /@users\.noreply\.github\.com$/ && $0 !~ /@localhost$/ {found=1}
  END {exit !found}
'; then
  printf 'Notice: Git history contains a non-noreply author email. Confirm that it is acceptable before publishing.\n'
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi

printf 'Repository audit passed: no tracked build output, credential files, large files, or common secret patterns found.\n'
