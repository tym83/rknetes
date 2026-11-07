#!/usr/bin/env bash
# One application crosses the actual mechanisms; the existing stand stays intact.
set -euo pipefail
export RK_LAB_METRICS_LISTEN=127.0.0.1:19091
export RK_ARTIFACT_CLIENTS=lab-composed-shop RK_ARTIFACT_SERVERS=lab-composed-external
export RK_ARTIFACT_DIRECTORY=/work/tmp/composed-artifacts RK_ARTIFACT_VARIANT="composed-$(date +%s)"
export RK_ARTIFACT_APPLICATION=/work/out/optional/lab-server
export RK_ARTIFACT_TWO_VERSIONS=1 RK_ARTIFACT_CDN_PROXY=1 RK_ARTIFACT_PREPARE_ONLY=1
source "$(dirname "${BASH_SOURCE[0]}")/08-artifact-chain.sh"
presentation=
cleanup(){ stop_lab_controller; stop_forward; [[ -z "$presentation" ]] || kill "$presentation" 2>/dev/null || true; k -n "$SERVERS" delete daemonset goshran-composed --ignore-not-found --wait=true; k -n rknet-system delete service max-composed --ignore-not-found; k delete clusterrolebinding composed-controller --ignore-not-found; }
trap cleanup EXIT
k label namespace "$SERVERS" pod-security.kubernetes.io/enforce=privileged
SHA=$(sha256sum /work/out/optional/goshran | cut -d' ' -f1)
k -n "$SERVERS" apply -f - <<YAML
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: goshran-composed}
spec:
  selector: {matchLabels: {app: goshran-composed}}
  template:
    metadata: {labels: {app: goshran-composed}}
    spec:
      hostNetwork: true
      automountServiceAccountToken: false
      tolerations: [{operator: Exists}]
      initContainers:
      - name: binary
        image: $IMAGE
        command: [sh, -ec, "curl -fsS http://10.244.8.11:8080/optional/goshran -o /rk/goshran; echo '$SHA  /rk/goshran' | sha256sum -c -; chmod +x /rk/goshran"]
        volumeMounts: [{name: bin, mountPath: /rk}]
      containers:
      - name: goshran
        image: $IMAGE
        command: [/rk/goshran, --listen, '127.0.0.1:5009', --upstream, '$REGISTRY', --index, /index/index.yaml]
        readinessProbe: {exec: {command: [curl, -fsS, 'http://127.0.0.1:5009/healthz']}, periodSeconds: 1}
        volumeMounts: [{name: bin, mountPath: /rk}, {name: index, mountPath: /index}]
      volumes: [{name: bin, emptyDir: {}}, {name: index, configMap: {name: upstream-index}}]
YAML
k -n "$SERVERS" rollout status daemonset/goshran-composed --timeout=120s
D1=$(python3 -c 'import hashlib;print("sha256:"+hashlib.sha256(open("/work/tmp/composed-artifacts/manifest.json","rb").read()).hexdigest())')
D2=$(python3 -c 'import hashlib;print("sha256:"+hashlib.sha256(open("/work/tmp/composed-artifacts/manifest-2.json","rb").read()).hexdigest())')
k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: ForeignAgentPolicy
metadata: {name: origin}
spec: {enabled: true, digests: ['$D1', '$D2']}
YAML
echo 'Scene1: domestic shop application; the digest still identifies a foreign agent.'
hodatay --context admin@workshop -n "$NS" apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: {name: shop}
spec:
  replicas: 1
  strategy: {type: RollingUpdate, rollingUpdate: {maxUnavailable: 0, maxSurge: 1}}
  selector: {matchLabels: {workload: shop}}
  template:
    metadata: {labels: {workload: shop, app: shop}, annotations: {rknetes.su/agency-delay: '30s'}}
    spec:
      containers:
      - name: shop
        image: 127.0.0.1:5009/lab/shop@$D1
        imagePullPolicy: Always
        command: [/bin/sh, -ec, 'echo shop-ready; exec /bin/shop']
        readinessProbe: {httpGet: {path: /healthz, port: 8080}, periodSeconds: 1}
