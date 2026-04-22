SHELL := /bin/bash
.PHONY: deploy test-status test-stop test-start clean help

ENDPOINT=http://localhost:4566
REGION=us-east-1

help:
	@echo ""
	@echo "  🚀 API-Driven Infrastructure — Commandes disponibles"
	@echo ""
	@echo "  make deploy       → Déploie toute l'infrastructure"
	@echo "  make test-status  → Vérifie l'état de l'instance EC2"
	@echo "  make test-stop    → Arrête l'instance EC2"
	@echo "  make test-start   → Démarre l'instance EC2"
	@echo "  make clean        → Supprime les ressources"
	@echo ""

deploy:
	@chmod +x deploy.sh && bash deploy.sh

test-status:
	@echo "📊 Statut de l'instance..."
	@. .env && curl -s "$$AWS_ENDPOINT_URL/restapis/$$API_ID/prod/_user_request_/ec2?action=status&instance_id=$$INSTANCE_ID" | python3 -m json.tool

test-stop:
	@echo "🛑 Arrêt de l'instance..."
	@. .env && curl -s "$$AWS_ENDPOINT_URL/restapis/$$API_ID/prod/_user_request_/ec2?action=stop&instance_id=$$INSTANCE_ID" | python3 -m json.tool

test-start:
	@echo "▶️  Démarrage de l'instance..."
	@. .env && curl -s "$$AWS_ENDPOINT_URL/restapis/$$API_ID/prod/_user_request_/ec2?action=start&instance_id=$$INSTANCE_ID" | python3 -m json.tool
	
clean:
	@echo "🧹 Suppression des ressources..."
	@aws --endpoint-url=$(ENDPOINT) lambda delete-function --function-name ec2-controller 2>/dev/null || true
	@aws --endpoint-url=$(ENDPOINT) ec2 terminate-instances --instance-ids $(INSTANCE_ID) 2>/dev/null || true
	@aws --endpoint-url=$(ENDPOINT) apigateway delete-rest-api --rest-api-id $(API_ID) 2>/dev/null || true
	@echo "✅ Ressources supprimées"
