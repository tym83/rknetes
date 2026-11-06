package admission

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"rknetes.su/rknetes/pkg/cluster"
	"strings"
	"time"
)

type Server struct{ C *cluster.Client }
type Review struct {
	APIVersion string    `json:"apiVersion"`
	Kind       string    `json:"kind"`
	Request    *Request  `json:"request,omitempty"`
	Response   *Response `json:"response,omitempty"`
}
type Request struct {
	UID         string `json:"uid"`
	Namespace   string `json:"namespace"`
	Name        string `json:"name"`
	Operation   string `json:"operation"`
	SubResource string `json:"subResource"`
	Resource    struct {
		Resource string `json:"resource"`
	} `json:"resource"`
	UserInfo struct {
		Username string `json:"username"`
	} `json:"userInfo"`
	Object cluster.Map `json:"object"`
}
type Response struct {
	UID       string  `json:"uid"`
	Allowed   bool    `json:"allowed"`
	Status    *Status `json:"status,omitempty"`
	Patch     string  `json:"patch,omitempty"`
	PatchType *string `json:"patchType,omitempty"`
}
type Status struct {
	Code    int    `json:"code"`
	Reason  string `json:"reason"`
	Message string `json:"message"`
}

func deny(out *Response, reason, message string) {
	out.Allowed = false
	out.Status = &Status{Code: 451, Reason: reason, Message: message}
}
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/healthz" {
		w.WriteHeader(200)
		return
	}
	var review Review
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<20)).Decode(&review); err != nil || review.Request == nil {
		http.Error(w, "invalid AdmissionReview", 400)
		return
	}
	req := review.Request
	out := &Response{UID: req.UID, Allowed: true}
	switch r.URL.Path {
	case "/calls":
		if req.Operation == "CONNECT" && (req.SubResource == "exec" || req.SubResource == "attach" || req.SubResource == "portforward") {
			policies, err := s.C.List(r.Context(), "callrestrictions", req.Namespace)
			if err != nil {
				deny(out, "AgencyUnavailable", err.Error())
				break
			}
			for _, p := range policies {
				if cluster.Bool(p.Object, "spec", "enabled") && req.UserInfo.Username != "system:serviceaccount:rknet-system:maxlet" {
					deny(out, "CallsRestricted", "Звонки ограничены для борьбы с мошенниками; подайте обращение через МАКС")
				}
			}
		}
	case "/erid":
		policies, err := s.C.List(r.Context(), "advertisingpolicies", req.Namespace)
		if err != nil {
			deny(out, "AgencyUnavailable", err.Error())
			break
		}
		for _, p := range policies {
			message := cluster.String(req.Object, "message")
			if message == "" {
				message = cluster.String(req.Object, "note")
			}
			if cluster.Bool(p.Object, "spec", "enabled") && (strings.Contains(message, "Successfully") || strings.HasPrefix(message, "Started container")) && cluster.String(req.Object, "metadata", "annotations", "rknetes.su/erid") == "" {
				deny(out, "UnmarkedAdvertisement", "Успешное событие рекламирует образ или узел; требуется erid")
			}
		}
	case "/archive":
		patches, err := s.archive(r.Context(), req)
		if err != nil {
			deny(out, "ArchiveUnavailable", err.Error())
			break
		}
		if len(patches) > 0 {
			patch, err := json.Marshal(patches)
			if err != nil {
				deny(out, "InvalidPatch", err.Error())
				break
			}
			out.Patch = base64.StdEncoding.EncodeToString(patch)
			pt := "JSONPatch"
			out.PatchType = &pt
		}
	case "/inoagent":
		policies, err := s.C.List(r.Context(), "foreignagentpolicies", req.Namespace)
		if err != nil {
			deny(out, "AgencyUnavailable", err.Error())
			break
		}
		patches, err := s.origin(r.Context(), req, policies)
		if err != nil {
			deny(out, "ImageResolutionUnavailable", err.Error())
			break
		}
		if len(patches) > 0 {
			patch, err := json.Marshal(patches)
			if err != nil {
				deny(out, "InvalidPatch", err.Error())
				break
			}
			out.Patch = base64.StdEncoding.EncodeToString(patch)
			pt := "JSONPatch"
			out.PatchType = &pt
		}
	default:
		if strings.HasPrefix(r.URL.Path, "/agency/") {
			raw := cluster.String(req.Object, "metadata", "annotations", "rknetes.su/agency-delay")
			if raw != "" {
				d, err := time.ParseDuration(raw)
				if err != nil || d < 0 || d > 30*time.Second {
					deny(out, "InvalidDelay", "agency-delay must be between 0s and 30s")
				} else {
					select {
					case <-r.Context().Done():
						return
					case <-time.After(d):
					}
				}
			}
		} else {
			http.Error(w, "unknown agency", 404)
			return
		}
	}
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(Review{APIVersion: "admission.k8s.io/v1", Kind: "AdmissionReview", Response: out}); err != nil {
		fmt.Printf("write review: %v\n", err)
	}
}
func IsForeign(image string, digests []string) bool {
	for _, d := range digests {
		if strings.HasSuffix(image, "@"+d) {
			return true
		}
	}
	first, _, slash := strings.Cut(image, "/")
	if !slash || (!strings.ContainsAny(first, ".:") && first != "localhost") {
		return true
	}
	for _, registry := range []string{"docker.io", "ghcr.io", "quay.io", "registry.k8s.io"} {
		if first == registry {
			return true
		}
	}
	return false
}
