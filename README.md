# Multi-Agent Student Loan Assistant with Python and Microsoft Agent Framework

⭐ If you like this sample, star it on GitHub — it helps a lot!

**Official repository:** [Azure-Samples/multi-agent-student-loan-processing-SA](https://github.com/Azure-Samples/multi-agent-student-loan-processing-SA)

[Overview](#overview) • [How to Interact](#how-to-interact-with-the-agent) • [Multi-Agent Architecture](#multi-agent-architecture-for-student-loan-processing) • [System Architecture](#system-architecture) • [Quick Start](#quick-start) • [Resources](#resources)

## Overview

The core use case of this application revolves around a **student loan processing assistant** designed to revolutionize the way students interact with loan applications. Utilizing the power of generative AI within a multi-agent architecture, this assistant aims to provide a seamless, conversational interface through which users can effortlessly inquire about student loans, prepare their applications, and receive automated loan decisions.

Instead of navigating through traditional web forms and submission processes, users can simply **converse with the AI-powered assistant** to:
- Ask general questions about student loan requirements and eligibility
- Get guidance on required documentation
- Upload loan application and bank statement documents
- Review extracted data and validation results
- Receive automated loan approval decisions based on financial analysis

The assistant leverages existing document processing APIs and business rules to ensure a reliable and secure service. Student loan applications and bank statements are processed using Azure OpenAI GPT-4o for data extraction. All business logic for loan approval (DTI calculation, credit evaluation) is exposed as external REST APIs and MCP tools consumed by the agents to provide the user with loan decisions.

This sample is powered by:

**[Microsoft Agent Framework](https://learn.microsoft.com/en-us/agent-framework/overview/agent-framework-overview)** - A Python framework for building multi-agent AI applications

## Features

This project provides the following features and technical patterns:

- **Multi-agent supervisor architecture** using GPT-4o on Azure AI Foundry
- **Exposing business APIs as MCP tools** for agents using [FastMCP](https://gofastmcp.com/getting-started/welcome)
- **Agent tools configuration** and automatic tools invocations with [Agent Framework](https://learn.microsoft.com/en-us/agent-framework/overview/agent-framework-overview)
- **Chat-based conversation** implemented as React Single Page Application with support for PDF document upload (loan applications and bank statements)
- **Document scanning and data extraction** with Azure OpenAI GPT-4o using structured outputs (Pydantic models)
- **Three-tier architecture** with FastAPI backend, React frontend, and separate business logic tier (MCP server)
- **Real-time streaming** responses with FastAPI Server-Sent Events (SSE)
- **Automated validation** with cross-document verification and completeness checks
- **State management** for tracking loan application workflow progress

## How to Interact with the Agent

![Student loan application workflow demonstrated in the chat interface](docs/assets/student-loan-process.gif)

Use the chat interface to complete a loan application from initial greeting through the final lending decision:

1. **Greet the agent** and ask about its student loan capabilities.
2. **Start an application** by telling the agent you are ready to apply.
3. **Upload the required PDFs**: a loan application and a bank statement. The applicant name must match in both documents.
4. **Confirm the upload** after verifying that both files appear in the chat.
5. **Wait for extraction** while GPT-4o reads the documents and returns structured application data.
6. **Review and confirm the extracted data** before the agent starts the loan evaluation.
7. **Receive the decision**, including approval status, debt-to-income ratio, interest rate when approved, and an explanation.
8. **End the session or begin another application** from the same chat experience.

_The animated walkthrough is sourced from the [Azure Samples solution accelerator](https://github.com/Azure-Samples/multi-agent-student-loan-processing-SA)._

## Multi-Agent Architecture for Student Loan Processing

![Multi-agent workflow for student loan processing](docs/assets/multi-agent-architecture.png)

The student loan processing assistant is designed as a **conversational multi-agent system** with each agent specializing in a specific functional domain (e.g., document extraction, validation, loan approval). The architecture consists of the following key components:

### Components

**🔵 Copilot Assistant (FastAPI Microservice)**

Serves as the central hub for processing user chat requests. It's a [FastAPI](https://fastapi.tiangolo.com/) app which uses Agent Framework to create specialized agents equipped with tools and orchestrates them using a custom workflow pattern.

- **Orchestration Agent**: Responsible for coordinating the entire loan application workflow. It triages user requests (general questions, document upload, confirmation), delegates tasks to specialized agents, and manages the conversation flow. This component ensures that user queries are efficiently handled by the relevant agent or executor. The orchestrator engages agents in a multi-turn conversation, collecting user feedback when data verification or action approval (like proceeding with loan decision) is required.

- **Intent Classifier Executor**: Detects user intent from chat messages (general_chat, document_upload, confirm_validation, proceed_to_decision) to route the conversation appropriately.

- **Document Scanner Service**: Specializes in extracting structured data from uploaded PDF documents (student loan applications and bank statements). It leverages Azure OpenAI GPT-4o with structured outputs (Pydantic models) to accurately extract fields like student number, loan amount, income, bank details, and account information.

- **Triage Validator Agent**: Focuses on validating extracted data through three levels: 1) Cross-document validation (matching bank names, account numbers between documents), 2) Database validation (checking if applicant exists - future feature), 3) Completeness check (ensuring all required fields are present with valid formats). Uses Azure OpenAI with Pydantic structured outputs to return validation results.

- **Decision Maker Agent**: Interfaces with the MCP Server to make final loan approval decisions. This agent calls multiple MCP tools such as `calculate_dti_ratio()` (Debt-to-Income calculation), `evaluate_credit_profile()` (credit scoring), and receives recommendations for approval/denial with interest rates and monthly payments.

- **Chat Agent**: Handles general conversational queries about student loans, eligibility requirements, and application process outside the formal loan workflow.

**🟢 Frontend Web App (React + Vite)**

A React-based single-page application providing the user interface for the chat experience.

- Real-time chat interface with streaming message support
- PDF document upload capability (drag-and-drop or file picker)
- Workflow status tracking and progress indicators
- Response formatting with markdown support
- Mobile-responsive design

**🟡 Business API - MCP Services (FastAPI Microservices)**

Backend systems exposed as MCP (Model Context Protocol) endpoints to provide business logic and data operations.

- **Loan Approval MCP Service**: Provides loan decision-making capabilities including DTI ratio calculation, credit profile evaluation, interest rate determination, and monthly payment calculation. This service implements the core business rules for approving or denying student loan applications based on financial criteria (DTI < 40% for approval).

The supervisor coordinates the specialized agents, maintains the workflow state, and routes validated application data to the MCP business tools for a deterministic lending decision.

## System Architecture

![Three-tier system architecture for the student loan processing solution](docs/assets/system-architecture.png)

The solution uses a three-tier architecture:

- **Frontend (React + Vite)** provides streaming chat, PDF upload, and workflow status.
- **Backend (FastAPI + Microsoft Agent Framework)** orchestrates intent classification, document extraction, validation, general chat, and loan-decision agents.
- **Business API (FastMCP)** exposes debt-to-income, credit-profile, interest-rate, and payment calculations as MCP tools.

Requests flow from the frontend to the backend orchestrator. The orchestrator invokes specialized agents and Azure services, then calls the MCP business API for loan calculations before streaming the result back to the user.

### Typical User Journey

1. **General Inquiry** - User asks questions about student loans
   - Intent: `general_chat`
   - Agent: Chat Agent responds with general information

2. **Document Upload** - User uploads loan application + bank statement PDFs
   - Intent: `document_upload`
   - Service: Document Scanner extracts structured data using GPT-4o
   - Output: StudentLoanApplication and BankStatement Pydantic models

3. **Validation** - System validates extracted data
   - Agent: Triage Validator performs 3-level validation
   - Checks: Bank name match, account number match, field completeness
   - Output: PASS / CONDITIONAL_PASS / FAIL status

4. **User Confirmation** - System presents validation results
   - User reviews extracted data
   - User types "yes" or "proceed" to confirm

5. **Loan Decision** - System evaluates loan application
   - Agent: Decision Maker Agent calls MCP Server
   - Tools: `calculate_dti_ratio()`, `evaluate_credit_profile()`
   - Output: APPROVED / DENIED with interest rate and payment details

6. **Final Response** - User receives decision
   - Chat interface displays approval status
   - Includes loan amount, interest rate, monthly payment

## 📁 Project Structure

```
Agent-Loan-Processing/
├── README.md                           # This file
├── LICENSE                             # MIT License
├── .gitignore                          # Git ignore rules
│
├── src/
│   ├── __init__.py                     # Parent package
│   │
│   ├── backend/                        # 🔵 BACKEND SERVER (FastAPI)
│   │   ├── .env.dev                    # Development environment variables
│   │   ├── pyproject.toml              # Backend dependencies
│   │   ├── applicationinsights.json    # Azure Application Insights config
│   │   └── app/
│   │       ├── main.py                 # FastAPI application entry point
│   │       │
│   │       ├── agents/                 # AI Agents
│   │       │   └── loan_workflow/
│   │       │       ├── loan_workflow_orchestrator.py      # Main orchestrator
│   │       │       ├── loan_document_extractor.py         # Document processing
│   │       │       ├── loan_application_validator.py      # Triage validation
│   │       │       ├── loan_approval_decision_maker.py    # MCP client
│   │       │       ├── user_intent_classifier.py          # Intent detection
│   │       │       ├── extraction_result_formatter.py     # Response formatting
│   │       │       ├── error_handler.py                   # Error handling
│   │       │       └── loan_application_instructions_provider.py
│   │       │
│   │       ├── api/                    # REST API endpoints
│   │       │   ├── chat_routes.py      # Chat & file upload endpoints
│   │       │   ├── auth_routers.py     # Authentication endpoints
│   │       │   └── content_routers.py  # Content management
│   │       │
│   │       ├── services/               # Business services
│   │       │   ├── loan_document_scanner.py       # Azure OpenAI extraction
│   │       │   └── azure_blob_storage_client.py   # Blob storage client
│   │       │
│   │       ├── models/                 # Pydantic models
│   │       │   ├── validation.py       # Validation models
│   │       │   ├── documents.py        # Document models
│   │       │   ├── chat.py             # Chat models
│   │       │   └── user.py             # User models
│   │       │
│   │       ├── config/                 # Configuration
│   │       │   ├── settings.py         # Environment settings
│   │       │   ├── azure_credential.py # Azure authentication
│   │       │   ├── logging.py          # Logging configuration
│   │       │   └── container_azure_chat.py  # Dependency injection
│   │       │
│   │       ├── utils/                  # Utilities
│   │       │   └── status_helpers.py   # Status mapping utilities
│   │       │
│   │       ├── tests/                  # Test suite
│   │       └── upload_data/            # Data upload scripts
│   │
│   ├── frontend/                       # 🟢 FRONTEND (React + Vite)
│   │   ├── src/
│   │   │   ├── App.tsx                 # Main React component
│   │   │   ├── main.tsx                # Entry point
│   │   │   ├── index.css               # Global styles
│   │   │   ├── components/             # React components
│   │   │   ├── services/               # API clients
│   │   │   ├── styles/                 # Component styles
│   │   │   └── guidelines/             # Design guidelines
│   │   ├── build/                      # Production build output
│   │   ├── package.json                # Frontend dependencies
│   │   ├── vite.config.ts              # Vite configuration
│   │   ├── index.html                  # HTML entry point
│   │   └── README.md                   # Frontend documentation
│   │
│   └── biz_api/                        # 🟡 BUSINESS API (MCP Server)
│       └── loan_approval/
│           ├── main.py                 # MCP server entry point
│           ├── mcp_tools.py            # MCP tool definitions
│           ├── services.py             # Business logic (DTI, credit eval)
│           ├── models.py               # Pydantic models for MCP
│           ├── test_loan_approval.py   # Unit tests
│           ├── logging_config.py       # Logging setup
│           ├── pyproject.toml          # API dependencies
│           ├── README.md               # Business API documentation
│           ├── DTI_IMPLEMENTATION.md   # DTI calculation details
│           └── test_data/              # Test cases
│
├── backup/                             # Reference implementations
├── docs/                               # Project documentation
└── infra/                              # Infrastructure as code (future)
```

## 🚀 Quick Start

### Prerequisites

- **WSL 2** with Ubuntu (Ubuntu 24.04 is validated)
- **Python 3.11+**
- **[uv](https://docs.astral.sh/uv/)** for Python environment and dependency management
- **Linux-native Node.js 18+** and npm (Node.js 22 is validated)
- **Azure CLI**, authenticated with `az login`
- **Azure OpenAI** account with GPT-4o deployment
- **Azure Blob Storage** account (e.g. `agentloanprocessing2025`)

  > Run `command -v node npm uv` inside WSL before setup. These commands must resolve to Linux paths such as `/usr/bin` or `/home/<user>/.local/bin`, not `/mnt/c/...`.

  > ⚠️ **Required storage account settings for local testing** — verify these in the Azure Portal under your storage account:
  >
  > | Setting | Required value |
  > |---|---|
  > | Public network access | **Enabled from all networks** (Networking → Public access) |
  > | Allow Blob anonymous access | **Enabled** (Configuration) |
  > | Allow storage account key access | **Enabled** (Configuration) |
  >
  > Without these settings the app will receive `AuthorizationFailure` errors when uploading documents.

### Installation

1. **Clone the repository into the WSL filesystem**:

```bash
mkdir -p ~/1.projects
cd ~/1.projects
git clone https://github.com/Azure-Samples/multi-agent-student-loan-processing-SA.git
cd Agent-Loan-Processing
```

Avoid placing the project under `/mnt/c`. Keeping the workspace under `/home/<user>` provides faster dependency installation, file watching, and hot reload.

2. **Create the backend development configuration**:

Create `src/backend/.env.dev` and add the settings for your Azure resources. This file is ignored by Git and must not be committed.

```bash
PROFILE=dev
AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com/
AZURE_OPENAI_KEY=your-api-key
AZURE_OPENAI_CHAT_DEPLOYMENT_NAME=gpt-4o
AZURE_STORAGE_ACCOUNT=your-storage-account
AZURE_STORAGE_CONTAINER=loan-documents
LOAN_APPROVAL_MCP_URL=http://localhost:8070/mcp
ENABLE_OTEL=false
```

Protect the local configuration:

```bash
chmod 600 src/backend/.env.dev
```

3. **Authenticate with Azure**:

```bash
az login
```

### Running the Application

There are two supported local-development methods:

1. Use the one-command launcher to start and supervise the complete system.
2. Start the MCP server, backend, and frontend manually in separate terminals.

The services must start in this order:

```text
MCP server (8070) → Backend API (8001) → Frontend (5173)
```

The backend can start before the MCP server, but loan-decision requests will fail when the backend attempts to connect to `http://localhost:8070/mcp`.

#### Method 1: Start Everything with One Script (Recommended)

The repository includes [`scripts/start-dev.sh`](./scripts/start-dev.sh), which starts all three building blocks with their correct working directories, virtual environments, environment values, ports, and readiness checks.

From the repository root, run:

```bash
./scripts/start-dev.sh
```

For the first run—or whenever dependencies change—restore dependencies before startup:

```bash
./scripts/start-dev.sh --install
```

Other launcher options:

| Command | Purpose |
|---|---|
| `./scripts/start-dev.sh` | Start all services with backend auto-reload |
| `./scripts/start-dev.sh --install` | Restore both Python environments and frontend packages, then start |
| `./scripts/start-dev.sh --no-reload` | Start all services without Uvicorn auto-reload |
| `./scripts/start-dev.sh --help` | Display launcher usage |

The launcher:

- Verifies required commands, environments, dependencies, and `src/backend/.env.dev`
- Rejects Windows Node.js/npm executables accidentally inherited through `/mnt/c`
- Fails clearly if ports `8070`, `8001`, or `5173` are already occupied
- Sets `PROFILE=dev` independently for the MCP server and backend
- Waits for each service before starting the next building block
- Prefixes output with `[mcp]`, `[backend]`, or `[frontend]`
- Monitors all processes and stops the complete system if a critical process exits
- Gracefully stops all three services when you press `Ctrl+C`

When startup succeeds, the launcher prints:

```bash
Frontend:    http://localhost:5173
Backend API: http://localhost:8001
API docs:    http://localhost:8001/docs
MCP server:  http://localhost:8070/mcp
```

#### Method 2: Start Each Building Block Manually

Use this method to debug an individual process or inspect each service in a separate terminal.

##### First-Time Dependency Setup

Run these commands once from the repository root:

```bash
# Backend environment
cd src/backend
uv sync --prerelease=allow
cd ../..

# MCP server environment
cd src/biz_api/loan_approval
uv sync
cd ../../..

# Frontend dependencies
cd src/frontend
npm ci
cd ../..
```

Each Python project creates and manages its own Linux virtual environment:

```text
src/backend/.venv
src/biz_api/loan_approval/.venv
```

Virtual-environment activation is optional because the following commands call each environment's Python executable directly.

##### Terminal 1 — MCP Business API (Port 8070)

```bash
cd ~/1.projects/Agent-Loan-Processing/src/biz_api/loan_approval
PROFILE=dev .venv/bin/python main.py
```

Wait until the output confirms that Uvicorn is running on `http://0.0.0.0:8070`.

##### Terminal 2 — Backend API (Port 8001)

```bash
cd ~/1.projects/Agent-Loan-Processing/src/backend
PROFILE=dev .venv/bin/python -m uvicorn app.main:app \
  --reload \
  --host 0.0.0.0 \
  --port 8001
```

Verify backend readiness:

```bash
curl --fail http://localhost:8001/openapi.json > /dev/null
```

Backend endpoints:

- API base: `http://localhost:8001`
- Swagger UI: `http://localhost:8001/docs`
- OpenAPI readiness check: `http://localhost:8001/openapi.json`

##### Terminal 3 — Frontend (Port 5173)

```bash
cd ~/1.projects/Agent-Loan-Processing/src/frontend
VITE_API_URL=http://localhost:8001/api npm run dev -- --host 0.0.0.0
```

Frontend will be available at: `http://localhost:5173`

To stop manual mode, press `Ctrl+C` in each of the three terminals.

#### Local Service Summary

| Building block | Port | Local endpoint | Development environment |
|---|---:|---|---|
| Frontend | 5173 | `http://localhost:5173` | Linux Node.js/npm |
| Backend API | 8001 | `http://localhost:8001` | `src/backend/.venv`, `PROFILE=dev` |
| MCP Business API | 8070 | `http://localhost:8070/mcp` | `src/biz_api/loan_approval/.venv`, `PROFILE=dev` |

## Guidance

### Running Locally for Development

Once you have the project cloned locally, you can run all the apps locally. For more details on how to run each app check:

- **[One-command launcher](#method-1-start-everything-with-one-script-recommended)**: Start and supervise the complete local system
- **[Manual startup](#method-2-start-each-building-block-manually)**: Run each building block in a separate terminal
- **[src/frontend/README.md](./src/frontend/README.md)**: Frontend web app setup
- **[src/biz_api/loan_approval/README.md](./src/biz_api/loan_approval/README.md)**: MCP business API server setup

### Cost Estimation

Pricing varies per region and usage, so it isn't possible to predict exact costs for your usage. However, you can try the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/) for the resources below:

- **Azure OpenAI**: Standard tier, GPT-4o model. Pricing per 1K tokens used, and at least 1K tokens are used per question. [Pricing](https://azure.microsoft.com/pricing/details/cognitive-services/openai-service/)
- **Azure Blob Storage**: Standard tier with ZRS (Zone-redundant storage). Pricing per storage and read operations. [Pricing](https://azure.microsoft.com/pricing/details/storage/blobs/)
- **Azure Document Intelligence**: Standard tier using pre-built layout (future). [Pricing](https://azure.microsoft.com/pricing/details/form-recognizer/)
- **Azure Monitor**: Pay-as-you-go tier. Costs based on data ingested (future). [Pricing](https://azure.microsoft.com/pricing/details/monitor/)

⚠️ To avoid unnecessary costs, remember to take down your app if it's no longer in use by stopping local servers or deleting Azure resource groups if deployed.

## Resources

Here are some resources to learn more about multi-agent architectures and technologies used in this sample:

- [Microsoft Agent Framework](https://github.com/microsoft/agent-framework)
- [AI Agents For Beginners](https://github.com/microsoft/ai-agents-for-beginners)
- [Azure AI Foundry](https://learn.microsoft.com/azure/ai-foundry/what-is-azure-ai-foundry)
- [Develop AI apps using Azure services](https://aka.ms/azai)
- [Building Effective Agents - Anthropic](https://www.anthropic.com/engineering/building-effective-agents)
- [AI agent orchestration patterns](https://learn.microsoft.com/azure/architecture/ai-ml/guide/ai-agent-design-patterns)

You can also find [more Azure AI agents samples here](https://aka.ms/aiapps).

## Getting Help

If you get stuck or have any questions about building AI apps, join:

[Azure AI Foundry Discord](https://aka.ms/foundry/discord)

If you have product feedback or errors while building visit:

[Azure AI Foundry Developer Forum](https://aka.ms/foundry/forum)

## 📚 Documentation

- **[Running the application](#running-the-application)**: Detailed setup and running instructions
- **[src/biz_api/loan_approval/README.md](./src/biz_api/loan_approval/README.md)**: MCP server documentation
- **[src/biz_api/loan_approval/DTI_IMPLEMENTATION.md](./src/biz_api/loan_approval/DTI_IMPLEMENTATION.md)**: DTI calculation logic
- **[src/frontend/README.md](./src/frontend/README.md)**: Frontend development guide

## 🧪 Testing

### Manual Testing

1. **Backend Health Check**:
```bash
curl --fail http://localhost:8001/openapi.json > /dev/null
# Expected: command exits successfully with HTTP 200
```

2. **MCP Server Test**:
```bash
cd src/biz_api/loan_approval
pytest test_loan_approval.py -v
# Tests DTI calculation, credit evaluation, and decision logic
```

3. **Full Workflow Test**:
   - Upload sample documents from `data/sample_documents/`
   - Use the chat interface to process application
   - Verify all workflow stages complete successfully

### Sample Test Data

- **Student Loan Application**: `data/sample_documents/sample-filled-student-loan-application.pdf`
- **Bank Statement**: `data/sample_documents/bank-statement-sample.pdf`
- **Expected Results**:
  - Extraction: Student number, loan amount, income, bank details
  - Validation: PASS (all fields match)
  - Decision: APPROVED or DENIED based on DTI ratio

### Unit Tests

```bash
# Test MCP business logic
cd src/biz_api/loan_approval
pytest test_loan_approval.py

# Test coverage includes:
# - DTI calculation (approved: <40%, denied: ≥40%)
# - Credit evaluation (excellent/good/fair/poor)
# - Interest rate determination
# - Monthly payment calculation
```

## � Current Status

### ✅ Completed Features

- [x] **Backend Server**: FastAPI with AI agent orchestration
- [x] **Frontend**: React chat interface with file upload
- [x] **Business API**: MCP server for loan decisions
- [x] **Document Extraction**: Azure OpenAI GPT-4o with structured outputs
- [x] **Validation System**: 3-level validation (cross-document, DB, completeness)
- [x] **Authentication**: JWT-based user authentication system
- [x] **Blob Storage**: Azure Blob Storage for document persistence
- [x] **Status Tracking**: Real-time workflow state management
- [x] **Error Handling**: Comprehensive error handling and logging
- [x] **Code Refactoring**: Modular architecture with utilities and models

### 🔮 Future Enhancements

- [ ] **Cosmos DB Integration**: Persistent applicant history and workflow state
- [ ] **Azure AI Search**: RAG pattern for loan policy queries
- [ ] **Azure Document Intelligence**: Advanced form recognition (alternative to GPT-4o)
- [ ] **Real-time Notifications**: WebSocket for instant status updates
- [ ] **Admin Dashboard**: Monitoring and analytics interface
- [ ] **Multi-language Support**: Internationalization (i18n)
- [ ] **Responsible AI**: Content safety filters and bias detection
- [ ] **Integration Tests**: End-to-end testing suite
- [ ] **CI/CD Pipeline**: Automated deployment to Azure

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-feature`
3. Commit your changes: `git commit -am 'Add new feature'`
4. Push to the branch: `git push origin feature/new-feature`
5. Create a Pull Request

### Development Guidelines

**Backend**:
- Use dependency injection via `dependency_injector`
- Follow Agent Framework patterns (executors, workflows)
- Use Pydantic models for all data validation
- Log at appropriate levels (info=essential, debug=detailed)
- Keep business logic in `services/` directory

**Frontend**:
- Follow React best practices with TypeScript
- Use Vite for development and building
- Maintain component modularity
- Handle loading and error states gracefully

**Business API**:
- Use MCP protocol for tool definitions
- Keep business rules testable and documented
- Provide comprehensive unit test coverage
- Document DTI thresholds and credit scoring logic

## Troubleshooting

If you have any issue when running or deploying this sample, [open an issue](https://github.com/Azure-Samples/multi-agent-student-loan-processing-SA/issues) in the official repository.

## Contributing

This project welcomes contributions and suggestions. Most contributions require you to agree to a Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us the rights to use your contribution. For details, visit [https://cla.opensource.microsoft.com](https://cla.opensource.microsoft.com/).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow [Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general). Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship. Any use of third-party trademarks or logos are subject to those third-party's policies.
