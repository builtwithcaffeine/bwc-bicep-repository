# Virtual Machine

> Windows

``` powershell
.\Invoke-AzDeployment.ps1 -tenantScope -subscriptionId "your-subscription-id" -location "westeurope" -bicepFile ".\main-windows.bicep" -deploy
```

> Linux

``` powershell
.\Invoke-AzDeployment.ps1 -subscriptionId "your-subscription-id" -location "westeurope" -bicepFile ".\main-linux.bicep" -deploy
```