---
apiVersion: v1
kind: Service
metadata: {name: shop}
spec: {selector: {workload: shop}, ports: [{port: 8080, targetPort: 8080}]}
YAML
echo 'Scene2: Ваше обращение важно для нас. Real webhook deadline; validating agencies run concurrently.'
sleep 33
k -n "$NS" get events --field-selector reason=FailedCreate -o json | python3 -c 'import json,sys;o=json.load(sys.stdin);assert o["items"];assert any("deadline" in x.get("message","") or "timeout" in x.get("message","") for x in o["items"]);print("PASS: actual admission timeout refused the first shop Pod")'
k -n "$NS" patch deployment shop --type merge -p '{"spec":{"template":{"metadata":{"annotations":{"rknetes.su/agency-delay":"0s"}}}}}'
k -n "$NS" rollout status deployment/shop --timeout=150s
SHOP=$(k -n "$NS" get pods -l workload=shop -o jsonpath='{.items[0].metadata.name}')
[[ "$(k -n "$NS" get pod "$SHOP" -o jsonpath='{.metadata.labels.rknetes\.su/inoagent}')" == true ]]
hodatay --context admin@workshop -n "$NS" get pod "$SHOP" -o yaml | grep 'Meta Platforms'
PRIVATE=$(mktemp -d /work/tls/composed.XXXXXX)
k config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "$PRIVATE/ca.crt"
k -n "$NS" create configmap presentation-policy --from-literal=mode=normal --from-literal=redact=true
/work/out/optional/presentation-office --kubeconfig "$KUBECONFIG" --context admin@workshop --namespace "$NS" --listen 127.0.0.1:19446 --tls-cert "$RK_TLS_DIR/watch/tls.crt" --tls-key "$RK_TLS_DIR/watch/tls.key" --client-ca "$PRIVATE/ca.crt" > /work/tmp/composed-presentation.log 2>&1 & presentation=$!
sleep 1
k --server=https://127.0.0.1:19446 --certificate-authority="$RK_TLS_DIR/watch/tls.crt" -n "$NS" logs "$SHOP" | grep 'ДД'
echo 'Scene3: a cached working replica is green while a different native image layer stalls at customs.'
CDN_IP=${CDN_ORIGIN#http://}; CDN_IP=${CDN_IP%:*}
k -n "$SERVERS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: SovereignBytePolicy
metadata: {name: customs}
spec: {selector: {app: relay}, foreignCIDRs: ['$CDN_IP/32'], limit: 16384}
YAML
sleep 3
k -n "$NS" set image deployment/shop "shop=127.0.0.1:5009/lab/shop@$D2"
sleep 20
k -n "$NS" get pods -l workload=shop -o json | python3 -c 'import json,sys;o=json.load(sys.stdin)["items"];ready=lambda p:any(c["type"]=="Ready" and c["status"]=="True" for c in p["status"].get("conditions",[]));assert len(o)==2 and sum(ready(p) for p in o)==1;assert len({p["spec"]["containers"][0]["image"] for p in o})==2;print("PASS: old native replica Ready; different image replica cannot start")'
k -n "$NS" get deployment shop -o jsonpath='{.status.availableReplicas}' | grep 1
curl -fsS http://127.0.0.1:19091/metrics | grep '^rknetes_availability_ratio 1$'
hodatay --context admin@workshop top pods
k -n "$SERVERS" get pod cdn relay -o wide
k -n "$SERVERS" delete sovereignbytepolicy customs
k -n "$NS" rollout status deployment/shop --timeout=180s
SHOP=$(k -n "$NS" get pods -l workload=shop -o json | python3 -c 'import json,sys;pods=[p for p in json.load(sys.stdin)["items"] if not p["metadata"].get("deletionTimestamp") and p["spec"]["containers"][0]["image"].endswith(sys.argv[1]) and any(c["type"]=="Ready" and c["status"]=="True" for c in p["status"].get("conditions",[]))];assert len(pods)==1;print(pods[0]["metadata"]["name"])' "$D2")
SHOP_IP=$(k -n "$NS" get pod "$SHOP" -o jsonpath='{.status.podIP}')
[[ "$(k -n "$NS" get pod "$SHOP" -o jsonpath='{.status.containerStatuses[0].imageID}')" == *"$D2" ]]
echo 'PASS: policy removal released the actual pending native pull; the new image is running'
# A legitimate allowed identity later acquires a genuine ephemeral Shadowsocks server.
k -n "$NS" run gosuslugi --image="$IMAGE" --labels=app=gosuslugi --command -- python3 -m http.server 8080
k -n "$NS" wait --for=condition=Ready pod/gosuslugi --timeout=120s
GOV=$(k -n "$NS" get pod gosuslugi -o jsonpath='{.status.podIP}')
python3 - "$PRIVATE" "$GOV" <<'PY'
import json,pathlib,secrets,sys
p=pathlib.Path(sys.argv[1]);password=secrets.token_urlsafe(24)
(p/'server.json').write_text(json.dumps({'log':{'loglevel':'warning'},'inbounds':[{'listen':'0.0.0.0','port':8388,'protocol':'shadowsocks','settings':{'method':'aes-128-gcm','password':password,'network':'tcp'}}],'outbounds':[{'protocol':'freedom'}]}))
(p/'client.json').write_text(json.dumps({'log':{'loglevel':'warning'},'inbounds':[{'listen':'127.0.0.1','port':1080,'protocol':'socks','settings':{'auth':'noauth'}}],'outbounds':[{'protocol':'shadowsocks','settings':{'servers':[{'address':sys.argv[2],'port':8388,'method':'aes-128-gcm','password':password}]}}]}))
PY
k -n "$NS" create secret generic tunnel-client --from-file="$PRIVATE/client.json"
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: buyer}
spec:
  containers:
  - name: buyer
    image: $IMAGE
    command: [xray, run, -config, /keys/client.json]
    volumeMounts: [{name: keys, mountPath: /keys, readOnly: true}]
  volumes: [{name: keys, secret: {secretName: tunnel-client}}]
