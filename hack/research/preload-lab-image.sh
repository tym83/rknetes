#!/usr/bin/env bash
# Import a digest-verified lab image into the three nested node caches.
set -euo pipefail
source "$(dirname "$0")/../e2e/common.sh"
IMAGE=$(cat /work/out/tools/lab-image.ref)
[[ "$IMAGE" == 10.244.8.11:5000/rknetes-lab-tools@sha256:* ]] || exit 2
SHA=$(sha256sum /work/out/tools/lab-image.tar | cut -d' ' -f1)
k -n rknet-system apply -f - <<YAML
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: rknet-lab-image-import, labels: {rknetes.su/managed: 'true'}}
spec:
  selector: {matchLabels: {app: rknet-lab-image-import}}
  template:
    metadata: {labels: {app: rknet-lab-image-import}, annotations: {rknetes.su/archive: '$SHA'}}
    spec:
      tolerations: [{operator: Exists}]
      initContainers:
      - name: import
        image: busybox:1.37
        command: [sh, -ec]
        args:
        - |
          wget -q -O /in/image.tar http://10.244.8.11:8080/tools/lab-image.tar
          echo '$SHA  /in/image.tar' | sha256sum -c -
          /host/ctr --address /run/containerd/containerd.sock --namespace k8s.io images import --digests /in/image.tar
          /host/ctr --address /run/containerd/containerd.sock --namespace k8s.io images tag --force 10.244.8.11:5000/rknetes-lab-tools:1 '$IMAGE'
        volumeMounts: [{name: input, mountPath: /in}, {name: ctr, mountPath: /host/ctr, readOnly: true}, {name: socket, mountPath: /run/containerd/containerd.sock}]
      containers: [{name: ready, image: busybox:1.37, command: [sleep, '3600']}]
      volumes:
      - {name: input, emptyDir: {sizeLimit: 1Gi}}
      - name: ctr
        hostPath: {path: /usr/bin/ctr, type: File}
      - name: socket
        hostPath: {path: /run/containerd/containerd.sock, type: Socket}
YAML
k -n rknet-system rollout status daemonset/rknet-lab-image-import --timeout=240s
k -n rknet-system logs -l app=rknet-lab-image-import -c import --tail=5
k -n rknet-system delete daemonset rknet-lab-image-import --wait=true
echo 'PASS: pinned lab image imported into nested node caches without changing any external registry'
