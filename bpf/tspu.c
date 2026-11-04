// Per-direction TCP sequence windows for explicitly selected lab Pod namespaces.
#include <linux/bpf.h>
#include <linux/pkt_cls.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/in.h>
#include <linux/tcp.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

struct range { __u32 network, mask; };
struct settings { __u32 limit, count; struct range ranges[8]; };
struct flow { __u32 src, dst; __u16 sport, dport; };
struct progress { __u32 base; };
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, 1);
    __type(key, __u32);
    __type(value, struct settings);
} config SEC(".maps");
struct {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 4096);
    __type(key, struct flow);
    __type(value, struct progress);
} connections SEC(".maps");

SEC("tc")
int sovereign_window(struct __sk_buff *skb) {
    void *data = (void *)(long)skb->data, *end = (void *)(long)skb->data_end;
    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > end || eth->h_proto != bpf_htons(ETH_P_IP)) return TC_ACT_OK;
    struct iphdr *ip = (void *)(eth + 1);
    if ((void *)(ip + 1) > end || ip->protocol != IPPROTO_TCP || ip->ihl < 5) return TC_ACT_OK;
    __u32 src = bpf_ntohl(ip->saddr), dst = bpf_ntohl(ip->daddr);
    // No policy can filter traffic outside the dedicated nested Pod range.
    if ((src & 0xffff0000) != 0x0a2a0000 || (dst & 0xffff0000) != 0x0a2a0000) return TC_ACT_OK;
    __u32 zero = 0;
    struct settings *cfg = bpf_map_lookup_elem(&config, &zero);
    if (!cfg || !cfg->limit) return TC_ACT_OK;
    int foreign = 0;
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        if (i < cfg->count && ((src & cfg->ranges[i].mask) == cfg->ranges[i].network ||
                              (dst & cfg->ranges[i].mask) == cfg->ranges[i].network)) foreign = 1;
    }
    if (!foreign) return TC_ACT_OK;
    struct tcphdr *tcp = (void *)ip + ip->ihl * 4;
    if ((void *)(tcp + 1) > end || tcp->doff < 5) return TC_ACT_OK;
    __u32 headers = ip->ihl * 4 + tcp->doff * 4, length = bpf_ntohs(ip->tot_len);
    struct flow key = {ip->saddr, ip->daddr, tcp->source, tcp->dest};
    __u32 seq = bpf_ntohl(tcp->seq);
    if (tcp->syn) {
        struct progress initial = {seq + 1};
        bpf_map_update_elem(&connections, &key, &initial, BPF_ANY);
        return TC_ACT_OK;
    }
    if (length <= headers) return TC_ACT_OK;
    __u32 payload = length - headers;
    struct progress *p = bpf_map_lookup_elem(&connections, &key);
    if (!p) {
        struct progress initial = {seq};
        bpf_map_update_elem(&connections, &key, &initial, BPF_NOEXIST);
        p = bpf_map_lookup_elem(&connections, &key);
        if (!p) return TC_ACT_SHOT;
    }
    __u32 offset = seq - p->base;
    // Unsigned subtraction handles sequence wrap; retransmissions cost no extra.
    // A packet crossing the budget is dropped whole, never corrupted/truncated.
    if (offset > cfg->limit || payload > cfg->limit - offset) return TC_ACT_SHOT;
    return TC_ACT_OK;
}
char LICENSE[] SEC("license") = "Apache-2.0";
