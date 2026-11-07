package admission

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/netip"
	"strings"
	"time"

	"github.com/google/go-containerregistry/pkg/authn"
	"github.com/google/go-containerregistry/pkg/name"
	"github.com/google/go-containerregistry/pkg/v1/remote"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"rknetes.su/rknetes/pkg/cluster"
)

type pullKeychain map[string]authn.AuthConfig

func (k pullKeychain) Resolve(resource authn.Resource) (authn.Authenticator, error) {
	for address, credentials := range k {
		address = strings.TrimPrefix(strings.TrimPrefix(address, "https://"), "http://")
		address = strings.TrimSuffix(address, "/v1/")
		if address == resource.RegistryStr() || address == "index.docker.io" && resource.RegistryStr() == "index.docker.io" {
			return authn.FromConfig(credentials), nil
		}
	}
	return authn.Anonymous, nil
}

func (s *Server) pullCredentials(ctx context.Context, req *Request) (pullKeychain, error) {
	keys := pullKeychain{}
	spec, _ := req.Object["spec"].(map[string]interface{})
	refs, _ := spec["imagePullSecrets"].([]interface{})
	if len(refs) == 0 {
		sa := cluster.String(req.Object, "spec", "serviceAccountName")
		if sa == "" {
			sa = "default"
		}
		account, err := s.C.R("serviceaccounts", req.Namespace).Get(ctx, sa, metav1.GetOptions{})
		if err != nil {
			return nil, fmt.Errorf("cannot read the Pod service account for image credentials")
		}
		refs, _ = account.Object["imagePullSecrets"].([]interface{})
	}
	for _, ref := range refs {
		secret, err := s.C.R("secrets", req.Namespace).Get(ctx, cluster.String(ref.(map[string]interface{}), "name"), metav1.GetOptions{})
		if err != nil {
			return nil, fmt.Errorf("cannot read a referenced imagePullSecret")
		}
		if cluster.String(secret.Object, "type") != "kubernetes.io/dockerconfigjson" {
			continue
		}
		data, err := base64.StdEncoding.DecodeString(cluster.String(secret.Object, "data", ".dockerconfigjson"))
		if err != nil {
			return nil, fmt.Errorf("invalid imagePullSecret encoding")
		}
		var config struct {
			Auths map[string]authn.AuthConfig `json:"auths"`
		}
		if json.Unmarshal(data, &config) != nil {
			return nil, fmt.Errorf("invalid Docker credential document")
		}
		for host, auth := range config.Auths {
			keys[host] = auth
		}
	}
	return keys, nil
}

func resolveImage(ctx context.Context, image string, keys authn.Keychain, insecure []string, mirrors map[string]string) (name.Reference, string, error) {
	options := []name.Option{name.WeakValidation}
	original, err := name.ParseReference(image, name.WeakValidation)
	if err != nil {
		return nil, "", fmt.Errorf("invalid image reference")
	}
	registry, _, _ := strings.Cut(image, "/")
	if mapped := mirrors[registry]; mapped != "" {
		address, _, _ := strings.Cut(mapped, ":")
		ip, err := netip.ParseAddr(address)
		if err != nil || !netip.MustParsePrefix("10.42.0.0/16").Contains(ip) {
			return nil, "", fmt.Errorf("resolution mirror must be a nested lab registry")
		}
		image = mapped + strings.TrimPrefix(image, registry)
		registry = mapped
	}
	for _, host := range insecure {
		if registry != host {
			continue
		}
		address, _, _ := strings.Cut(host, ":")
		ip, err := netip.ParseAddr(address)
		if err != nil || !netip.MustParsePrefix("10.42.0.0/16").Contains(ip) {
			return nil, "", fmt.Errorf("insecure registry must be an explicit nested lab Pod address")
		}
		options = append(options, name.Insecure)
	}
	ref, err := name.ParseReference(image, options...)
	if err != nil {
		return nil, "", fmt.Errorf("invalid image reference")
	}
	descriptor, err := remote.Head(ref, remote.WithContext(ctx), remote.WithAuthFromKeychain(keys))
	if err != nil {
		return nil, "", fmt.Errorf("cannot resolve image digest for %s", ref.Name())
	}
	return original, descriptor.Digest.String(), nil
}

