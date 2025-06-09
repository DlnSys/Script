# ============================================================================
# SCRIPT POWERSHELL - ADMINISTRATION ACTIVE DIRECTORY
# ============================================================================
# Description : Script interactif pour créer des OU, groupes et utilisateurs AD
# Auteur : Administrateur système
# Version : 1.1 - Corrigée
# ============================================================================

# Import du module Active Directory
Import-Module ActiveDirectory

# ============================================================================
# VARIABLES GLOBALES ET CONFIGURATION
# ============================================================================

# Variables globales pour stocker les informations saisies
$Global:DomainInfo = @{}
$Global:OUPrincipale = ""
$Global:OUList = @()
$Global:GroupesList = @()
$Global:MotDePasseGenerique = ""
$Global:FormatEmail = ""
$Global:LogFile = ""

# ============================================================================
# FONCTIONS UTILITAIRES
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Type = "INFO"
    )
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$TimeStamp] [$Type] $Message"
    
    # Affichage console avec couleurs
    switch ($Type) {
        "ERROR" { Write-Host $LogEntry -ForegroundColor Red }
        "SUCCESS" { Write-Host $LogEntry -ForegroundColor Green }
        "WARNING" { Write-Host $LogEntry -ForegroundColor Yellow }
        default { Write-Host $LogEntry -ForegroundColor Cyan }
    }
    
    # Écriture dans le fichier de log
    if (![string]::IsNullOrEmpty($Global:LogFile)) {
        Add-Content -Path $Global:LogFile -Value $LogEntry
    }
}

function Show-Banner {
    Clear-Host
    Write-Host "============================================================================" -ForegroundColor Magenta
    Write-Host "           SCRIPT D'ADMINISTRATION ACTIVE DIRECTORY" -ForegroundColor Magenta
    Write-Host "============================================================================" -ForegroundColor Magenta
    Write-Host ""
}

function Confirm-Action {
    param([string]$Message)
    do {
        $response = Read-Host "$Message (O/N)"
    } while ($response -notmatch '^[ONon]$')
    return ($response -match '^[Oo]$')
}

# ============================================================================
# ÉTAPE 1 : CONFIGURATION INITIALE
# ============================================================================

