#!/usr/bin/env bash
# Collect pinned upstream programs, retaining names, licences and source identity.
set -euo pipefail
export PATH=/work/bin:$PATH
ROOT=/work/import-tools
mkdir -p "$ROOT/downloads" "$ROOT/bin" "$ROOT/licenses" /work/evidence/import-tools
cd "$ROOT/downloads"
curl -fsSL --retry 3 https://download.docker.com/linux/static/stable/x86_64/docker-28.0.1.tgz -o docker.tgz
curl -fsSL --retry 3 https://dl.grafana.com/oss/release/grafana-11.5.2.linux-amd64.tar.gz -o grafana.tgz
printf '%s\n' '205b16da72842143a6fa1849126b7bd74b5d12a609387d3d037fb104440ea349  grafana.tgz' | sha256sum -c -
curl -fsSL --retry 3 https://github.com/prometheus/prometheus/releases/download/v3.2.1/prometheus-3.2.1.linux-amd64.tar.gz -o prometheus.tgz
curl -fsSL --retry 3 https://github.com/prometheus/prometheus/releases/download/v3.2.1/sha256sums.txt -o prometheus-sha256sums.txt
sed -n '/  prometheus-3.2.1.linux-amd64.tar.gz$/s/prometheus-3.2.1.linux-amd64.tar.gz/prometheus.tgz/p' prometheus-sha256sums.txt | sha256sum -c -
tar -xzf docker.tgz -C "$ROOT"
tar -xzf prometheus.tgz -C "$ROOT"
tar -xzf grafana.tgz -C "$ROOT"
cp "$ROOT/docker/docker" "$ROOT/bin/gruzchik"
cp "$ROOT/prometheus-3.2.1.linux-amd64/prometheus" "$ROOT/bin/prometey"
cp "$ROOT/grafana-v11.5.2/bin/grafana" "$ROOT/bin/grafa"
cp "$ROOT/prometheus-3.2.1.linux-amd64/LICENSE" "$ROOT/licenses/prometheus-LICENSE"
cp "$ROOT/prometheus-3.2.1.linux-amd64/NOTICE" "$ROOT/licenses/prometheus-NOTICE"
cp "$ROOT/grafana-v11.5.2/LICENSE" "$ROOT/licenses/grafana-LICENSE"
curl -fsSL https://raw.githubusercontent.com/moby/moby/v28.0.1/LICENSE -o "$ROOT/licenses/docker-LICENSE"
export KUBECONFIG=/work/kube/rknetes.conf
for component in coredns cilium; do
 if [[ "$component" == coredns ]]; then
  image=$(kubectl --context admin@workshop -n kube-system get deployment coredns -o jsonpath='{.spec.template.spec.containers[0].image}'); source=coredns; target=spravochnaya09
 else
  image=$(kubectl --context admin@workshop -n kube-system get daemonset cilium -o jsonpath='{.spec.template.spec.containers[0].image}'); source=usr/bin/cilium-dbg; target=resnichki
 fi
 digest=$(crane digest --platform linux/amd64 "$image")
 printf '%s\t%s@%s\n' "$component" "${image%@*}" "$digest" >> /work/evidence/import-tools/images.tsv
 crane export --platform linux/amd64 "${image%@*}@$digest" - | tar -xOf - "$source" > "$ROOT/bin/$target"
 chmod +x "$ROOT/bin/$target"
done
cp /work/bin/helm "$ROOT/bin/kormilo"
sha256sum "$ROOT"/bin/* "$ROOT"/downloads/*.tgz > /work/evidence/import-tools/artifacts.sha256
for name in "$ROOT"/bin/*; do go version -m "$name" > "/work/evidence/import-tools/$(basename "$name").buildinfo"; done
