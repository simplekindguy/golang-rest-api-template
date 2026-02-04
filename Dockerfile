# ───────────────────────────────────────────────────────────
# 🌟 STAGE 1: BUILD GO APPLICATION
# ───────────────────────────────────────────────────────────
FROM golang:1.24.7 AS builder
# Tool versions (defaults)
ARG SWAG_VERSION=v1.16.3
ARG MIGRATE_VERSION=v4.17.1
ARG LINT_VERSION=v1.55.2
ARG IMPORTS_VERSION=latest
ARG VULN_VERSION=latest


# Build args (no secrets - app gets config at runtime via env_file)
ARG SWAG_VERSION
ARG MIGRATE_VERSION
ARG LINT_VERSION
ARG IMPORTS_VERSION
ARG VULN_VERSION

# Set environment variables for versions (same as Makefile)
ENV SERVER_PORT=$SERVER_PORT
ENV DB_HOST=$DB_HOST
ENV DB_PORT=$DB_PORT
ENV DB_USER=$DB_USER
ENV DB_PASSWORD=$DB_PASSWORD
ENV DB_NAME=$DB_NAME
ENV DEBUG=$DEBUG
ENV DISABLE_LOGS=$DISABLE_LOGS
ENV LOG_FORMAT=$LOG_FORMAT
ENV LOG_CALLER=$LOG_CALLER
ENV LOG_STACKTRACE=$LOG_STACKTRACE
ENV GOPROXY=https://proxy.golang.org,direct
ENV GOPRIVATE=github.com/simplekindguy/*
ENV GOSUMDB=sum.golang.org
# Set the working directory inside the container
WORKDIR /app

# Copy Go modules manifests
COPY go.mod go.sum ./

# Download Go dependencies
RUN go env && \
    go mod tidy -v && \
    go mod download -x

# Install Swagger (for docs) and golang-migrate (for DB migrations)
RUN go install github.com/swaggo/swag/cmd/swag@${SWAG_VERSION}
RUN curl -L https://github.com/golang-migrate/migrate/releases/download/${MIGRATE_VERSION}/migrate.linux-amd64.tar.gz -o migrate.tar.gz && \
    tar -xvf migrate.tar.gz && \
    mv migrate /usr/local/bin/migrate && \
    chmod +x /usr/local/bin/migrate && \
    rm -f migrate.tar.gz

# Copy the entire project into the container
COPY . .

# 🔥 Ensure `/app/build/` exists
RUN mkdir -p /app/build

# Generate Swagger documentation
RUN make generate_docs

# 🔥 Build the Go application using Makefile
RUN make build

# ───────────────────────────────────────────────────────────
# 🌟 STAGE 2: CREATE A SMALLER FINAL IMAGE
# ───────────────────────────────────────────────────────────
FROM debian:bullseye-slim

# Set the working directory
WORKDIR /app

# Install dependencies required to run the app
RUN apt-get update && apt-get install -y ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

# Copy the compiled Go binary from the builder stage
COPY --from=builder /app/build/server /app/server

# Copy the Swagger docs to serve them later
COPY --from=builder /app/docs /app/docs

# Copy the migration files
COPY --from=builder /app/package/database/migrations /app/migrations

# Copy the migrate tool from the builder stage
COPY --from=builder /usr/local/bin/migrate /usr/local/bin/migrate

EXPOSE 8080

# Run the application
CMD ["/app/server"]