function Initialize-Configuration {
    Show-Banner
    Write-Host "ÉTAPE 1 : CONFIGURATION INITIALE" -ForegroundColor Yellow
    Write-Host "=================================" -ForegroundColor Yellow
    Write-Host ""
    
    # Configuration du fichier de logs
    $LogPath = Read-Host "Entrez le chemin pour le fichier de logs (ou appuyez sur Entrée pour utiliser le répertoire courant)"
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = $PWD.Path
    }
    $Global:LogFile = Join-Path $LogPath "AD_Administration_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    
    Write-Log "Démarrage du script d'administration Active Directory"
    
    # Configuration du domaine
    Write-Host "Configuration du domaine :" -ForegroundColor Cyan
    
    # Détection des domaines existants
    try {
        $currentDomain = Get-ADDomain -ErrorAction Stop
        $availableDomains = @($currentDomain)
        
        # Tentative de récupération d'autres domaines dans la forêt
        try {
            $forest = Get-ADForest -ErrorAction SilentlyContinue
            if ($forest) {
                $availableDomains = $forest.Domains | ForEach-Object {
                    try {
                        Get-ADDomain -Identity $_ -ErrorAction SilentlyContinue
                    } catch { }
                } | Where-Object { $_ -ne $null }
            }
        } catch { }
        
        if ($availableDomains.Count -gt 0) {
            Write-Host "Domaines Active Directory détectés :" -ForegroundColor Green
            for ($i = 0; $i -lt $availableDomains.Count; $i++) {
                Write-Host "  $($i + 1). $($availableDomains[$i].DNSRoot) | DN: $($availableDomains[$i].DistinguishedName)" -ForegroundColor Green
            }
            Write-Host "  $($availableDomains.Count + 1). Créer/Spécifier un nouveau domaine" -ForegroundColor Yellow
            Write-Host ""
            
            do {
                $choixDomain = Read-Host "Choisissez un domaine (1-$($availableDomains.Count + 1))"
            } while ($choixDomain -notmatch '^\d+$' -or [int]$choixDomain -lt 1 -or [int]$choixDomain -gt ($availableDomains.Count + 1))
            
            if ([int]$choixDomain -le $availableDomains.Count) {
                # Utilisation d'un domaine existant
                $selectedDomain = $availableDomains[[int]$choixDomain - 1]
                $Global:DomainInfo = @{
                    Name = $selectedDomain.DNSRoot
                    DN = $selectedDomain.DistinguishedName
                }
                Write-Log "Domaine existant sélectionné : $($Global:DomainInfo.Name) | DN : $($Global:DomainInfo.DN)" "SUCCESS"
            } else {
                # Création/Spécification d'un nouveau domaine
                $domainName = Read-Host "Entrez le nom du nouveau domaine (ex: entreprise.local)"
                $domainParts = $domainName.Split('.')
                
                $Global:DomainInfo = @{
                    Name = $domainName
                    DN = ($domainParts | ForEach-Object { "DC=$_" }) -join ","
                }
                Write-Log "Nouveau domaine configuré : $($Global:DomainInfo.Name) | DN : $($Global:DomainInfo.DN)" "SUCCESS"
            }
        } else {
            # Aucun domaine détecté, saisie manuelle
            Write-Host "Aucun domaine Active Directory détecté." -ForegroundColor Yellow
            $domainName = Read-Host "Entrez le nom du domaine (ex: entreprise.local)"
            $domainParts = $domainName.Split('.')
            
            $Global:DomainInfo = @{
                Name = $domainName
                DN = ($domainParts | ForEach-Object { "DC=$_" }) -join ","
            }
            Write-Log "Domaine configuré manuellement : $($Global:DomainInfo.Name) | DN : $($Global:DomainInfo.DN)" "SUCCESS"
        }
    }
    catch {
        # Erreur lors de la détection, saisie manuelle
        Write-Host "Impossible de détecter les domaines Active Directory (Erreur: $($_.Exception.Message))" -ForegroundColor Yellow
        Write-Host "Configuration manuelle requise." -ForegroundColor Yellow
        $domainName = Read-Host "Entrez le nom du domaine (ex: entreprise.local)"
        $domainParts = $domainName.Split('.')
        
        $Global:DomainInfo = @{
            Name = $domainName
            DN = ($domainParts | ForEach-Object { "DC=$_" }) -join ","
        }
        Write-Log "Domaine configuré manuellement après erreur : $($Global:DomainInfo.Name) | DN : $($Global:DomainInfo.DN)" "SUCCESS"
    }
    
    # Configuration de l'OU principale
    Write-Host "`nConfiguration de l'OU principale :" -ForegroundColor Cyan
    $Global:OUPrincipale = Read-Host "Entrez le nom de l'OU principale (sans le préfixe OU_)"
    $Global:OUPrincipale = "OU_$($Global:OUPrincipale)"
    
    Write-Log "OU principale configurée : $Global:OUPrincipale"
    
    # Configuration du mot de passe générique
    Write-Host "`nConfiguration du mot de passe générique :" -ForegroundColor Cyan
    do {
        $Global:MotDePasseGenerique = Read-Host "Entrez le mot de passe générique pour tous les utilisateurs" -AsSecureString
        $confirmPassword = Read-Host "Confirmez le mot de passe" -AsSecureString
        
        $pwd1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Global:MotDePasseGenerique))
        $pwd2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmPassword))
        
        if ($pwd1 -ne $pwd2) {
            Write-Host "Les mots de passe ne correspondent pas. Veuillez recommencer." -ForegroundColor Red
        }
    } while ($pwd1 -ne $pwd2)
    
    Write-Log "Mot de passe générique configuré"
    
    # Configuration du format d'email
    Write-Host "`nConfiguration du format d'email :" -ForegroundColor Cyan
    Write-Host "Exemples de formats :"
    Write-Host "1. P.nom@domain (ex: J.dupont@entreprise.local)"
    Write-Host "2. prenom.nom@domain (ex: jean.dupont@entreprise.local)"
    Write-Host "3. nom.prenom@domain (ex: dupont.jean@entreprise.local)"
    
    do {
        $choixFormat = Read-Host "Choisissez le format (1, 2 ou 3)"
    } while ($choixFormat -notmatch '^[123]$')
    
    switch ($choixFormat) {
        "1" { $Global:FormatEmail = "P.nom@$($Global:DomainInfo.Name)" }
        "2" { $Global:FormatEmail = "prenom.nom@$($Global:DomainInfo.Name)" }
        "3" { $Global:FormatEmail = "nom.prenom@$($Global:DomainInfo.Name)" }
    }
    
    Write-Log "Format d'email configuré : $Global:FormatEmail"
    
    Write-Host "`nConfiguration terminée !" -ForegroundColor Green
    Read-Host "Appuyez sur Entrée pour continuer"
}

