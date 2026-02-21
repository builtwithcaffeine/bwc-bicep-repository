# Azure Virtual Machine Image Builder


## [0] Base Infrastructure

During the deploying of the base infrastructure the following resources are created

- Resource Group
- Virtual Network + Private Dns Zone
- Storage Account (with Private EndPoint)
- Managed Identity
- Shared Compute Image Gallery


## [1] Creating New Initial Image

During the deployment of a new Image the following resources are created:

- Reference existing resources:
   -> Virtual Network
   -> Storage Account
- Resource Group
- Image Template

## [2] Updating Existing Image
