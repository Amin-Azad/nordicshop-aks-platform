# NordicShop Alert Plan

## 1. API Unavailable

PromQL:

```promql
sum(
  up{
    job="kubernetes-pods",
    kubernetes_namespace="nordicshop",
    app="nordicshop-api"
  }
) < 1