# ============================================================================
# ÉTAPE 2 : CRÉATION DES UNITÉS D'ORGANISATION
# ============================================================================

function Create-OrganizationalUnits {
    Show-Banner
    Write-Host "ÉTAPE 2 : CRÉATION DES UNITÉS D'ORGANISATION" -ForegroundColor Yellow
    Write-Host "=============================================" -ForegroundColor Yellow
    Write-Host ""
    
    # Création de l'OU principale
    Write-Host "Création de l'OU principale : $Global:OUPrincipale" -ForegroundColor Cyan
    
    if (Confirm-Action "Confirmer la création de l'OU principale '$Global:OUPrincipale'") {
        try {
            New-ADOrganizationalUnit -Name $Global:OUPrincipale -Path $Global:DomainInfo.DN -ErrorAction Stop
            Write-Log "OU principale créée avec succès : $Global:OUPrincipale" "SUCCESS"
        }
        catch {
            Write-Log "Erreur lors de la création de l'OU principale : $($_.Exception.Message)" "ERROR"
            return $false
        }
    }
    
    # Création de l'OU pour les Domain Local
    $OUDomainLocal = "OU_DomainLocal"
    Write-Host "`nCréation de l'OU pour les groupes Domain Local : $OUDomainLocal" -ForegroundColor Cyan
    
    if (Confirm-Action "Confirmer la création de l'OU '$OUDomainLocal'") {
        try {
            New-ADOrganizationalUnit -Name $OUDomainLocal -Path "OU=$Global:OUPrincipale,$($Global:DomainInfo.DN)" -ErrorAction Stop
            Write-Log "OU Domain Local créée avec succès : $OUDomainLocal" "SUCCESS"
        }
        catch {
            Write-Log "Erreur lors de la création de l'OU Domain Local : $($_.Exception.Message)" "ERROR"
        }
    }
    
    # Saisie des OU de services
    Write-Host "`nSaisie des unités d'organisation de services :" -ForegroundColor Cyan
    Write-Host "Entrez les noms des services/départements (le préfixe OU_ sera ajouté automatiquement)"
    Write-Host "Tapez 'fin' ou laissez vide pour terminer la saisie"
    Write-Host ""
    
    do {
        $serviceName = Read-Host "Nom du service"
        
        if (![string]::IsNullOrWhiteSpace($serviceName) -and $serviceName -ne "fin") {
            $ouName = "OU_$serviceName"
            
            if (Confirm-Action "Confirmer la création de l'OU '$ouName'") {
                try {
                    New-ADOrganizationalUnit -Name $ouName -Path "OU=$Global:OUPrincipale,$($Global:DomainInfo.DN)" -ErrorAction Stop
                    $Global:OUList += $ouName
                    Write-Log "OU de service créée avec succès : $ouName" "SUCCESS"
                }
                catch {
                    Write-Log "Erreur lors de la création de l'OU '$ouName' : $($_.Exception.Message)" "ERROR"
                }
            }
        }
    } while (![string]::IsNullOrWhiteSpace($serviceName) -and $serviceName -ne "fin")
    
    Write-Host "`nOU créées :" -ForegroundColor Green
    $Global:OUList | ForEach-Object { Write-Host "  - $_" -ForegroundColor Green }
    
    Read-Host "Appuyez sur Entrée pour continuer"
    return $true
}

# ============================================================================
# ÉTAPE 3 : CRÉATION DES GROUPES DE SÉCURITÉ
# ============================================================================

