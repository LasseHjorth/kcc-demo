terraform apply
git commit
git push
connect to GKE
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd get secret argocd-initial-admin-secret -o json| jq '.data.password|@base64d'
kubectl -n argocd port-forward service/argocd-server 8080:80
http://127.0.0.1

kubectl -n argocd apply -f .secret/repo.yaml