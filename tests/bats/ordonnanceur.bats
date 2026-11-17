#!/usr/bin/env bats
# Ordonnanceur : dépendances, arrêt sur erreur, relances, reprise, verrou, fenêtre, durée maximale.
# Les jobs sont des scripts factices qui notent leur passage dans un fichier de trace.

load aide

setup() {
    preparer_environnement
    FAUX=$BATS_TEST_TMPDIR/faux
    mkdir -p "$FAUX"
    export TRACE=$BATS_TEST_TMPDIR/trace
    : > "$TRACE"
}

# faux_job NOM CODE [COMMANDE] : job qui note son nom, exécute COMMANDE puis sort avec CODE.
faux_job() {
    printf '#!/bin/sh\necho %s >> "$TRACE"\n%s\nexit %s\n' "$1" "${3:-:}" "$2" > "$FAUX/$1.sh"
    chmod +x "$FAUX/$1.sh"
}

definir_chaine() {
    cat > "$BATS_TEST_TMPDIR/chaine.yaml"
}

ordonnanceur() {
    run python3 "$RACINE/ordonnanceur/ordonnanceur.py" --definition "$BATS_TEST_TMPDIR/chaine.yaml" "$@"
}

trace() {
    tr '\n' ' ' < "$TRACE"
}

@test "lance les jobs dans l'ordre des dépendances, pas dans l'ordre du fichier" {
    faux_job a 0
    faux_job b 0
    faux_job c 0
    definir_chaine <<EOF
chaine: essai
jobs:
  - {nom: c, commande: $FAUX/c.sh, depend_de: [b]}
  - {nom: b, commande: $FAUX/b.sh, depend_de: [a]}
  - {nom: a, commande: $FAUX/a.sh}
EOF
    ordonnanceur
    [ "$status" -eq 0 ]
    [ "$(trace)" = "a b c " ]
}

@test "s'arrête sur une erreur fonctionnelle sans la relancer" {
    faux_job a 0
    faux_job b 2
    faux_job c 0
    definir_chaine <<EOF
chaine: essai
jobs:
  - {nom: a, commande: $FAUX/a.sh}
  - {nom: b, commande: $FAUX/b.sh, depend_de: [a], essais: 3}
  - {nom: c, commande: $FAUX/c.sh, depend_de: [b]}
EOF
    ordonnanceur
    [ "$status" -eq 2 ]
    [ "$(trace)" = "a b " ]
}

@test "relance une erreur technique jusqu'au succès" {
    # Échoue au premier passage, réussit au second.
    faux_job a 0 '[ -f "$TRACE.deja" ] || { touch "$TRACE.deja"; exit 3; }'
    definir_chaine <<EOF
chaine: essai
jobs:
  - {nom: a, commande: $FAUX/a.sh, essais: 3, delai_relance: 0}
EOF
    ordonnanceur
    [ "$status" -eq 0 ]
    [ "$(trace)" = "a a " ]
}

@test "abandonne après le nombre d'essais prévu" {
    faux_job a 3
    definir_chaine <<EOF
chaine: essai
jobs:
  - {nom: a, commande: $FAUX/a.sh, essais: 2, delai_relance: 0}
EOF
    ordonnanceur
    [ "$status" -eq 3 ]
    [ "$(trace)" = "a a " ]
}

@test "un job en alerte laisse la chaîne continuer et la termine en alerte" {
    faux_job a 1
    faux_job b 0
    definir_chaine <<EOF
chaine: essai
jobs:
  - {nom: a, commande: $FAUX/a.sh}
  - {nom: b, commande: $FAUX/b.sh, depend_de: [a]}
EOF
    ordonnanceur
    [ "$status" -eq 1 ]
    [ "$(trace)" = "a b " ]
}

@test "la reprise repart du job en échec sans relancer les jobs terminés" {
    faux_job a 0
    faux_job b 2
    faux_job c 0
    definir_chaine <<EOF
chaine: essai
jobs:
  - {nom: a, commande: $FAUX/a.sh}
  - {nom: b, commande: $FAUX/b.sh, depend_de: [a]}
  - {nom: c, commande: $FAUX/c.sh, depend_de: [b]}
EOF
    ordonnanceur
    [ "$status" -eq 2 ]
    ordonnanceur
    [ "$status" -eq 2 ]
    [[ "$output" == *reprise_requise* ]]
    faux_job b 0
    ordonnanceur --reprise
    [ "$status" -eq 0 ]
    [ "$(trace)" = "a b b c " ]
}

@test "une chaîne terminée n'est rejouée qu'avec --depuis-debut" {
    faux_job a 0
    definir_chaine <<EOF
chaine: essai
jobs:
  - {nom: a, commande: $FAUX/a.sh}
EOF
    ordonnanceur
    ordonnanceur
    [ "$status" -eq 0 ]
    [ "$(trace)" = "a " ]
    ordonnanceur --depuis-debut
    [ "$(trace)" = "a a " ]
}

@test "le verrou empêche une deuxième exécution simultanée" {
    faux_job a 0 'sleep 3'
    definir_chaine <<EOF
chaine: essai
jobs:
  - {nom: a, commande: $FAUX/a.sh}
EOF
    python3 "$RACINE/ordonnanceur/ordonnanceur.py" --definition "$BATS_TEST_TMPDIR/chaine.yaml" \
        > /dev/null 2>&1 3>&- &
    premier=$!
    # Attend que le premier lancement ait démarré son job.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -s "$TRACE" ] && break
        sleep 0.5
    done
    ordonnanceur --depuis-debut
    [ "$status" -eq 4 ]
    wait "$premier"
}

@test "refuse de lancer hors de la fenêtre horaire, sauf si elle est forcée" {
    faux_job a 0
    # Fenêtre d'une heure qui commence dans deux heures : l'heure courante est forcément dehors.
    read -r debut fin < <(python3 -c 'import datetime; h = (datetime.datetime.now().hour + 2) % 24; print(f"{h:02d}:00 {(h + 1) % 24:02d}:00")')
    definir_chaine <<EOF
chaine: essai
fenetre: {debut: "$debut", fin: "$fin"}
jobs:
  - {nom: a, commande: $FAUX/a.sh}
EOF
    ordonnanceur
    [ "$status" -eq 2 ]
    [ ! -s "$TRACE" ]
    ordonnanceur --forcer-fenetre
    [ "$status" -eq 0 ]
    [ "$(trace)" = "a " ]
}

@test "arrête un job qui dépasse sa durée maximale" {
    faux_job a 0 'sleep 30'
    definir_chaine <<EOF
chaine: essai
jobs:
  - {nom: a, commande: $FAUX/a.sh, duree_max: 1}
EOF
    ordonnanceur
    [ "$status" -eq 3 ]
    [[ "$output" == *depassement* ]]
}

@test "refuse une définition avec un cycle de dépendances" {
    faux_job a 0
    definir_chaine <<EOF
chaine: essai
jobs:
  - {nom: a, commande: $FAUX/a.sh, depend_de: [b]}
  - {nom: b, commande: $FAUX/a.sh, depend_de: [a]}
EOF
    ordonnanceur
    [ "$status" -eq 3 ]
    [[ "$output" == *cycle* ]]
}