function Create-SecurityGroups {
    Show-Banner
    Write-Host "ÉTAPE 3 : CRÉATION DES GROUPES DE SÉCURITÉ" -ForegroundColor Yellow
    Write-Host "===========================================" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "Types de groupes disponibles :" -ForegroundColor Cyan
    Write-Host "1. Groupes Globaux (GG_) - Format: GG_(NomService_NomFonction)"
    Write-Host "2. Groupes Domain Local (DL_) - Format: DL_(NomService_NomFonction_TypeAccès)"
    Write-Host ""
    Write-Host "Types d'accès pour les DL_ :"
    Write-Host "  CT = Contrôle total"
    Write-Host "  RW = ReadWrite"
    Write-Host "  R = Read"
    Write-Host ""
    Write-Host "Tapez 'fin' ou laissez vide pour terminer la saisie"
    Write-Host ""
    
    do {
        $typeGroupe = ""
        do {
            $typeGroupe = Read-Host "Type de groupe (1=GG_, 2=DL_, fin pour terminer)"
        } while ($typeGroupe -notmatch '^[12]$|^fin$|^$')
        
        if ($typeGroupe -eq "fin" -or [string]::IsNullOrWhiteSpace($typeGroupe)) {
            break
        }
        
        if ($typeGroupe -eq "1") {
            # Création d'un groupe global
            $nomService = Read-Host "Nom du service"
            $nomFonction = Read-Host "Nom de la fonction"
            
            if (![string]::IsNullOrWhiteSpace($nomService) -and ![string]::IsNullOrWhiteSpace($nomFonction)) {
                $groupName = "GG_$($nomService)_$($nomFonction)"
                
                if (Confirm-Action "Confirmer la création du groupe '$groupName'") {
                    $groupInfo = @{
                        Name = $groupName
                        Type = "Global"
                        Service = $nomService
                        Fonction = $nomFonction
                        Path = ""
                    }
                    $Global:GroupesList += $groupInfo
                    Write-Log "Groupe global ajouté à la liste : $groupName" "SUCCESS"
                }
            }
        }
        elseif ($typeGroupe -eq "2") {
            # Création d'un groupe domain local
            $nomService = Read-Host "Nom du service"
            $nomFonction = Read-Host "Nom de la fonction"
            
            do {
                $typeAcces = Read-Host "Type d'accès (CT/RW/R)"
            } while ($typeAcces -notmatch '^(CT|RW|R)$')
            
            if (![string]::IsNullOrWhiteSpace($nomService) -and ![string]::IsNullOrWhiteSpace($nomFonction)) {
                $groupName = "DL_$($nomService)_$($nomFonction)_$($typeAcces)"
                
                # Description basée sur le type d'accès et le service
                $description = switch ($typeAcces) {
                    "CT" { "Contrôle total pour le service $nomService" }
                    "RW" { "Lecture/Écriture pour le service $nomService" }
                    "R" { "Lecture seule pour le service $nomService" }
                }
                
                if (Confirm-Action "Confirmer la création du groupe '$groupName'") {
                    $groupInfo = @{
                        Name = $groupName
                        Type = "DomainLocal"
                        Service = $nomService
                        Fonction = $nomFonction
                        TypeAcces = $typeAcces
                        Description = $description
                        Path = ""
                    }
                    $Global:GroupesList += $groupInfo
                    Write-Log "Groupe domain local ajouté à la liste : $groupName" "SUCCESS"
                }
            }
        }
    } while ($true)
    
    Write-Host "`nGroupes à créer :" -ForegroundColor Green
    $Global:GroupesList | ForEach-Object {
        Write-Host "  - $($_.Name) ($($_.Type))" -ForegroundColor Green
    }
    
    Read-Host "Appuyez sur Entrée pour continuer"
}

# ============================================================================
# ÉTAPE 4 : ASSOCIATION DES GROUPES AUX OU
# ============================================================================

function Associate-GroupsToOUs {
    Show-Banner
    Write-Host "ÉTAPE 4 : ASSOCIATION DES GROUPES AUX UNITÉS D'ORGANISATION" -ForegroundColor Yellow
    Write-Host "===========================================================" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "OU disponibles :" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Global:OUList.Count; $i++) {
        Write-Host "  $($i + 1). $($Global:OUList[$i])" -ForegroundColor Cyan
    }
    Write-Host ""
    
    # Association des groupes globaux aux OU de services
    $groupesGlobaux = $Global:GroupesList | Where-Object { $_.Type -eq "Global" }
    
    foreach ($group in $groupesGlobaux) {
        Write-Host "Association du groupe global : $($group.Name)" -ForegroundColor Yellow
        
        do {
            $choixOU = Read-Host "Choisissez l'OU de destination (1-$($Global:OUList.Count))"
        } while ($choixOU -notmatch '^\d+$' -or [int]$choixOU -lt 1 -or [int]$choixOU -gt $Global:OUList.Count)
        
        $selectedOU = $Global:OUList[[int]$choixOU - 1]
        $group.Path = "OU=$selectedOU,OU=$Global:OUPrincipale,$($Global:DomainInfo.DN)"
        
        Write-Log "Groupe '$($group.Name)' associé à l'OU '$selectedOU'" "SUCCESS"
    }
    
    # Association automatique des groupes domain local à l'OU_DomainLocal
    $groupesDL = $Global:GroupesList | Where-Object { $_.Type -eq "DomainLocal" }
    
    foreach ($group in $groupesDL) {
        $group.Path = "OU=OU_DomainLocal,OU=$Global:OUPrincipale,$($Global:DomainInfo.DN)"
        Write-Log "Groupe DL '$($group.Name)' associé automatiquement à OU_DomainLocal" "SUCCESS"
    }
    
    Write-Host "`nAssociations terminées !" -ForegroundColor Green
    Read-Host "Appuyez sur Entrée pour continuer"
}

