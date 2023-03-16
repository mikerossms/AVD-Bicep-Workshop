<#
.SYNOPSIS
    This script will deploy the AADDS bicep template and passes in the PFX certificate

.DESCRIPTION
    Notes:
    - Make sure you have generated the PFX certificate and updated that in the script below (use generateCert.ps1 as a local admin to generate this)
    - Ensure that the $domainName is correct (must match an AD domain name)
    - Ensure that the SubID is correct for your tenancy
    - This can take up to 60 mins to deploy and costs around £100/month
    - Add Domain Admins to the "AAD DC Administrators" group in Azure AD

    Ref: https://github.com/Azure/ResourceModules/tree/main/modules/Microsoft.AAD/DomainServices
    Ref: https://learn.microsoft.com/en-us/azure/active-directory-domain-services/tutorial-create-instance
    Ref: https://learn.microsoft.com/en-us/azure/active-directory-domain-services/powershell-create-instance
    Ref: https://learn.microsoft.com/en-us/azure/active-directory-domain-services/tutorial-create-instance#enable-user-accounts-for-azure-ad-ds 

#>

#IMPORTANT: $domainName MUST match a domain name in Azure AD
#Get the runtime parameters from the user
param (
    [Parameter(Mandatory)]
    [String]$domainName,
    [String]$identityRG = "rg-identity",
    [String]$location = "uksouth",
    [Parameter(Mandatory)]
    [String]$subID,
    [Bool]$dologin = $true
)

$tags = @{
    Environment='prod'
    Owner="LBG"
}

#Base64 encoded PFX certificate (use generateCert.ps1 as a local admin to generate this)
#This can be added to the AADDS but is not required.  It will need uncommenting in the Bicep as well as in this code
# $pfxCertificate = '<base 64 string if required>'

# #Acquire the certificate password as a secure string
# $pfxCertificatePassword = Read-Host -Prompt "Enter the PFX password" -AsSecureString

#Login to azure (if required) - if you have already done this once, then it is unlikley you will need to do it again for the remainer of the session
if ($dologin) {
    Write-Host "Log in to Azure using an account with permission to create Resource Groups and Assign Permissions" -ForegroundColor Green
    Connect-AzAccount -Subscription $subID
}

#check that the subscription ID we are connected to matches the one we want and change it if not
if ((Get-AzContext).Subscription.Id -ne $subID) {
    #they dont match so try and change the context
    Write-Host "Changing context to subscription: $subID" -ForegroundColor Yellow
    $context = Set-AzContext -SubscriptionId $subID

    if ($context.Subscription.Id -ne $subID) {
        Write-Host "ERROR: Cannot change to subscription: $subID" -ForegroundColor Red
        exit 1
    }

    Write-Host "Changed context to subscription: $subID" -ForegroundColor Green
}

#Create a resource group for the diagnostic resources if it does not already exist then check it has been created successfully
if (-not (Get-AzResourceGroup -Name $identityRG -ErrorAction SilentlyContinue)) {
    Write-Host "Creating Resource Group: $identityRG" -ForegroundColor Green
    if (-not (New-AzResourceGroup -Name $identityRG -Location $location)) {
        Write-Host "ERROR: Cannot create Resource Group: $identityRG" -ForegroundColor Red
        exit 1
    }
}

#Check to make sure the AADDS Service Principal is present and if not create it
$id = Get-AzAdServicePrincipal -AppId "2565bd9d-da50-47d4-8b85-4c97f669dc36" -ErrorAction SilentlyContinue
if (-not $id) {
    Write-Host "Creating AADDS Service Principal" -ForegroundColor Green
    New-AzAdServicePrincipal -AppId "2565bd9d-da50-47d4-8b85-4c97f669dc36"
}

# Register the resource provider for Azure AD Domain Services with Resource Manager.
Register-AzResourceProvider -ProviderNamespace Microsoft.AAD

#Install the Azure AD module if not already installed
if (-not (Get-Module -Name AzureAD -ListAvailable)) {
    Write-Host "Installing AzureAD module" -ForegroundColor Green
    Install-Module -Name AzureAD -Force
}

#Deploy AADDS and pass in the PFX certificate (base 64 encoded) and Certificate password (secure string)
Write-Host "Deploying AADDS and supporting infrastructure"
New-AzResourceGroupDeployment -ResourceGroupName $identityRG `
 -TemplateFile .\aadds.bicep `
 #-pfxCertificatePassword $pfxCertificatePassword `
 -TemplateParameterObject @{
    #pfxCertificate = $pfxCertificate;
    domainName = $domainName;
    tags = $tags;
    location = $location
 }

Write-Host "Assuming no errors, AADDS should now be deployed and configured.  You can now join your VMs to the domain."
Write-Host 'Please add Domain Admin users to the "AAD DC Administrators" group in the Azure Portal' -ForegroundColor Yellow