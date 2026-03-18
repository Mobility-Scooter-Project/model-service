import os
import yaml

# Configuration
MODEL_DIR = "src/model"
NGINX_CONF_PATH = "nginx.conf"
DOCKER_COMPOSE_PATH = "docker-compose.yaml"
HTTP_PORT = 8000

def generate_infra():
    # 1. Discover models (must have an __init__.py and requirements.txt)
    models = []
    for entry in os.scandir(MODEL_DIR):
        if entry.is_dir():
            if os.path.exists(os.path.join(entry.path, "__init__.py")) and \
               os.path.exists(os.path.join(entry.path, "requirements.txt")):
                models.append(entry.name)

    print(f"Detected models: {models}")

    # 2. Generate nginx.conf
    nginx_lines = ["server {", f"    listen {HTTP_PORT};", ""]
    for model in models:
        nginx_lines.extend([
            f"    # {model.upper()} Routing",
            f"    location /api/v1/{model}/ {{",
            f"        proxy_pass http://{model}:{HTTP_PORT}/;",
            "        proxy_set_header Host $host;",
            "        proxy_set_header X-Real-IP $remote_addr;",
            "        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;",
            "        proxy_set_header X-Forwarded-Proto $scheme;",
            "    }",
            ""
        ])
    nginx_lines.append("}")
    
    with open(NGINX_CONF_PATH, "w") as f:
        f.write("\n".join(nginx_lines))

    # 3. Generate docker-compose.yaml
    compose_data = {
        "services": {
            "nginx": {
                "image": "nginx:alpine",
                "ports": [f"{HTTP_PORT}:{HTTP_PORT}"],
                "volumes": [f"./{NGINX_CONF_PATH}:/etc/nginx/conf.d/default.conf:ro"],
                "depends_on": models
            }
        }
    }

    for model in models:
        model_config = {
            "build": {
                "context": ".",
                "args": {"MODEL_NAME": model}
            },
            "environment": [
                f"MODEL_NAME={model}",
                "TORCH_HOME=/app/.cache/torch",
                "HF_HOME=/app/.cache/huggingface",
                "YOLO_CONFIG_DIR=/app/.cache/yolo"
            ],
            "volumes": [
                "./.models:/app/.cache"
            ]
        }
        
        # Add model-specific environment variables if needed
        if model == "whisperx":
            model_config["environment"].extend([
                "HF_TOKEN=${HF_TOKEN}",
                "WHISPERX_SIZE=base",
                "COMPUTE_TYPE=int8"
            ])
            
        compose_data["services"][model] = model_config

    with open(DOCKER_COMPOSE_PATH, "w") as f:
        yaml.dump(compose_data, f, sort_keys=False, default_flow_style=False)

    print("Successfully updated local infrastructure files.")

if __name__ == "__main__":
    generate_infra()