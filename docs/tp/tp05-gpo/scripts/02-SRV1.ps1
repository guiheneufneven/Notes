<#
    ENI - ASR - Administration Windows Server
    TP05 : Les stratégies de groupes (domNG.ad)
    Commandes exécutées sur SRV1 (PowerShell administrateur)

    SRV1 intervient sur deux points du TP :
      - le partage qui reçoit les dossiers Documents redirigés (étape 8)
      - le déploiement des imprimantes, piloté depuis la console Gestion de
        l'impression (étape 5)
      - il sert aussi de cobaye pour tester la GPO de Bureau à distance (étape 9)
#>


# =====================================================================
# 1. PARTAGE D'ACCUEIL DES DOSSIERS REDIRIGES
#    A exécuter APRES la création du groupe DL_Documents_Depot sur CD1.
#
#    Bonnes pratiques de sécurité demandées par l'énoncé :
#      - partage masqué par le "$" (invisible dans le voisinage réseau)
#      - partage en contrôle total pour les utilisateurs authentifiés :
#        la sécurité fine est gérée en NTFS, le plus restrictif des deux
#        s'appliquant lors d'un accès réseau
#      - héritage supprimé pour repartir d'une ACL maîtrisée
#      - chaque utilisateur peut CREER son dossier mais ne peut pas ouvrir
#        ceux des autres : droit limité à AD (créer des dossiers) + RD
#        (lister) sur la racine uniquement
#      - CREATEUR PROPRIETAIRE en contrôle total sur les sous-dossiers :
#        celui qui crée son dossier en devient propriétaire et le maîtrise
# =====================================================================

New-Item -Path "E:\DATA\Documents" -ItemType Directory
New-SmbShare -Name 'Documents$' -Path "E:\DATA\Documents" -FullAccess "Utilisateurs authentifiés"

# *S-1-5-32-544 = BUILTIN\Administrateurs
# *S-1-5-18     = SYSTEM
# *S-1-3-0      = CREATEUR PROPRIETAIRE  ((IO) = hérité par les sous-objets seulement)
icacls "E:\DATA\Documents" /inheritance:r `
    /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "*S-1-3-0:(OI)(CI)(IO)F" `
             "DOMNG\DL_Documents_Depot:(CI)(AD,RD)"

# Vérifications
Get-SmbShare -Name 'Documents$' | Format-Table Name,Path
Get-SmbShareAccess -Name 'Documents$' | Format-Table Name,AccountName,AccessRight
icacls "E:\DATA\Documents"

# Après les tests côté client : un dossier par utilisateur redirigé,
# et AUCUN dossier pour ctalmie (intérimaire exclu de la GPO).
Get-ChildItem "E:\DATA\Documents" | Format-Table Name,CreationTime


# =====================================================================
# 2. DEPLOIEMENT DES IMPRIMANTES (console Gestion de l'impression)
#
#    printmanagement.msc > SRV1 > Imprimantes > clic droit sur l'imprimante
#    > Déployer avec une stratégie de groupe
#      Dell5210        -> GPO-Imprimante-Direction et GPO-Imprimante-Informatique
#      Dell5210-Compta -> GPO-Imprimante-Comptabilite
#      Cocher "Les utilisateurs auxquels cette GPO s'applique (par utilisateur)"
#
#    PIEGE RENCONTRE : depuis SRV1, le sélecteur de GPO reste vide (la console
#    n'arrive pas à énumérer les GPO du domaine). La manipulation a donc été
#    faite DEPUIS CD1, en y ajoutant SRV1 comme serveur d'impression distant
#    (Install-WindowsFeature RSAT-Print-Services sur CD1).
# =====================================================================

Get-Printer | Format-Table Name,ShareName,PortName,Published


# =====================================================================
# 3. TEST DE LA GPO BUREAU A DISTANCE (étape 9)
#    L'énoncé demande de désactiver le Bureau à distance avant de tester.
# =====================================================================

# Etat avant : RDP désactivé manuellement
Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 1
Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" | Format-List fDenyTSConnections

# Application de la stratégie
gpupdate /force

# Etat après : la clé de STRATEGIE impose l'activation et le NLA
Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" |
    Format-List fDenyTSConnections,UserAuthentication
# fDenyTSConnections : 0   -> connexions autorisées
# UserAuthentication : 1   -> NLA exigé
#
# La clé HKLM:\System\CurrentControlSet\Control\Terminal Server peut rester à 1 :
# la valeur sous SOFTWARE\Policies est prioritaire et c'est elle que lit le
# service. Dans les propriétés système, la case est d'ailleurs grisée.

# Membres autorisés, alimentés par la préférence de GPO
net localgroup "Utilisateurs du Bureau à distance"

# Le service d'écoute doit être relancé (ou le serveur redémarré) pour prendre
# en compte la stratégie :
Restart-Service TermService -Force

# Contrôles finaux
Get-NetTCPConnection -LocalPort 3389 -State Listen
Get-NetFirewallRule -DisplayGroup "Bureau à distance" | Format-Table DisplayName,Enabled,Profile
