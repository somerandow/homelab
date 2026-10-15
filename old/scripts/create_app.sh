#!/bin/bash

function create_app_scope() {
  echo "Generating application scope for IDE..."
  cat << EOT > ".idea/scopes/$1.xml"
<component name="DependencyValidationManager">
  <scope name="$1" pattern="file:*/$1//*" />
</component>
EOT
}

function create_app_appset() {
  echo "Generating application set..."
  mkdir -p "argocd/app/$1"
  cat << EOT > "argocd/app/$1/applicationset.yaml"
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: $1
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions:
    - 'missingkey=error'
  generators:
    - clusters:
        selector:
          matchLabels:
            argocd.argoproj.io/secret-type: cluster
        values:
          # TODO: Update renovate config
          # renovate: datasource=docker depName=REPLACE_ME
          # TODO: Update targetRevision
          targetRevision: "main"
          namespace: $1
  template:
    metadata:
      name: '$1-{{.name | slugify}}'
      labels:
        app.kubernetes.io/component: argocd-application
        # TODO: Update labels
        homelab.wojoinc.xyz/app-group: 'REPLACE_ME'
    spec:
      project: default
      sources:
        - repoURL: 'https://github.com/somerandow/homelab'
          targetRevision: main
          path: argocd/app/$1/base
          kustomize:
            components:
              - ../../../env/{{ index .metadata.labels "cluster-environment" }}/$1
              - ../../../flavor/{{ index .metadata.labels "cluster-flavor" }}/$1
              - ../../../clusters/{{ .name }}/$1
            ignoreMissingComponents: true
      destination:
        server: '{{ .server }}'
        namespace: '{{ .values.namespace }}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ApplyOutOfSyncOnly=true
          - ServerSideApply=true
          - RespectIgnoreDifferences=true
      ignoreDifferences: []
EOT
}

function create_app_kustomize() {
  mkdir -p "argocd/app/$name/base"
  cat << EOT > "argocd/app/$name/base/kustomization.yaml"
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
EOT
  mkdir -p "argocd/clusters/$cluster/$name"
  cat << EOT > "argocd/clusters/$cluster/$name/kustomization.yaml"
---
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
EOT
}

function create_app_helm() {
  # TODO: Add helm support eventually
  return
}

read -p "App name: " name
read -p "Enter application type (kustomize/helm): " type

create_app_appset "$name"
create_app_scope "$name"

PS3="Select cluster: "
mapfile -t clusters < <(ls -1 argocd/clusters)
clusters+=("continue")

select cluster in "${clusters[@]}"; do
  case $cluster in
  "continue")
    break
    ;;
  esac
  echo "Generating files for cluster: $cluster"
  case $type in
  "kustomize")
    create_app_kustomize "$name" "$cluster"
    ;;
  "helm")
    create_app_helm "$name" "$cluster"
    ;;
  esac
done
