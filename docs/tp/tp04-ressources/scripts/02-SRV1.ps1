<#
    ENI - ASR - Administration Windows Server
    TP04 : Gestion de ressources (domNG.ad)
    Commandes exécutées sur SRV1 (PowerShell en administrateur)
#>


# =====================================================================
# 0. PREREQUIS (hyperviseur VMware)
#    Ajout de 3 disques durs SCSI de 20 Go aux propriétés de la VM SRV1.
# =====================================================================

# Contrôle : les 3 disques doivent être vus, vierges (RAW) et éligibles au pool
Get-Disk | Format-Table Number,FriendlyName,Size,PartitionStyle,OperationalStatus
Get-PhysicalDisk -CanPool $true | Format-Table FriendlyName,Size,BusType


# =====================================================================
# 1. POOL DE STOCKAGE ET VOLUMES
#    Le disque virtuel est créé en MIROIR : les données sont écrites en
#    double, donc la perte d'un disque n'interrompt pas le service.
# =====================================================================

New-StoragePool -FriendlyName "Pool-SRV1" -StorageSubSystemFriendlyName "Windows Storage*" -PhysicalDisks (Get-PhysicalDisk -CanPool $true)

New-VirtualDisk -StoragePoolFriendlyName "Pool-SRV1" -FriendlyName "VD-Donnees" -ResiliencySettingName Mirror -ProvisioningType Fixed -Size 16GB

$Disque = Get-VirtualDisk "VD-Donnees" | Get-Disk
Initialize-Disk -Number $Disque.Number -PartitionStyle GPT

# DATA : 10 Go, NTFS, lettre E:
New-Partition -DiskNumber $Disque.Number -Size 10GB -DriveLetter E | Format-Volume -FileSystem NTFS -NewFileSystemLabel "DATA" -Confirm:$false

# USERS : 5 Go, NTFS, monté dans le dossier C:\Base (pas de lettre de lecteur)
New-Item -Path "C:\Base" -ItemType Directory
$Part = New-Partition -DiskNumber $Disque.Number -Size 5GB
$Part | Format-Volume -FileSystem NTFS -NewFileSystemLabel "USERS" -Confirm:$false
$Part | Add-PartitionAccessPath -AccessPath "C:\Base\"

# Vérifications
Get-StoragePool "Pool-SRV1" | Format-Table FriendlyName,Size,HealthStatus
Get-VirtualDisk | Format-Table FriendlyName,ResiliencySettingName,Size,HealthStatus
Get-Partition -DiskNumber $Disque.Number | Format-Table PartitionNumber,DriveLetter,Size,AccessPaths


# =====================================================================
# 2. ARBORESCENCE DES DOSSIERS
# =====================================================================

New-Item -Path "E:\DATA\Documentation"         -ItemType Directory
New-Item -Path "E:\DATA\Services\Comptabilité" -ItemType Directory
New-Item -Path "E:\DATA\Informatique"          -ItemType Directory


# =====================================================================
# 3. PERMISSIONS NTFS (méthode AGDLP : les droits vont aux groupes DL)
#    /inheritance:r = suppression de l'héritage, on repart d'une ACL propre
#    (OI)(CI)       = s'applique au dossier, aux sous-dossiers et aux fichiers
#    F = contrôle total, M = modification, RX = lecture et exécution
#    *S-1-5-32-544  = BUILTIN\Administrateurs, *S-1-5-18 = SYSTEM
# =====================================================================

# Documentation : lecture pour tous, contrôle total Informatique,
# REFUS explicite pour les intérimaires (le refus l'emporte sur l'autorisation,
# sinon Christophe hériterait de la lecture via "Utilisateurs du domaine")
icacls "E:\DATA\Documentation" /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "DOMNG\DL_Documentation_CT:(OI)(CI)F" "DOMNG\DL_Documentation_Lecture:(OI)(CI)RX"
icacls "E:\DATA\Documentation" /deny "DOMNG\DL_Documentation_Refus:(OI)(CI)F"

# Comptabilité : modification pour les comptables, contrôle total Informatique,
# aucun droit pour les autres services (aucune ACE = aucun accès)
icacls "E:\DATA\Services\Comptabilité" /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "DOMNG\DL_Compta_CT:(OI)(CI)F" "DOMNG\DL_Compta_Modif:(OI)(CI)M"

# Informatique : contrôle total Informatique uniquement
icacls "E:\DATA\Informatique" /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "DOMNG\DL_Info_CT:(OI)(CI)F"