func (s *Server) origin(ctx context.Context, req *Request, policies []cluster.Object) ([]cluster.Map, error) {
	ctx, cancel := context.WithTimeout(ctx, 6*time.Second)
	defer cancel()
	patches := []cluster.Map{}
	foreign := false
	var keys pullKeychain
	spec, _ := req.Object["spec"].(map[string]interface{})
	annotations := cluster.Labels(req.Object, "metadata", "annotations")
	if annotations == nil {
		annotations = map[string]string{}
	}
	origins := map[string]string{}
	if raw := annotations["rknetes.su/original-images"]; raw != "" {
		if json.Unmarshal([]byte(raw), &origins) != nil {
			return nil, fmt.Errorf("invalid recorded image provenance")
		}
	}
	for _, policy := range policies {
		if !cluster.Bool(policy.Object, "spec", "enabled") {
			continue
		}
		resolve := cluster.Bool(policy.Object, "spec", "resolveDigests")
		digests := cluster.Strings(policy.Object, "spec", "digests")
		insecure := cluster.Strings(policy.Object, "spec", "insecureRegistries")
		mirrors := cluster.Labels(policy.Object, "spec", "registryMirrors")
		if resolve {
			if keys == nil {
				var err error
				keys, err = s.pullCredentials(ctx, req)
				if err != nil {
					return nil, err
				}
			}
			for _, source := range cluster.Strings(policy.Object, "spec", "foreignImages") {
				_, digest, err := resolveImage(ctx, source, keys, insecure, mirrors)
				if err != nil {
					return nil, err
				}
				digests = append(digests, digest)
			}
		}
		for _, field := range []string{"containers", "initContainers", "ephemeralContainers"} {
			containers, _ := spec[field].([]interface{})
			for index, item := range containers {
				container := item.(map[string]interface{})
				image := cluster.String(container, "image")
				foreign = foreign || IsForeign(image, digests)
				if !resolve {
					continue
				}
				source, digest, err := resolveImage(ctx, image, keys, insecure, mirrors)
				if err != nil {
					return nil, err
				}
				foreign = foreign || IsForeign(source.Context().Digest(digest).Name(), digests)
				provenanceKey := field + "/" + cluster.String(container, "name")
				if origins[provenanceKey] == "" {
					origins[provenanceKey] = source.Context().Digest(digest).Name()
				}
				target := cluster.Labels(policy.Object, "spec", "rewriteImages")[image]
				if target == "" {
					continue
				}
				destination, domesticDigest, err := resolveImage(ctx, target, keys, insecure, mirrors)
				if err != nil {
					return nil, err
				}
				if domesticDigest != digest {
					return nil, fmt.Errorf("domestic mirror digest differs from the requested upstream image")
				}
				pinned := destination.Context().Digest(digest).Name()
				patches = append(patches, cluster.Map{"op": "replace", "path": fmt.Sprintf("/spec/%s/%d/image", field, index), "value": pinned})
			}
		}
	}
	if foreign {
		labels := cluster.Labels(req.Object, "metadata", "labels")
		if labels == nil {
			labels = map[string]string{}
		}
		labels["rknetes.su/inoagent"] = "true"
		patches = append(patches, cluster.Map{"op": "add", "path": "/metadata/labels", "value": labels})
	}
	if len(origins) > 0 {
		data, _ := json.Marshal(origins)
		annotations["rknetes.su/original-images"] = string(data)
		patches = append(patches, cluster.Map{"op": "add", "path": "/metadata/annotations", "value": annotations})
	}
	return patches, nil
}
