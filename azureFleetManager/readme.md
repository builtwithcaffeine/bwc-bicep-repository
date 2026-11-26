
## Deployment

The Fleet can be deployed without members. `members` and `updateStages` both default
to empty arrays; add clusters and update stages in a later deployment as needed.
An update strategy is created only when `updateStages` is non-empty, and
`updateStrategyResourceId` is null otherwise. See `example.bicepparam` for a
deployment with members and an update strategy.

```
az deployment sub create --name 'iac-fleet-manage' --location 'westeurope' --template-file ./main.bicep --confirm-with-what-if
```
