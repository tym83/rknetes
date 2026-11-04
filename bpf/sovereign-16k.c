// Count unique TCP payload bytes at tc egress; ACKs stay live after the limit.
// Attach only inside a selected lab Pod network namespace.
#include <linux/bpf.h>
#include <linux/pkt_cls.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/in.h>
#include <linux/tcp.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

struct flow { __u32 src, dst; __u16 sport, dport; };
struct progress { __u32 base, end; };
// iproute2's built-in loader uses this stable ELF map ABI. The fixture image
// does not link libbpf, so BTF-style .maps would leave map relocations unresolved.
struct bpf_elf_map {
    __u32 type, size_key, size_value, max_elem, flags, id, pinning;
};
struct bpf_elf_map connections SEC("maps") = {
    .type = BPF_MAP_TYPE_LRU_HASH,
    .size_key = sizeof(struct flow),
    .size_value = sizeof(struct progress),
    .max_elem = 4096,
};

SEC("tc")
int sovereign_16k(struct __sk_buff *skb) {
    void *data = (void *)(long)skb->data, *end = (void *)(long)skb->data_end;
    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > end || eth->h_proto != bpf_htons(ETH_P_IP)) return TC_ACT_OK;
    struct iphdr *ip = (void *)(eth + 1);
    if ((void *)(ip + 1) > end || ip->protocol != IPPROTO_TCP || ip->ihl < 5) return TC_ACT_OK;
    struct tcphdr *tcp = (void *)ip + ip->ihl * 4;
    if ((void *)(tcp + 1) > end || tcp->doff < 5) return TC_ACT_OK;
    // Foreign lab traffic uses this source port. Other ports and destinations
    // outside the nested Pod CIDR never enter this counter.
    if (tcp->source != bpf_htons(8081) || (bpf_ntohl(ip->daddr) & 0xffff0000) != 0x0a2a0000) return TC_ACT_OK;
    __u32 headers = ip->ihl * 4 + tcp->doff * 4;
    __u32 length = bpf_ntohs(ip->tot_len);
    if (length <= headers) return TC_ACT_OK;
    __u32 payload = length - headers;
    struct flow key = {ip->saddr, ip->daddr, tcp->source, tcp->dest};
    __u32 seq = bpf_ntohl(tcp->seq);
    struct progress *p = bpf_map_lookup_elem(&connections, &key);
    if (!p) {
        struct progress initial = {seq, seq};
        bpf_map_update_elem(&connections, &key, &initial, BPF_NOEXIST);
        p = bpf_map_lookup_elem(&connections, &key);
        if (!p) return TC_ACT_SHOT;
    }
    // Sequence-relative accounting does not charge retransmissions twice.
    if ((__u32)(seq - p->base) + payload > 16384) return TC_ACT_SHOT;
    if ((__s32)(seq + payload - p->end) > 0) p->end = seq + payload;
    return TC_ACT_OK;
}
char LICENSE[] SEC("license") = "Apache-2.0";
