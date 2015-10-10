Configuration CreateSharePointFarm {
  param (
        [Parameter(Mandatory=$true)] [ValidateNotNullorEmpty()] [string] $FarmName,
        [Parameter(Mandatory=$true)] [ValidateNotNullorEmpty()] [string] $WebApplicationUrl,
        [Parameter(Mandatory=$true)] [ValidateNotNullorEmpty()] [string] $MySiteHostUrl,
        [Parameter(Mandatory=$true)] [ValidateNotNullorEmpty()] [string] $TeamSiteHostUrl,
        [Parameter(Mandatory=$true)] [ValidateNotNullorEmpty()] [PSCredential] $FarmAccount,
        [Parameter(Mandatory=$true)] [ValidateNotNullorEmpty()] [PSCredential] $InstallAccount,
        [Parameter(Mandatory=$true)] [ValidateNotNullorEmpty()] [string]       $DatabaseServer,
        [Parameter(Mandatory=$true)] [ValidateNotNullorEmpty()] [PSCredential] $ContentAccount,
        [Parameter(Mandatory=$true)] [ValidateNotNullorEmpty()] [PSCredential] $ServiceAccount

    )



    Import-DscResource -ModuleName xSharePoint
    Import-DscResource -ModuleName xWebAdministration
    Import-DscResource -ModuleName xCredSSP
    Import-DscResource -ModuleName xStorage

    $FarmPrefix =  $FarmName + "_"

    Node $AllNodes.NodeName
    {
        xDisk LogsDisk { DiskNumber = 2; DriveLetter = "l" }
        xDisk IndexDisk { DiskNumber = 3; DriveLetter = "i" }
        

        xCredSSP CredSSPServer { Ensure = "Present"; Role = "Server" } 
        xCredSSP CredSSPClient { Ensure = "Present"; Role = "Client"; DelegateComputers = '*.askwictor.com','$env:COMPUTERNAME', 'localhost' }

        Script HighPerformancePowerPlan
        {  
            SetScript   = { Powercfg -SETACTIVE SCHEME_MIN }  
            TestScript  = { return ( Powercfg -getactivescheme) -like "*High Performance*" }  
            GetScript   = { return @{ Powercfg = ( "{0}" -f ( powercfg -getactivescheme ) ) } }
        }

        WindowsFeature ADPS
        {
            Name = "RSAT-AD-PowerShell"
            Ensure = "Present"
        }

 
        xWebAppPool RemoveDotNet2Pool         { Name = ".NET v2.0";            Ensure = "Absent";}
        xWebAppPool RemoveDotNet2ClassicPool  { Name = ".NET v2.0 Classic";    Ensure = "Absent";}
        xWebAppPool RemoveDotNet45Pool        { Name = ".NET v4.5";            Ensure = "Absent";}
        xWebAppPool RemoveDotNet45ClassicPool { Name = ".NET v4.5 Classic";    Ensure = "Absent";}
        xWebAppPool RemoveClassicDotNetPool   { Name = "Classic .NET AppPool"; Ensure = "Absent";}
        xWebAppPool RemoveDefaultAppPool      { Name = "DefaultAppPool";       Ensure = "Absent";}
        xWebSite    RemoveDefaultWebSite      { Name = "Default Web Site";     Ensure = "Absent"; PhysicalPath = "C:\inetpub\wwwroot"; }


   
 
    }

    Node $AllNodes.Where{$_.Role -eq "FirstServer"}.NodeName 
    {

        # This is just for demo purposes
        File RemoveAppOffline{
            DestinationPath = "C:\inetpub\wwwroot\wss\VirtualDirectories\80\App_Offline.htm"
            Ensure = "Absent"
            DependsOn = "[xSPSite]MySiteHost"
        }

        # This is just for demo purposes
        File AddAppOffline{
            DestinationPath = "C:\inetpub\wwwroot\wss\VirtualDirectories\80"
            Ensure = "Present"
            SourcePath = "c:\DSC\App_Offline.htm"
        }
        
        xSPCreateFarm CreateSPFarm
        {
            DatabaseServer           = $DatabaseServer
            FarmConfigDatabaseName   = "$($FarmPrefix)SP_Config"
            AdminContentDatabaseName = "$($FarmPrefix)SP_AdminContent"
            Passphrase               = "pass@word1"
            FarmAccount              =  $FarmAccount
            CentralAdministrationPort = 21000
            ServerRole               = "Custom"
            InstallAccount           =  $InstallAccount            
            DependsOn                = "[xCredSSP]CredSSPClient","[File]AddAppOffline"

        }


        xSPManagedAccount ServicePoolManagedAccount
        {
            AccountName    = $ServiceAccount.UserName
            Account        = $ServiceAccount
            Schedule       = ""
            InstallAccount = $InstallAccount
            DependsOn      = "[xSPCreateFarm]CreateSPFarm"
        }
        xSPManagedAccount WebPoolManagedAccount
        {
            AccountName    = $ContentAccount.UserName
            Account        = $ContentAccount
            Schedule       = ""
            InstallAccount = $InstallAccount
            DependsOn      = "[xSPCreateFarm]CreateSPFarm"
        }

        xSPDiagnosticLoggingSettings ApplyDiagnosticLogSettings
        {
            InstallAccount                              = $InstallAccount
            LogPath                                     = "L:\ULSLogs"
            LogSpaceInGB                                = 10
            AppAnalyticsAutomaticUploadEnabled          = $false
            CustomerExperienceImprovementProgramEnabled = $true
            DaysToKeepLogs                              = 6
            DownloadErrorReportingUpdatesEnabled        = $false
            ErrorReportingAutomaticUploadEnabled        = $false
            ErrorReportingEnabled                       = $false
            EventLogFloodProtectionEnabled              = $true
            EventLogFloodProtectionNotifyInterval       = 5
            EventLogFloodProtectionQuietPeriod          = 2
            EventLogFloodProtectionThreshold            = 5
            EventLogFloodProtectionTriggerPeriod        = 2
            LogCutInterval                              = 15
            LogMaxDiskSpaceUsageEnabled                 = $true
            ScriptErrorReportingDelay                   = 30
            ScriptErrorReportingEnabled                 = $true
            ScriptErrorReportingRequireAuth             = $true
            DependsOn                                   = @("[xSPCreateFarm]CreateSPFarm", "[xDisk]LogsDisk")
        }

         xSPUsageApplication UsageApplication 
        {
            Name                  = "$FarmName Usage Service Application"
            DatabaseName          = "$($FarmPrefix)SP_Usage"
            UsageLogCutTime       = 5
            UsageLogLocation      = "L:\UsageLogs"
            UsageLogMaxFileSizeKB = 1024
            InstallAccount        = $InstallAccount
            DependsOn             = "[xSPCreateFarm]CreateSPFarm"
        }
        xSPStateServiceApp StateServiceApp
        {
            Name           = "$FarmName State Service Application"
            DatabaseName   = "$($FarmPrefix)SP_State"
            InstallAccount = $InstallAccount
            DependsOn      = "[xSPCreateFarm]CreateSPFarm"
        }
        xSPDistributedCacheService EnableDistributedCache
        {
            Name           = "$($FarmPrefix)AppFabricCachingService"
            Ensure         = "Present"
            CacheSizeInMB  = 768 # TODO: Add check for 0
            ServiceAccount = $ServiceACcount.UserName
            InstallAccount = $InstallAccount
            CreateFirewallRules = $true
            DependsOn      = @('[xSPCreateFarm]CreateSPFarm','[xSPManagedAccount]ServicePoolManagedAccount')
        }

        xSPServiceInstance ClaimsToWindowsTokenServiceInstance
        {  
            Name           = "Claims to Windows Token Service"
            Ensure         = "Present"
            InstallAccount = $InstallAccount
            DependsOn      = "[xSPCreateFarm]CreateSPFarm"
        } 
        xSPServiceInstance UserProfileServiceInstance
        {  
            Name           = "User Profile Service"
            Ensure         = "Present"
            InstallAccount = $InstallAccount
            DependsOn      = "[xSPCreateFarm]CreateSPFarm"
        }        
        
        xSPServiceInstance ManagedMetadataServiceInstance
        {  
            Name           = "Managed Metadata Web Service"
            Ensure         = "Present"
            InstallAccount = $InstallAccount
            DependsOn      = "[xSPCreateFarm]CreateSPFarm"
        }

        
        xSPServiceAppPool MainServiceAppPool
        {
            Name           = "Service Applications"
            ServiceAccount = $ServiceAccount.UserName
            InstallAccount = $InstallAccount
            DependsOn      = "[xSPCreateFarm]CreateSPFarm"
        }
        xSPUserProfileServiceApp UserProfileServiceApp
        {
            Name                = "$FarmName User Profile Service Application"
            ApplicationPool     = "Service Applications"
            MySiteHostLocation  = "$MySiteHostUrl"
            ProfileDBName       = "$($FarmPrefix)SP_UserProfiles"
            ProfileDBServer     = $DatabaseServer
            SocialDBName        = "$($FarmPrefix)SP_Social"
            SocialDBServer      = $DatabaseServer
            SyncDBName          = "$($FarmPrefix)SP_ProfileSync"
            SyncDBServer        = $DatabaseServer
            FarmAccount         = $FarmAccount
            InstallAccount      = $InstallAccount
            DependsOn           = @('[xSPServiceAppPool]MainServiceAppPool', '[xSPManagedPath]PersonalManagedPath', '[xSPSite]MySiteHost', '[xSPManagedMetaDataServiceApp]ManagedMetadataServiceApp', '[xSPSearchServiceApp]SearchServiceApp')
        }
        xSPManagedMetaDataServiceApp ManagedMetadataServiceApp
        {  
            Name              = "$FarmName Managed Metadata Service Application"
            InstallAccount    = $InstallAccount
            ApplicationPool   = "Service Applications"
            DatabaseServer    = $DatabaseServer
            DatabaseName      = "$($FarmPrefix)SP_ManagedMetadata"
            DependsOn         = "[xSPServiceAppPool]MainServiceAppPool"
        }
        xSPSearchServiceApp SearchServiceApp
        {  
            Name            = "$FarmName Search Service Application"
            DatabaseName    = "$($FarmPrefix)SP_Search"
            ApplicationPool = "Service Applications"
            InstallAccount  = $InstallAccount
            DependsOn       = "[xSPServiceAppPool]MainServiceAppPool"
        }
        



        xSPWebApplication HostNameSiteCollectionWebApp
        {
            Name                   = "$FarmName SharePoint Sites"
            ApplicationPool        = "$FarmName SharePoint Sites"
            ApplicationPoolAccount = $ContentAccount.UserName
            AllowAnonymous         = $false
            AuthenticationMethod   = "NTLM"
            DatabaseName           = "$($FarmPrefix)SP_Content_01"
            DatabaseServer         = $DatabaseServer
            Url                    = $WebApplicationUrl
            Port                   = "80"            
            InstallAccount         = $InstallAccount
            DependsOn              = "[xSPManagedAccount]WebPoolManagedAccount"
        }
        xSPManagedPath TeamsManagedPath 
        {
            WebAppUrl      = "$WebApplicationUrl"
            InstallAccount = $InstallAccount
            RelativeUrl    = "teams"
            Explicit       = $false
            HostHeader     = $true
            DependsOn      = "[xSPWebApplication]HostNameSiteCollectionWebApp"
        }
        xSPManagedPath PersonalManagedPath 
        {
            WebAppUrl      = "$WebApplicationUrl"
            InstallAccount = $InstallAccount
            RelativeUrl    = "personal"
            Explicit       = $false
            HostHeader     = $true
            DependsOn      = "[xSPWebApplication]HostNameSiteCollectionWebApp"
        }
        xSPSite RootSite
        {
            Url                      = "$WebApplicationUrl"
            OwnerAlias               = $InstallAccount.UserName
            Name                     = "Root Site"
            InstallAccount           = $InstallAccount
            DependsOn                = "[xSPWebApplication]HostNameSiteCollectionWebApp"
        }
        xSPSite TeamSite
        {
            Url                      = "$TeamSiteUrl"
            OwnerAlias               = $InstallAccount.UserName
            HostHeaderWebApplication = "$WebApplicationUrl"
            Name                     = "Team Sites"
            Template                 = "STS#0"
            InstallAccount           = $InstallAccount
            DependsOn                = "[xSPSite]RootSite"
        }
        xSPSite MySiteHost
        {
            Url                      = "$MySiteHostUrl"
            OwnerAlias               = $InstallAccount.UserName
            HostHeaderWebApplication = "$WebApplicationUrl"
            Name                     = "My Site Host"
            Template                 = "SPSMSITEHOST#0"
            InstallAccount           = $InstallAccount
            DependsOn                = "[xSPSite]RootSite"
        }


        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
        }
    }    
}

