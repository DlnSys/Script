#!/bin/bash

# Script de déploiement automatisé de clés SSH
# Auteur: Assistant IA
# Version: 1.0

set -euo pipefail

# Configuration
LOG_FILE="ssh_deploy.log"
DEFAULT_KEY_PATH="$HOME/.ssh/id_ed25519"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
USER=$(whoami)

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Tableaux pour stocker les informations
declare -a SERVERS=()
declare -a DEPLOY_STATUS=()

# Fonction de logging
log() {
    local level="$1"
    shift
    local message="$*"
    echo "[$TIMESTAMP] [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCÈS]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERREUR]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[ATTENTION]${NC} $message" ;;
    esac
}

# Fonction pour afficher l'en-tête
show_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║             DÉPLOIEMENT AUTOMATISÉ DE CLÉS SSH               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    log "INFO" "Démarrage du script de déploiement SSH"
}

# Fonction pour générer une nouvelle clé SSH
generate_ssh_key() {
    local key_path="$1"
    local comment="$2"
    
    log "INFO" "Génération d'une nouvelle clé Ed25519..."
    
    if ssh-keygen -t ed25519 -f "$key_path" -C "$comment" -N ""; then
        log "SUCCESS" "Clé SSH générée avec succès : ${key_path}"
        return 0
    else
        log "ERROR" "Échec de la génération de la clé SSH"
        return 1
    fi
}

# Fonction pour trouver un nom de clé disponible
find_available_key_name() {
    local base_name="$1"
    local counter=1
    local key_path="$base_name"
    
    while [[ -f "$key_path" ]]; do
        key_path="${base_name}_${counter}"
        ((counter++))
    done
    
    echo "$key_path"
}

# Fonction pour gérer la clé SSH
handle_ssh_key() {
    echo -e "${YELLOW}=== GESTION DE LA CLÉ SSH ===${NC}"
    echo
    echo "Options disponibles :"
    echo "1) Générer une nouvelle paire de clés Ed25519"
    echo "2) Utiliser une clé publique existante"
    echo
    
    while true; do
        read -p "Votre choix (1 ou 2) : " choice
        case "$choice" in
            1)
                # Génération d'une nouvelle clé
                echo
                echo "Suggestions de commentaires :"
                echo "1) ${USER}@prod"
                echo "2) ${USER}@prod-$(date +%Y%m%d)"
                echo "3) deploy-key-$(date +%Y%m%d)"
                echo "4) Commentaire personnalisé"
                echo
                
                read -p "Choisissez un commentaire (1-4) ou appuyez sur Entrée pour '${USER}@deploy-$(date +%Y%m%d)' : " comment_choice
                
                case "$comment_choice" in
                    1) COMMENT="${USER}@prod" ;;
                    2) COMMENT="${USER}@prod-$(date +%Y%m%d)" ;;
                    3) COMMENT="deploy-key-$(date +%Y%m%d)" ;;
                    4) 
                        read -p "Entrez votre commentaire personnalisé : " COMMENT
                        [[ -z "$COMMENT" ]] && COMMENT="${USER}@deploy-$(date +%Y%m%d)"
                        ;;
                    *) COMMENT="${USER}@deploy-$(date +%Y%m%d)" ;;
                esac
                
                # Vérifier si la clé existe déjà et proposer des alternatives
                if [[ -f "$DEFAULT_KEY_PATH" ]]; then
                    echo
                    log "INFO" "Une clé existe déjà à $DEFAULT_KEY_PATH"
                    echo "Options :"
                    echo "1) Remplacer la clé existante"
                    echo "2) Créer une nouvelle clé avec un nom différent"
                    echo "3) Utiliser la clé existante"
                    echo
                    
                    read -p "Votre choix (1-3) : " key_option
                    case "$key_option" in
                        1)
                            read -p "Confirmer le remplacement de la clé existante ? (o/N) : " replace
                            if [[ ! "$replace" =~ ^[oO]$ ]]; then
                                echo "Opération annulée."
                                continue
                            fi
                            CHOSEN_KEY_PATH="$DEFAULT_KEY_PATH"
                            ;;
                        2)
                            CHOSEN_KEY_PATH=$(find_available_key_name "$DEFAULT_KEY_PATH")
                            log "INFO" "Nouvelle clé sera créée : $CHOSEN_KEY_PATH"
                            ;;
                        3)
                            PUBLIC_KEY_PATH="${DEFAULT_KEY_PATH}.pub"
                            log "SUCCESS" "Utilisation de la clé existante : $PUBLIC_KEY_PATH"
                            break
                            ;;
                        *)
                            echo "Choix invalide."
                            continue
                            ;;
                    esac
                else
                    CHOSEN_KEY_PATH="$DEFAULT_KEY_PATH"
                fi
                
                if generate_ssh_key "$CHOSEN_KEY_PATH" "$COMMENT"; then
                    PUBLIC_KEY_PATH="${CHOSEN_KEY_PATH}.pub"
                    break
                else
                    echo "Échec de la génération. Veuillez réessayer."
                fi
                ;;
            2)
                # Utilisation d'une clé existante
                echo
                read -p "Chemin vers la clé publique [${DEFAULT_KEY_PATH}.pub] : " key_input
                PUBLIC_KEY_PATH="${key_input:-${DEFAULT_KEY_PATH}.pub}"
                
                if [[ ! -f "$PUBLIC_KEY_PATH" ]]; then
                    log "ERROR" "Clé publique introuvable : $PUBLIC_KEY_PATH"
                    continue
                fi
                
                log "SUCCESS" "Clé publique trouvée : $PUBLIC_KEY_PATH"
                break
                ;;
            *)
                echo "Choix invalide. Veuillez saisir 1 ou 2."
                ;;
        esac
    done
    
    # Afficher le contenu de la clé publique
    echo
    echo -e "${GREEN}Clé publique à déployer :${NC}"
    echo "$(cat "$PUBLIC_KEY_PATH")"
    echo
}

