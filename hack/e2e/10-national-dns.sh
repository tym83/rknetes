#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-national-dns
new_namespace "$NS"
start_lab_controller
trap 'stop_lab_controller; stop_forward' EXIT
IMAGE=$(cat /work/out/tools/lab-image.ref)
PRIVATE=$(mktemp -d /work/tls/national-dns.XXXXXX)
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -keyout "$PRIVATE/tls.key" -out "$PRIVATE/tls.crt" -subj /CN=domestic.lab -addext subjectAltName=DNS:domestic.lab >/dev/null 2>&1
k -n "$NS" create secret tls clock-certificate --cert="$PRIVATE/tls.crt" --key="$PRIVATE/tls.key"
REGISTRY_IMAGE="registry:3@$(crane digest --platform linux/amd64 registry:3)"
k -n "$NS" run registry --image="$REGISTRY_IMAGE" --labels=dependency=foreign --env=OTEL_TRACES_EXPORTER=none --env=REGISTRY_LOG_LEVEL=error
k -n "$NS" wait --for=condition=Ready pod/registry --timeout=120s
REGISTRY=$(k -n "$NS" get pod registry -o jsonpath='{.status.podIP}')
start_forward "$NS" pod/registry 15001:5000
crane copy --platform linux/amd64 --insecure busybox:1.37 127.0.0.1:15001/lab/shop:1
stop_forward
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: domestic, labels: {dependency: domestic}}
spec:
  automountServiceAccountToken: false
  containers:
  - name: tls
    image: $IMAGE
    command: [openssl, s_server, -accept, '8443', -cert, /tls/tls.crt, -key, /tls/tls.key, -www, -quiet]
    volumeMounts: [{name: tls, mountPath: /tls, readOnly: true}]
  volumes: [{name: tls, secret: {secretName: clock-certificate}}]
YAML
k -n "$NS" wait --for=condition=Ready pod/domestic --timeout=120s
DOMESTIC=$(k -n "$NS" get pod domestic -o jsonpath='{.status.podIP}')
DNS_SHA=$(sha256sum /work/out/optional/national-dns | cut -d' ' -f1)
CLOCK_SHA=$(sha256sum /work/out/optional/lab-clock | cut -d' ' -f1)
k -n "$NS" create configmap foreign-zones --from-literal="zones.json={\"records\":{\"registry.foreign.lab.\":\"$REGISTRY\"}}"
dns_pod() {
 local name=$1 config=$2 dependency=$3
 k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: $name, labels: {app: $name, dependency: $dependency}}
spec:
  automountServiceAccountToken: false
  initContainers:
  - name: binary
    image: $IMAGE
    command: [sh, -ec, "curl -fsS http://10.244.8.11:8080/optional/national-dns -o /rk/national-dns; echo '$DNS_SHA  /rk/national-dns' | sha256sum -c -; chmod +x /rk/national-dns"]
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: resolver
    image: $IMAGE
    command: [/rk/national-dns, --ntp-listen, ':1123']
    readinessProbe: {tcpSocket: {port: 1053}, periodSeconds: 1}
    volumeMounts: [{name: bin, mountPath: /rk}, {name: zones, mountPath: /config, readOnly: true}]
  volumes: [{name: bin, emptyDir: {}}, {name: zones, configMap: {name: $config}}]
YAML
 k -n "$NS" wait --for=condition=Ready "pod/$name" --timeout=120s
}
dns_pod foreign-resolver foreign-zones foreign
FOREIGN=$(k -n "$NS" get pod foreign-resolver -o jsonpath='{.status.podIP}')
k -n "$NS" create configmap national-zones --from-literal="zones.json={\"records\":{\"domestic.lab.\":\"$DOMESTIC\"},\"upstream\":\"$FOREIGN:1053\"}"
dns_pod national-resolver national-zones domestic
k -n "$NS" apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata: {name: national-dns}
spec:
  selector: {app: national-resolver}
  ports: [{name: udp, port: 53, targetPort: 1053, protocol: UDP}, {name: tcp, port: 53, targetPort: 1053, protocol: TCP}]
