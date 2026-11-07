#!/usr/bin/env bash
# The weekly build checkout is confined to the existing tenant and builder PVC.
set -euo pipefail
source "$(dirname "$0")/../workshop/common.sh"
node=$(wk get pod builder -o jsonpath='{.spec.nodeName}')
image=$(wk get pod builder -o jsonpath='{.status.containerStatuses[?(@.name=="tools")].imageID}')
[[ "$image" == *@sha256:* ]]
wk apply -f - <<YAML
apiVersion: batch/v1
kind: CronJob
metadata: {name: rknetes-upstream-sync, namespace: tenant-rknetes}
spec:
  schedule: '0 3 * * 5'
  timeZone: Etc/UTC
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 3600
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 0
      activeDeadlineSeconds: 1800
      template:
        spec:
          nodeName: $node
          restartPolicy: Never
          automountServiceAccountToken: false
          containers:
          - name: merge
            image: $image
            command: [bash, /work/src/rknetes/hack/import/weekly-sync.sh]
            resources: {requests: {cpu: 100m, memory: 128Mi}, limits: {cpu: '2', memory: 1Gi}}
            volumeMounts: [{name: work, mountPath: /work}]
          volumes: [{name: work, persistentVolumeClaim: {claimName: kuberoot-build}}]
YAML
