#!/bin/bash

function move_kustomization() {
    cp "argocd/app/$1/base/kustomization.yaml" "argocd/app/$1/base/kustomization.yaml.bak"
}

function restore_kustomization() {
    cp "argocd/app/$1/base/kustomization.yaml.bak" "argocd/app/$1/base/kustomization.yaml" || exit
    rm "argocd/app/$1/base/kustomization.yaml.bak"
}

function missing_component() {
    echo "WARN: missing/invalid component: $1, real path: $(realpath $1)" >&2
}

function add_components() {
    olddir=$(pwd)
    cd "argocd/app/$1/base" || exit
    # TODO automatically determine env etc.
    kustomize edit add component ../../../flavor/talos/common 2>/dev/null || missing_component ../../../flavor/talos/common
    kustomize edit add component "../components/flavor/talos" 2>/dev/null || missing_component "../components/flavor/talos"
    kustomize edit add component ../../../env/prod/common 2>/dev/null || missing_component ../../../env/prod/common
    kustomize edit add component "../components/env/prod" 2>/dev/null || missing_component "../components/env/prod"
    kustomize edit add component "../../../cluster/$2/common" 2>/dev/null || missing_component "../../../cluster/$2/common"
    kustomize edit add component "../components/cluster/$2" 2>/dev/null || missing_component "../components/cluster/$2"
    cd "$olddir" || exit
}

function build_kustomization() {
    if [ -t 1 ]; then
      read -rsp "Review warnings, then press <Enter> to render"
      kustomize build "argocd/app/$1/base" | less
    else
      kustomize build "argocd/app/$1/base"
    fi
}

app=$1
cluster=$2

echo -e "rendering:\napp: $app\ncluster: $cluster" >&2

move_kustomization "$app"
add_components "$app" "$cluster"
build_kustomization "$app"
restore_kustomization "$app"