# ============================================================================
# ÉTAPE 5 : CRÉATION EFFECTIVE DES GROUPES
# ============================================================================

function Create-Groups {
    Show-Banner
    Write-Host "ÉTAPE 5 : CRÉATION EFFECTIVE DES GROUPES" -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Yellow
    Write-Host ""
    
    foreach ($group in $Global:GroupesList) {
        try {
            $groupParams = @{
                Name = $group.Name
                Path = $group.Path
                GroupScope = if ($group.Type -eq "Global") { "Global" } else { "DomainLocal" }
                GroupCategory = "Security"
            }
            
            if ($group.Type -eq "DomainLocal" -and $group.Description) {
                $groupParams.Description = $group.Description
            }
            
            New-ADGroup @groupParams -ErrorAction Stop
            Write-Log "Groupe créé avec succès : $($group.Name) dans $($group.Path)" "SUCCESS"
        }
        catch {
            Write-Log "Erreur lors de la création du groupe '$($group.Name)' : $($_.Exception.Message)" "ERROR"
        }
    }
    
    Read-Host "Appuyez sur Entrée pour continuer"
}

# ============================================================================
# ÉTAPE 6 : ASSOCIATION DES GROUPES DL AUX GG
# ============================================================================

function Associate-DLToGG {
    Show-Banner
    Write-Host "ÉTAPE 6 : ASSOCIATION DES GROUPES DOMAIN LOCAL AUX GROUPES GLOBAUX" -ForegroundColor Yellow
    Write-Host "===================================================================" -ForegroundColor Yellow
    Write-Host ""
    
    $groupesGlobaux = $Global:GroupesList | Where-Object { $_.Type -eq "Global" }
    $groupesDL = $Global:GroupesList | Where-Object { $_.Type -eq "DomainLocal" }
    
    if ($groupesGlobaux.Count -eq 0 -or $groupesDL.Count -eq 0) {
        Write-Log "Aucune association possible - pas assez de groupes de types différents" "WARNING"
        Read-Host "Appuyez sur Entrée pour continuer"
        return
    }
    
    Write-Host "Groupes Domain Local disponibles :" -ForegroundColor Cyan
    for ($i = 0; $i -lt $groupesDL.Count; $i++) {
        Write-Host "  $($i + 1). $($groupesDL[$i].Name)" -ForegroundColor Cyan
    }
    Write-Host ""
    
    Write-Host "Groupes Globaux disponibles :" -ForegroundColor Cyan
    for ($i = 0; $i -lt $groupesGlobaux.Count; $i++) {
        Write-Host "  $($i + 1). $($groupesGlobaux[$i].Name)" -ForegroundColor Cyan
    }
    Write-Host ""
    
    foreach ($ggGroup in $groupesGlobaux) {
        Write-Host "Association pour le groupe global : $($ggGroup.Name)" -ForegroundColor Yellow
        
        do {
            $choixDL = Read-Host "Choisissez le groupe DL à associer (1-$($groupesDL.Count), 0 pour passer)"
        } while ($choixDL -notmatch '^\d+$' -or [int]$choixDL -lt 0 -or [int]$choixDL -gt $groupesDL.Count)
        
        if ([int]$choixDL -gt 0) {
            $selectedDL = $groupesDL[[int]$choixDL - 1]
            
            try {
                Add-ADGroupMember -Identity $selectedDL.Name -Members $ggGroup.Name -ErrorAction Stop
                Write-Log "Groupe '$($ggGroup.Name)' ajouté au groupe '$($selectedDL.Name)'" "SUCCESS"
            }
            catch {
                Write-Log "Erreur lors de l'association '$($ggGroup.Name)' -> '$($selectedDL.Name)' : $($_.Exception.Message)" "ERROR"
            }
        }
    }
    
    Read-Host "Appuyez sur Entrée pour continuer"
}

