kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd get secret argocd-initial-admin-secret -o json| jq '.data.password|@base64d'
kubectl -n argocd port-forward service/argocd-server 8080:80


