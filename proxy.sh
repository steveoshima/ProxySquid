#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p auth
chmod 700 auth

case "${1:-}" in
  start)
    docker compose config --quiet
    docker compose run --rm --no-deps --entrypoint squid squid -k parse
    docker compose up -d --force-recreate
    ;;
  auth)
    username="${2:-}"
    if [[ ! "$username" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
      echo "Usage: bash proxy.sh auth USERNAME (letters, digits, _, ., -)" >&2
      exit 1
    fi
    read -r -s -p "New proxy password: " password
    printf '\n'
    read -r -s -p "Confirm password: " confirmation
    printf '\n'
    if [[ -z "$password" || "$password" != "$confirmation" ]]; then
      echo "Passwords must be nonempty and match. Proxy mode has not changed." >&2
      exit 1
    fi
    hash="$(printf '%s\n' "$password" | docker compose run --rm --no-deps -T --entrypoint openssl squid passwd -6 -stdin)"
    unset password confirmation
    # Replace the single-user password file atomically, without storing plaintext.
    umask 077
    printf '%s:%s\n' "$username" "$hash" > auth/passwords.new
    chmod 644 auth/passwords.new
    mv auth/passwords.new auth/passwords
    unset hash
    docker compose -f compose.yaml -f compose.auth.yaml config --quiet
    docker compose -f compose.yaml -f compose.auth.yaml run --rm --no-deps --entrypoint squid squid -k parse
    docker compose -f compose.yaml -f compose.auth.yaml up -d --force-recreate
    ;;
  stop)
    docker compose down
    ;;
  status)
    docker compose ps
    ;;
  logs)
    docker compose logs --tail=100 -f squid
    ;;
  update)
    docker compose pull squid
    echo "Image pulled. To apply it, use 'bash proxy.sh start' for no-auth mode"
    echo "or 'bash proxy.sh auth USERNAME' to set credentials and enable auth."
    ;;
  *)
    echo "Usage: bash proxy.sh {start|auth USERNAME|stop|status|logs|update}" >&2
    exit 1
    ;;
esac