$ConfigurationData = @{
    AllNodes = @(
        @{
            NodeName="awsp1602"
            Role = "FirstServer"
            PSDscAllowPlainTextPassword=$true # Should really not be used, use certificates instead            
         } 
    )
    NonNodeData =  @{
        FarmName = "FarmA"
    }
}

$farmAccount = Get-Credential -Message "Farm Account" -UserName "ASKWICTOR\SPFarm"
$installAccount = Get-Credential -Message "Install Account" -UserName "ASKWICTOR\SPInstall"
$contentAccount = Get-Credential -Message "Content Account" -UserName "ASKWICTOR\SPContent"
$serviceAccount = Get-Credential -Message "Service Account" -UserName "ASKWICTOR\SPService"
$FarmName = $env:COMPUTERNAME
$WebApplicationUrl = "http://root.$($env:COMPUTERNAME).askwictor.com"
$TeamSiteUrl = "http://teams.$($env:COMPUTERNAME).askwictor.com"
$MySiteHostUrl = "http://my.$($env:COMPUTERNAME).askwictor.com"
$DatabaseServer = "awsp1601.askwictor.com"

CreateSharePointFarm -ConfigurationData $ConfigurationData -Verbose `
    -InstallAccount $installAccount `
    -FarmAccount $farmAccount `
    -ServiceAccount $serviceAccount `
    -ContentAccount $contentAccount `
    -FarmName  $FarmName `
    -WebApplicationUrl $WebApplicationUrl `
    -TeamSiteHostUrl $TeamSiteUrl `
    -MySiteHostUrl $MySiteHostUrl `
    -DatabaseServer $DatabaseServer


Start-DscConfiguration .\CreateSharePointFarm -Verbose -Wait -Force -Debug

#Start-DscConfiguration .\CreateSharePointFarm -Wait -Force 
