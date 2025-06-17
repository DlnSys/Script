# 🔒 SSH Security Hardening — Sécurisation interactive du service SSH

**Auteur** : DlnSys  
**Version** : 1.0  
**Plateformes** : Debian / Ubuntu (sudo requis)

---

## 📌 Description

`ssh_security.sh` est un script Bash interactif conçu pour **renforcer la sécurité du service SSH** sur un serveur Linux.  
Il propose un ensemble de bonnes pratiques de durcissement, vous guide étape par étape, **sauvegarde automatiquement vos fichiers de configuration**, et enregistre un **journal complet des modifications**.

> Ce script est pensé pour les administrateurs système et les utilisateurs soucieux de la sécurité de leurs accès distants.

---

## ✨ Fonctionnalités

- 🔐 Sauvegarde automatique de la configuration actuelle (`sshd_config`)
- 🧱 Durcissement interactif basé sur les bonnes pratiques :
  - Désactivation de l'accès root via SSH
  - Désactivation de l'authentification par mot de passe
  - Forçage de l'usage des clés SSH
  - Modification du port SSH
  - Configuration du délai de connexion, du nombre de tentatives, etc.
- 🔍 Vérification syntaxique après chaque modification
- 📝 Journalisation complète (`/var/log/ssh_security_YYYYMMDD_HHMMSS.log`)
- 📁 Sauvegardes stockées dans `/root/ssh_backups/`

---

## ⚙️ Prérequis

- Accès `root` ou `sudo`
- OS basé sur Debian (Debian 10+, Ubuntu 18.04+)
- `systemctl`, `cp`, `grep`, `sed`, `awk`, `ufw` (facultatif)

---

## 🚀 Utilisation

### 1. Rends le script exécutable :
```bash
chmod +x ssh_security.sh
```

### 2. Lance le script avec `sudo` :
```bash
sudo ./ssh_security.sh
```

### 3. Suis les instructions à l’écran.

Chaque étape propose :
- Une explication de l'option
- Une recommandation
- Un choix interactif (Oui / Non / Personnalisé)

---

## 📦 Fichiers générés

- 🧾 `/var/log/ssh_security_YYYYMMDD_HHMMSS.log` — log complet de l’exécution
- 📂 `/root/ssh_backups/sshd_config_YYYYMMDD_HHMMSS` — sauvegarde de la config précédente

---

## 🛠️ Astuce : Redémarrer SSH proprement

Certaines modifications nécessitent un redémarrage du service SSH :

```bash
sudo systemctl restart ssh
```

Le script le propose automatiquement après validation.

---

## 📚 Bonnes pratiques incluses

- Port non standard (par défaut : 22 → optionnel)
- RootLogin désactivé
- PasswordAuthentication désactivé
- PermitEmptyPasswords désactivé
- MaxAuthTries abaissé
- LoginGraceTime réduit
- Usage de `AllowUsers` ou `AllowGroups` (optionnel)

---

## 🧪 Testé sur

- Debian 11 (Bullseye)
- Ubuntu 20.04 / 22.04 LTS

---

## ⚠️ Mise en garde

🔴 **ATTENTION : Ne pas exécuter ce script à distance sans avoir préalablement configuré l’accès par clé SSH.**  
Sinon, vous risquez de **vous verrouiller hors de votre serveur** après désactivation des mots de passe ou de l'accès root.

---

## 🧑‍💻 Auteur

Script écrit par **DlnSys**  
Libre à l'usage, partage et modification encouragés — avec prudence 😉

---

## 🧾 Licence

Ce script est fourni "tel quel", sans garantie.  
Utilisation libre pour usage personnel ou professionnel. Attribution appréciée.

---
