# PhongVu OpsHub Backend

This is the new backend architecture for the PhongVu OpsHub mobile application, transitioning from n8n to a robust Microservices architecture for high scalability, real-time tracking, and optimal performance.

## Architecture Overview

The system is composed of two primary microservices interacting with a shared PostgreSQL database and Redis for real-time pub/sub:

1. **Main API Service (NestJS + Prisma)**
   - **Responsibility:** Core business logic, User Authentication (JWT/RBAC), Warranty Management, and Data Consistency.
   - **Why NestJS:** Strongly-typed (TypeScript), highly structured (Module-based), excellent for complex business rules.

2. **Realtime Service (Golang + GORM)**
   - **Responsibility:** High-performance tasks, Real-time Chat via WebSockets, High-volume barcode scanning (Sorting feature).
   - **Why Golang:** Incredible concurrency model (Goroutines) allowing tens of thousands of simultaneous WebSocket connections with minimal RAM usage.

## Infrastructure
- **Message Broker / Cache:** Redis
- **Database:** PostgreSQL
- **Deployment:** Docker & Docker Compose

## Repository Structure
- `/backend-nest`: Contains the Main API Service codebase.
- `/backend-go`: Contains the Realtime Service codebase.
- `/shared-docs`: API documentation, DB Schemas, and architecture diagrams.

## Quick Start (Local Development)
*(Instructions to be added)*
