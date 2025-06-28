# 🛡️ UFW & Fail2Ban — Sécurisation interactive du serveur

**Auteur** : DlnSys  
**Version** : 1.0  
**Plateformes** : Debian / Ubuntu (sudo requis)

---

## 📌 Description

`ufw_f2b.sh` est un script Bash interactif conçu pour **sécuriser rapidement un serveur Linux** en configurant les outils **UFW (Uncomplicated Firewall)** et **Fail2Ban**.  
Il automatise les étapes critiques, propose des options personnalisables et génère un **fichier journal de l’exécution** pour archivage ou audit.

---

## ✨ Fonctionnalités

### 🔥 UFW (Pare-feu) :
- Activation du pare-feu
- Définition de règles d'accès (SSH, HTTP, HTTPS, personnalisées)
- Restriction de ports sensibles
- Affichage clair de la politique en place

### 🚫 Fail2Ban :
- Activation et configuration de la protection brute-force
- Surveillance du service SSH (par défaut)
- Filtres prêts pour WordPress, Apache, NGINX, etc.
- Envoi d’alertes par e-mail (optionnel)
- Configuration générée dans `/etc/fail2ban/jail.local`

### 📝 Génération automatique :
- Fichier de log : `/var/log/security_setup_YYYYMMDD_HHMMSS.log`
- Répertoire temporaire : `/tmp/security_configs/`

---

## ⚙️ Prérequis

- OS : Debian ou Ubuntu
- Paquets nécessaires :
  - `ufw`
  - `fail2ban`
  - `mailutils` (si alertes mail activées)

Pour installer tout :
```bash
sudo apt update && sudo apt install ufw fail2ban mailutils -y
```

---

## 🚀 Utilisation

### 1. Rends le script exécutable :
```bash
chmod +x ufw_f2b.sh
```

### 2. Exécute-le avec `sudo` :
```bash
sudo ./ufw_f2b.sh
```

### 3. Suis les instructions à l’écran :
- Choisis les services à autoriser (par ex. SSH, HTTP, HTTPS)
- Active/désactive Fail2Ban
- Configure les alertes (facultatif)

---

## 📂 Fichiers générés

- 🧾 `/var/log/security_setup_YYYYMMDD_HHMMSS.log` — log détaillé
- 📁 `/tmp/security_configs/` — fichiers de configuration générés temporairement
- 🛡️ `/etc/fail2ban/jail.local` — configuration finale de Fail2Ban

---

## 📚 Bonnes pratiques incluses

- Blocage automatique après plusieurs tentatives SSH échouées
- Blocage d’IP malveillantes basé sur des journaux (auth.log, nginx.log, etc.)
- Pare-feu restrictif mais fonctionnel
- Gestion facilitée des ports utilisés

---

## 🧪 Testé sur

- Debian 11
- Ubuntu 20.04 / 22.04

---

## 🧑‍💻 Auteur

Script initialement généré par **Assistant Claude**, avec l’intention d’optimiser la sécurité serveur pour les non-spécialistes comme les admins confirmés.

---

## 🛡️ Avertissement

⚠️ **L’exécution de ce script modifie la configuration du pare-feu et du service SSH**. Assure-toi de ne pas bloquer ton propre accès à distance.

---

## 🧾 Licence

Ce script est fourni librement, sans garantie.  
Utilisation personnelle ou professionnelle autorisée. Attribution appréciée.

---