# ============================================================================
# ÉTAPE 7 : IMPORTATION DES UTILISATEURS
# ============================================================================

function Import-Users {
    Show-Banner
    Write-Host "ÉTAPE 7 : IMPORTATION DES UTILISATEURS" -ForegroundColor Yellow
    Write-Host "=======================================" -ForegroundColor Yellow
    Write-Host ""
    
    # Demande du chemin du fichier CSV
    Write-Host "Format CSV attendu :" -ForegroundColor Cyan
    Write-Host "prenom,nom,fonction,Department_OU,GroupToAdd1,GroupToAdd2" -ForegroundColor Cyan
    Write-Host "Exemple :"
    Write-Host "Jean,Dupont,Administrateur,IT,GG_IT_Admin,DL_IT_Admin_CT" -ForegroundColor Gray
    Write-Host ""
    
    do {
        $csvPath = Read-Host "Entrez le chemin complet du fichier CSV"
        if (!(Test-Path $csvPath)) {
            Write-Host "Fichier introuvable. Veuillez vérifier le chemin." -ForegroundColor Red
        }
    } while (!(Test-Path $csvPath))
    
    try {
        $users = Import-Csv -Path $csvPath -Delimiter "," -ErrorAction Stop
        Write-Log "Fichier CSV importé avec succès : $($users.Count) utilisateurs trouvés" "SUCCESS"
    }
    catch {
        Write-Log "Erreur lors de l'importation du CSV : $($_.Exception.Message)" "ERROR"
        return
    }
    
    # Affichage des OU disponibles pour le choix de destination
    Write-Host "`nOU disponibles pour les utilisateurs :" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Global:OUList.Count; $i++) {
        Write-Host "  $($i + 1). $($Global:OUList[$i])" -ForegroundColor Cyan
    }
    
    # Traitement de chaque utilisateur
    foreach ($user in $users) {
        Write-Host "`nTraitement de l'utilisateur : $($user.prenom) $($user.nom)" -ForegroundColor Yellow
        
        # Génération de l'email selon le format choisi
        $email = switch ($Global:FormatEmail) {
            { $_.StartsWith("P.nom") } { 
                "$($user.prenom.Substring(0,1)).$($user.nom)@$($Global:DomainInfo.Name)".ToLower()
            }
            { $_.StartsWith("prenom.nom") } { 
                "$($user.prenom).$($user.nom)@$($Global:DomainInfo.Name)".ToLower()
            }
            { $_.StartsWith("nom.prenom") } { 
                "$($user.nom).$($user.prenom)@$($Global:DomainInfo.Name)".ToLower()
            }
        }
        
        # Nettoyage de l'email (suppression des accents et caractères spéciaux)
        $email = $email -replace '[àáâãäå]', 'a' -replace '[èéêë]', 'e' -replace '[ìíîï]', 'i' -replace '[òóôõö]', 'o' -replace '[ùúûü]', 'u' -replace '[ç]', 'c' -replace '[ñ]', 'n' -replace '[^a-z0-9@.]', ''
        
        # Détermination de l'OU de destination
        $ouDestination = ""
        if (![string]::IsNullOrWhiteSpace($user.Department_OU)) {
            $ouName = "OU_$($user.Department_OU)"
            if ($Global:OUList -contains $ouName) {
                $ouDestination = "OU=$ouName,OU=$Global:OUPrincipale,$($Global:DomainInfo.DN)"
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($ouDestination)) {
            Write-Host "OU de destination non trouvée pour $($user.Department_OU). Choisissez manuellement :" -ForegroundColor Yellow
            do {
                $choixOU = Read-Host "Choisissez l'OU (1-$($Global:OUList.Count))"
            } while ($choixOU -notmatch '^\d+$' -or [int]$choixOU -lt 1 -or [int]$choixOU -gt $Global:OUList.Count)
            
            $selectedOU = $Global:OUList[[int]$choixOU - 1]
            $ouDestination = "OU=$selectedOU,OU=$Global:OUPrincipale,$($Global:DomainInfo.DN)"
        }
        
        # Création de l'utilisateur
        try {
            $userParams = @{
                Name = "$($user.prenom) $($user.nom)"
                GivenName = $user.prenom
                Surname = $user.nom
                SamAccountName = "$($user.prenom).$($user.nom)".ToLower()
                UserPrincipalName = $email
                EmailAddress = $email
                Title = $user.fonction
                Path = $ouDestination
                AccountPassword = $Global:MotDePasseGenerique
                ChangePasswordAtLogon = $true
                Enabled = $true
            }
            
            New-ADUser @userParams -ErrorAction Stop
            Write-Log "Utilisateur créé avec succès : $($userParams.Name) | Email : $email" "SUCCESS"
            
            # Ajout aux groupes
            $groupsToAdd = @()
            if (![string]::IsNullOrWhiteSpace($user.GroupToAdd1)) { $groupsToAdd += $user.GroupToAdd1 }
            if (![string]::IsNullOrWhiteSpace($user.GroupToAdd2)) { $groupsToAdd += $user.GroupToAdd2 }
            
            foreach ($groupName in $groupsToAdd) {
                try {
                    Add-ADGroupMember -Identity $groupName -Members $userParams.SamAccountName -ErrorAction Stop
                    Write-Log "Utilisateur '$($userParams.SamAccountName)' ajouté au groupe '$groupName'" "SUCCESS"
                }
                catch {
                    Write-Log "Erreur lors de l'ajout au groupe '$groupName' : $($_.Exception.Message)" "ERROR"
                }
            }
        }
        catch {
            Write-Log "Erreur lors de la création de l'utilisateur '$($user.prenom) $($user.nom)' : $($_.Exception.Message)" "ERROR"
        }
    }
    
    Write-Host "`nImportation des utilisateurs terminée !" -ForegroundColor Green
    Read-Host "Appuyez sur Entrée pour continuer"
}

