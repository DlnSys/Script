#!/bin/bash

set -euo pipefail  # Mode strict au niveau du script (sécurité ++)

# === Paramètres généraux ===
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/ssh_deployment_$(date +%Y%m%d_%H%M%S).log"
readonly DEFAULT_KEY="$HOME/.ssh/id_ed25519.pub"

# Couleurs (affichage console)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# === Fonction de log améliorée ===
log() {
    local level="$1"; shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Affichage avec couleurs
print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        INFO)    echo -e "${BLUE}[ℹ]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[✓]${NC} $message" ;;
        WARNING) echo -e "${YELLOW}[⚠]${NC} $message" ;;
        ERROR)   echo -e "${RED}[✗]${NC} $message" ;;
        *)       echo -e "[?] $message" ;;
    esac
    log "$status" "$message"
}

# Vérifie si une chaîne est une IP valide (IPv4)
validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if ((octet < 0 || octet > 255)); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Vérifie le format utilisateur@host
validate_server_format() {
    local server="$1"
    if [[ ! $server =~ ^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+$ ]]; then
        return 1
    fi
    local user="${server%@*}"
    local host="${server#*@}"
    if [[ $user =~ [[:space:]$\`\'\"] ]]; then
        return 1
    fi
    if validate_ip "$host" || [[ $host =~ ^[a-zA-Z0-9.-]+$ ]]; then
        return 0
    fi
    return 1
}

# Teste la connectivité SSH à une machine
test_ssh_connectivity() {
    local server="$1"
    print_status "INFO" "Test de connectivité vers $server..."
    if timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no "$server" exit 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Génère une paire de clés SSH Ed25519 si besoin
generate_ssh_key_pair() {
    local private_key_path="$HOME/.ssh/id_ed25519"
    local public_key_path="$HOME/.ssh/id_ed25519.pub"

    print_status "INFO" "Génération d'une nouvelle paire de clés SSH Ed25519"

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    local default_comment="$USER@$hostname-$(date +%Y%m%d)"

    echo ""
    print_status "INFO" "Configuration du commentaire de la clé SSH (option -C)"
    echo "Le commentaire permet d'identifier facilement la clé dans les logs et authorized_keys"
    echo ""
    echo "Exemples de commentaires :"
    echo "  • utilisateur@prod"
    echo "  • utilisateur@prod-$(date +%Y%m%d)              (avec date)"
    echo "  • prod-servers             (par usage)"
    echo "  • deploy-key-$(date +%Y%m%d)                (clé de déploiement)"
    echo "  • $default_comment        (proposition par défaut)"
    echo ""

    read -rp "Commentaire pour la clé SSH (-C) : " key_comment
    [[ -z "$key_comment" ]] && key_comment="$default_comment"

    if [[ "$key_comment" =~ [\"\'\\] ]]; then
        print_status "ERROR" "Le commentaire ne peut pas contenir de guillemets ou antislash"
        return 1
    fi

    print_status "INFO" "Génération avec commentaire : $key_comment"
    if ssh-keygen -t ed25519 -f "$private_key_path" -C "$key_comment" -N ""; then
        chmod 600 "$private_key_path"
        chmod 644 "$public_key_path"
        print_status "SUCCESS" "Clé générée : $public_key_path"
        echo "$public_key_path"
    else
        print_status "ERROR" "Échec de la génération de la clé SSH"
        return 1
    fi
}

# Choix interactif de la clé à utiliser
select_or_create_ssh_key() {
    local key_path=""
    print_status "INFO" "=== Gestion de la clé SSH publique ==="

    if [[ -f "$DEFAULT_KEY" ]]; then
        print_status "SUCCESS" "Clé par défaut trouvée : $DEFAULT_KEY"
        local key_info
        key_info=$(ssh-keygen -l -f "$DEFAULT_KEY" 2>/dev/null || echo "Clé invalide")
        echo "Informations : $key_info"
        read -rp "Utiliser cette clé existante ? [O/n] : " use_default
        if [[ "${use_default,,}" != "n" ]]; then
            key_path="$DEFAULT_KEY"
        fi
    fi

    if [[ -z "$key_path" ]]; then
        echo ""
        echo "Options disponibles :"
        echo "1. Générer une nouvelle paire de clés Ed25519 (recommandé)"
        echo "2. Spécifier le chemin d'une clé existante"
        echo ""
        while true; do
            read -rp "Votre choix [1-2] : " key_choice
            case "$key_choice" in
                1)
                    key_path=$(generate_ssh_key_pair)
                    break
                    ;;
                2)
                    while true; do
                        read -rp "Chemin vers votre clé publique SSH : " key_input
                        key_path="${key_input/#\~/$HOME}"  # Expansion du tilde
                        if [[ -f "$key_path" ]]; then
                            break
                        else
                            print_status "ERROR" "Fichier introuvable : $key_path"
                            read -rp "Réessayer ? [O/n] : " retry
                            [[ "${retry,,}" == "n" ]] && return 1
                        fi
                    done
                    break
                    ;;
                *)
                    print_status "ERROR" "Choix invalide"
                    ;;
            esac
        done
    fi

    # Vérifie la validité de la clé sélectionnée
    if ! ssh-keygen -l -f "$key_path" &>/dev/null; then
        print_status "ERROR" "Fichier de clé SSH invalide : $key_path"
        return 1
    fi

    local final_key_info
    final_key_info=$(ssh-keygen -l -f "$key_path" 2>/dev/null || echo "Informations indisponibles")
    print_status "SUCCESS" "Clé SSH validée : $final_key_info"
    echo "$key_path"
}

# Saisie des serveurs cibles (format utilisateur@serveur)
collect_servers() {
    local servers=()
    print_status "INFO" "Collecte des serveurs cibles (format attendu : utilisateur@ip ou utilisateur@hostname)"
    echo "Tapez 'non' pour terminer la saisie."
    while true; do
        read -rp "Quelle id@serveur voulez-vous renseigner (ou 'non' pour arrêter) : " server_input
        if [[ "${server_input,,}" == "non" ]]; then
            break
        fi
        [[ -z "$server_input" ]] && continue
        if validate_server_format "$server_input"; then
            if [[ " ${servers[*]} " == *" $server_input "* ]]; then
                print_status "WARNING" "Serveur déjà ajouté : $server_input"
            else
                servers+=("$server_input")
                print_status "SUCCESS" "Serveur ajouté : $server_input"
            fi
        else
            print_status "ERROR" "Format invalide. Utilisez : utilisateur@ip ou utilisateur@hostname"
        fi
    done
    if [[ ${#servers[@]} -eq 0 ]]; then
        print_status "ERROR" "Aucun serveur spécifié"
        return 1
    fi
    printf '%s\n' "${servers[@]}"
}

# Déploiement sur un serveur donné
deploy_key_to_server() {
    local key_path="$1"
    local server="$2"
    print_status "INFO" "Déploiement vers $server"
    if ! test_ssh_connectivity "$server"; then
        print_status "ERROR" "Impossible de se connecter à $server"
        return 1
    fi
    if ssh-copy-id -i "$key_path" "$server" 2>&1 | tee -a "$LOG_FILE"; then
        print_status "SUCCESS" "Clé déployée avec succès sur $server"
        return 0
    else
        print_status "ERROR" "Échec du déploiement sur $server"
        return 1
    fi
}

# Fonction principale
main_deploy() {
    print_status "INFO" "=== Déploiement de clés SSH - Version Sécurisée ==="
    if ! command -v ssh-copy-id &>/dev/null; then
        print_status "ERROR" "ssh-copy-id n'est pas installé"
        exit 1
    fi
    if ! command -v ssh-keygen &>/dev/null; then
        print_status "ERROR" "ssh-keygen n'est pas installé"
        exit 1
    fi

    # Sélection/Création de la clé SSH
    local key_path
    key_path=$(select_or_create_ssh_key) || exit 1
    print_status "SUCCESS" "Clé SSH prête : $key_path"

    # Collecte des serveurs (tableau)
    local -a servers
    mapfile -t servers < <(collect_servers) || exit 1
    print_status "INFO" "Serveurs à traiter : ${#servers[@]}"

    # Récapitulatif
    echo ""
    echo "=== RÉCAPITULATIF ==="
    echo "Clé SSH : $key_path"
    echo "Serveurs :"
    printf '  - %s\n' "${servers[@]}"
    echo ""
    read -rp "Confirmer le déploiement ? [o/N] : " confirm
    if [[ "${confirm,,}" != "o" ]]; then
        print_status "INFO" "Déploiement annulé"
        exit 0
    fi

    # Boucle de déploiement
    local success_count=0
    local total_count=${#servers[@]}
    for server in "${servers[@]}"; do
        if deploy_key_to_server "$key_path" "$server"; then
            ((success_count++))
        fi
        echo ""
    done

    # Rapport final
    print_status "INFO" "=== RAPPORT FINAL ==="
    print_status "SUCCESS" "Déploiements réussis : $success_count/$total_count"
    if [[ $success_count -eq $total_count ]]; then
        print_status "SUCCESS" "Tous les déploiements ont réussi !"
    else
        print_status "WARNING" "Certains déploiements ont échoué. Consultez $LOG_FILE"
    fi
}

# === Point d'entrée ===
main_deploy "$@"