YAML
DNS=$(k -n "$NS" get service national-dns -o jsonpath='{.spec.clusterIP}')
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: client}
spec:
  automountServiceAccountToken: false
  dnsPolicy: None
  dnsConfig: {nameservers: ['$DNS'], options: [{name: ndots, value: '1'}, {name: timeout, value: '1'}, {name: attempts, value: '1'}]}
  initContainers:
  - name: binary
    image: $IMAGE
    command: [sh, -ec, "curl -fsS http://10.244.8.11:8080/optional/lab-clock -o /rk/lab-clock; echo '$CLOCK_SHA  /rk/lab-clock' | sha256sum -c -; chmod +x /rk/lab-clock"]
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: client
    image: $IMAGE
    command: [sleep, '1800']
    volumeMounts: [{name: bin, mountPath: /rk}, {name: tls, mountPath: /tls, readOnly: true}]
  volumes: [{name: bin, emptyDir: {}}, {name: tls, secret: {secretName: clock-certificate}}]
YAML
k -n "$NS" wait --for=condition=Ready pod/client --timeout=120s
resolve() { k -n "$NS" exec client -- python3 -c 'import socket,sys;print(socket.gethostbyname(sys.argv[1]))' "$1"; }
pull() { k -n "$NS" exec client -- timeout 7 crane pull --insecure registry.foreign.lab:5000/lab/shop:1 /tmp/shop.tar; }
clock() { k -n "$NS" exec client -- /rk/lab-clock --ntp "$FOREIGN:1123" --unsynced-offset 48h --url "https://$DOMESTIC:8443" --ca /tls/tls.crt; }
[[ "$(resolve domestic.lab)" == "$DOMESTIC" ]]
[[ "$(resolve registry.foreign.lab)" == "$REGISTRY" ]]
pull
clock
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: SovereigntyDrill
metadata: {name: quarterly}
spec: {enabled: false, quarterly: true, durationSeconds: 60, foreignSelector: {dependency: foreign}}
YAML
ready_cron() { [[ "$(k -n "$NS" get cronjob -o jsonpath='{.items[0].spec.schedule}' 2>/dev/null)" == '0 3 1 */3 *' ]]; }
wait_until ready_cron
CRON=$(k -n "$NS" get cronjob -o jsonpath='{.items[0].metadata.name}')
k -n "$NS" create job quarterly-now --from="cronjob/$CRON"
active() { [[ "$(k -n "$NS" get sovereigntydrill quarterly -o jsonpath='{.spec.enabled}')" == true ]]; }
wait_until active
k -n "$NS" wait --for=condition=Ready sovereigntydrill/quarterly --timeout=60s
sleep 3
[[ "$(resolve domestic.lab)" == "$DOMESTIC" ]]
if resolve registry.foreign.lab; then exit 1; fi
if pull; then exit 1; fi
if clock > /work/tmp/drill-clock.log 2>&1; then exit 1; fi
cat /work/tmp/drill-clock.log
grep -q 'certificate has expired' /work/tmp/drill-clock.log
k -n "$NS" get sovereigntydrill quarterly -o json
k -n "$NS" wait --for=condition=Complete job/quarterly-now --timeout=120s
k -n "$NS" logs job/quarterly-now -c drill
recovered() { [[ "$(resolve registry.foreign.lab)" == "$REGISTRY" ]]; }
wait_until recovered
pull
clock
[[ "$(k -n "$NS" get sovereigntydrill quarterly -o jsonpath='{.spec.enabled}')" == false ]]
echo 'PASS: real quarterly CronJob, lab DNS/OCI outage, actual NTP loss and TLS expiry under a controlled application clock; full automatic recovery without any host clock or external routing change'