# ============================================================================
# FONCTION PRINCIPALE
# ============================================================================

function Start-ADAdministration {
    try {
        # Vérification des prérequis
        if (!(Get-Module -Name ActiveDirectory -ListAvailable)) {
            Write-Host "Le module Active Directory n'est pas disponible. Veuillez l'installer." -ForegroundColor Red
            return
        }
        
        # Exécution des étapes
        Initialize-Configuration
        
        if (Create-OrganizationalUnits) {
            Create-SecurityGroups
            Associate-GroupsToOUs
            Create-Groups
            Associate-DLToGG
            Import-Users
        }
        
        # Résumé final
        Show-Banner
        Write-Host "SCRIPT TERMINÉ AVEC SUCCÈS !" -ForegroundColor Green
        Write-Host "============================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Résumé des actions :" -ForegroundColor Cyan
        Write-Host "- OU principale créée : $Global:OUPrincipale" -ForegroundColor White
        Write-Host "- OU de services créées : $($Global:OUList.Count)" -ForegroundColor White
        Write-Host "- Groupes créés : $($Global:GroupesList.Count)" -ForegroundColor White
        Write-Host "- Fichier de logs : $Global:LogFile" -ForegroundColor White
        Write-Host ""
        Write-Log "Script terminé avec succès" "SUCCESS"
        
    }
    catch {
        Write-Log "Erreur critique dans le script principal : $($_.Exception.Message)" "ERROR"
    }
}

# ============================================================================
# FONCTIONS BONUS - GESTION AVANCÉE
# ============================================================================

