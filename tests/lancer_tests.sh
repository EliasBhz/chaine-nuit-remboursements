#!/bin/sh
# Lance la suite bats sous ksh puis sous bash, après avoir appliqué le schéma de la base.
set -u
cd "$(dirname "$0")/.." || exit 3

psql -X -q -v ON_ERROR_STOP=1 -f sql/schema.sql || exit 3

rc=0
for interpreteur in ksh bash; do
    printf '\n=== Jobs exécutés avec %s ===\n' "$interpreteur"
    SHELL_TEST=$interpreteur bats tests/bats || rc=1
done
exit "$rc"