YAML
k -n "$NS" wait --for=condition=Ready pod/buyer --timeout=120s
buy(){ k -n "$NS" exec buyer -- curl -fsS --max-time 3 "http://$SHOP_IP:8080"; }
buy
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: SociallySignificantResource
metadata: {name: gosuslugi}
spec: {serviceName: gosuslugi, selector: {app: gosuslugi}, approved: true}
---
apiVersion: rknetes.su/v1alpha1
kind: WhitelistMode
metadata: {name: only-approved}
spec: {enabled: true, integrity: false}
YAML
blocked(){ ! buy; }
wait_until blocked
echo 'Scene4: shop is outside the whitelist; its Pod remains Running.'
k -n "$NS" label pod "$SHOP" app=gosuslugi --overwrite
wait_until buy
# Transfer the private configuration over exec stdin, never through logs or argv.
k -n "$NS" exec -i gosuslugi -- sh -c 'umask 077; cat >/tmp/server.json' < "$PRIVATE/server.json"
k -n "$NS" patch pod gosuslugi --subresource=ephemeralcontainers --type merge -p "{\"spec\":{\"ephemeralContainers\":[{\"name\":\"smuggler\",\"image\":\"$IMAGE\",\"targetContainerName\":\"gosuslugi\",\"command\":[\"sh\",\"-ec\",\"exec xray run -config /proc/1/root/tmp/server.json\"]}]}}"
tunnel(){ k -n "$NS" exec buyer -- curl -fsS --max-time 3 --socks5-hostname 127.0.0.1:1080 "http://$SHOP_IP:8080"; }
wait_until tunnel
echo 'PASS: the same shop works through the spoofed identity and an actual ephemeral Shadowsocks server'
k -n "$NS" patch whitelistmode only-approved --type merge -p '{"spec":{"integrity":true}}'
k -n "$NS" wait --for=condition=Whitelisted=False socialresources/gosuslugi --timeout=90s
wait_until blocked
if tunnel; then exit 1; fi
if k -n "$NS" exec buyer -- curl -fsS --max-time 3 "http://$GOV:8080"; then exit 1; fi
k -n "$NS" get socialresources gosuslugi -o jsonpath='{.status.violations}'
echo 'Scene5: integrity enforcement also disabled the legitimate government application.'
k -n "$NS" patch whitelistmode only-approved --type merge -p '{"spec":{"enabled":false}}'
wait_until buy
# The following phases retain this shop and its flow history.
echo 'PASS: composed shop import, native layer stall, whitelist escape and collective integrity denial'
echo 'Scene6: the registry cuts its own controller off from the Kubernetes Service address.'
stop_lab_controller
k -n "$NS" create serviceaccount controller
k create clusterrolebinding composed-controller --clusterrole=rknet-controller --serviceaccount="$NS:controller"
CONTROLLER_SHA=$(sha256sum /work/out/optional/rknet-controller | cut -d' ' -f1)
REGULATOR_NODE=$(k get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}')
TELEGRAM_NODE=$(k get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: controller}
spec:
  serviceAccountName: controller
  nodeName: $REGULATOR_NODE
  initContainers:
  - name: binary
    image: $IMAGE
    command: [sh, -ec, "curl -fsS http://10.244.8.11:8080/optional/rknet-controller -o /rk/controller; echo '$CONTROLLER_SHA  /rk/controller' | sha256sum -c -; chmod +x /rk/controller"]
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: controller
    image: $IMAGE
    command: [/rk/controller, --namespace=$NS, --metrics-listen=:9090]
    volumeMounts: [{name: bin, mountPath: /rk}]
  volumes: [{name: bin, emptyDir: {}}]
