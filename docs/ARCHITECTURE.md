# Architecture

## 1. Introduction

This document outlines the high-level architecture for Skilld.

## 2. Technology Stack

### Core Components

- **Backend Framework**: **FastAPI** (Python)
- **Database**: **PostgreSQL**
- **Authentication & Authorization**: **JWT (JSON Web Tokens)** via `fastapi-users` (internally using `python-jose`)
- **File Storage**: **AWS S3** (for CVs, images, videos)

### Development

- **Frontend**: **Next.js** (React framework)
- **Styling**: **TailwindCSS**
- **Package Manager**: **pnpm**

### Infrastructure

- **Containerization**: **Docker** (and `docker-compose`)
- **Web Server/Proxy**: **Nginx**
- **Email Service**: **AWS SES** (via `fastapi-users` configuration)
- **Cache/Message Broker**: **Redis**

## 3. System Architecture

```mermaid
graph TD
    Client[Client App<br/>(Web/Mobile)] --> Nginx[Nginx]

    subgraph "Skilld Application Cluster"
        Nginx --> FastAPI[FastAPI Server<br/>(Python 3.11)]

        FastAPI -->|SQL queries| Postgres[(PostgreSQL)]
        FastAPI -->|Auth/Cache| Redis[(Redis)]

        subgraph "File Storage"
            FastAPI --> S3[AWS S3]
        end

        subgraph "External Services"
            FastAPI -->|Send Emails| SES[AWS SES]
        end
    end

    Client -.-> S3
```

## 4. High-Level Design (HLD)

### 4.1. Monolithic Architecture

The system is currently built as a **Monolith**.

- The **FastAPI server** handles all business logic, API routing, and database interactions.
- Frontend assets (HTML/CSS/JS/Images) are served either by a dedicated frontend build (e.g., Next.js) or directly by the backend depending on the deployment strategy.

### 4.2. Database Schema (PostgreSQL)

The schema is organized into distinct domains:

#### **Auth Module** (`auth_` tables)

- **Users**: Contains primary user data (email, hashed password, roles).
- **Refresh Tokens**: Manages session tokens.
- **Social Auth**: Integrations for Google Sign-In (`user_social_auth`).

#### **User Profile Module** (`user_profile_` tables)

- **Profiles**: Core profile information.
- **Skills**: A master list of skills (e.g., "Python", "React").
- **User Skills**: A many-to-many mapping between Users and Skills, including proficiency levels.
- **Resume**: Links to uploaded CV files stored in S3.
- **Portfolio**: Links to video and image portfolios.
- **Employment & Education**: Professional history and academic records.
- **Projects**: User-created projects.
- **Industries & Locations**: Classification tags.
- **Experience Certificates**: Digital certificates.

#### **Company Module** (`company_` tables)

- **Companies**: Company information.
- **Company Industry**: Company classifications.
- **Addresses**: Physical locations of companies.

#### **Jobs Module** (`job_` tables)

- **Job Boards**: A table to identify external sources (e.g., LinkedIn, Indeed).
- **Job Listings**: Job postings aggregated from job boards.
- **Application Requests**: Applications submitted by users for jobs.

#### **Skill Test Module** (`skill_test_` tables)

- **Test Categories**: Groups of tests (e.g., "Python Basics").
- **Questions**: Multiple-choice questions for testing.
- **Test Attempts**: Records of when users took tests.
- **Test Results**: Detailed results of user attempts.
- **User Answers**: Specific answers given by users during tests.

#### **Other Modules**

- **Settings**: Application-wide settings (`settings_app`).
- **Roles**: Role definitions (`role_` tables).

### 4.3. File Storage Strategy

- **Files**: CVs, resumes, and other documents are stored **externally** in **AWS S3**.
- **Metadata**: The database (`user_resume`) stores URLs and metadata pointing to these files.
- **Benefits**: offloads storage, allows for scalability, and enables CDNs.

### 4.4. Authentication Flow

1. **Login**: User sends credentials to the `/auth/login/password` endpoint.
2. **Verification**: `fastapi-users` validates the password against the hashed value in the `users` table.
3. **Token Generation**: If valid, it generates an **Access Token** and a **Refresh Token**.
4. **Storage**: The client stores these tokens (usually in memory or localStorage).
5. **Access**: The client includes the Access Token in the `Authorization: Bearer <token>` header for subsequent requests.
6. **Refresh**: When the Access Token expires, the client uses the Refresh Token to get a new pair via `/auth/login/refresh`.
