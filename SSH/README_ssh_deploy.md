# 🔐 SSH Deploy — Déploiement automatisé de clés SSH

**Auteur** : DlnSys  
**Version** : 1.1  
**Dernière mise à jour** : Correction de la vérification avec la bonne clé privée  

---

## 📌 Description

`ssh_deploy.sh` est un script Bash interactif permettant de **générer, sélectionner et déployer facilement des clés SSH** sur un ou plusieurs serveurs distants.  
Il simplifie le processus souvent répétitif de configuration de l’authentification sans mot de passe (SSH key-based login), tout en gardant une **traçabilité dans des logs** clairs et détaillés.

---

## ✨ Fonctionnalités principales

- 🎯 Génération d'une nouvelle paire de clés SSH (Ed25519)
- 📂 Sélection interactive d’une clé publique existante
- 🗂 Listing des clés disponibles dans `~/.ssh/`
- 📤 Déploiement de la clé sur plusieurs serveurs via `ssh-copy-id`
- 🔍 Vérification automatique du bon fonctionnement de la connexion SSH sans mot de passe
- 📝 Journalisation complète dans un fichier `ssh_deploy.log`
- 💡 Gestion intelligente des clés existantes (remplacement, duplication ou réutilisation)
- 🎨 Interface colorée et intuitive

---

## ⚙️ Prérequis

Avant d'exécuter le script, assure-toi d’avoir installé les outils suivants :

- `ssh`
- `ssh-keygen`
- `ssh-copy-id`
- `timeout`
- `find`
- `awk`

---

## 🚀 Utilisation

### 1. Lance le script :
```bash
./ssh_deploy.sh
```

### 2. Suis les instructions interactives :
- Choisis de **générer une nouvelle clé** ou d’**utiliser une clé existante**.
- Sélectionne les **serveurs cibles** (format `utilisateur@ip` ou `utilisateur@hostname`).
- Confirme le déploiement.
- Le script s’occupe du reste : déploiement, vérification et journalisation.

---

## 🗃️ Fichiers générés

- 🔑 `~/.ssh/id_ed25519` : clé privée (ou autre nom si doublon détecté)
- 📄 `~/.ssh/id_ed25519.pub` : clé publique
- 🧾 `ssh_deploy.log` : journal complet des opérations

---

## 📚 Exemple de session

```text
=== GESTION DE LA CLÉ SSH ===
1) Générer une nouvelle paire de clés Ed25519
2) Utiliser une clé publique existante

Serveur #1 : user@192.168.1.10
Serveur #2 : user@myserver.local
Serveur #3 : non

=== RÉCAPITULATIF ===
Clé publique : /home/user/.ssh/id_ed25519.pub
Serveurs : user@192.168.1.10, user@myserver.local
```

---

## 📦 Exemple de commande post-déploiement

Après exécution réussie, tu peux te connecter à un serveur ainsi :
```bash
ssh -i ~/.ssh/id_ed25519 user@192.168.1.10
```

---

## 🧪 Testé sur

- Debian 12 / Ubuntu 22.04
- Bash 5.1+
- Serveurs SSH par défaut (OpenSSH)

---

## 🧑‍💻 Auteur

Script écrit par **DlnSys**  
N'hésitez pas à modifier et adapter le script à vos besoins.

---

## 🛡️ Remarques de sécurité

- Ne partage jamais ta **clé privée** (`id_ed25519`) !
- Vérifie les droits sur tes fichiers `~/.ssh` :
  ```bash
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/id_ed25519
  chmod 644 ~/.ssh/id_ed25519.pub
  ```

---

## 🧾 Licence

Ce script est distribué librement, sans garantie.  
Usage personnel ou professionnel autorisé. Attribution appréciée.

---
