<#
    ENI - ASR - Administration Windows Server
    TP04 : Gestion de ressources (domNG.ad)
    Commandes exécutées sur CD1 (PowerShell en administrateur)

    Méthode AGDLP :
      A  = comptes utilisateurs
      G  = groupes globaux par service (G-Comptabilité, G-Informatique... du TP03)
      DL = groupes de domaine local, un par ressource et par niveau de droit
      P  = les permissions (NTFS, imprimante) sont données UNIQUEMENT aux groupes DL
#>


# =====================================================================
# 1. GROUPES DE DOMAINE LOCAUX
#
#    Groupe DL                    Membre (groupe global)      Droit accordé
#    ---------------------------  --------------------------  --------------------
#    DL_Documentation_Refus       G-Intérimaires              Refus total
#    DL_Documentation_Lecture     Utilisateurs du domaine     Lecture
#    DL_Documentation_CT          G-Informatique              Contrôle total
#    DL_Compta_Modif              G-Comptabilité              Modification
#    DL_Compta_CT                 G-Informatique              Contrôle total
#    DL_Info_CT                   G-Informatique              Contrôle total
#    DL_Imprimante_Impression     Utilisateurs du domaine     Imprimer (jour)
#    DL_Imprimante_Compta         G-Comptabilité              Imprimer (20h-6h)
#    DL_Imprimante_Gestion        David (dgrenier)            Gérer les documents
#    DL_Imprimante_CT             G-Informatique              Contrôle total
# =====================================================================

# OU dédiée aux groupes de ressources
New-ADOrganizationalUnit -Name "Ressources" -Path "OU=Groupes,OU=DOMNG,DC=domNG,DC=ad"

$OU = "OU=Ressources,OU=Groupes,OU=DOMNG,DC=domNG,DC=ad"

"DL_Documentation_Refus","DL_Documentation_Lecture","DL_Documentation_CT",
"DL_Compta_Modif","DL_Compta_CT","DL_Info_CT",
"DL_Imprimante_Impression","DL_Imprimante_Compta","DL_Imprimante_Gestion","DL_Imprimante_CT" |
    ForEach-Object { New-ADGroup -Name $_ -GroupScope DomainLocal -GroupCategory Security -Path $OU }

# "Utilisateurs du domaine" récupéré par son SID (RID 513) : indépendant du nom français
$DomUsers = Get-ADGroup "$((Get-ADDomain).DomainSID)-513"

Add-ADGroupMember "DL_Documentation_Refus"   -Members "G-Intérimaires"
Add-ADGroupMember "DL_Documentation_Lecture" -Members $DomUsers
Add-ADGroupMember "DL_Documentation_CT"      -Members "G-Informatique"
Add-ADGroupMember "DL_Compta_Modif"          -Members "G-Comptabilité"
Add-ADGroupMember "DL_Compta_CT"             -Members "G-Informatique"
Add-ADGroupMember "DL_Info_CT"               -Members "G-Informatique"
Add-ADGroupMember "DL_Imprimante_Impression" -Members $DomUsers
Add-ADGroupMember "DL_Imprimante_Compta"     -Members "G-Comptabilité"
Add-ADGroupMember "DL_Imprimante_Gestion"    -Members "dgrenier"
Add-ADGroupMember "DL_Imprimante_CT"         -Members "G-Informatique"

# Vérification
Get-ADGroup -Filter 'Name -like "DL_*"' | ForEach-Object { "$($_.Name) : " + ((Get-ADGroupMember $_).Name -join ", ") }

# Activation de Christophe et Ivan (créés désactivés et sans mot de passe au TP03),
# nécessaire pour les tests d'accès et de délégation
"ctalmie","itard" | ForEach-Object { Set-ADAccountPassword $_ -Reset -NewPassword (ConvertTo-SecureString "<MotDePasse>" -AsPlainText -Force); Enable-ADAccount $_ }


# =====================================================================
# 2. PUBLICATION DU PARTAGE DANS L'ANNUAIRE
#    GUI : ADUC > clic droit sur l'OU > Nouveau > Dossier partagé
# =====================================================================

New-ADObject -Type volume -Name "Documentation" -Path "OU=Serveurs,OU=DOMNG,DC=domNG,DC=ad" -OtherAttributes @{uNCName="\\SRV1\Documentation"}


# =====================================================================
# 3. DELEGATION DE PRIVILEGES DANS L'AD
#    GUI : clic droit sur l'OU > Délégation de contrôle > choisir l'utilisateur
#          ou le groupe > cocher "Créer, supprimer et gérer les comptes
#          d'utilisateurs" et "Réinitialiser les mots de passe utilisateur..."
#
#    En ligne de commande avec dsacls :
#      /I:T  = cet objet et tous les sous-objets
#      /I:S  = uniquement les sous-objets
#      CCDC;user = créer (Create Child) et supprimer (Delete Child) des objets user
#      GA;;user  = contrôle total sur les objets user (modification + réinit. mdp)
#
#    La délégation est faite OU par OU : en la posant sur l'OU Utilisateurs,
#    le service Informatique serait inclus, ce que le TP interdit.
# =====================================================================

$Compta = "OU=Comptabilité,OU=Utilisateurs,OU=DOMNG,DC=domNG,DC=ad"
$Direct = "OU=DIRECTION,OU=Utilisateurs,OU=DOMNG,DC=domNG,DC=ad"

# David : gestion des comptes du service Comptabilité
dsacls $Compta /I:T /G "DOMNG\dgrenier:CCDC;user"
dsacls $Compta /I:S /G "DOMNG\dgrenier:GA;;user"

# Support technique : tous les services sauf Informatique
foreach ($OUSvc in $Compta, $Direct) {
    dsacls $OUSvc /I:T /G "DOMNG\G-Support technique:CCDC;user"
    dsacls $OUSvc /I:S /G "DOMNG\G-Support technique:GA;;user"
}

# Isabelle : groupe disposant nativement de tous les privilèges sur l'annuaire
# = Administrateurs de l'entreprise (RID 519, portée forêt), récupéré par SID
Add-ADGroupMember -Identity "$((Get-ADDomain).DomainSID)-519" -Members "ivedere"

# Vérifications
dsacls $Compta
Get-ADUser ivedere -Properties MemberOf | ForEach-Object { $_.MemberOf }