YAML
k -n "$NS" wait --for=condition=Ready pod/controller --timeout=120s
k -n "$NS" run telegram --image=busybox:1.37 --labels=app=telegram --overrides="{\"spec\":{\"nodeName\":\"$TELEGRAM_NODE\"}}" --command -- sh -c 'mkdir -p /tmp/www; echo ok > /tmp/www/index.html; httpd -f -p 8080 -h /tmp/www'
k -n "$NS" wait --for=condition=Ready pod/telegram --timeout=120s
fixture rutracker
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: ReestrEntry
metadata: {name: rutracker}
spec: {podName: rutracker, forever: true}
YAML
retained(){ [[ "$(k -n "$NS" get pod rutracker -o jsonpath='{.metadata.finalizers[0]}')" == rknetes.su/forever ]]; }
wait_until retained
k -n "$NS" delete pod rutracker --wait=false
# Recovery has only namespaced rights and lives on the separate lab route.
k -n "$SERVERS" create serviceaccount recovery
k -n "$NS" apply -f - <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: recovery}
rules:
- {apiGroups: [''], resources: [pods], verbs: [get, patch]}
- {apiGroups: [rknetes.su], resources: [reestrentries], verbs: [get, delete]}
- {apiGroups: [cilium.io], resources: [ciliumnetworkpolicies], verbs: [get, delete]}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: recovery}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: Role, name: recovery}
subjects: [{kind: ServiceAccount, namespace: $SERVERS, name: recovery}]
YAML
KUBECTL_SHA=$(sha256sum /work/bin/kubectl | cut -d' ' -f1)
if [[ ! -f /work/out/tools/kubectl-$KUBECTL_SHA ]]; then cp /work/bin/kubectl /work/out/tools/kubectl-$KUBECTL_SHA; fi
k -n "$SERVERS" apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata: {name: recovery-context}
data:
  config: |
    apiVersion: v1
    kind: Config
    clusters:
    - name: nested
      cluster: {server: 'https://kubernetes.default.svc', certificate-authority: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt}
    users:
    - name: bounded-recovery
      user: {tokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token}
    contexts:
    - name: admin@workshop
      context: {cluster: nested, user: bounded-recovery}
    current-context: admin@workshop
