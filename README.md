# Discord-app — Clone de Discord en PHP / PostgreSQL

![PHP](https://img.shields.io/badge/PHP-8.3-777BB4?logo=php&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)
![jQuery](https://img.shields.io/badge/jQuery-4-0769AD?logo=jquery&logoColor=white)
![S3](https://img.shields.io/badge/Stockage-S3%20compatible-569A31?logo=amazons3&logoColor=white)
![Composer](https://img.shields.io/badge/Composer-PSR--4-885630?logo=composer&logoColor=white)

Application web de messagerie inspirée de Discord, développée **en solo** et **sans framework** : serveurs, salons, messages privés, rôles et permissions, upload de médias.

Démarré comme projet de BUT Informatique (IUT du Littoral Côte d'Opale), il a ensuite été **entièrement refactorisé** : migration de scripts PHP « legacy » vers une API REST, architecture en couches, système de permissions binaires et stockage objet découplé. L'objectif était de passer d'un projet de cours à une base de code qui ressemble à ce qu'on écrit en entreprise.

<!--
APERÇU — à ajouter : 2 ou 3 captures d'écran dans docs/screenshots/ puis les référencer ici.
![Salon](docs/screenshots/salon.png)
-->

---

## Sommaire

- [Fonctionnalités](#fonctionnalités)
- [Stack technique](#stack-technique)
- [Architecture](#architecture)
- [Décisions techniques](#décisions-techniques)
- [API REST](#api-rest)
- [Système de permissions](#système-de-permissions)
- [Sécurité](#sécurité)
- [Installation](#installation)
- [Limites connues et pistes d'amélioration](#limites-connues-et-pistes-damélioration)
- [Auteur](#auteur)

---

## Fonctionnalités

- **Authentification complète** : inscription, connexion, déconnexion, réinitialisation du mot de passe par e-mail (token cryptographique à usage unique, expiration)
- **Serveurs** : création avec icône et bannière personnalisées, liste des serveurs rejoints / disponibles, rejoindre un serveur
- **Salons textuels** : envoi, modification et suppression de messages (rafraîchissement par polling)
- **Messagerie privée** : conversations 1-to-1 avec contrôle d'appartenance à la conversation
- **Rôles et permissions** : attribution / retrait de rôles à un membre, interface conditionnée par les permissions de l'utilisateur
- **Médias** : upload vers un stockage objet S3-compatible (Backblaze B2), historique des fichiers uploadés par utilisateur
- **Paramètres de serveur** : vue dédiée de configuration (en cours de finalisation)

## Stack technique

| Couche | Technologies |
| --- | --- |
| Backend | PHP 8.3 (vanilla, sans framework), PDO |
| Base de données | PostgreSQL 16 (hébergée sur Neon) |
| Frontend | HTML / CSS (CSS Grid), JavaScript, jQuery, modules IIFE |
| Stockage de fichiers | Backblaze B2 via `aws/aws-sdk-php` (API S3) |
| E-mails | PHPMailer |
| Configuration | `vlucas/phpdotenv` (variables d'environnement) |
| Dépendances | Composer, autoloading PSR-4 (`App\` → `src/`) |

## Architecture

Le backend suit une architecture en couches **Model / Repository / Service**, avec des contrats d'abstraction (interfaces) pour tout ce qui touche à l'extérieur (fichiers, notifications).

```
Discord-app/
├── src/                         # Logique métier (hors webroot)
│   ├── bootstrap.php            # Autoloader, session, chargement Composer
│   ├── Database.php             # Connexion PDO (Singleton, configuration via .env)
│   ├── Permissions.php          # Constantes de permissions + vérification bitwise
│   ├── Models/                  # Entités : Users, Server, Channel, Message, Conv, UploadHistorique
│   ├── Repositories/            # Accès aux données (requêtes SQL préparées uniquement)
│   ├── Services/                # Règles métier : AuthService, MessageService, MediaService,
│   │                            #   S3StorageService, EmailNotificationService
│   ├── Interfaces/              # FileStorageInterface, NotificationInterface
│   └── migration_img.php        # Script CLI de migration des images locales vers le bucket
│
└── public/                      # Seul dossier exposé au navigateur
    ├── *.html                   # Pages : connexion, inscription, salon
    ├── css/                     # Feuilles de style
    ├── js/
    │   ├── modules/             # API.js (appels REST centralisés), Permissions.js,
    │   │                        #   UIComponents.js, validation.js, Appstat.js
    │   └── *.js                 # Chat, Serveur, Mp, Profils, Modales…
    └── php/api/                 # Points d'entrée REST (auth, channels, conversations,
                                 #   members, servers, users)
```

**Cheminement d'une requête :**

```
Navigateur (jQuery)  →  API.js  →  public/php/api/<ressource>  →  Service  →  Repository  →  PostgreSQL
                                                                      └────→  Interface (stockage / e-mail)
```

## Décisions techniques

**Architecture en couches (Model / Repository / Service).**
Les requêtes SQL vivent uniquement dans les repositories, la logique métier dans les services, et les endpoints ne font que valider l'entrée et répondre en JSON. Chaque couche est testable et remplaçable indépendamment, c'est le découpage que l'on retrouve dans la plupart des projets d'entreprise (y compris dans les frameworks comme Symfony ou Laravel).

**Inversion de dépendances (SOLID).**
`MediaService` dépend de `FileStorageInterface`, pas de Backblaze. `AuthService` dépend de `NotificationInterface`, pas de PHPMailer. Passer de B2 à Cloudflare R2, ou de l'e-mail au SMS, revient à écrire une nouvelle implémentation sans toucher au code métier. Les dépendances sont injectées par constructeur.

**Stockage objet découplé.**
Les médias ne sont plus stockés sur le disque du serveur mais dans un bucket S3-compatible. Le serveur d'application reste ainsi sans état (condition de base pour le déployer sur plusieurs instances). Deux politiques coexistent dans `MediaService` : les médias de **serveur** remplacent et suppriment l'ancien fichier, les médias **utilisateur** conservent un historique.

**Permissions par masque de bits.**
Chaque permission est une puissance de 2 stockée dans un entier. Les permissions d'un utilisateur sont le OU binaire de ses rôles, la vérification est un ET binaire. C'est compact, rapide, et c'est le même modèle que Discord, Unix ou les droits Linux. La logique est volontairement **dupliquée en PHP et en JS** : le serveur fait autorité, le client s'en sert pour adapter l'interface.

**API REST issue d'une migration progressive.**
Les anciens scripts (`recup_message.php`, `send_mp.php`, `supp_message.php`…) ont été regroupés par ressource, avec les verbes HTTP appropriés (`GET`, `POST`, `PUT`, `DELETE`) et des réponses JSON structurées.

**Configuration par variables d'environnement.**
Aucun identifiant en dur dans le code : la connexion à la base et les clés du bucket sont chargées depuis un fichier `.env` ignoré par Git (modèle fourni dans `.env.exemple`).

## API REST

Les endpoints sont dans `public/php/api/`. Toutes les routes sauf l'authentification nécessitent une session ouverte.

| Ressource | Méthode | Description |
| --- | --- | --- |
| `auth/register.php` | `POST` | Inscription |
| `auth/login.php` | `POST` | Connexion |
| `auth/logout.php` | `GET` | Déconnexion |
| `auth/password.php` | `POST` / `GET` | Demande de réinitialisation / validation du token |
| `users/index.php` | `GET` | Profil de l'utilisateur connecté ou d'un utilisateur (`?id=`) |
| `servers/index.php` | `GET` / `POST` | Serveurs de l'utilisateur ou disponibles (`?available`) / rejoindre un serveur |
| `servers/create.php` | `POST` | Créer un serveur (multipart : nom, description, icône, bannière) |
| `servers/roles.php` | `GET` | Rôles d'un serveur |
| `members/index.php` | `GET` / `POST` / `DELETE` | Membres d'un serveur avec leurs rôles / attribuer un rôle / retirer un rôle |
| `channels/index.php` | `GET` | Salons d'un serveur |
| `channels/messages.php` | `GET` / `POST` / `PUT` / `DELETE` | Messages d'un salon |
| `conversations/index.php` | `GET` / `POST` / `PUT` / `DELETE` | Conversations privées et leurs messages |

Format de réponse : objet JSON avec un champ `status` (`success` / `error`), puis `data` ou `message` selon le cas.

## Système de permissions

12 permissions codées sur des bits distincts (`src/Permissions.php`, miroir dans `public/js/modules/Permissions.js`) :

| Valeur | Permission | Valeur | Permission |
| ---: | --- | ---: | --- |
| 1 | `LIRE_MESSAGES` | 64 | `MENTIONNER_TOUS` |
| 2 | `ENVOYER_MESSAGES` | 128 | `SUPPRIMER_MESSAGES` |
| 4 | `GERER_MESSAGES` | 256 | `EXCLURE_MEMBRES` |
| 8 | `INVITER_MEMBRES` | 512 | `BANNIR_MEMBRES` |
| 16 | `GERER_SALONS` | 1024 | `ADMINISTRATEUR` |
| 32 | `GERER_SERVEUR` | 2048 | `GERER_ROLES` |

- Le total d'un membre est le **OU** des permissions de tous ses rôles
- Une permission est accordée si `(total & requis) === requis`
- `ADMINISTRATEUR` court-circuite toutes les vérifications
- Côté serveur, ces règles sont appliquées pour la gestion des rôles (`GERER_ROLES` requis pour attribuer ou retirer un rôle)

## Sécurité

| Menace | Mesure en place |
| --- | --- |
| Injection SQL | Requêtes préparées PDO partout, `ATTR_EMULATE_PREPARES` désactivé (vraies requêtes préparées côté PostgreSQL) |
| Stockage des mots de passe | `password_hash` / `password_verify` (bcrypt) |
| Réinitialisation de mot de passe | Token `random_bytes(32)`, expiration, invalidation après usage |
| XSS | Le contenu utilisateur est injecté dans le DOM via `.text()` et non `.html()` |
| Accès aux messages privés | Vérification que l'utilisateur appartient bien à la conversation |
| Gestion des rôles | Vérification de la permission `GERER_ROLES` côté serveur |
| Fuite de secrets | Configuration par `.env` (non versionné), dossier `vendor/` ignoré |
| Exposition du code | Logique métier dans `src/`, hors du dossier public |

## Installation

**Prérequis :** PHP 8.3+ (extensions `pdo_pgsql` et `fileinfo`), Composer, une base PostgreSQL, et optionnellement un bucket S3-compatible pour les uploads.

```bash
# 1. Cloner le dépôt
git clone https://github.com/Noa-Mormentyn/Discord-app.git
cd Discord-app

# 2. Installer les dépendances
composer install

# 3. Configurer l'environnement
cp .env.exemple .env      # puis renseigner DB_* et B2_*

# 4. Créer le schéma de base de données
#    → importer database/schema.sql dans votre base PostgreSQL

# 5. Lancer le serveur de développement
php -S localhost:8080 -t public/
```

Puis ouvrir `http://localhost:8080/index.html`.

**Variables d'environnement** (voir `.env.exemple`) :

| Variable | Rôle |
| --- | --- |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` | Connexion PostgreSQL |
| `DB_SSLMODE` | Mode SSL (`require` pour une base cloud comme Neon) |
| `B2_KEY_ID`, `B2_APPLICATION_KEY`, `B2_BUCKET`, `B2_ENDPOINT`, `B2_REGION` | Accès au bucket S3-compatible |

**Migration des anciennes images** (optionnel, une seule fois) : `php src/migration_img.php` envoie les images locales vers le bucket et met à jour les URLs en base.

## Limites connues et pistes d'amélioration

Le projet est en développement actif. Les chantiers identifiés, par ordre de priorité :

- [ ] **Contrôle d'accès** : étendre la vérification serveur des permissions et de l'appartenance à un serveur à tous les endpoints (salons, messages, serveurs), aujourd'hui appliquée à la gestion des rôles et aux messages privés
- [ ] **Tests automatisés** : tests unitaires PHPUnit sur les services et sur `Permissions`
- [ ] **Temps réel** : remplacer le polling (5 s) par Server-Sent Events ou WebSocket
- [ ] **Durcissement des sessions** : régénération de l'identifiant de session, cookies `HttpOnly` / `SameSite`, protection CSRF
- [ ] **Conteneurisation** : `Dockerfile` et `docker-compose` (PHP + PostgreSQL) pour un démarrage en une commande
- [ ] **CI** : GitHub Actions (lint, tests) à chaque push
- [ ] **Médias publics** : accès aux images via URLs pré-signées ou migration vers Cloudflare R2
- [ ] **Interface** : finalisation de la vue des paramètres de serveur

## Auteur

**Noa Mormentyn** — étudiant en BUT Informatique, IUT du Littoral Côte d'Opale

[GitHub](https://github.com/Noa-Mormentyn)
