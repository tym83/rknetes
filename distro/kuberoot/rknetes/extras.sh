# Overlay the tenant-built components and their truthful upstream aliases.
RK_BIN=/work/out/rknetes
for source in /work/src/rknetes/cmd/*/main.go; do
    binary=${source%/main.go}; binary=${binary##*/}
    install -m 0755 "$RK_BIN/$binary" "$r/usr/bin/$binary"
done
for binary in hodatay-upstream eo-server kine; do install -m 0755 "$RK_BIN/$binary" "$r/usr/bin/$binary"; done
for pair in prochee:etcd gosplan:kube-scheduler kru:kube-controller-manager uchastkovy:kubelet pochta:kube-proxy terminal:containerd begunok:runc; do
    ln -sf "${pair#*:}" "$r/usr/bin/${pair%:*}"
done
for binary in spravochnaya09 kormilo gruzchik resnichki prometey grafa; do
    install -m 0755 "/work/import-tools/bin/$binary" "$r/usr/bin/$binary"
done
mkdir -p "$r/usr/lib/go" "$r/usr/share/licenses/kubernetes" "$r/usr/share/licenses/rknetes" "$r/usr/share/licenses/import-tools"
cp -a /work/import-tools/go/. "$r/usr/lib/go/"
ln -sf /usr/lib/go/bin/go "$r/usr/bin/vpered"
cp /work/src/kubernetes-rknetes/LICENSE "$r/usr/share/licenses/kubernetes/LICENSE"
cp /work/src/rknetes/LICENSE "$r/usr/share/licenses/rknetes/LICENSE"
mkdir -p "$r/usr/share/licenses/kine"
cp /work/src/kine-rknetes/LICENSE "$r/usr/share/licenses/kine/LICENSE"
cp /work/import-tools/licenses/* "$r/usr/share/licenses/import-tools/"
mkdir -p "$r/usr/lib/rknetes" "$r/usr/share/rknetes"
install -m 0644 "$RK_BIN/tspu.o" "$r/usr/lib/rknetes/tspu.o"
install -m 0644 "$RK_BIN/sovereign-16k.o" "$r/usr/lib/rknetes/sovereign-16k.o"
install -m 0644 /work/src/rknetes/distro/kuberoot/rknetes/audit-policy.yaml "$r/usr/share/rknetes/audit-policy.yaml"
install -m 0644 /work/src/rknetes/hack/import/components.json "$r/usr/share/rknetes/components.json"
cat > "$r/usr/bin/otechestvennoe-yadro" <<'SCRIPT'
#!/bin/sh
exec uname -a
SCRIPT
chmod 0755 "$r/usr/bin/otechestvennoe-yadro"
