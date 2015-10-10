# Remove all mof files (pending,current,backup,MetaConfig.mof,caches,etc)
dir C:\windows\system32\Configuration\*.mof*
rm C:\windows\system32\Configuration\*.mof*

# Kill the LCM/DSC processes
gps wmi* | ? {$_.modules.ModuleName -like "*DSC*"}
gps wmi* | ? {$_.modules.ModuleName -like "*DSC*"} | stop-process -force