# Vérification (le refus apparaît en premier, noté (N) = aucun accès)
icacls "E:\DATA\Documentation"
icacls "E:\DATA\Services\Comptabilité"
icacls "E:\DATA\Informatique"


# =====================================================================
# 4. PARTAGES
#    Partage en contrôle total pour "Tout le monde" : la sécurité fine est
#    assurée par le NTFS (c'est le plus restrictif des deux qui s'applique).
#    Le "$" final rend le partage Info invisible dans le voisinage réseau.
# =====================================================================

New-SmbShare -Name "Documentation" -Path "E:\DATA\Documentation"         -FullAccess "Tout le monde"
New-SmbShare -Name "Compta"        -Path "E:\DATA\Services\Comptabilité" -FullAccess "Tout le monde"
New-SmbShare -Name 'Info$'         -Path "E:\DATA\Informatique"          -FullAccess "Tout le monde"

# Vérifications
Get-SmbShare | Where-Object Path -like "E:\*" | Format-Table Name,Path
Get-SmbShareAccess -Name "Documentation","Compta",'Info$' | Format-Table Name,AccountName,AccessRight

# Fichier de test pour les essais depuis le client
"Fichier de test" | Out-File "E:\DATA\Documentation\lisezmoi.txt"


# =====================================================================
# 5. SERVEUR D'IMPRESSION
# =====================================================================

Install-WindowsFeature Print-Server -IncludeManagementTools

# Pilote : extraction de l'archive fournie puis ajout au magasin de pilotes
Expand-Archive "C:\Drivers_OPD_Dell_A16_Windows_x86_x64.zip" -DestinationPath "C:\Drivers"
pnputil /add-driver "C:\Drivers\Software_OPD_Dell_A16_Win\dellopd.inf"
Add-PrinterDriver -Name "Dell Open Print Driver (PCL 5)"

# Pilote 32 bits : Gestion de l'impression (printmanagement.msc)
#   SRV1 > Pilotes > clic droit > Ajouter un pilote > cocher x86
#   > Disque fourni > C:\Drivers\Software_OPD_Dell_A16_Win\dellopd.inf
#   > Dell Open Print Driver (PCL 5)
#   Si Windows réclame les fichiers : C:\Drivers\Software_OPD_Dell_A16_Win\i386

# Port TCP/IP standard (dans l'assistant graphique, l'imprimante étant absente
# du réseau, choisir le type de périphérique : Generic Network Card)
Add-PrinterPort -Name "IP_192.168.21.30" -PrinterHostAddress "192.168.21.30"

# Deux imprimantes logiques sur le MEME port : impossible d'appliquer des
# horaires différents par groupe sur une seule imprimante.
Add-Printer -Name "Dell5210"        -DriverName "Dell Open Print Driver (PCL 5)" -PortName "IP_192.168.21.30" -Shared -ShareName "Dell5210"        -Published
Add-Printer -Name "Dell5210-Compta" -DriverName "Dell Open Print Driver (PCL 5)" -PortName "IP_192.168.21.30" -Shared -ShareName "Dell5210-Compta" -Published

# Vérifications
Get-PrinterDriver | Where-Object Name -like "*PCL 5*" | Format-Table Name,PrinterEnvironment
Get-Printer | Format-Table Name,ShareName,PortName,DriverName,Published


# =====================================================================
# 6. PARAMETRES DES IMPRIMANTES (console graphique)
#
#    Dell5210-Compta > Propriétés > Avancé :
#      Disponible de 20:00 à 06:00
#
#    Dell5210 > Propriétés > Sécurité :
#      supprimer "Tout le monde"
#      DL_Imprimante_Impression : Imprimer
#      DL_Imprimante_Compta     : REFUSER Imprimer  (la compta imprime la nuit)
#      DL_Imprimante_Gestion    : Imprimer + Gérer les documents  (David)
#      DL_Imprimante_CT         : Contrôle total (les 3 cases)
#
#    Dell5210-Compta > Propriétés > Sécurité :
#      supprimer "Tout le monde"
#      DL_Imprimante_Compta  : Imprimer
#      DL_Imprimante_Gestion : Imprimer + Gérer les documents
#      DL_Imprimante_CT      : Contrôle total
#
#    Référencement dans l'AD : onglet Partage > "Répertorier dans l'annuaire"
#    (déjà fait par le paramètre -Published des commandes Add-Printer)
# =====================================================================
