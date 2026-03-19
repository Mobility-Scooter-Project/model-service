import os

MODEL_DIR = "src/model"
K8S_OUT_DIR = "k8s"

def generate_k8s_infra():
    models = []
    if os.path.exists(MODEL_DIR):
        for entry in os.scandir(MODEL_DIR):
            if entry.is_dir() and entry.name != "__pycache__":
                if os.path.exists(os.path.join(entry.path, "__init__.py")) and \
                   os.path.exists(os.path.join(entry.path, "requirements.txt")):
                    models.append(entry.name)

    os.makedirs(K8S_OUT_DIR, exist_ok=True)

    prefixes = "\n".join([f"      - /api/v1/{m}" for m in models])
    routes = "\n".join([f"""    - http:
        paths:
          - path: /api/v1/{m}/
            pathType: Prefix
            backend:
              service:
                name: {m}-svc
                port: 
                  number: 8000""" for m in models])

    ingress_manifest = f"""apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: api-strip-prefix
spec:
  stripPrefix:
    prefixes:
{prefixes}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: model-service-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: default-api-strip-prefix@kubernetescrd
spec:
  rules:
{routes}
"""
    with open(os.path.join(K8S_OUT_DIR, "ingress.yaml"), "w") as f:
        f.write(ingress_manifest)

    for model in models:
        env_vars = f"""            - name: MODEL_NAME
              value: "{model}"
            - name: TORCH_HOME
              value: "/app/.cache/torch"
            - name: HF_HOME
              value: "/app/.cache/huggingface"
            - name: YOLO_CONFIG_DIR
              value: "/app/.cache/yolo" """

        secrets_manifest = ""
        
        if model == "whisperx":
            secrets_manifest = """apiVersion: v1
kind: Secret
metadata:
  name: whisperx-secrets
type: Opaque
stringData:
  HF_TOKEN: "replace_with_your_huggingface_token"
---
"""
            env_vars += """
            - name: WHISPERX_SIZE
              value: "base"
            - name: COMPUTE_TYPE
              value: "int8"
            - name: HF_TOKEN
              valueFrom:
                secretKeyRef:
                  name: whisperx-secrets
                  key: HF_TOKEN"""

        model_manifest = f"""{secrets_manifest}apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {model}-cache-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {model}-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {model}
  template:
    metadata:
      labels:
        app: {model}
    spec:
      containers:
        - name: {model}
          image: ghcr.io/mobility-scooter-project/model-service/{model}:latest
          ports:
            - containerPort: 8000
          env:
{env_vars}
          resources:
            limits:
              nvidia.com/gpu: 1
          volumeMounts:
            - name: model-cache
              mountPath: /app/.cache
      volumes:
        - name: model-cache
          persistentVolumeClaim:
            claimName: {model}-cache-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: {model}-svc
spec:
  selector:
    app: {model}
  ports:
    - protocol: TCP
      port: 8000
      targetPort: 8000
"""
        with open(os.path.join(K8S_OUT_DIR, f"{model}.yaml"), "w") as f:
            f.write(model_manifest)

if __name__ == "__main__":
    generate_k8s_infra()