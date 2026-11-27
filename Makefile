LIVE_DIR := live/local-kind
KUBECONFIG := $(LIVE_DIR)/01-cluster/kubeconfig
TPS ?= 10
DURATION ?= 600

.PHONY: plan up down status creds headlamp-token stress

plan:
	cd $(LIVE_DIR) && terragrunt run --all -- plan

up:
	cd $(LIVE_DIR) && terragrunt run --all --non-interactive -- apply -auto-approve
	@$(MAKE) creds

down:
	cd $(LIVE_DIR) && terragrunt run --all --non-interactive -- destroy -auto-approve

stress:
	@echo "Starting pgbench CDC stress test ($(TPS) TPS for $(DURATION)s)..."
	@kubectl --kubeconfig=$(KUBECONFIG) -n streaming delete job pgbench-cdc-stress 2>/dev/null || true
	@cd $(LIVE_DIR)/03-streaming && terragrunt apply -auto-approve -var="stress_tps=$(TPS)" -var="stress_duration_seconds=$(DURATION)"

creds:
	@echo ""
	@echo "================ PLATFORM URLS & CREDENTIALS ================"
	@echo "Vault UI            : http://localhost:8200  (Token: root)"
	@echo "Redpanda Console UI : http://localhost:8080"
	@echo "Headlamp K8s UI     : http://localhost:8081  (Token saved in Vault: secret/platform/headlamp)"
	@echo "Grafana UI          : http://localhost:3000  (User: admin)"
	@printf "Grafana Password    : "
	@kubectl --kubeconfig=$(KUBECONFIG) -n observability get secret grafana-admin -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo "(syncing...)"
	@echo ""
	@echo "MinIO Console UI    : http://localhost:9001  (User: lakehouse-admin)"
	@printf "MinIO Password      : "
	@kubectl --kubeconfig=$(KUBECONFIG) -n lakehouse get secret minio-credentials -o jsonpath='{.data.MINIO_ROOT_PASSWORD}' 2>/dev/null | base64 -d || echo "(syncing...)"
	@echo ""
	@echo "============================================================="

headlamp-token:
	@kubectl --kubeconfig=$(KUBECONFIG) -n kube-system create token headlamp-platform-admin

status:
	@kubectl --kubeconfig=$(KUBECONFIG) get pods -A
