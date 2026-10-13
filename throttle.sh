#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

usage() {
  echo "Usage: bash throttle.sh {enable KBPS|disable|status}" >&2
  echo "KBPS is an integer from 8 to 1000000, e.g. 128 or 256 (kilobits/second)." >&2
}

case "${1:-}" in
  enable)
    rate="${2:-}"
    if [[ $# -ne 2 || ! "$rate" =~ ^[1-9][0-9]{0,6}$ ]]; then
      usage
      exit 1
    fi
    if (( rate < 8 || rate > 1000000 )); then
      usage
      exit 1
    fi
    bytes_per_second=$((rate * 1000 / 8))
    ;;
  disable|status)
    if [[ $# -ne 1 ]]; then
      usage
      exit 1
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac

if [[ "${1}" == status ]]; then
  cat throttle/limits.conf
  echo "This is the saved setting. Check 'bash proxy.sh status' for container state."
  exit 0
fi

# A directory mount lets Squid see atomic replacements without recreation.
docker compose exec -T squid test -r /etc/squid/throttle/limits.conf
previous="$(cat throttle/limits.conf)"
restore_setting() {
  printf '%s\n' "$previous" > throttle/limits.conf.new
  mv throttle/limits.conf.new throttle/limits.conf
}
trap 'rm -f throttle/limits.conf.new' EXIT

if [[ "${1}" == enable ]]; then
  printf 'delay_pools 1\ndelay_class 1 1\ndelay_parameters 1 %s/%s\ndelay_initial_bucket_level 0\ndelay_access 1 allow all\n' \
    "$bytes_per_second" "$bytes_per_second" > throttle/limits.conf.new
else
  printf 'delay_pools 0\n' > throttle/limits.conf.new
fi
chmod 644 throttle/limits.conf.new
mv throttle/limits.conf.new throttle/limits.conf

if ! docker compose exec -T squid squid -k parse; then
  restore_setting
  echo "Invalid Squid configuration; restored the previous throttle setting." >&2
  exit 1
fi
if ! docker compose exec -T squid squid -k reconfigure; then
  restore_setting
  echo "Squid reload failed; restored the saved setting. Check 'bash proxy.sh logs' before retrying." >&2
  exit 1
fi

if [[ "${1}" == enable ]]; then
  echo "Download throttle enabled: $rate kbps shared across all proxy users."
else
  echo "Download throttle disabled."
fi
echo "Reconnect clients for a clean test; existing tunnels may retain their previous limit."
