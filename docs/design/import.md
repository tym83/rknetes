# Domestic development

The native commands are real upstream executables. `hack/import/components.json`
maps every name in the concept: `eo-server`, `prochee`, `gosplan`, `kru`,
`uchastkovy`, `pochta`, `spravochnaya09`, `terminal`, `begunok`, `hodatay`,
`kormilo`, `gruzchik`, `resnichki`, `prometey`, `grafa`, `vpered`, `yaml-office`
and `otechestvennoe-yadro`. Kubernetes is still Kubernetes; the Linux name runs
`uname`. YAML remains YAML, with a parser that rejects tabs and emits two-space
indents. The auxiliary server programs are installed executables; their presence
does not start Docker, Prometheus or Grafana on every node.

The underlying versions and hashes are recorded in `import-tools.tar.gz`.
Docker28.0.1 comes from the [official static distribution](https://download.docker.com/linux/static/stable/x86_64/).
Prometheus3.2.1 retains its [release identity](https://github.com/prometheus/prometheus/releases/tag/v3.2.1).
Grafana11.5.2 retains its AGPLv3 licence and the
[official tarball checksum](https://grafana.com/grafana/download/11.5.2?edition=oss).
These upstream licences remain distinct from RKNetes' Apache-2.0 licence.

`go-mirror` implements the [Go module proxy protocol](https://go.dev/ref/mod#module-proxy)
against `proxy.golang.org`, preserving bytes and native checksum verification.
08-module-mirror proves two fresh caches, direct byte equality and an offline
cache hit. 08-toolchain-mirror downloads and runs the actual Go1.26.0 compiler
through that mirror. The lab address represents `proxy.otechestvennoe.su`;
no public DNS name is claimed or published. The dependencies become domestic
by the location of their cache, without changing their authors or licence.

The native Pod REST list handler writes the audit annotation
`rknetes.su/terminology: использование иностранной терминологии`.
The metadata-only audit policy records Pod lists, with rotation limited to
three10MiB files and seven days. An ordinary `kubectl get pods` produces this
record. Discovery translates `стручки` to the same native `pods` route, so the
Russian spelling receives the same charge: the server cannot recover the
original client spelling from a normalized API URL.

The Friday03:00UTC CronJob `tenant-rknetes/rknetes-upstream-sync` uses only the
existing builder PVC. It fetches upstream, fast-forwards its separate
`/work/upstream-sync/kubernetes` checkout and reapplies the literal rebranding.
The proof Job completed an actual one-commit fast-forward; before/after commits
and patches are retained. LICENSE and NOTICE comparisons stay clean. No push
occurs, and this checkout does not replace the pinned release source. A merge
conflict fails the Job and leaves its evidence for review.

The final native overlay replaces the upstream dirty Kine binary with a clean
build of commit35f4319798cf3543e49f86c775a1f8c5c23b1e80 (v0.17.1). The first
rebuild exposed Go automatically changing protobuf from an indirect to a direct
requirement. With the original go.mod and `-mod=readonly`, SQLite/server tests
pass, `vcs.modified=false`, and two builds match SHA256
`2b10a10a1eb8218a297dbdc7ce41c045d54e5093e2f53be3fcf61bcfb4cd1467`.
The observed patch and both build identities are in `kine-provenance.tar.gz`.
