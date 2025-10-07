#!/bin/bash
BASE_DIR="bootstrap/clusters"
PLAINTEXT_SUFFIX="_plain.yaml"
INSTALLER_IMAGE="factory.talos.dev/metal-installer-secureboot/735cad5462c0a7cac42071fb192067589ae25105934e5b666bebd8192e66454a:v1.11.1"

function gen_base_config {
  CLUSTER=$1
  # Drop first arg now that we've stored it, so we can directly pass any additional flags
  shift
  # shellcheck disable=SC2207
  patches=( $(find "$BASE_DIR/$CLUSTER"/patches/cluster-* -exec sh -c 'echo --config-patch @"$1"' sh {} \;) )
  talosctl gen config \
    "$CLUSTER" \
    "https://api.$CLUSTER:6443" \
    --with-examples=false \
    --with-docs=false \
    --with-kubespan=false \
    --with-cluster-discovery=false \
    --with-secrets "$BASE_DIR/$CLUSTER/secrets/secrets$PLAINTEXT_SUFFIX" \
    --install-image="$INSTALLER_IMAGE" \
    --output - \
    "${patches[@]}" \
    "$@"
}

function decrypt_secrets() {
  sops decrypt --extract '["data"]' "$1/secrets/secrets.yaml" > "$1/secrets/secrets$PLAINTEXT_SUFFIX"
  if [ -f "$1/secrets/$NODE.yaml" ]; then
    sops decrypt "$1/secrets/$NODE.yaml" > "$1/secrets/$NODE$PLAINTEXT_SUFFIX"
  fi
}

function talosconfig() {
  CLUSTER=$1
  GEN_TALOSCONFIG=$2
  shift
  shift
  sops decrypt --extract '["data"]' "$BASE_DIR/$CLUSTER/secrets/secrets.yaml" > "$BASE_DIR/$CLUSTER/secrets/secrets$PLAINTEXT_SUFFIX"
  # TODO Handle when config already exists, since talosctl is picky about persistent flags
  talosctl gen config \
    "$CLUSTER" \
    "https://api.$CLUSTER:6443" \
    --with-secrets "$BASE_DIR/$CLUSTER/secrets/secrets$PLAINTEXT_SUFFIX" \
    --output-types=talosconfig \
    --output "$GEN_TALOSCONFIG" \
    "$@"
}

function main() {
  ADDL_FLAGS=()

  while [[ $# -gt 0 ]]; do
    case $1 in
      -b|--cluster)
        CLUSTER="$2"
        shift
        shift
        ;;
      -n|--node)
        NODE="$2"
        shift
        shift
        ;;
      -t|--type)
        TYPE="$2"
        shift
        shift
        ;;
      -i|--image)
        INSTALLER_IMAGE="$2"
        shift
        shift
        ;;
      -c|--talosconfig)
        GEN_TALOSCONFIG="$2"
        shift
        shift
        ;;
      --*|-*)
        ADDL_FLAGS+=("$1 $2")
        shift
        shift
        ;;
      *)
        echo "Unknown option $1"
        exit 1
        ;;
    esac
  done

  if [ -n "$GEN_TALOSCONFIG" ]; then
    talosconfig "$CLUSTER" "$GEN_TALOSCONFIG" "${ADDL_FLAGS[@]}"
    rm "$BASE_DIR/$CLUSTER/secrets/secrets$PLAINTEXT_SUFFIX"
    exit 0
  fi

  case $TYPE in
    "control-plane")
      # Rewrite type name to match the argument expected by talosctl
      TYPE="controlplane"
      PATCH_PREFIX="control-plane"
      ;;
    "worker")
      PATCH_PREFIX="worker"
      ;;
    *)
      echo "unsupported node type specified: $TYPE"
      exit 1
      ;;
  esac

  echo "configuring as $TYPE" >> /dev/stderr
  decrypt_secrets "$BASE_DIR/$CLUSTER"
  # shellcheck disable=SC2207
  patches=( $(find "$BASE_DIR/$CLUSTER/patches/$PATCH_PREFIX"-* -exec sh -c 'echo --config-patch @"$1"' sh {} \;) )
  # shellcheck disable=SC2046
  gen_base_config "$CLUSTER" --config-patch @"$BASE_DIR/$CLUSTER/nodes/$NODE.yaml" \
    $([ -f "$BASE_DIR/$CLUSTER/secrets/$NODE$PLAINTEXT_SUFFIX" ] && echo --config-patch @"$BASE_DIR/$CLUSTER"/secrets/"$NODE$PLAINTEXT_SUFFIX") \
    "${patches[@]}" \
    --output-types "$TYPE"

  rm "$BASE_DIR/$CLUSTER/secrets/secrets$PLAINTEXT_SUFFIX"
  if [ -f "$BASE_DIR/$CLUSTER/secrets/$NODE$PLAINTEXT_SUFFIX" ]; then
    rm "$BASE_DIR/$CLUSTER/secrets/$NODE$PLAINTEXT_SUFFIX"
  fi
}

main "$@"
