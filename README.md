# 🚀 API-Driven Infrastructure — Atelier AWS LocalStack

> Orchestration d'une instance EC2 via API Gateway + Lambda dans un environnement AWS émulé (LocalStack), exécuté sur GitHub Codespaces.

---

## 📐 Architecture cible

```
Requête HTTP
     │
     ▼
┌─────────────────┐
│   API Gateway   │  ← point d'entrée HTTP (GET /ec2?action=start|stop|status)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Lambda Function│  ← ec2-controller (Python 3.11)
│  ec2-controller │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Instance EC2  │  ← simulée dans LocalStack
│   (LocalStack)  │
└─────────────────┘
```

---

## 🛠️ Prérequis

- [GitHub Codespaces](https://github.com/features/codespaces)
- Python 3.x (inclus dans Codespaces)
- Pas de compte AWS réel nécessaire — tout est émulé avec **LocalStack**

---

## ⚡ Démarrage rapide (automatisé)

```bash
# 1. Lancer LocalStack
localstack start -d

# 2. Déployer toute l'infrastructure en une commande
make deploy

# 3. Tester
make test-status
make test-stop
make test-start
```

---

## 📋 Installation étape par étape

### Séquence 1 — GitHub Codespace

Créer un Codespace connecté à ce repository depuis [github.com/codespaces](https://github.com/codespaces).

---

### Séquence 2 — Installation de LocalStack

```bash
# Créer l'environnement virtuel
sudo -i mkdir rep_localstack
sudo -i python3 -m venv ./rep_localstack

# Installer LocalStack
sudo -i pip install --upgrade pip && python3 -m pip install localstack && export S3_SKIP_SIGNATURE_VALIDATION=0

# Démarrer LocalStack en arrière-plan
localstack start -d

# Vérifier que les services sont disponibles
localstack status services
```

> 💡 Aller dans l'onglet **[PORTS]** du Codespace et rendre le port **4566** public. L'URL obtenue est votre `AWS_ENDPOINT`.

---

### Séquence 3 — Déploiement de l'infrastructure

#### Variables d'environnement

```bash
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCESS_KEY_ID=test # ou variable stockées dans GitHub Secrets
export AWS_SECRET_ACCESS_KEY=test # ou variable stockées dans GitHub Secrets
export AWS_ENDPOINT_URL=http://localhost:4566
```

#### 1. Installer AWS CLI

```bash
pip install awscli --break-system-packages
```

#### 2. Créer une instance EC2

```bash
# Récupérer une AMI disponible
AMI_ID=$(aws --endpoint-url=$AWS_ENDPOINT_URL ec2 describe-images --query 'Images[0].ImageId' --output text)

# Lancer l'instance
aws --endpoint-url=$AWS_ENDPOINT_URL ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t2.micro \
  --count 1

# Stocker l'ID de l'instance
export INSTANCE_ID=$(aws --endpoint-url=$AWS_ENDPOINT_URL ec2 describe-instances \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

echo "Instance ID : $INSTANCE_ID"
```

#### 3. Déployer la fonction Lambda

```bash
# Zipper le code
zip lambda.zip lambda_function.py

# Créer la fonction
aws --endpoint-url=$AWS_ENDPOINT_URL lambda create-function \
  --function-name ec2-controller \
  --runtime python3.11 \
  --handler lambda_function.handler \
  --zip-file fileb://lambda.zip \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --environment Variables={INSTANCE_ID=$INSTANCE_ID}
```

#### 4. Configurer API Gateway

```bash
# Créer l'API
API_ID=$(aws --endpoint-url=$AWS_ENDPOINT_URL apigateway create-rest-api \
  --name "EC2ControlAPI" --query 'id' --output text)

# Ressource root
ROOT_ID=$(aws --endpoint-url=$AWS_ENDPOINT_URL apigateway get-resources \
  --rest-api-id $API_ID --query 'items[0].id' --output text)

# Créer la ressource /ec2
RESOURCE_ID=$(aws --endpoint-url=$AWS_ENDPOINT_URL apigateway create-resource \
  --rest-api-id $API_ID --parent-id $ROOT_ID --path-part ec2 --query 'id' --output text)

# Méthode GET
aws --endpoint-url=$AWS_ENDPOINT_URL apigateway put-method \
  --rest-api-id $API_ID --resource-id $RESOURCE_ID \
  --http-method GET --authorization-type NONE

# Intégration Lambda
aws --endpoint-url=$AWS_ENDPOINT_URL apigateway put-integration \
  --rest-api-id $API_ID --resource-id $RESOURCE_ID \
  --http-method GET --type AWS_PROXY --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:ec2-controller/invocations

# Déployer
aws --endpoint-url=$AWS_ENDPOINT_URL apigateway create-deployment \
  --rest-api-id $API_ID --stage-name prod
```

---

## 🧪 Tests

```bash
# Voir l'état de l'instance
curl "http://localhost:4566/restapis/$API_ID/prod/_user_request_/ec2?action=status&instance_id=$INSTANCE_ID"

# Stopper l'instance
curl "http://localhost:4566/restapis/$API_ID/prod/_user_request_/ec2?action=stop&instance_id=$INSTANCE_ID"

# Démarrer l'instance
curl "http://localhost:4566/restapis/$API_ID/prod/_user_request_/ec2?action=start&instance_id=$INSTANCE_ID"
```

### Réponse attendue

```json
{"statusCode": 200, "body": "{\"message\": \"Instance i-xxxxxxxxxx est en état : running\"}"}
```

---

## 📁 Structure du projet

```
API_Driven/
├── README.md              # Documentation (ce fichier)
├── Makefile               # Automatisation des commandes
├── deploy.sh              # Script de déploiement complet
└── lambda_function.py     # Code de la fonction Lambda
```

---

## 🔧 Commandes Makefile disponibles

| Commande | Description |
|---|---|
| `make deploy` | Déploie toute l'infrastructure |
| `make test-status` | Vérifie l'état de l'instance EC2 |
| `make test-stop` | Arrête l'instance EC2 |
| `make test-start` | Démarre l'instance EC2 |
| `make clean` | Supprime les ressources créées |

---

## ⚠️ Notes importantes

- L'endpoint LocalStack est `http://localhost:4566`
- La Lambda utilise `http://172.17.0.1:4566` pour contacter LocalStack depuis son conteneur interne
- Si LocalStack redémarre, relancer `make deploy` pour recréer l'infrastructure
