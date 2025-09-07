#!/usr/bin/env bash

set -euo pipefail

KUBERNETES_DIR=$1

[[ -z "${KUBERNETES_DIR}" ]] && echo "Kubernetes location not specified" && exit 1

kustomize_args=("--load-restrictor=LoadRestrictionsNone")
kustomize_config="kustomization.yaml"
kubeconform_args=(
    "-strict"
    "-ignore-missing-schemas"
    "-skip"
    "Gateway,HTTPRoute,Secret"
    "-schema-location"
    "default"
    "-schema-location"
    "https://kubernetes-schemas.pages.dev/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
    "-verbose"
)

echo "=== Validating standalone manifests in ${KUBERNETES_DIR}/flux ==="
if [[ ! -d "${KUBERNETES_DIR}/flux" ]]; then
    echo "WARNING: Directory ${KUBERNETES_DIR}/flux does not exist, skipping standalone manifest validation"
else
    standalone_files=$(find "${KUBERNETES_DIR}/flux" -maxdepth 1 -type f -name '*.yaml' | wc -l)
    echo "Found ${standalone_files} standalone YAML files to validate"
    
    find "${KUBERNETES_DIR}/flux" -maxdepth 1 -type f -name '*.yaml' -print0 | while IFS= read -r -d $'\0' file;
    do
        echo "Validating standalone file: ${file}"
        if ! kubeconform "${kubeconform_args[@]}" "${file}"; then
            echo "ERROR: Kubeconform validation failed for file: ${file}"
            exit 1
        fi
        echo "✓ Validation passed for: ${file}"
    done
    if [[ ${PIPESTATUS[0]} != 0 ]]; then
        echo "ERROR: Standalone manifest validation failed"
        exit 1
    fi
fi

echo "=== Validating kustomizations in ${KUBERNETES_DIR}/flux ==="
if [[ ! -d "${KUBERNETES_DIR}/flux" ]]; then
    echo "WARNING: Directory ${KUBERNETES_DIR}/flux does not exist, skipping flux kustomization validation"
else
    flux_kustomizations=$(find "${KUBERNETES_DIR}/flux" -type f -name $kustomize_config | wc -l)
    echo "Found ${flux_kustomizations} kustomization.yaml files in flux directory"
    
    find "${KUBERNETES_DIR}/flux" -type f -name $kustomize_config -print0 | while IFS= read -r -d $'\0' file;
    do
        kustomize_dir="${file/%$kustomize_config}"
        echo "Building and validating kustomization: ${kustomize_dir}"
        
        if ! kustomize_output=$(kustomize build "${kustomize_dir}" "${kustomize_args[@]}" 2>&1); then
            echo "ERROR: Kustomize build failed for: ${kustomize_dir}"
            echo "Kustomize error output:"
            echo "${kustomize_output}"
            exit 1
        fi
        
        if ! echo "${kustomize_output}" | kubeconform "${kubeconform_args[@]}"; then
            echo "ERROR: Kubeconform validation failed for kustomization: ${kustomize_dir}"
            echo "Kustomize output that failed validation:"
            echo "${kustomize_output}"
            exit 1
        fi
        echo "✓ Validation passed for kustomization: ${kustomize_dir}"
    done
    if [[ ${PIPESTATUS[0]} != 0 ]]; then
        echo "ERROR: Flux kustomization validation failed"
        exit 1
    fi
fi

echo "=== Validating kustomizations in ${KUBERNETES_DIR}/apps ==="
if [[ ! -d "${KUBERNETES_DIR}/apps" ]]; then
    echo "WARNING: Directory ${KUBERNETES_DIR}/apps does not exist, skipping apps kustomization validation"
else
    apps_kustomizations=$(find "${KUBERNETES_DIR}/apps" -type f -name $kustomize_config | wc -l)
    echo "Found ${apps_kustomizations} kustomization.yaml files in apps directory"
    
    find "${KUBERNETES_DIR}/apps" -type f -name $kustomize_config -print0 | while IFS= read -r -d $'\0' file;
    do
        kustomize_dir="${file/%$kustomize_config}"
        echo "Building and validating kustomization: ${kustomize_dir}"
        
        if ! kustomize_output=$(kustomize build "${kustomize_dir}" "${kustomize_args[@]}" 2>&1); then
            echo "ERROR: Kustomize build failed for: ${kustomize_dir}"
            echo "Kustomize error output:"
            echo "${kustomize_output}"
            exit 1
        fi
        
        if ! echo "${kustomize_output}" | kubeconform "${kubeconform_args[@]}"; then
            echo "ERROR: Kubeconform validation failed for kustomization: ${kustomize_dir}"
            echo "Kustomize output that failed validation:"
            echo "${kustomize_output}"
            exit 1
        fi
        echo "✓ Validation passed for kustomization: ${kustomize_dir}"
    done
    if [[ ${PIPESTATUS[0]} != 0 ]]; then
        echo "ERROR: Apps kustomization validation failed"
        exit 1
    fi
fi
