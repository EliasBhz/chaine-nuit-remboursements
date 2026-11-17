#!/usr/bin/env python3
"""Ordonnanceur minimal de la chaîne de nuit.

Lit la définition YAML de la chaîne et lance les jobs dans l'ordre de leurs dépendances, avec :
fenêtre horaire, relance automatique des erreurs techniques, reprise au job en échec et verrou
contre la double exécution. Les jobs s'exécutent l'un après l'autre.

Codes retour : ceux des jobs (0 à 3, voir docs/codes_retour.md), plus 4 si la chaîne tourne déjà.
"""

import argparse
import datetime
import fcntl
import json
import os
import re
import subprocess
import sys
import time

import yaml

RC_OK = 0
RC_ALERTE = 1
RC_ERREUR_FONCTIONNELLE = 2
RC_ERREUR_TECHNIQUE = 3
RC_DEJA_EN_COURS = 4

TERMINE = "TERMINE"
ALERTE = "ALERTE"
ECHEC = "ECHEC"
EN_COURS = "EN_COURS"
STATUTS_REUSSIS = (TERMINE, ALERTE)

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class ErreurDefinition(Exception):
    """Définition de chaîne incohérente : champ manquant, dépendance inconnue, cycle."""


def lire_heure(texte):
    if not re.fullmatch(r"([01]\d|2[0-3]):[0-5]\d", str(texte)):
        raise ErreurDefinition(f"heure invalide : {texte!r} (format HH:MM entre guillemets)")
    heures, minutes = str(texte).split(":")
    return datetime.time(int(heures), int(minutes))


def lire_definition(chemin):
    with open(chemin, encoding="utf-8") as fichier:
        definition = yaml.safe_load(fichier) or {}

    jobs = definition.get("jobs") or []
    if not jobs:
        raise ErreurDefinition("aucun job défini")
    noms = set()
    for job in jobs:
        for champ in ("nom", "commande"):
            if champ not in job:
                raise ErreurDefinition(f"champ « {champ} » manquant : {job}")
        if job["nom"] in noms:
            raise ErreurDefinition(f"job défini deux fois : {job['nom']}")
        noms.add(job["nom"])
        job.setdefault("depend_de", [])
        job.setdefault("essais", 1)
        job.setdefault("delai_relance", 0)
        job.setdefault("duree_max", 3600)
    for job in jobs:
        for dependance in job["depend_de"]:
            if dependance not in noms:
                raise ErreurDefinition(f"{job['nom']} dépend de {dependance}, qui n'existe pas")

    fenetre = definition.get("fenetre")
    if fenetre:
        definition["fenetre"] = (lire_heure(fenetre["debut"]), lire_heure(fenetre["fin"]))
    definition["jobs"] = ordre_execution(jobs)
    return definition


def ordre_execution(jobs):
    """Tri topologique : un job passe après toutes ses dépendances, l'ordre du YAML départage."""
    ordonnes, places, restants = [], set(), list(jobs)
    while restants:
        prets = [job for job in restants if all(d in places for d in job["depend_de"])]
        if not prets:
            raise ErreurDefinition("cycle de dépendances entre " + ", ".join(j["nom"] for j in restants))
        ordonnes.append(prets[0])
        places.add(prets[0]["nom"])
        restants.remove(prets[0])
    return ordonnes


def dans_fenetre(maintenant, debut, fin):
    """Fenêtre [debut, fin[. Si fin précède debut, la fenêtre passe minuit, cas d'une chaîne de nuit."""
    if debut <= fin:
        return debut <= maintenant < fin
    return maintenant >= debut or maintenant < fin


def horodatage():
    return datetime.datetime.now().isoformat(timespec="seconds")


class Journal:
    """Logs au même format JSON que les jobs shell, dans le même fichier du lot."""

    def __init__(self, chaine, execution, date_traitement, rep_logs):
        self.base = {"chaine": chaine, "execution": execution, "job": "ordonnanceur",
                     "lot": f"{date_traitement[:4]}-{date_traitement[4:6]}-{date_traitement[6:]}"}
        os.makedirs(rep_logs, exist_ok=True)
        self.chemin = os.path.join(rep_logs, f"chaine-{date_traitement}.jsonl")

    def evenement(self, niveau, evenement, message, **champs):
        ligne = {"horodatage": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                 "niveau": niveau, **self.base, "evenement": evenement, "message": message, **champs}
        texte = json.dumps(ligne, ensure_ascii=False, separators=(",", ":"))
        print(texte, flush=True)
        with open(self.chemin, "a", encoding="utf-8") as fichier:
            fichier.write(texte + "\n")


def niveau_pour(rc):
    return {RC_OK: "INFO", RC_ALERTE: "ALERTE"}.get(rc, "ERREUR")


