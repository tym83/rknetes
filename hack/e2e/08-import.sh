#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
# Use the unchanged upstream kubectl to consume the server's discovery alias.
k get стручки -n rknet-system
HODATAY_KUBECTL=/work/out/rknetes/hodatay-upstream hodatay --context admin@workshop version | grep 'Кормчий'
HODATAY_KUBECTL=/work/out/rknetes/hodatay-upstream hodatay --context admin@workshop version -o yaml > /tmp/rknetes-native-version.yaml
grep 'gitVersion: v1.37.1' /tmp/rknetes-native-version.yaml
grep 'gitTreeState: dirty' /tmp/rknetes-native-version.yaml
k get namespace default -o yaml > /tmp/rknetes-original.yaml
hodatay --context admin@workshop get namespace default -o yaml | grep 'Meta Platforms'
echo 'PASS: upstream discovery accepts стручки; branded text preserves actual structured build metadata'
