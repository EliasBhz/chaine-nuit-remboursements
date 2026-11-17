#!/usr/bin/env bats
# Job archiver_purger : contenu de l'archive, fichiers conservés, rejeu, rétention.

load aide

setup() {
    preparer_environnement
    cd "$CHAINE_DONNEES"
    mkdir -p entree valides rejets travail sortie archive
    echo "$ENTETE" > entree/FS_20250115_01.csv
    : > valides/FS_20250115_01.csv
    : > rejets/FS_20250115_01.csv.rejets
    echo "lues=0" > travail/controle_20250115.stats
    echo "id_paiement;id_assure;nb_feuilles;montant" > sortie/PAI_20250115.csv
    echo "compte rendu" > sortie/CR_20250115.txt
    ARCHIVE=$CHAINE_DONNEES/archive/lot_20250115.tar.gz
}

@test "archive le lot, retire les fichiers de travail, garde les sorties" {
    lancer_job archiver_purger
    [ "$status" -eq 0 ]
    [ "$(gzip -dc "$ARCHIVE" | tar -tf - | wc -l)" -eq 6 ]
    [ ! -f entree/FS_20250115_01.csv ]
    [ ! -f valides/FS_20250115_01.csv ]
    [ ! -f travail/controle_20250115.stats ]
    [ -f sortie/PAI_20250115.csv ]
    [ -f sortie/CR_20250115.txt ]
}

@test "rejouer après archivage ne modifie pas l'archive" {
    lancer_job archiver_purger
    empreinte=$(cksum < "$ARCHIVE")
    lancer_job archiver_purger
    [ "$status" -eq 0 ]
    [ "$(cksum < "$ARCHIVE")" = "$empreinte" ]
}

@test "lot sans fichier reçu ni archive : alerte" {
    rm entree/FS_20250115_01.csv
    lancer_job archiver_purger
    [ "$status" -eq 1 ]
}

@test "purge les archives au-delà de la rétention et garde les récentes" {
    : > archive/lot_20200101.tar.gz
    touch -t 202001010000 archive/lot_20200101.tar.gz
    : > archive/lot_20250114.tar.gz
    export RETENTION_JOURS=30
    lancer_job archiver_purger
    [ "$status" -eq 0 ]
    [ ! -f archive/lot_20200101.tar.gz ]
    [ -f archive/lot_20250114.tar.gz ]
}

@test "une rétention non entière est refusée" {
    export RETENTION_JOURS=trente
    lancer_job archiver_purger
    [ "$status" -eq 3 ]
}
