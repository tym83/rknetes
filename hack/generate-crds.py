#!/usr/bin/env python3
"""Generate structural CRDs without a code-generation toolchain."""
import json
from pathlib import Path

string = {"type": "string"}
boolean = {"type": "boolean"}
integer = {"type": "integer", "minimum": 0}
strings = {"type": "array", "items": string}
labels = {"type": "object", "additionalProperties": string}

def obj(properties, required=()):
    return {"type": "object", "properties": properties, "required": list(required)}

def enum(*values):
    return {"type": "string", "enum": list(values)}

kinds = {
    "ReestrEntry": ("reestrentries", ["reestr"], obj({
        "podName": string, "selector": labels, "reason": string,
        "escalate": boolean, "nodeAfterSeconds": integer, "poolAfterSeconds": integer,
        "serviceAfterSeconds": integer, "forever": boolean,
    })),
    "ThrottlePolicy": ("throttlepolicies", ["throttle"], obj({
        "pattern": string, "bandwidth": string,
        "mode": {**enum("Ограничение", "Замедление", "Деградация", "ТехническиеПроблемы"),
                 "description": "Ограничение; Замедление; Деградация; ТехническиеПроблемы."},
    }, ["pattern", "bandwidth", "mode"])),
    "SovereignBytePolicy": ("sovereignbytepolicies", [], obj({"selector": labels, "foreignCIDRs": strings, "limit": integer})),
    "WhitelistMode": ("whitelistmodes", [], obj({"enabled": boolean, "integrity": boolean, "capacity": integer,
        "capacityMeasurement": string, "reservedEntries": integer, "periodSeconds": integer,
        "activePercent": {"type": "integer", "minimum": 1, "maximum": 99}})),
    "SociallySignificantResource": ("sociallysignificantresources", ["socialresources"], obj({
        "serviceName": string, "selector": labels, "approved": boolean,
        "dependencies": strings, "allowedImages": strings, "allowedServiceAccounts": strings,
    }, ["serviceName", "selector"])),
    "TunnelProfile": ("tunnelprofiles", [], obj({"protocolLadder": strings, "blockedProtocols": strings, "compliant": boolean, "target": string,
        "agentPodName": string, "agentPort": integer, "pigeonRef": string, "gatewayNamespace": string, "gatewaySelector": labels})),
    "Pigeon": ("pigeons", [], obj({"claimName": string, "nodeName": string, "destinationNamespace": string, "delaySeconds": integer, "observeTraffic": boolean, "lossPercent": {"type": "integer", "minimum": 0, "maximum": 100}})),
    "Werewolf": ("werewolves", [], obj({"address": string, "selector": labels, "port": integer}, ["address", "selector", "port"])),
    "CallRestriction": ("callrestrictions", [], obj({"enabled": boolean})),
    "ForeignAgentPolicy": ("foreignagentpolicies", [], obj({"enabled": boolean, "digests": strings, "rewriteImages": labels, "resolveDigests": boolean, "foreignImages": strings, "insecureRegistries": strings, "registryMirrors": labels})),
    "ArchivePolicy": ("archivepolicies", [], obj({"claimName": string, "volumeName": string, "selector": labels, "maxBytes": integer, "retentionDays": integer, "capturePayload": boolean})),
    "DataBoundaryPolicy": ("databoundarypolicies", [], obj({"selector": labels, "primaryService": string})),
    "SovereigntyDrill": ("sovereigntydrills", [], obj({"enabled": boolean, "foreignSelector": labels, "quarterly": boolean, "durationSeconds": integer})),
    "BloggerRegistration": ("bloggerregistrations", [], obj({"resource": string, "name": string, "registered": boolean, "threshold": integer})),
    "AdvertisingPolicy": ("advertisingpolicies", [], obj({"enabled": boolean})),
    "CoolingPolicy": ("coolingpolicies", [], obj({"nodeName": string, "durationSeconds": integer, "captchaURL": string, "captchaSHA256": string, "captchaSolved": boolean, "reason": string}, ["nodeName"])),
    "StatusStatement": ("statusstatements", [], obj({"subject": string})),
}
crds = []
for kind, (plural, short, spec) in kinds.items():
    crds.append({"apiVersion": "apiextensions.k8s.io/v1", "kind": "CustomResourceDefinition",
        "metadata": {"name": plural + ".rknetes.su"}, "spec": {
            "group": "rknetes.su", "scope": "Namespaced",
            "names": {"kind": kind, "plural": plural, "singular": kind.lower(), "shortNames": short},
            "versions": [{"name": "v1alpha1", "served": True, "storage": True,
                "subresources": {"status": {}},
                "schema": {"openAPIV3Schema": obj({"apiVersion": string, "kind": string,
                    "metadata": {"type": "object"}, "spec": spec,
                    "status": {"type": "object", "x-kubernetes-preserve-unknown-fields": True}})},
            }],
        }})
Path("deploy/crds.yaml").write_text("\n---\n".join(json.dumps(c, indent=2, ensure_ascii=False) for c in crds) + "\n")