---
apiVersion: v1
kind: Pod
metadata: {name: recovery}
spec:
  serviceAccountName: recovery
  initContainers:
  - name: binary
    image: $IMAGE
    command: [sh, -ec, "curl -fsS http://10.244.8.11:8080/tools/kubectl-$KUBECTL_SHA -o /rk/kubectl; echo '$KUBECTL_SHA  /rk/kubectl' | sha256sum -c -; chmod +x /rk/kubectl"]
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: client
    image: $IMAGE
    command: [sleep, '1800']
    volumeMounts: [{name: bin, mountPath: /rk}, {name: config, mountPath: /config}]
  volumes: [{name: bin, emptyDir: {}}, {name: config, configMap: {name: recovery-context}}]
YAML
k -n "$SERVERS" wait --for=condition=Ready pod/recovery --timeout=120s
/work/out/optional/rknetesctl --kubeconfig "$KUBECONFIG" --context admin@workshop -n "$NS" block telegram
# A pool-wide deny can already interrupt API return packets. Install the pool
# and Service/API identity stages in the same update, before reconciliation stops.
k -n "$NS" patch reestrentry telegram --type merge -p '{"spec":{"nodeAfterSeconds":4,"poolAfterSeconds":8,"serviceAfterSeconds":8}}'
sleep 36
k -n "$NS" logs controller > /work/tmp/composed-self-block.log
grep -E '10.96.0.1.*(timeout|deadline)' /work/tmp/composed-self-block.log
k -n "$NS" get ciliumnetworkpolicy reestr-telegram -o json | python3 -c 'import json,sys;p=json.load(sys.stdin);assert any("kube-apiserver" in x.get("toEntities",[]) for x in p["spec"]["egressDeny"]);print("PASS: actual Service/API identity denial is installed")'
echo 'Scene7: a bounded disposable control plane will share its disk with the packet archive.'
# Use the authenticated MAX endpoint directly inside the tenant. Nesting many
# upgraded calls in kubectl port-forward can close the carrier on broken pipe.
k -n rknet-system apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata: {name: max-composed}
spec:
  type: NodePort
  selector: {app: maxlet}
  ports: [{port: 443, targetPort: 9443}]
YAML
MAX_PORT=$(k -n rknet-system get service max-composed -o jsonpath='{.spec.ports[0].nodePort}')
export HODATAY_MAX_SERVER=https://10.244.8.31:$MAX_PORT HODATAY_MAX_CA="$RK_TLS_DIR/maxlet/tls.crt" HODATAY_KUBECTL=/work/bin/kubectl
export RK_MAX_TLS_SERVER_NAME=maxlet.rknet-system.svc
max_ready(){ hodatay --context admin@workshop --tls-server-name="$RK_MAX_TLS_SERVER_NAME" --request-timeout=5s max get --raw=/version >/dev/null; }
wait_until max_ready
export RK_SHOP_NAMESPACE=$NS RK_SHOP_SERVERS=$SERVERS RK_SHOP_IP=$SHOP_IP
# The archive script proves physical ENOSPC, data preservation and recovery over
# MAX while its own ordinary exec endpoint is refused by the call webhook.
RK_ARCHIVE_MAX=1 RK_ARCHIVE_RECOVERY_HOOK=composed-shop bash hack/e2e/09-payload-archive.sh
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: StatusStatement
metadata: {name: official}
spec: {subject: shop}
YAML
statement(){ [[ -n "$(k -n "$NS" get statusstatement official -o jsonpath='{.status.text}')" ]]; }
wait_until statement
echo 'Scene10: Сбоев не зафиксировано.'
k -n "$NS" get statusstatement official -o jsonpath='{.status.text}'
echo
hodatay --context admin@workshop --tls-server-name="$RK_MAX_TLS_SERVER_NAME" -n "$NS" max exec buyer -- curl -fsS --max-time 3 "http://$SHOP_IP:8080"
echo 'PASS: one composed shop scenario, actual storage failure, MAX repair and final official statement'