function Get-ADSummary {
    <#
    .SYNOPSIS
    Affiche un résumé de l'Active Directory
    #>
    Show-Banner
    Write-Host "RÉSUMÉ DE L'ACTIVE DIRECTORY" -ForegroundColor Yellow
    Write-Host "=============================" -ForegroundColor Yellow
    Write-Host ""
    
    try {
        # Informations du domaine
        $domain = Get-ADDomain
        Write-Host "Domaine : $($domain.DNSRoot)" -ForegroundColor Cyan
        Write-Host "DN : $($domain.DistinguishedName)" -ForegroundColor Cyan
        
        # Comptage des objets
        $users = (Get-ADUser -Filter *).Count
        $computers = (Get-ADComputer -Filter *).Count
        $groups = (Get-ADGroup -Filter *).Count
        $ous = (Get-ADOrganizationalUnit -Filter *).Count
        
        Write-Host "`nStatistiques :" -ForegroundColor Green
        Write-Host "  Utilisateurs : $users" -ForegroundColor White
        Write-Host "  Ordinateurs : $computers" -ForegroundColor White
        Write-Host "  Groupes : $groups" -ForegroundColor White
        Write-Host "  Unités d'organisation : $ous" -ForegroundColor White
        
    }
    catch {
        Write-Host "Erreur lors de la récupération des informations : $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Read-Host "`nAppuyez sur Entrée pour continuer"
}

function Remove-ADTestObjects {
    <#
    .SYNOPSIS
    Supprime les objets de test créés par le script
    #>
    Show-Banner
    Write-Host "SUPPRESSION DES OBJETS DE TEST" -ForegroundColor Yellow
    Write-Host "===============================" -ForegroundColor Yellow
    Write-Host ""
    
    $ouPrincipaleName = Read-Host "Entrez le nom de l'OU principale à supprimer (ex: OU_MonEntreprise)"
    
    if (Confirm-Action "ATTENTION : Êtes-vous sûr de vouloir supprimer l'OU '$ouPrincipaleName' et tous ses objets enfants ?") {
        try {
            # Recherche de l'OU
            $ou = Get-ADOrganizationalUnit -Filter "Name -eq '$ouPrincipaleName'" -ErrorAction Stop
            
            if ($ou) {
                # Suppression récursive
                Remove-ADOrganizationalUnit -Identity $ou.DistinguishedName -Recursive -Confirm:$false -ErrorAction Stop
                Write-Host "OU '$ouPrincipaleName' et tous ses objets enfants supprimés avec succès." -ForegroundColor Green
            } else {
                Write-Host "OU '$ouPrincipaleName' introuvable." -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "Erreur lors de la suppression : $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Read-Host "Appuyez sur Entrée pour continuer"
}

function Show-Menu {
    <#
    .SYNOPSIS
    Affiche le menu principal du script
    #>
    do {
        Show-Banner
        Write-Host "MENU PRINCIPAL" -ForegroundColor Yellow
        Write-Host "==============" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "1. Exécuter le script complet d'administration AD" -ForegroundColor Cyan
        Write-Host "2. Afficher le résumé de l'Active Directory" -ForegroundColor Cyan
        Write-Host "3. Supprimer des objets de test" -ForegroundColor Cyan
        Write-Host "4. Quitter" -ForegroundColor Cyan
        Write-Host ""
        
        $choice = Read-Host "Choisissez une option (1-4)"
        
        switch ($choice) {
            "1" { Start-ADAdministration }
            "2" { Get-ADSummary }
            "3" { Remove-ADTestObjects }
            "4" { 
                Write-Host "Au revoir !" -ForegroundColor Green
                return 
            }
            default { 
                Write-Host "Option invalide. Veuillez choisir entre 1 et 4." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    } while ($true)
}

# ============================================================================
# EXEMPLE DE FICHIER CSV
# ============================================================================

function Create-SampleCSV {
    <#
    .SYNOPSIS
    Crée un fichier CSV d'exemple pour les utilisateurs
    #>
    $csvContent = @"
prenom,nom,fonction,Department_OU,GroupToAdd1,GroupToAdd2
Jean,Dupont,Administrateur Système,IT,GG_IT_Admin,DL_IT_Admin_CT
Marie,Martin,Développeuse,IT,GG_IT_Dev,DL_IT_Dev_RW
Pierre,Durand,Comptable,Finance,GG_Finance_User,DL_Finance_User_R
Sophie,Bernard,Responsable RH,RH,GG_RH_Manager,DL_RH_Manager_CT
"@
    
    $csvPath = Join-Path $PWD.Path "exemple_utilisateurs.csv"
    $csvContent | Out-File -FilePath $csvPath -Encoding UTF8
    Write-Host "Fichier CSV d'exemple créé : $csvPath" -ForegroundColor Green
}

# ============================================================================
# LANCEMENT DU SCRIPT
# ============================================================================

# Vérification des privilèges administrateur
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ATTENTION : Ce script nécessite des privilèges administrateur." -ForegroundColor Red
    Write-Host "Veuillez relancer PowerShell en tant qu'administrateur." -ForegroundColor Red
    Read-Host "Appuyez sur Entrée pour quitter"
    exit 1
}

# Vérification du module Active Directory
if (!(Get-Module -Name ActiveDirectory -ListAvailable)) {
    Write-Host "Le module Active Directory n'est pas installé." -ForegroundColor Red
    Write-Host "Pour l'installer, exécutez : Install-WindowsFeature -Name RSAT-AD-PowerShell" -ForegroundColor Yellow
    Read-Host "Appuyez sur Entrée pour quitter"
    exit 1
}

# Création du fichier CSV d'exemple si demandé
$createSample = Read-Host "Voulez-vous créer un fichier CSV d'exemple ? (O/N)"
if ($createSample -match '^[Oo]) {
    Create-SampleCSV
}

# Lancement du menu principal
Show-Menu