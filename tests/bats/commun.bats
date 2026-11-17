#!/usr/bin/env bats
# Bibliothèque commune : logs JSON, codes retour, contrôle de la date de traitement.

load aide

setup() {
    preparer_environnement
}

# Écrit un script qui source la bibliothèque puis exécute les lignes lues sur l'entrée standard.
ecrire_script() {
    {
        printf 'JOB_REP=%s/jobs\n' "$RACINE"
        printf '. "$JOB_REP/lib/commun.sh"\n'
        cat
    } > "$BATS_TEST_TMPDIR/script.sh"
}

@test "log_event écrit du JSON valide, avec nombres et caractères échappés" {
    ecrire_script <<'EOF'
initialiser_job essai
log_event INFO test 'guillemets " et barre \ oblique' n=12 taux=1.5 id=007 nom=abc
terminer_job 0
EOF
    run "$SHELL_TEST" "$BATS_TEST_TMPDIR/script.sh"
    [ "$status" -eq 0 ]
    python3 - "$CHAINE_LOGS/chaine-$DATE_TRAITEMENT.jsonl" <<'EOF'
import json, sys
lignes = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
test = next(l for l in lignes if l["evenement"] == "test")
assert test["n"] == 12 and test["taux"] == 1.5, test
assert test["id"] == "007" and test["nom"] == "abc", test
assert test["message"] == 'guillemets " et barre \\ oblique', test["message"]
assert test["job"] == "essai" and test["lot"] == "2025-01-15", test
EOF
}

@test "terminer_job sort avec le code demandé et trace la durée" {
    ecrire_script <<'EOF'
initialiser_job essai
terminer_job 1
EOF
    run "$SHELL_TEST" "$BATS_TEST_TMPDIR/script.sh"
    [ "$status" -eq 1 ]
    grep '"evenement":"fin"' "$CHAINE_LOGS/chaine-$DATE_TRAITEMENT.jsonl" \
        | grep '"niveau":"ALERTE"' | grep '"code_retour":1' | grep -q '"duree_s":'
}

@test "echec trace l'erreur et sort avec le code fourni" {
    ecrire_script <<'EOF'
initialiser_job essai
echec 2 "Données incohérentes"
EOF
    run "$SHELL_TEST" "$BATS_TEST_TMPDIR/script.sh"
    [ "$status" -eq 2 ]
    grep -q '"evenement":"erreur","message":"Données incohérentes"' "$CHAINE_LOGS/chaine-$DATE_TRAITEMENT.jsonl"
}

@test "une date de traitement mal formée est refusée en erreur technique" {
    export DATE_TRAITEMENT=2025-01-15
    ecrire_script <<'EOF'
initialiser_job essai
terminer_job 0
EOF
    run "$SHELL_TEST" "$BATS_TEST_TMPDIR/script.sh"
    [ "$status" -eq 3 ]
}

@test "epoch renvoie l'heure courante en secondes" {
    ecrire_script <<'EOF'
epoch
EOF
    run "$SHELL_TEST" "$BATS_TEST_TMPDIR/script.sh"
    [ "$status" -eq 0 ]
    [ "$output" -gt 1700000000 ]
}