def lire_etat(chemin):
    if not os.path.exists(chemin):
        return None
    with open(chemin, encoding="utf-8") as fichier:
        return json.load(fichier)


def ecrire_etat(chemin, etat):
    # Écriture puis renommage : un arrêt brutal ne laisse jamais un état à moitié écrit.
    temporaire = chemin + ".tmp"
    with open(temporaire, "w", encoding="utf-8") as fichier:
        json.dump(etat, fichier, ensure_ascii=False, indent=2)
    os.replace(temporaire, chemin)


def executer_job(job, env, journal, rep_sorties):
    """Lance un job, relance ses erreurs techniques. Renvoie (code retour, nombre d'essais)."""
    commande = [os.path.join(RACINE, job["commande"])]
    if env.get("CHAINE_SHELL") and commande[0].endswith(".sh"):
        commande.insert(0, env["CHAINE_SHELL"])
    sortie = os.path.join(rep_sorties, job["nom"] + ".out")
    nom = job["nom"]

    for essai in range(1, job["essais"] + 1):
        journal.evenement("INFO", "lancement", f"Lancement de {nom}", cible=nom, essai=essai)
        debut = time.monotonic()
        with open(sortie, "a", encoding="utf-8") as fichier:
            processus = subprocess.Popen(commande, env=env, stdout=fichier, stderr=subprocess.STDOUT)
            try:
                rc = processus.wait(timeout=job["duree_max"])
            except subprocess.TimeoutExpired:
                journal.evenement("ERREUR", "depassement",
                                  f"{nom} dépasse sa durée maximale de {job['duree_max']} s, arrêt demandé",
                                  cible=nom, duree_max_s=job["duree_max"])
                # SIGTERM d'abord pour laisser le job tracer sa fin, SIGKILL s'il ne s'arrête pas.
                processus.terminate()
                try:
                    processus.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    processus.kill()
                    processus.wait()
                rc = RC_ERREUR_TECHNIQUE
        # Un code hors convention ou une mort par signal sont traités comme une erreur technique.
        if rc < 0 or rc > RC_ERREUR_TECHNIQUE:
            rc = RC_ERREUR_TECHNIQUE
        journal.evenement(niveau_pour(rc), "retour", f"{nom} terminé avec le code {rc}", cible=nom,
                          code_retour=rc, essai=essai, duree_s=round(time.monotonic() - debut, 1))

        # Seule une erreur technique peut disparaître en relançant : une erreur fonctionnelle demande une analyse.
        if rc != RC_ERREUR_TECHNIQUE or essai == job["essais"]:
            return rc, essai
        journal.evenement("ALERTE", "relance", f"Relance de {nom} dans {job['delai_relance']} s",
                          cible=nom, essai_suivant=essai + 1)
        time.sleep(job["delai_relance"])
    return RC_ERREUR_TECHNIQUE, job["essais"]


def executer_chaine(definition, args, date_traitement, execution, journal, chemin_etat, rep_sorties):
    etat = lire_etat(chemin_etat)
    if etat and not (args.reprise or args.depuis_debut):
        if all(etat["jobs"].get(j["nom"], {}).get("statut") in STATUTS_REUSSIS for j in definition["jobs"]):
            journal.evenement("INFO", "deja_terminee",
                              "Chaîne déjà terminée pour ce lot, --depuis-debut pour la rejouer")
            return RC_OK
        journal.evenement("ERREUR", "reprise_requise",
                          "Chaîne déjà lancée pour ce lot sans aboutir : utiliser --reprise ou --depuis-debut")
        return RC_ERREUR_FONCTIONNELLE
    if not etat or args.depuis_debut:
        etat = {"lot": journal.base["lot"], "jobs": {}}
    etat["execution"] = execution

    fenetre = definition.get("fenetre")
    if fenetre and args.forcer_fenetre and not dans_fenetre(datetime.datetime.now().time(), *fenetre):
        journal.evenement("ALERTE", "fenetre_forcee", "Lancement forcé hors de la fenêtre horaire")

    mode = "reprise" if args.reprise else "complet"
    journal.evenement("INFO", "debut_chaine", f"Début de la chaîne ({mode})", mode=mode)
    env = dict(os.environ, DATE_TRAITEMENT=date_traitement, CHAINE_EXECUTION=execution,
               CHAINE_NOM=journal.base["chaine"])
    alerte = False

    for job in definition["jobs"]:
        nom = job["nom"]
        precedent = etat["jobs"].get(nom, {}).get("statut")
        if precedent in STATUTS_REUSSIS:
            journal.evenement("INFO", "deja_termine", f"{nom} déjà terminé, non relancé", cible=nom)
            alerte = alerte or precedent == ALERTE
            continue
        if fenetre and not args.forcer_fenetre and not dans_fenetre(datetime.datetime.now().time(), *fenetre):
            debut, fin = (h.strftime("%H:%M") for h in fenetre)
            journal.evenement("ERREUR", "hors_fenetre", f"Hors de la fenêtre {debut}-{fin} : {nom} non lancé",
                              cible=nom)
            return RC_ERREUR_FONCTIONNELLE

        etat["jobs"][nom] = {"statut": EN_COURS, "debut": horodatage()}
        ecrire_etat(chemin_etat, etat)
        rc, essais = executer_job(job, env, journal, rep_sorties)
        statut = {RC_OK: TERMINE, RC_ALERTE: ALERTE}.get(rc, ECHEC)
        etat["jobs"][nom].update(statut=statut, code_retour=rc, essais=essais, fin=horodatage())
        ecrire_etat(chemin_etat, etat)

        if statut == ECHEC:
            journal.evenement("ERREUR", "fin_chaine", f"Chaîne arrêtée sur {nom}, reprise possible avec --reprise",
                              cible=nom, code_retour=rc)
            return rc
        alerte = alerte or statut == ALERTE

    rc = RC_ALERTE if alerte else RC_OK
    journal.evenement(niveau_pour(rc), "fin_chaine", "Chaîne terminée", code_retour=rc)
    return rc


