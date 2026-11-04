# Overlay the tenant-built components on the kuberoot filesystem.
RK_BIN=/work/out/rknetes
for binary in rknet-controller rknet-admission rknetesctl hodatay hodatay-upstream goshran maxlet lab-server eo-server; do
    install -m 0755 "$RK_BIN/$binary" "$r/usr/bin/$binary"
done
cp "$r/usr/bin/kube-scheduler" "$r/usr/bin/gosplan"
cp "$r/usr/bin/kubelet" "$r/usr/bin/uchastkovy"
mkdir -p "$r/usr/share/licenses/kubernetes" "$r/usr/share/licenses/rknetes"
cp /work/src/kubernetes-rknetes/LICENSE "$r/usr/share/licenses/kubernetes/LICENSE"
cp /work/src/rknetes/LICENSE "$r/usr/share/licenses/rknetes/LICENSE"
