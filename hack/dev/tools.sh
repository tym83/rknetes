#!/usr/bin/env bash
# Run in the tools container.
set -euo pipefail
mkdir -p /work/bin /work/kube
if [[ ! -x /work/bin/kubectl ]]; then
  curl -fsSLo /work/bin/kubectl https://dl.k8s.io/v1.37.1/bin/linux/amd64/kubectl
  curl -fsSLo /work/bin/kubectl.sha256 https://dl.k8s.io/v1.37.1/bin/linux/amd64/kubectl.sha256
  (cd /work/bin && printf '%s  kubectl\n' "$(cat kubectl.sha256)" | sha256sum -c -)
  chmod +x /work/bin/kubectl
fi
if [[ ! -x /work/bin/helm ]]; then
  curl -fsSLo /work/tmp/helm.tar.gz https://get.helm.sh/helm-v3.19.0-linux-amd64.tar.gz
  curl -fsSLo /work/tmp/helm.sha256 https://get.helm.sh/helm-v3.19.0-linux-amd64.tar.gz.sha256sum
  (cd /work/tmp && sed 's/helm-v3.19.0-linux-amd64.tar.gz/helm.tar.gz/' helm.sha256 | sha256sum -c -)
  tar -xzf /work/tmp/helm.tar.gz -C /work/tmp
  cp /work/tmp/linux-amd64/helm /work/bin/helm
fi
