# Dockerfile for building and serving OpenAPI documentation with Swagger UI

# Stage 1: Build OpenAPI v2 from Protobuf using gRPC Gateway
FROM golang:1.24 as build

RUN apt-get update && apt-get install -y \
    git \
    curl \
    unzip

RUN curl -LO https://github.com/protocolbuffers/protobuf/releases/download/v21.12/protoc-21.12-linux-x86_64.zip \
    && unzip protoc-21.12-linux-x86_64.zip -d /usr/local \
    && rm protoc-21.12-linux-x86_64.zip

ENV GOPROXY=direct
RUN go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-openapiv2@latest
WORKDIR /app
RUN git clone https://github.com/grpc-ecosystem/grpc-gateway.git
RUN git clone https://github.com/googleapis/googleapis.git
COPY . .
RUN protoc -I ./Protos -I grpc-gateway -I googleapis --openapiv2_out ./template --openapiv2_opt logtostderr=true,allow_merge=true,merge_file_name=commitment commitment.proto


# Stage 2: Convert OpenAPI v2 to v3 using Node.js
FROM node:18-alpine AS openapi-convert

WORKDIR /convert
RUN apk add --no-cache jq && npm install -g swagger2openapi
COPY --from=build /app/template/commitment.swagger.json ./swagger.json
COPY --from=build /app/template/index.html ./index.html
RUN swagger2openapi swagger.json -o openapi.json

# Stage 3: Add metadata and security definitions
RUN jq '.info = { \
    "title": "Commitment Pacing API", \
    "version": "1.0", \
    "description": "API for managing commitment pacing" \
    } | .components.securitySchemes = { \
    "Bearer": { \
        "type": "http", \
        "scheme": "bearer", \
        "bearerFormat": "JWT", \
        "description": "JWT Authorization header using the Bearer scheme. Example: '\''Authorization: Bearer {token}'\''" \
    } \
} | .security = [{"Bearer": []}]' openapi.json > openapi-complete.json

# Final stage: Serve using NGINX
FROM nginx:alpine

# Copy Swagger UI files (index.html, swagger.json) from build stage
COPY --from=openapi-convert /convert/openapi-complete.json /usr/share/nginx/html/swagger.json
COPY --from=openapi-convert /convert/index.html /usr/share/nginx/html/index.html

# Expose port
EXPOSE 80

# Start NGINX
CMD ["nginx", "-g", "daemon off;"]

