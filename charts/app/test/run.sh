#!/usr/bin/env bash
# Tests for the app library chart: renders the fixture chart and asserts with yq.
set -u
cd "$(dirname "$0")/fixture"
helm dependency build >/dev/null || { echo "dependency build failed"; exit 1; }
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1${2:+: $2}"; }

# r <args...>: render with the fixture values + args
r() { helm template rel . -f values.yaml "$@" 2>&1; }
# eq <name> <yq-expr> <expected> <helm args...>: yq over the rendered output
eq() {
  local n=$1 e=$2 want=$3; shift 3
  local out got; out=$(r "$@") || { bad "$n" "render failed: $out"; return; }
  got=$(echo "$out" | yq -r "$e" | grep -v -e "^---\$" -e "^null\$" | { if [ "$e" = .kind ]; then sort; else cat; fi; } | paste -sd, -)
  [ "$got" = "$want" ] && ok "$n" || bad "$n" "got '$got', want '$want'"
}
# fails <name> <message-substring> <helm args...>
fails() {
  local n=$1 m=$2; shift 2
  local out; out=$(r "$@") && { bad "$n" "rendered, expected failure"; return; }
  echo "$out" | grep -q -- "$m" && ok "$n" || bad "$n" "wrong error: $out"
}
D='select(.kind=="Deployment")'

eq "default strategy"        "$D | .spec.strategy.rollingUpdate | (.maxUnavailable, .maxSurge)" "0,1"
eq "default pull secret"     "$D | .spec.template.spec.imagePullSecrets[0].name" "harbor-pull"
eq "default runAsNonRoot"    "$D | .spec.template.spec.securityContext | (.runAsNonRoot, .runAsUser, .fsGroup)" "true,1000,1000"
eq "container hardening"     "$D | .spec.template.spec.containers[0].securityContext | (.allowPrivilegeEscalation, .capabilities.drop[0], .readOnlyRootFilesystem)" "false,ALL,false"
eq "no cpu limit"            "$D | .spec.template.spec.containers[0].resources.limits.cpu // \"none\"" "none"
eq "memory limit = request"  "$D | .spec.template.spec.containers[0].resources.limits.memory" "128Mi"
eq "explicit memory limit kept" "$D | .spec.template.spec.containers[0].resources.limits.memory" "256Mi" --set resources.limits.memory=256Mi
eq "image from repo:tag"     "$D | .spec.template.spec.containers[0].image" "harbor.example.com/app/web:1.2.3"
eq "version label"           "$D | .metadata.labels.\"app.kubernetes.io/version\"" "1.2.3"
eq "replicas default 1"      "$D | .spec.replicas" "1"
eq "replicas omitted w/ hpa" "$D | .spec.replicas // \"none\"" "none" --set autoscaling.hpa.enabled=true --set autoscaling.hpa.maxReplicas=3
eq "readOnlyRootFilesystem on" "$D | .spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem" "true" --set readOnlyRootFilesystem=true
eq "recreate flag"           "$D | .spec.strategy.type" "Recreate" --set strategy.recreate=true

fails "missing readinessProbe fails" "readinessProbe is required" --set readinessProbe=null
fails "missing requests fails"       "resources.requests is required" --set resources=null
fails "empty image tag fails"        "image.tag is required" --set image.tag=
fails "hpa + keda fails"             "pick one" --set autoscaling.hpa.enabled=true --set autoscaling.hpa.maxReplicas=3 \
  --set autoscaling.keda.enabled=true --set autoscaling.keda.maxReplicas=3

I='select(.kind=="Ingress")'
ING=(--set ingress.enabled=true --set 'ingress.hosts[0].host=a.example.com')
eq "ingress absent by default" ".kind" "Deployment,Service,ServiceAccount" 
eq "ingress class + issuer"  "$I | .spec.ingressClassName, .metadata.annotations.\"cert-manager.io/cluster-issuer\"" "haproxy,lets-encrypt-cloudflare" "${ING[@]}"
eq "ingress tls + backend"   "$I | .spec.tls[0].secretName, .spec.rules[0].http.paths[0].path" "rel-tls,/" "${ING[@]}"
eq "allowList annotation"    "$I | .metadata.annotations.\"haproxy.org/allow-list\"" "192.0.2.0/24,198.51.100.7/32" "${ING[@]}" \
  --set 'ingress.allowList={192.0.2.0/24,198.51.100.7/32}'
