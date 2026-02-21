# Virtual Network Gateway

```
Invoke-AzDeployment.ps1 -targetScope [tenant, mgmt, sub] -subscriptionId [azure-subscription] -location [azure-location] -environmentType [dev, acc, prod] -deploy
```

## Useful Links

- [Gateway Skus](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-about-vpngateways#gwsku)

- [Configure Point to Site (Entra Id)](https://learn.microsoft.com/en-us/azure/vpn-gateway/openvpn-azure-ad-tenant)