.PHONY: test test-unit test-integration test-coverage lint clean install help
.PHONY: docker-build docker-test docker-test-unit docker-test-integration docker-shell docker-clean
.PHONY: docker-up docker-down docker-pull-model

# ============================================================================
# Configuration
# ============================================================================
OLLAMA_MODEL ?= tinyllama
DOCKER_COMPOSE = docker compose

# ============================================================================
# Help
# ============================================================================
help:
	@echo "Gentleman Guardian Angel - Development Commands"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Local Development:"
	@echo "  test             Run all tests locally"
	@echo "  test-unit        Run unit tests only"
	@echo "  test-integration Run integration tests only"
	@echo "  test-coverage    Run tests with coverage report"
	@echo "  lint             Run shellcheck linter"
	@echo "  clean            Clean cache and temp files"
	@echo "  install          Install gga locally"
	@echo ""
	@echo "Docker Development (Recommended):"
	@echo "  docker-build     Build test Docker image"
	@echo "  docker-test      Run all tests in Docker (with Ollama)"
	@echo "  docker-test-unit Run unit tests in Docker"
	@echo "  docker-test-integration  Run integration tests with real Ollama"
	@echo "  docker-shell     Open shell in test container"
	@echo "  docker-up        Start Ollama service"
	@echo "  docker-down      Stop all Docker services"
	@echo "  docker-pull-model Pull Ollama model (default: tinyllama)"
	@echo "  docker-clean     Remove Docker volumes and images"
	@echo ""
	@echo "CI:"
	@echo "  check            Run lint + tests (pre-commit)"
	@echo ""

# ============================================================================
# Local Development Targets
# ============================================================================

# Run all tests locally
test:
	@echo "Running all tests..."
	shellspec

# Run unit tests only
test-unit:
	@echo "Running unit tests..."
	shellspec spec/unit

# Run integration tests only
test-integration:
	@echo "Running integration tests..."
	shellspec spec/integration

# Run tests with coverage (requires kcov)
test-coverage:
	@echo "Running tests with coverage..."
	shellspec --kcov

# Lint shell scripts
lint:
	@echo "Linting shell scripts..."
	shellcheck bin/gga lib/*.sh
	@echo "✅ Linting passed"

# Clean temp files and cache
clean:
	@echo "Cleaning..."
	rm -rf coverage/
	rm -rf ~/.cache/gga/
	@echo "✅ Cleaned"

# Install locally
install:
	@echo "Installing gga locally..."
	./install.sh

# Quick check before commit
check: lint test
	@echo ""
	@echo "✅ All checks passed!"

# ============================================================================
# Docker Development Targets
# ============================================================================

# Build test Docker image
docker-build:
	@echo "Building test Docker image..."
	$(DOCKER_COMPOSE) build test

# Start Ollama service in background
docker-up:
	@echo "Starting Ollama service..."
	$(DOCKER_COMPOSE) up -d ollama
	@echo "Waiting for Ollama to be healthy..."
	@until $(DOCKER_COMPOSE) exec ollama curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; do \
		echo "  Waiting..."; \
		sleep 2; \
	done
	@echo "✅ Ollama is ready"

# Pull model into Ollama
docker-pull-model: docker-up
	@echo "Pulling model: $(OLLAMA_MODEL)..."
	$(DOCKER_COMPOSE) exec ollama ollama pull $(OLLAMA_MODEL)
	@echo "✅ Model $(OLLAMA_MODEL) ready"

# Run all tests in Docker
docker-test: docker-build docker-up docker-pull-model
	@echo "Running all tests in Docker..."
	$(DOCKER_COMPOSE) run --rm test shellspec
	@echo "✅ All tests passed"

# Run unit tests in Docker (no Ollama needed)
docker-test-unit: docker-build
	@echo "Running unit tests in Docker..."
	$(DOCKER_COMPOSE) run --rm --no-deps test shellspec spec/unit

# Run integration tests in Docker (with Ollama)
docker-test-integration: docker-build docker-up docker-pull-model
	@echo "Running integration tests in Docker with real Ollama..."
	$(DOCKER_COMPOSE) run --rm test shellspec spec/integration

# Open shell in test container
docker-shell: docker-build
	@echo "Opening shell in test container..."
	$(DOCKER_COMPOSE) run --rm test bash

# Stop all Docker services
docker-down:
	@echo "Stopping Docker services..."
	$(DOCKER_COMPOSE) down

# Full Docker cleanup
docker-clean:
	@echo "Cleaning Docker resources..."
	$(DOCKER_COMPOSE) down -v --rmi local
	@echo "✅ Docker resources cleaned"
