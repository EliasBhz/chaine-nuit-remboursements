#!/bin/sh
# Analyse statique des scripts shell, en mode POSIX : ce qui passe ici tourne sous ksh comme sous bash.
cd "$(dirname "$0")/.." || exit 3
shellcheck -x -s sh jobs/*.sh jobs/lib/commun.sh tests/*.sh
