#!/usr/bin/env bash
set -euo pipefail

app_path="${1:-}"
budget_mib="${2:-5}"

if [[ -z "$app_path" || ! -d "$app_path" ]]; then
  echo "Usage: $0 /path/to/PopRocket.app [installed-budget-MiB]" >&2
  exit 2
fi
if ! [[ "$budget_mib" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Size budget must be a positive number of MiB." >&2
  exit 2
fi

installed_kib="$(du -sk "$app_path" | awk '{print $1}')"
installed_mib="$(awk -v kib="$installed_kib" 'BEGIN { printf "%.2f", kib / 1024 }')"
budget_kib="$(awk -v mib="$budget_mib" 'BEGIN { printf "%.0f", mib * 1024 }')"

archive_path="$(mktemp -t poprocket-size).zip"
trap 'rm -f "$archive_path"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
compressed_bytes="$(stat -f '%z' "$archive_path")"
compressed_mib="$(awk -v bytes="$compressed_bytes" 'BEGIN { printf "%.2f", bytes / 1048576 }')"

echo "Installed: ${installed_mib} MiB"
echo "Compressed: ${compressed_mib} MiB"
echo "Budget: ${budget_mib} MiB installed"

if (( installed_kib > budget_kib )); then
  echo "PopRocket exceeds the installed-size budget." >&2
  exit 1
fi