def afficher_statut(chemin_etat, definition):
    etat = lire_etat(chemin_etat)
    if not etat:
        print("Aucune exécution enregistrée pour ce lot.")
        return RC_OK
    print(f"Lot {etat['lot']}, exécution {etat.get('execution', '?')}")
    for job in definition["jobs"]:
        info = etat["jobs"].get(job["nom"], {})
        print(f"  {job['nom']:<26} {info.get('statut', 'A_FAIRE'):<9} "
              f"code={info.get('code_retour', '-')} essais={info.get('essais', '-')}")
    return RC_OK


def main(argv=None):
    parser = argparse.ArgumentParser(description="Ordonnanceur de la chaîne de nuit.")
    parser.add_argument("--definition", default=os.path.join(RACINE, "ordonnanceur", "chaine.yaml"),
                        help="fichier YAML de la chaîne")
    parser.add_argument("--date", help="date de traitement AAAAMMJJ (défaut : DATE_TRAITEMENT ou aujourd'hui)")
    parser.add_argument("--forcer-fenetre", action="store_true", help="autoriser un lancement hors fenêtre")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--reprise", action="store_true", help="reprendre au job en échec")
    mode.add_argument("--depuis-debut", action="store_true", help="rejouer toute la chaîne")
    mode.add_argument("--statut", action="store_true", help="afficher l'état du lot sans rien lancer")
    args = parser.parse_args(argv)

    date_traitement = args.date or os.environ.get("DATE_TRAITEMENT") or datetime.date.today().strftime("%Y%m%d")
    if not re.fullmatch(r"\d{8}", date_traitement):
        print(f"Date de traitement invalide : {date_traitement}", file=sys.stderr)
        return RC_ERREUR_TECHNIQUE
    try:
        definition = lire_definition(args.definition)
    except (OSError, yaml.YAMLError, ErreurDefinition) as erreur:
        print(f"Définition de chaîne invalide : {erreur}", file=sys.stderr)
        return RC_ERREUR_TECHNIQUE

    donnees = os.environ.get("CHAINE_DONNEES", "/data")
    rep_logs = os.environ.get("CHAINE_LOGS", os.path.join(donnees, "logs"))
    rep_etat = os.environ.get("CHAINE_ETAT", os.path.join(donnees, "etat"))
    rep_sorties = os.path.join(rep_logs, date_traitement)
    os.makedirs(rep_etat, exist_ok=True)
    os.makedirs(rep_sorties, exist_ok=True)
    chemin_etat = os.path.join(rep_etat, f"etat-{date_traitement}.json")

    if args.statut:
        return afficher_statut(chemin_etat, definition)

    chaine = definition.get("chaine", "chaine")
    execution = datetime.datetime.now().strftime("%Y%m%dT%H%M%S")
    journal = Journal(chaine, execution, date_traitement, rep_logs)

    # Le verrou est porté par le descripteur ouvert : il est libéré même si le processus meurt.
    verrou = open(os.path.join(rep_etat, f"{chaine}.lock"), "w")
    try:
        fcntl.flock(verrou, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        journal.evenement("ERREUR", "deja_en_cours", "La chaîne est déjà en cours d'exécution")
        return RC_DEJA_EN_COURS
    try:
        return executer_chaine(definition, args, date_traitement, execution, journal, chemin_etat, rep_sorties)
    finally:
        verrou.close()


if __name__ == "__main__":
    sys.exit(main())
