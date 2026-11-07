# Yarovaya storage

ArchivePolicy selects new lab Pods for a `yarovaya` sidecar. The collector mounts
`claimName` as a PVC, or an explicitly named existing Pod volume. Its binary is
verified against the immutable runtime-artifact hash. Host-network Pods are
rejected. Only IPv4 packets whose two endpoint addresses belong to Pods in the
same labelled lab namespace enter the PCAP file. Independent Hubble records
must also name that namespace at both ends. No external traffic is captured.

Payloads are actual Ethernet/IP packet bytes, not fabricated flow counters.
PCAP and Hubble JSONL rotate at4MiB; storage defaults to256MiB per collector.
Files use mode0600, directories0700. Payload writes synchronize each1MiB and
when rotating a segment. The default retention is180days; smaller values are
rejected. Active collectors remove their expired segments, preserving recent
segments even when the space limit is reached. A PVC can outlive its collector;
its retained files stay available to its owner. `collectorPod`, stored bytes,
filesystem availability and Recording/StorageExhausted describe the most recent
collector report for the policy. A full archive stops recording new data.

09-payload-archive proves admission injection, an exact HTTP response inside a
PCAP, actual Hubble endpoint metadata and pruning of a controlled181-day-old
file while retaining a recent file. The test does not wait six months.

For the shared-disk failure, a disposable Pod creates one256MiB loopback ext4
filesystem. Its actual apiserver and etcd share that filesystem with captured
UDP traffic. The apiserver listens only on the Pod's loopback address and
requires its private test certificate. The real cluster never uses this etcd.
In payload-archive-6, packet files filled the filesystem to100%; etcd's bbolt
backend reported `no space left on device` and terminated. One queued write
completed before subsequent API writes failed. This version fails outright;
it does not turn into a healthy read-only database merely because the concept
calls the state read-only.

Removing the packet archive and restarting etcd preserved the original
ConfigMap and allowed a new write. Deleting the disposable Pod unmounted and
detached its allocated loop device. The original nested API remained ready.
The256MiB backing file bounds physical storage consumption in the lab.
`payload-archive.tar.gz` retains the passing run and all five earlier attempts.
