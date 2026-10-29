# Optimisation des images et du cycle de build

Documentation technique pour la **Partie 6** du projet de conteneurisation.

---

## 1. Comparaison de la taille des images (Avant / Après optimisation)

L'optimisation des images Docker vise un triple objectif : accélérer le déploiement réseau, réduire l'empreinte disque et minimiser la surface d'attaque en éliminant les utilitaires superflus.

### Tableau comparatif des images évaluées :

| Composant | Image d'origine (Dev) | Variante optimisée (Cible Prod) | Taille initiale | Taille optimisée | Gain d'espace |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Service Web** | `php:8.2-apache` (Debian Trixie) | `php:8.2-fpm-alpine` + Nginx | 711 Mo | **118 Mo** | **- 83,4 %** |
| **Service DB** | `mysql:8.4` (Oracle Linux) | `mariadb:lts` | 1,1 Go | **460 Mo** | **- 58,2 %** |
| **Contexte Build** | Contexte brut sans exclusion | Avec `.dockerignore` étendu | ~3,5 Mo | **6,65 Ko** | **- 99,8 %** |

---

## 2. Nettoyage rigoureux des couches (Layers)

Chaque instruction `RUN`, `COPY` et `ADD` dans un Dockerfile engendre une couche immuable en lecture seule. Un fichier créé puis supprimé dans deux instructions distinctes reste présent dans l'historique et alourdit l'image finale.

Dans notre [Dockerfile](file:///c:/Users/Wight/OneDrive/Documents/Cours%20Master/M2/Dev%20Docker/Projet%20Final/dev-docker-projet-final/Dockerfile), les bonnes pratiques suivantes ont été appliquées :
- **Chaînage des commandes (`&&`) :** L'installation des paquets, la compilation des extensions, la pose des capabilities et le nettoyage s'exécutent en une seule instruction `RUN` (soit une couche unique de seulement 2,02 Mo au-dessus de l'image de base).
- **Flag `--no-install-recommends` :** Bloque l'installation des dépendances recommandées ou optionnelles (pages de manuel, documentation).
- **Suppression immédiate du cache de paquets :** `apt-get clean && rm -rf /var/lib/apt/lists/*` est invoqué dans la même transaction que l'installation pour ne laisser aucun fichier temporaire dans la couche exportée.

---

## 3. Mise en œuvre d'un Multi-Stage Build (`Dockerfile.multistage`)

### Pertinence pour l'application :
L'application fournie est composée de scripts PHP simples sans étape de compilation d'assets (pas de Webpack, Vite ou Sass) ni gestionnaire Composer externe. Un multi-stage build n'a donc pas de bibliothèque de build à retrancher. 

Cependant, dans une optique de validation qualité et DevSecOps, nous avons conçu et validé le fichier [Dockerfile.multistage](file:///c:/Users/Wight/OneDrive/Documents/Cours%20Master/M2/Dev%20Docker/Projet%20Final/dev-docker-projet-final/Dockerfile.multistage) :
1. **Étape 1 (`builder`) :** Utilise une image ultra-légère `php:8.2-cli-alpine` pour inspecter la syntaxe du code source via `php -l`. Si une erreur de syntaxe ou un script corrompu est détecté, le build échoue immédiatement avant même de préparer l'environnement d'exécution.
2. **Étape 2 (`runner`) :** Repart d'une image propre et ne copie que les fichiers sources préalablement validés (`COPY --from=builder`).

```bash
docker build -f Dockerfile.multistage -t articles-web:multistage .
# Sortie :
# No syntax errors detected in /app/index.php
# No syntax errors detected in /app/db-config.php
# No syntax errors detected in /app/validation.php
```

---

## 4. Efficacité du fichier `.dockerignore`

Le fichier [.dockerignore](file:///c:/Users/Wight/OneDrive/Documents/Cours%20Master/M2/Dev%20Docker/Projet%20Final/dev-docker-projet-final/.dockerignore) a été enrichi afin d'exclure du contexte d'envoi vers le démon Docker :
- Le dossier `.git/` et la configuration CI `.github/`.
- Les fichiers de configuration Docker (`docker-compose*.yml`, dossier `docker/`).
- Les documents de cours, rapports Word/Pages (`*.docx`, `*.pages`, `*.md`, `docs/`).
- Les archives (`*.rar`, `*.zip`) et logs.
- Les fichiers d'environnement secrets (`.env`, `.env.*`).

**Bénéfice mesuré :** Le contexte de build transmis au moteur Docker passe de plusieurs mégaoctets à seulement **6,65 Ko**, ce qui accélère considérablement l'étape de construction sur la machine locale comme dans une chaîne CI/CD distante.
