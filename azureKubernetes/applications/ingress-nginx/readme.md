# Helm Install - Nginx Ingress Controller

## Manually Add the Helm Repository

``` bash
helm repo add internal-ingress https://kubernetes.github.io/ingress-nginx
helm repo update
```

## Install the Nginx Controller

``` bash
helm install internal-ingress \
     internal-ingress/ingress-nginx \
     --create-namespace \
     --namespace internal-ingress \
     --set controller.replicaCount=2 \
     --set controller.service.externalTrafficPolicy=Local \
     --set fullnameOverride=ingress-nginx
```


## Check Deployment

> **Check Deployments**

```
kubectl get -n internal-ingress deployments
```

> **Get Pods for Ingress**

```
kubectl get pods -n internal-ingress
```