# Fonction pour collecter les serveurs cibles
collect_servers() {
    echo -e "${YELLOW}=== COLLECTE DES SERVEURS CIBLES ===${NC}"
    echo
    echo "Format attendu : utilisateur@ip ou utilisateur@hostname"
    echo "Tapez 'non' pour terminer la saisie"
    echo
    
    local server_count=1
    while true; do
        read -p "Serveur #$server_count : " server
        
        if [[ "$server" == "non" ]] || [[ "$server" == "n" ]]; then
            break
        fi
        
        if [[ -z "$server" ]]; then
            continue
        fi
        
        # Validation basique du format
        if [[ ! "$server" =~ ^[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+$ ]]; then
            log "WARNING" "Format invalide. Utilisez : utilisateur@hostname"
            continue
        fi
        
        SERVERS+=("$server")
        log "INFO" "Serveur ajouté : $server"
        ((server_count++))
    done
    
    if [[ ${#SERVERS[@]} -eq 0 ]]; then
        log "ERROR" "Aucun serveur spécifié"
        exit 1
    fi
    
    echo
    log "SUCCESS" "${#SERVERS[@]} serveur(s) collecté(s)"
}

# Fonction pour tester la connectivité SSH
test_connectivity() {
    local server="$1"
    log "INFO" "Test de connectivité vers $server..."
    
    # Timeout de 10 secondes pour le test
    if timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no "$server" "exit" 2>/dev/null; then
        log "SUCCESS" "Connexion SSH réussie (clé déjà déployée) : $server"
        return 0
    elif timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$server" "exit" 2>/dev/null; then
        log "SUCCESS" "Connexion SSH possible : $server"
        return 0
    else
        log "WARNING" "Connexion SSH échouée ou nécessite un mot de passe : $server"
        return 1
    fi
}

# Fonction pour déployer la clé SSH
deploy_key() {
    local server="$1"
    log "INFO" "Déploiement de la clé vers $server..."
    
    # Utilisation de ssh-copy-id avec options robustes
    if ssh-copy-id -o StrictHostKeyChecking=no -i "$PUBLIC_KEY_PATH" "$server" 2>/dev/null; then
        log "SUCCESS" "Clé déployée avec succès : $server"
        DEPLOY_STATUS+=("SUCCESS:$server")
        return 0
    else
        log "ERROR" "Échec du déploiement : $server"
        DEPLOY_STATUS+=("FAILED:$server")
        return 1
    fi
}

# Fonction pour vérifier le déploiement
verify_deployment() {
    local server="$1"
    log "INFO" "Vérification du déploiement vers $server..."
    
    if timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no "$server" "echo 'Connexion SSH sans mot de passe réussie'" 2>/dev/null; then
        log "SUCCESS" "Vérification réussie : $server"
        return 0
    else
        log "ERROR" "Vérification échouée : $server"
        return 1
    fi
}

# Fonction pour afficher le récapitulatif
show_summary() {
    echo
    echo -e "${YELLOW}=== RÉCAPITULATIF ===${NC}"
    echo
    echo -e "${BLUE}Clé publique :${NC} $PUBLIC_KEY_PATH"
    echo -e "${BLUE}Serveurs ciblés :${NC}"
    
    for server in "${SERVERS[@]}"; do
        echo "  • $server"
    done
    
    echo
    echo -e "${BLUE}Logs :${NC} $LOG_FILE"
    echo
}

# Fonction pour afficher les résultats finaux
show_results() {
    echo
    echo -e "${YELLOW}=== RÉSULTATS DU DÉPLOIEMENT ===${NC}"
    echo
    
    local success_count=0
    local failed_count=0
    
    for status in "${DEPLOY_STATUS[@]}"; do
        local result="${status%%:*}"
        local server="${status##*:}"
        
        if [[ "$result" == "SUCCESS" ]]; then
            echo -e "${GREEN}✓${NC} $server"
            ((success_count++))
        else
            echo -e "${RED}✗${NC} $server"
            ((failed_count++))
        fi
    done
    
    echo
    echo -e "${GREEN}Réussis :${NC} $success_count"
    echo -e "${RED}Échecs :${NC} $failed_count"
    echo
    
    if [[ $success_count -gt 0 ]]; then
        log "SUCCESS" "Déploiement terminé : $success_count réussi(s), $failed_count échec(s)"
    else
        log "ERROR" "Aucun déploiement réussi"
    fi
}

# Fonction pour confirmer le déploiement
confirm_deployment() {
    echo
    read -p "Voulez-vous procéder au déploiement ? (o/N) : " confirm
    if [[ ! "$confirm" =~ ^[oO]$ ]]; then
        log "INFO" "Déploiement annulé par l'utilisateur"
        exit 0
    fi
}

# Fonction principale
main() {
    show_header
    
    # Gestion de la clé SSH
    handle_ssh_key
    
    # Collecte des serveurs
    collect_servers
    
    # Affichage du récapitulatif
    show_summary
    
    # Confirmation
    confirm_deployment
    
    echo
    echo -e "${YELLOW}=== DÉPLOIEMENT EN COURS ===${NC}"
    echo
    
    # Test de connectivité et déploiement
    for server in "${SERVERS[@]}"; do
        echo -e "${BLUE}Traitement de $server...${NC}"
        
        # Test de connectivité
        if ! test_connectivity "$server"; then
            echo "  Connexion SSH nécessite probablement un mot de passe"
        fi
        
        # Déploiement
        if deploy_key "$server"; then
            # Vérification du déploiement
            sleep 1
            verify_deployment "$server"
        fi
        
        echo
    done
    
    # Affichage des résultats
    show_results
    
    echo
    echo -e "${BLUE}Logs complets disponibles dans :${NC} $LOG_FILE"
    echo -e "${GREEN}Script terminé avec succès !${NC}"
}

# Gestion des signaux pour un arrêt propre
trap 'echo; log "WARNING" "Script interrompu par l'\''utilisateur"; exit 130' INT TERM

# Vérification des prérequis
if ! command -v ssh-keygen &> /dev/null; then
    log "ERROR" "ssh-keygen n'est pas installé"
    exit 1
fi

if ! command -v ssh-copy-id &> /dev/null; then
    log "ERROR" "ssh-copy-id n'est pas installé"
    exit 1
fi

# Création du répertoire SSH si nécessaire
[[ ! -d "$HOME/.ssh" ]] && mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

# Exécution du script principal
main "$@"