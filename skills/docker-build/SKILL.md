---
name: docker-build
description: Docker image building best practices including multi-stage builds, layer optimization, and security hardening. Use when creating Dockerfiles, optimizing image size, or debugging container builds.
---

# Docker Build

## Multi-Stage Build Pattern

```dockerfile
# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build

# Runtime stage
FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
USER node
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

## Layer Optimization

1. Order instructions from least to most frequently changing
2. Combine RUN commands to reduce layers
3. Use `.dockerignore` to exclude unnecessary files
4. Pin base image versions (not `latest`)

```dockerfile
# Good: combined and ordered
COPY package*.json ./
RUN npm ci && npm cache clean --force
COPY . .

# Bad: separate commands, poor ordering
RUN npm install
COPY . .
```

## Security Hardening

- Run as non-root user: `USER node` or `USER 1000`
- Use minimal base images: `alpine`, `distroless`, `scratch`
- Don't store secrets in images — use runtime injection
- Scan images: `docker scout`, `trivy`, `grype`

## Debugging

```bash
# Build with progress output
docker build --progress=plain -t myapp .

# Inspect intermediate layers
docker history myapp

# Run shell in failed build
docker run -it --entrypoint sh <image-id>

# Check image size breakdown
docker images --format "{{.Repository}}:{{.Tag}} {{.Size}}"
```
