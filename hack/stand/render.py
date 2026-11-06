#!/usr/bin/env python3
"""Render the add-on installation with private builder binaries and serving CA."""
import json
import os

objects = []
def add(api, kind, name, **fields):
    resource = {"apiVersion": api, "kind": kind, "metadata": {"name": name}, **fields}
    objects.append(resource)
    return resource

def ns(resource):
    resource["metadata"]["namespace"] = "rknet-system"
    return resource

ns(add("v1", "ServiceAccount", "rknet-controller"))
ns(add("v1", "ServiceAccount", "rknet-admission"))
add("rbac.authorization.k8s.io/v1", "ClusterRole", "rknet-controller", rules=[
    {"apiGroups": ["rknetes.su"], "resources": ["*"], "verbs": ["get", "list", "watch", "create", "patch", "update", "delete"]},
    {"apiGroups": [""], "resources": ["namespaces", "pods", "nodes", "services", "serviceaccounts", "secrets", "configmaps", "events"], "verbs": ["get", "list", "watch", "create", "patch", "update"]},
    {"apiGroups": [""], "resources": ["pods/status"], "verbs": ["patch"]},
    {"apiGroups": [""], "resources": ["pods/proxy"], "verbs": ["get"]},
    {"apiGroups": ["coordination.k8s.io"], "resources": ["leases"], "verbs": ["get"]},
    {"apiGroups": ["batch"], "resources": ["cronjobs", "jobs"], "verbs": ["get", "list", "create", "update", "patch", "delete"]},
    {"apiGroups": ["rbac.authorization.k8s.io"], "resources": ["roles", "rolebindings", "clusterroles", "clusterrolebindings"], "verbs": ["get", "create", "update", "patch"]},
    {"apiGroups": [""], "resources": ["persistentvolumes", "persistentvolumeclaims"], "verbs": ["get", "list", "create", "update", "patch", "delete"]},
    {"apiGroups": [""], "resources": ["pods"], "verbs": ["delete"]},
    {"apiGroups": ["discovery.k8s.io"], "resources": ["endpointslices"], "verbs": ["get", "list", "watch"]},
    {"apiGroups": ["cilium.io"], "resources": ["ciliumnetworkpolicies"], "verbs": ["get", "list", "watch", "create", "patch", "update", "delete"]},
])
add("rbac.authorization.k8s.io/v1", "ClusterRole", "rknet-admission", rules=[
    {"apiGroups": ["rknetes.su"], "resources": ["callrestrictions", "advertisingpolicies", "foreignagentpolicies"], "verbs": ["get", "list"]},
    {"apiGroups": [""], "resources": ["configmaps", "secrets", "serviceaccounts"], "verbs": ["get"]},
])
ns(add("v1", "ServiceAccount", "watch-office"))
add("rbac.authorization.k8s.io/v1", "ClusterRole", "watch-office", rules=[
    {"apiGroups":[""],"resources":["namespaces","configmaps"],"verbs":["get","list","watch"]},
    {"apiGroups":["rknetes.su"],"resources":["bloggerregistrations","bloggerregistrations/status"],"verbs":["get","list","create","patch"]},
    {"apiGroups":["authorization.k8s.io"],"resources":["subjectaccessreviews"],"verbs":["create"]},
])
for name in ("rknet-controller", "rknet-admission", "watch-office"):
    add("rbac.authorization.k8s.io/v1", "ClusterRoleBinding", name,
        roleRef={"apiGroup": "rbac.authorization.k8s.io", "kind": "ClusterRole", "name": name},
        subjects=[{"kind": "ServiceAccount", "name": name, "namespace": "rknet-system"}])
    volumes = [{"name": "bin", "emptyDir": {}}]
    mounts = [{"name": "bin", "mountPath": "/bin/rk", "readOnly": True}]
    if name in ("rknet-admission", "watch-office"):
        volumes.append({"name": "tls", "secret": {"secretName": "admission-tls" if name == "rknet-admission" else "watch-office-tls"}})
        mounts.append({"name": "tls", "mountPath": "/tls", "readOnly": True})
    container = {"name": name, "image": "busybox:1.37", "command": ["/bin/rk/" + name],
                 "resources": {"requests": {"cpu": "50m", "memory": "64Mi"}, "limits": {"cpu": "1", "memory": "256Mi"}}, "volumeMounts": mounts}
    ns(add("apps/v1", "Deployment", name, spec={"replicas": 1, "selector": {"matchLabels": {"app": name}},
       "template": {"metadata": {"labels": {"app": name}}, "spec": {"serviceAccountName": name,
       "initContainers": [{"name": "binary", "image": "busybox:1.37", "command": ["sh", "-ec", 'wget -q -O /out/' + name + ' "$1/' + name + '"; chmod 755 /out/' + name, "download", os.environ["RK_BINARY_URL"]], "volumeMounts": [{"name": "bin", "mountPath": "/out"}]}],
       "containers": [container], "volumes": volumes}}}))
