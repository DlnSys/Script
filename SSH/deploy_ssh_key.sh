#!/bin/bash

deploy_ssh_key_interactive() {
    set -euo pipefail  # Mode strict
    
    # Configuration
    readonly SCRIPT_NAME="$(basename "$0")"
    readonly LOG_FILE="/var/log/ssh_deployment_$(date +%Y%m%d_%H%M%S).log"
    readonly DEFAULT_KEY="$HOME/.ssh/id_ed25519.pub"
    
    # Couleurs pour l'affichage
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly NC='\033[0m' # No Color
    
    # Fonction de logging
    log() {
        local level="$1"
        shift
        local message="$*"
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    }
    
    # Affichage coloré
    print_status() {
        local status="$1"
        local message="$2"
        case "$status" in
            "INFO")  echo -e "${BLUE}[ℹ]${NC} $message" ;;
            "SUCCESS") echo -e "${GREEN}[✓]${NC} $message" ;;
            "WARNING") echo -e "${YELLOW}[⚠]${NC} $message" ;;
            "ERROR")   echo -e "${RED}[✗]${NC} $message" ;;
        esac
        log "$status" "$message"
    }
    
    # Validation d'une adresse IP
    validate_ip() {
        local ip="$1"
        if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            local IFS='.'
            local -a octets=($ip)
            for octet in "${octets[@]}"; do
                if ((octet > 255)); then
                    return 1
                fi
            done
            return 0
        fi
        return 1
    }
    
    # Validation du format utilisateur@serveur
    validate_server_format() {
        local server="$1"
        
        # Format: utilisateur@ip ou utilisateur@hostname
        if [[ ! $server =~ ^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+$ ]]; then
            return 1
        fi
        
        local user="${server%@*}"
        local host="${server#*@}"
        
        # Validation utilisateur (pas de caractères dangereux)
        if [[ $user =~ [[:space:]$\`\'\"] ]]; then
            return 1
        fi
        
        # Validation hostname/IP
        if validate_ip "$host" || [[ $host =~ ^[a-zA-Z0-9.-]+$ ]]; then
            return 0
        fi
        
        return 1
    }
    
    # 📡 Test de connectivité SSH avec timeout
    test_ssh_connectivity() {
        local server="$1"
        local timeout=10
        
        print_status "INFO" "Test de connectivité vers $server..."
        
        if timeout "$timeout" ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no "$server" exit 2>/dev/null; then
            return 0
        else
            return 1
        fi
    }
    
    # 🔑 Génération automatique d'une paire de clés SSH Ed25519
    generate_ssh_key_pair() {
        local private_key_path="$HOME/.ssh/id_ed25519"
        local public_key_path="$HOME/.ssh/id_ed25519.pub"
        
        print_status "INFO" "Génération d'une nouvelle paire de clés SSH Ed25519"
        
        # Création du répertoire .ssh si nécessaire
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        
        # Proposition de commentaires personnalisés avec exemples
        local hostname
        hostname=$(hostname 2>/dev/null || echo "unknown")
        local default_comment="$USER@$hostname-$(date +%Y%m%d)"
        
        echo ""
        print_status "INFO" "Configuration du commentaire de la clé SSH (option -C)"
        echo "Le commentaire permet d'identifier facilement la clé dans les logs et authorized_keys"
        echo ""
        echo "Exemples de commentaires :"
        echo "  • admin@neologix                    (utilisateur@entreprise)"
        echo "  • admin@neologix-$(date +%Y%m%d)              (avec date)"
        echo "  • neologix-prod-servers             (par usage)"
        echo "  • deploy-key-$(date +%Y%m%d)                (clé de déploiement)"
        echo "  • $default_comment        (proposition par défaut)"
        echo ""
        
        read -rp "Commentaire pour la clé SSH (-C) : " key_comment
        
        # Si vide, utiliser le défaut
        if [[ -z "$key_comment" ]]; then
            key_comment="$default_comment"
            print_status "INFO" "Utilisation du commentaire par défaut : $key_comment"
        fi
        
        # Validation du commentaire (pas de caractères dangereux)
        if [[ "$key_comment" =~ [\"\'\\] ]]; then
            print_status "ERROR" "Le commentaire ne peut pas contenir de guillemets ou antislash"
            return 1
        fi
        
        print_status "INFO" "Génération avec commentaire : $key_comment"
        
        # Génération de la paire de clés avec le commentaire personnalisé
        if ssh-keygen -t ed25519 -f "$private_key_path" -C "$key_comment" -N ""; then
            print_status "SUCCESS" "Paire de clés générée avec succès"
            print_status "INFO" "Clé privée : $private_key_path"
            print_status "INFO" "Clé publique : $public_key_path"
            print_status "INFO" "Commentaire : $key_comment"
            
            # Sécurisation des permissions
            chmod 600 "$private_key_path"
            chmod 644 "$public_key_path"
            
            # Affichage de la clé publique pour vérification
            echo ""
            print_status "SUCCESS" "Aperçu de la clé publique générée :"
            echo "$(head -c 80 "$public_key_path")... $key_comment"
            
            echo "$public_key_path"
        else
            print_status "ERROR" "Échec de la génération de la clé SSH"
            exit 1
        fi
    }
    
    # 🔍 Sélection ou création interactive de la clé SSH publique
    select_or_create_ssh_key() {
        local key_path=""
        
        print_status "INFO" "=== Gestion de la clé SSH publique ==="
        
        # Vérification de l'existence de la clé par défaut
        if [[ -f "$DEFAULT_KEY" ]]; then
            echo ""
            print_status "SUCCESS" "Clé par défaut trouvée : $DEFAULT_KEY"
            
            # Affichage des informations de la clé
            local key_info
            key_info=$(ssh-keygen -l -f "$DEFAULT_KEY" 2>/dev/null || echo "Clé invalide")
            echo "Informations : $key_info"
            
            read -rp "Utiliser cette clé existante ? [O/n] : " use_default
            if [[ ${use_default,,} != "n" ]]; then
                key_path="$DEFAULT_KEY"
            fi
        else
            print_status "INFO" "Aucune clé par défaut trouvée ($DEFAULT_KEY)"
        fi
        
        # Si pas de clé sélectionnée, proposer les options
        if [[ -z "$key_path" ]]; then
            echo ""
            echo "Options disponibles :"
            echo "1. Générer une nouvelle paire de clés Ed25519 (recommandé)"
            echo "2. Spécifier le chemin d'une clé existante"
            echo ""
            
            read -rp "Votre choix [1-2] : " key_choice
            
            case "$key_choice" in
                1)
                    # Génération automatique d'une nouvelle clé
                    key_path=$(generate_ssh_key_pair)
                    ;;
                2)
                    # Sélection manuelle d'une clé existante
                    while true; do
                        read -rp "Chemin vers votre clé publique SSH : " key_input
                        key_path="${key_input/#\~/$HOME}"  # Expansion du tilde
                        
                        if [[ -f "$key_path" ]]; then
                            break
                        else
                            print_status "ERROR" "Fichier introuvable : $key_path"
                            read -rp "Réessayer ? [O/n] : " retry
                            if [[ "${retry,,}" == "n" ]]; then
                                exit 1
                            fi
                        fi
                    done
                    ;;
                *)
                    print_status "ERROR" "Choix invalide"
                    exit 1
                    ;;
            esac
        fi
        
        # 🔒 Validation finale du contenu de la clé
        if ! ssh-keygen -l -f "$key_path" &>/dev/null; then
            print_status "ERROR" "Fichier de clé SSH invalide : $key_path"
            exit 1
        fi
        
        # Affichage des informations finales de la clé sélectionnée
        local final_key_info
        final_key_info=$(ssh-keygen -l -f "$key_path" 2>/dev/null || echo "Informations indisponibles")
        print_status "SUCCESS" "Clé SSH validée : $final_key_info"
        
        echo "$key_path"
    }
    
    # Collecte interactive des serveurs
    collect_servers() {
        local -a servers=()
        
        print_status "INFO" "Collecte des serveurs cibles"
        echo "Format attendu : utilisateur@ip ou utilisateur@hostname"
        echo "Exemple : admin@192.168.1.100 ou user@server.domain.com"
        echo ""
        
        while true; do
            read -rp "Quelle id@serveur voulez-vous renseigner (répondez 'non' pour arrêter) : " server_input
            
            if [[ "${server_input,,}" == "non" ]]; then
                break
            fi
            
            if [[ -z "$server_input" ]]; then
                continue
            fi
            
            if validate_server_format "$server_input"; then
                # Vérifier si déjà ajouté
                local already_added=false
                for existing_server in "${servers[@]}"; do
                    if [[ "$existing_server" == "$server_input" ]]; then
                        already_added=true
                        break
                    fi
                done
                
                if [[ "$already_added" == "true" ]]; then
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
            exit 1
        fi
        
        printf '%s\n' "${servers[@]}"
    }
    
    # 🚀 Déploiement de la clé SSH sur un serveur
    deploy_key_to_server() {
        local key_path="$1"
        local server="$2"
        
        print_status "INFO" "Déploiement vers $server"
        
        # Test de connectivité préalable
        if ! test_ssh_connectivity "$server"; then
            print_status "ERROR" "Impossible de se connecter à $server"
            return 1
        fi
        
        # Déploiement avec gestion d'erreur
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
        
        # Vérifications préalables
        if ! command -v ssh-copy-id &>/dev/null; then
            print_status "ERROR" "ssh-copy-id n'est pas installé"
            exit 1
        fi
        
        if ! command -v ssh-keygen &>/dev/null; then
            print_status "ERROR" "ssh-keygen n'est pas installé"
            exit 1
        fi
        
        # 🔑 Sélection ou création de la clé SSH
        local key_path
        key_path=$(select_or_create_ssh_key)
        print_status "SUCCESS" "Clé SSH prête : $key_path"
        
        # Collecte des serveurs
        local -a servers
        readarray -t servers < <(collect_servers)
        
        print_status "INFO" "Serveurs à traiter : ${#servers[@]}"
        
        # Confirmation
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
        
        # Déploiement
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
    
    # Point d'entrée
    main_deploy "$@"
}

# =============================================================================
# 🔧 2. SÉCURISATION SSH DEBIAN INTERACTIVE
# =============================================================================

deploy_ssh_key_interactive "$@"