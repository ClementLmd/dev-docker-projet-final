# CI/CD et publication sur Docker Hub

Documentation technique pour la **Partie 7** du projet de conteneurisation.

---

## 1. Architecture du pipeline d'automatisation (.github/workflows/docker.yml)

Le déploiement continu et la validation qualité sont orchestrés par **GitHub Actions**. Le fichier de configuration [.github/workflows/docker.yml](file:///c:/Users/Wight/OneDrive/Documents/Cours%20Master/M2/Dev%20Docker/Projet%20Final/dev-docker-projet-final/.github/workflows/docker.yml) automatise l'intégralité du cycle de vie du code à chaque modification.

### 1.1 Événements déclencheurs (Triggers)
Le pipeline s'active automatiquement lors :
- D'un `push` sur la branche `main`.
- D'une `pull_request` ciblant `main`.

---

## 2. Déroulement séquentiel des Jobs

Le workflow est découpé en deux étapes interdépendantes :

```
[ Push / PR sur main ]
         │
         ▼
┌─────────────────────────────────┐
│  JOB 1 : Lint & Syntax Tests    │
│  - Checkout du code             │
│  - Setup PHP 8.2 & extensions   │
│  - Linting syntaxique (php -l)  │
│  - Validation syntaxe Compose   │
└─────────────────────────────────┘
         │ (Succès requis)
         ▼
┌───────────────────────────────────────────────┐
│  JOB 2 : Build, Scan & Publish                │
│  - Initialisation Docker Buildx & Cache GHA   │
│  - Authentification sécurisée Docker Hub      │
│  - Extraction métadonnées (latest, sha-xxxx)  │
│  - Construction & Scan Trivy (articles-web)   │
│  - Construction (articles-db)                 │
│  - Push automatique des 2 images étiquetées   │
└───────────────────────────────────────────────┘
```

### 2.1 Job 1 : Lint & Syntax Tests
Avant toute opération Docker consommatrice de ressources, le code applicatif est vérifié :
- `find sources/app -name "*.php" | xargs -n1 php -l` : garantit l'absence d'erreurs de syntaxe PHP.
- `docker compose config` : valide la syntaxe YAML et la résolution des variables d'environnement.

### 2.2 Job 2 : Build, Scan & Publish
Dès que les tests sont validés :
1. **Docker Buildx** initialise un environnement de build moderne exploitant le cache GitHub Actions (`cache-from: type=gha`) pour réduire le temps de build.
2. **Double étiquetage systématique** :
   - Tag `latest` : désigne la version de référence en production.
   - Tag `sha-<commit>` : assure la traçabilité immuable entre le commit Git et l'image Docker correspondante.
3. **Scan Trivy automatisé** : L'action officielle Aqua Security analyse l'image `articles-web` produite et consigne le rapport des failles directement dans les logs du build.
4. **Publication sur Docker Hub** : Les images `articles-web` et `articles-db` sont téléversées sur le registre public.

---

## 3. Gestion sécurisée des identifiants (GitHub Secrets)

Aucun mot de passe ni token n'est inscrit dans le fichier YAML. La connexion au registre s'effectue au moyen de deux secrets chiffrés configurés dans le dépôt GitHub (`Settings > Secrets and variables > Actions`) :

| Variable secrète | Description | Portée |
| :--- | :--- | :--- |
| `DOCKERHUB_USERNAME` | Identifiant du compte Docker Hub | Connexion au registre |
| `DOCKERHUB_TOKEN` | Jeton d'accès personnel (Personal Access Token - PAT) | Droits `Read & Write` sur les dépôts |

> **Bonne pratique appliquée :** L'étape de push est conditionnée (`secrets.DOCKERHUB_USERNAME != '' && github.event_name != 'pull_request'`). Cela évite l'échec du pipeline pour les contributeurs externes ou les branches locales ne disposant pas encore des secrets.

---

## 4. Procédure de publication manuelle (Équivalence CLI)

En cas de publication ponctuelle hors pipeline CI/CD, les commandes suivantes reproduisent fidèlement le processus :

```bash
# 1. Authentification
docker login -u <username>

# 2. Étiquetage de l'image applicative
docker tag articles-web:dev <username>/articles-web:latest
docker tag articles-web:dev <username>/articles-web:v1.0.0

# 3. Étiquetage de l'image de base de données
docker tag articles-db:dev <username>/articles-db:latest
docker tag articles-db:dev <username>/articles-db:v1.0.0

# 4. Publication sur le registre distant
docker push <username>/articles-web:latest
docker push <username>/articles-web:v1.0.0
docker push <username>/articles-db:latest
docker push <username>/articles-db:v1.0.0
```