ns(add("v1", "Service", "rknet-admission", spec={"selector": {"app": "rknet-admission"}, "ports": [{"port": 443, "targetPort": 9443}]}))
ns(add("v1", "Service", "watch-office", spec={"selector":{"app":"watch-office"},"ports":[{"port":443,"targetPort":9443}]}))
selector = {"matchLabels": {"rknetes.su/lab": "true"}}
def hook(name, path, operations, resources, groups=[""]):
    return {"name": name + ".rknetes.su", "admissionReviewVersions": ["v1"], "sideEffects": "None", "failurePolicy": "Fail", "timeoutSeconds": 30,
            "namespaceSelector": selector, "clientConfig": {"service": {"name": "rknet-admission", "namespace": "rknet-system", "path": path}, "caBundle": os.environ["RK_CA"]},
            "rules": [{"operations": operations, "apiGroups": groups, "apiVersions": ["v1"], "resources": resources, "scope": "Namespaced"}]}
hooks = [hook("calls", "/calls", ["CONNECT"], ["pods/exec", "pods/attach", "pods/portforward"]),
         hook("erid", "/erid", ["CREATE", "UPDATE"], ["events"], ["", "events.k8s.io"])]
hooks += [hook("agency-" + str(i), "/agency/" + str(i), ["CREATE"], ["pods"]) for i in range(15)]
add("admissionregistration.k8s.io/v1", "ValidatingWebhookConfiguration", "rknet-agencies", webhooks=hooks)
add("admissionregistration.k8s.io/v1", "MutatingWebhookConfiguration", "rknet-origin", webhooks=[hook("inoagent", "/inoagent", ["CREATE"], ["pods"])])

ns(add("v1", "ServiceAccount", "maxlet"))
add("scheduling.k8s.io/v1", "PriorityClass", "rknetes-max", value=900000000, globalDefault=False, preemptionPolicy="Never", description="MAX has scheduling priority over ordinary Pods; the host kubelet is outside Pod priority.")
add("rbac.authorization.k8s.io/v1", "ClusterRole", "maxlet", rules=[
    {"apiGroups": [""], "resources": ["pods", "namespaces", "configmaps"], "verbs": ["get"]},
    {"apiGroups": [""], "resources": ["pods/exec", "pods/attach", "pods/portforward"], "verbs": ["create", "get"]},
    {"apiGroups": [""], "resources": ["pods/log"], "verbs": ["get"]},
    {"apiGroups": [""], "resources": ["events"], "verbs": ["get", "list", "watch"]},
    {"apiGroups": ["authorization.k8s.io"], "resources": ["subjectaccessreviews"], "verbs": ["create"]},
])
add("rbac.authorization.k8s.io/v1", "ClusterRoleBinding", "maxlet", roleRef={"apiGroup":"rbac.authorization.k8s.io","kind":"ClusterRole","name":"maxlet"}, subjects=[{"kind":"ServiceAccount","name":"maxlet","namespace":"rknet-system"}])
ns(add("apps/v1", "DaemonSet", "maxlet", spec={"selector":{"matchLabels":{"app":"maxlet"}},"template":{"metadata":{"labels":{"app":"maxlet"}},"spec":{
    "serviceAccountName":"maxlet","priorityClassName":"rknetes-max","tolerations":[{"operator":"Exists"}],
    "initContainers":[{"name":"binary","image":"busybox:1.37","command":["sh","-ec",'wget -q -O /bin/rk/maxlet "$1/maxlet"; chmod +x /bin/rk/maxlet',"download",os.environ["RK_BINARY_URL"]],"volumeMounts":[{"name":"bin","mountPath":"/bin/rk"}]}],
    "containers":[{"name":"maxlet","image":"busybox:1.37","command":["/bin/rk/maxlet"],"volumeMounts":[{"name":"bin","mountPath":"/bin/rk"},{"name":"tls","mountPath":"/tls"},{"name":"archive","mountPath":"/archive"}]}],
    "volumes":[{"name":"bin","emptyDir":{}},{"name":"tls","secret":{"secretName":"maxlet-tls"}},{"name":"archive","hostPath":{"path":"/var/lib/rknetes/max","type":"DirectoryOrCreate"}}]
}}}))
ns(add("v1","Service","maxlet",spec={"selector":{"app":"maxlet"},"ports":[{"port":443,"targetPort":9443}]}))
print(json.dumps({"apiVersion": "v1", "kind": "List", "items": objects}))