eq "no monitoring label by default" "$I | .metadata.labels.\"blackbox-exporter/ignore\" // \"none\"" "none" "${ING[@]}"
eq "monitoring false label"  "$I | .metadata.labels.\"blackbox-exporter/ignore\"" "true" "${ING[@]}" --set ingress.monitoring=false
eq "empty clusterIssuer drops annotation" "$I | .metadata.annotations.\"cert-manager.io/cluster-issuer\" // \"none\"" "none" "${ING[@]}" --set ingress.clusterIssuer=

P='select(.kind=="PodDisruptionBudget")'
eq "no PDB at 1 replica"     ".kind" "Deployment,Service,ServiceAccount"
eq "PDB at 2 replicas"       "$P | .spec.minAvailable" "1" --set replicas=2
eq "PDB at hpa min 2"        "$P | .spec.minAvailable" "1" --set autoscaling.hpa.enabled=true --set autoscaling.hpa.minReplicas=2 --set autoscaling.hpa.maxReplicas=4
eq "hpa cpu default 70"      'select(.kind=="HorizontalPodAutoscaler") | .spec.metrics[0].resource.target.averageUtilization' "70" --set autoscaling.hpa.enabled=true --set autoscaling.hpa.maxReplicas=4
eq "keda scaledobject + PDB" 'select(.kind=="ScaledObject") | .spec.minReplicaCount, .spec.triggers[0].type' "2,rabbitmq" \
  --set autoscaling.keda.enabled=true --set autoscaling.keda.minReplicas=2 --set autoscaling.keda.maxReplicas=5 --set autoscaling.keda.triggers[0].type=rabbitmq
eq "PDB at keda min 2"       "$P | .spec.minAvailable" "1" --set autoscaling.keda.enabled=true --set autoscaling.keda.minReplicas=2 --set autoscaling.keda.maxReplicas=5 --set autoscaling.keda.triggers[0].type=rabbitmq

eq "no scrape without port"  'select(.kind=="VMServiceScrape") | .kind // "none"' ""
eq "scrape with metrics.port" 'select(.kind=="VMServiceScrape") | .spec.endpoints[0].port, .spec.endpoints[0].path' "metrics,/metrics" --set metrics.port=9464
eq "scrape can be disabled"  'select(.kind=="VMServiceScrape") | .kind' "" --set metrics.port=9464 --set metrics.enabled=false
eq "service exposes metrics" 'select(.kind=="Service") | .spec.ports[1].name' "metrics" --set metrics.port=9464

eq "sidecar rendered"        "$D | .spec.template.spec.containers[1].name" "nginx" --set 'sidecars[0].name=nginx' --set 'sidecars[0].image=nginx:1'

# alert-manager shaped values: render, expected shape, lint
AM=(-f alert-manager.yaml)
out=$(helm template rel . "${AM[@]}" 2>&1) && ok "alert-manager renders" || bad "alert-manager renders" "$out"
eq "alert-manager containers" "$D | .spec.template.spec.containers[].name" "node,nginx" "${AM[@]}"
eq "alert-manager ingress"   "$I | .spec.rules[0].http.paths[0].path, .metadata.annotations.\"haproxy.org/src-ip-header\"" "/api/v1/alerts,CF-Connecting-IP" "${AM[@]}"
eq "alert-manager kinds"     ".kind" "Deployment,Ingress,PodDisruptionBudget,Service,ServiceAccount,VMServiceScrape" "${AM[@]}"
out=$(helm lint . "${AM[@]}" 2>&1) && ok "alert-manager helm lint" || bad "alert-manager helm lint" "$out"
out=$(helm lint . -f values.yaml 2>&1) && ok "default helm lint" || bad "default helm lint" "$out"

if command -v kubeconform >/dev/null; then
  helm template rel . "${AM[@]}" | kubeconform -ignore-missing-schemas -strict -summary >/dev/null \
    && ok "kubeconform" || bad "kubeconform"
else
  echo "skip kubeconform (not installed)"
fi

echo; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
