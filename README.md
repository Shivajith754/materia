# Matéria

> **Hybrid AI Research Assistant for Materials Science & Polymer Engineering**  
> *Built for the #BuildHybridAI 2026 Hackathon*

---

## Overview

Literature review in materials science and polymer engineering is often bottlenecked by two extremes: conventional academic databases return hundreds of dense papers with no immediate synthesis, while general-purpose commercial chatbots frequently hallucinate non-existent polymer grades, incorrect glass transition temperatures ($T_g$), and fabricated DOI citations.

**Matéria** addresses this challenge by combining **Firebase AI Logic hybrid inference** with live literature retrieval from **OpenAlex** (over 250 million scientific works). Matéria runs private, low-latency search suggestions directly on-device using Apple Intelligence, automatically falls back to cloud-hosted Gemini when needed, and generates grounded research briefs citing retrieved scholarly works.

---

## Key Features

### 1. Hybrid AI Logic Inference (On-Device + Cloud)
- **Primary (On-Device):** Uses `FirebaseAI.SystemLanguageModel` to run query refinement locally via Apple Foundation Models on eligible devices. Queries remain on-device during input suggestion generation.
- **Secondary (Cloud Failover):** Uses `HybridModelProvider.hybridModel(primary:secondary:)` to route queries to `gemini-3.5-flash-lite` if the on-device model is unavailable or encounters an execution failure.
- **Privacy-First Consent Gate:** If on-device Apple Intelligence is unsupported on the current hardware, the app pauses cloud execution and requests explicit user consent before sending queries online.
- **Dynamic Model Attribution:** Inspects response metadata to visibly label whether each suggestion was generated **On-device** or via the **Cloud**.

### 2. Live OpenAlex Scientific Literature Engine
- Queries scholarly works indexed by OpenAlex—including peer-reviewed journal articles, conference proceedings, and preprints—across materials science and chemistry.
- Extracts publication year, author lists, journal source, citation counts, and clickable DOI / publisher URLs.
- **1-Hour In-Memory Cache:** Eliminates redundant network queries for identical research topics.
- **In-Flight Deduplication:** Coalesces simultaneous requests for the same query into a single task.
- **Intelligent Rate-Limit Handling:** Automatically retries transient HTTP 429 throttling using server-specified `Retry-After` headers, while detecting daily budget exhaustion to prevent wasteful calls.

### 3. Grounded AI Research Synthesis
- Synthesizes retrieved abstracts into a structured 3-section research brief:
  1. **Overview:** A concise 2–3 sentence synthesis highlighting central themes across retrieved abstracts without conversational filler.
  2. **Key Findings:** 3 to 5 dense, fact-based bullet points summarizing quantitative measurements (e.g., tensile modulus, glass transition temperature $T_g$, thermal degradation onset), each attributed to its specific supporting paper (`[Author, Year]`).
  3. **Research Gaps:** Critical limitations, unaddressed processing variables, or open questions noted in the literature.
- **Hallucination Mitigation:** Configured with low temperature (0.1) and constrained prompt engineering instructing the model to rely strictly on retrieved abstract excerpts and avoid extrapolating unstated properties.

### 4. Modern Swift 6 & Native SwiftUI Architecture
- **Complete Concurrency Compliance:** Built with Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`) using actors, `Sendable` types, and immutable state.
- **Editorial Design System:** Refined dark-themed interface with custom typography, fluid animations, debounced inputs, and multi-state summary cards.

---

## Architecture

```text
User Query
    │
    ▼
[ResearchView] ── (Debounced 450ms)
    │
    ├── Check Apple Intelligence Status (localAIStatus)
    │     ├── On-Device Available ──► SystemLanguageModel (Apple Foundation Models)
    │     └── On-Device Unavailable ──► Check User Cloud Consent
    │                                     ├── Granted ──► gemini-3.5-flash-lite (Cloud)
    │                                     └── Denied  ──► Display Opt-In Banner
    │
    ▼
User Submits Search
    │
    ▼
[OpenAlexService]
    ├── In-Memory 1-Hour Cache Check
    ├── In-Flight Request Deduplication
    └── HTTP Request with OPENALEX_API_KEY (Exponential Backoff for 429s)
    │
    ▼
[ResultsView]
    ├── Display Supporting Scientific Papers (DOIs, Citations, Authors)
    │
    ▼ (User taps "Summarize")
[AISummaryService]
    └── Gemini 3.5 Flash Lite (Temp: 0.1, Grounded in Top 5 Abstracts)
        ├── Overview (Concise synthesis)
        ├── Key Findings (Attributed bullet points)
        └── Research Gaps (Identified limitations)
```

---

## Getting Started

### Prerequisites
- macOS 15.0 or later with **Xcode 26.0+** (Swift 6.0) installed
- Target platform: **iOS 26.0+** (Simulator or physical device compatible with Apple Intelligence)
- **XcodeGen** (`brew install xcodegen`)
- An OpenAlex API key (Optional; see judge note below)

> **Note for Hackathon Judges:**  
> Setting up an OpenAlex API key is completely **optional**. If `.env` is omitted or left with default placeholder values, Matéria automatically operates in anonymous access mode with standard public OpenAlex rate limits, allowing immediate literature searching without third-party account registration.

---

### Setup Instructions

#### Step 1: Clone the Repository
```bash
git clone https://github.com/Shivajith754/materia.git
cd materia
```

#### Step 2: Configure Environment Variables (Optional)
To use a custom OpenAlex API key with elevated rate limits:
```bash
cp .env.example .env
```
Open `.env` and add your key:
```bash
OPENALEX_API_KEY=your_key_here
```
*(If skipped or left with placeholder values, Matéria automatically falls back to anonymous OpenAlex requests.)*

#### Step 3: Firebase Configuration

You have two paths to evaluate the app:

##### Option A: Evaluate with Your Own Firebase Project (Recommended for Judges)
1. In the [Firebase Console](https://console.firebase.google.com/), click **Add project** (e.g., `materia-eval`).
2. Add an iOS app using bundle identifier **`com.materia.research.Materia`** (matches `project.yml`).
3. Enable the required Firebase services:
   - **Firebase AI Logic / Vertex AI in Firebase:** Navigate to **Build > AI Logic** (or Vertex AI in Firebase) in the left sidebar and click **Get started**. This enables the `firebasevertexai.googleapis.com` API in Google Cloud.
   - **Firebase App Check:** Navigate to **Build > App Check**, click **Get started**, select the registered iOS app, and ensure App Check is turned on.
4. Download the generated `GoogleService-Info.plist` and place it at:
   ```bash
   Materia/Resources/GoogleService-Info.plist
   ```

##### Option B: Evaluate with Pre-Bundled Demo Configuration
The repository includes a preconfigured `GoogleService-Info.plist` under `Materia/Resources/GoogleService-Info.plist` (project `materia-41c9d`). When using this configuration, proceed directly to Step 4.

#### Step 4: Generate the Xcode Project
Run `xcodegen` to construct `Materia.xcodeproj` with dependencies and build phases:
```bash
xcodegen generate
```

#### Step 5: Register App Check Debug Token (Required for Simulator Testing)
Firebase AI Logic enforces App Check attestation for cloud Gemini calls. Hardware attestation (DeviceCheck / App Attest) is unavailable in the iOS Simulator, so `FirebaseConfigurator.swift` enables `AppCheckDebugProviderFactory` in `DEBUG` builds.

To authorize your simulator in Firebase Console:
1. Open the project in Xcode:
   ```bash
   open Materia.xcodeproj
   ```
2. Select an iOS Simulator running iOS 26.0+ (e.g., **iPhone 16 Pro** or **iPhone 17**) and press **Cmd + R** to run.
3. In Xcode's bottom debug console, look for the dynamic App Check debug token printed by Firebase during launch:
   ```text
   [FirebaseAppCheck][I-FAA001001] Firebase App Check Debug Token:
   12345678-ABCD-EF01-2345-6789ABCDEF01
   ```
4. Open the [Firebase Console](https://console.firebase.google.com/) for your project and navigate to **Build** > **App Check** > **Apps**.
5. Click the three dots menu (`⋮`) next to the iOS app (`com.materia.research.Materia`) and select **Manage debug tokens**.
6. Click **Add debug token**, name it (e.g., `Judge Simulator`), paste the UUID from your Xcode console, and click **Save**.

*Once registered, cloud requests from your simulator will pass App Check verification without returning HTTP 403 Forbidden errors.*

#### Step 6: Test Search and AI Synthesis
1. In the search bar, type a materials science topic (e.g., `"chitosan hydrogel self-healing"` or `"graphene oxide nanofiltration"`).
2. Notice the instant on-device or cloud query suggestions appear below the search bar.
3. Tap a suggestion or press **Return** to query live literature via OpenAlex.
4. On the results page, tap **"Summarize Findings"** to generate an AI research brief synthesizing key metrics, supporting citations, and research gaps.

---

## How `.env` is Loaded & Distributed Build Security

Matéria provides a seamless local development experience while enforcing strict boundaries to ensure **no API keys are ever leaked into distributed builds**:

1. **Local Debug-Only Convenience:**
   - In `project.yml`, the post-build script (`Copy .env for Development`) copies `.env` into `${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/.env` **strictly when `CONFIGURATION == "Debug"`**.
   - This allows simulator and local debug devices to access local configuration without requiring developers to manually edit Xcode schemes.

2. **Distributed & Release Build Protection:**
   - **Post-Build Sanitation:** In non-Debug configurations (e.g., `Release`, `Archive`), the post-build script explicitly runs:
     ```bash
     rm -f "${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/.env"
     ```
     This guarantees no `.env` file can ever persist in a distributed application bundle.
   - **Compiler Elimination (`#if DEBUG`):** In `EnvironmentConfig.swift`, all `.env` disk and bundle traversal logic is enclosed in `#if DEBUG`. In release builds, the parsing routines are completely omitted from the compiled binary.
   - **Git Exclusion:** `.env` is ignored by `.gitignore` and is never committed to version control.
   - **Production Credential Model:** For production distributed deployments, configuration should be supplied via process environment variables, Xcode configuration settings, or secure server-side relays rather than local filesystem files.

3. **Multi-Tier Runtime Resolution:**
   `EnvironmentConfig.swift` reads configuration lazily and thread-safely in the following priority order:
   - **Process Environment:** `ProcessInfo.processInfo.environment["OPENALEX_API_KEY"]` (ideal for CI/CD runners or Xcode scheme overrides).
   - **Local `.env` File (`#if DEBUG`):** Traverses parent directories from `#filePath` up to the repository root, checks `PROJECT_DIR` and `SRCROOT`, checks the working directory, and checks app bundle resources.
   - **Info.plist:** Checks for compile-time bundle dictionary entries.
   - **UserDefaults:** Checks for runtime overrides under `OPENALEX_API_KEY`.

4. **Placeholder Detection & Anonymous Fallback:**
   If `.env` is absent or contains known placeholder values (such as `your_key_here` or `your_openalex_api_key_here`), `EnvironmentConfig.openAlexApiKey` safely returns `nil`. `OpenAlexService` then performs anonymous requests with informative logging instead of failing.

5. **Diagnostic Log Sanitization:**
   `sanitizedKeyPreview` redacts key contents to display only the trailing four characters (e.g., `••••abcd`), preventing sensitive tokens from leaking into system logs.

---

## Running the Automated Test Suites

Matéria includes automated test suites covering environment resolution, caching, rate-limit retries, and hybrid inference failover:

```bash
# 1. OpenAlex Engine & Authentication Tests (33 tests)
swiftc -parse-as-library -swift-version 6 -D DEBUG \
  Materia/Services/EnvironmentConfig.swift \
  Materia/Services/OpenAlexService.swift \
  Materia/Models/ScientificPaper.swift \
  Materia/Models/ResearchQuery.swift \
  Tests/TestOpenAlex.swift -o /tmp/openalex_test && /tmp/openalex_test

# 2. AI Research Summary Parsing Tests (8 tests)
swiftc -parse-as-library -swift-version 6 \
  Tests/TestSummaryParsing.swift -o /tmp/summary_test && /tmp/summary_test

# 3. Hybrid Inference & Cloud Fallback Tests (14 tests)
swiftc -parse-as-library -swift-version 6 \
  Tests/TestCloudFallback.swift -o /tmp/fallback_test && /tmp/fallback_test
```

---

## Security & Secrets Policy

- **No Hardcoded Keys:** Live API keys, private tokens, and credentials are never checked into Git.
- **Development-Only Local Environment:** Developer keys are loaded dynamically from `.env` in `Debug` builds only; distributed builds strictly exclude both `.env` files and file-parsing routines.
- **Hardware-Backed App Check:** Hardware-backed device attestation (`AppAttestProviderFactory`) is used in release builds; dynamic debug tokens are used in development.
- **Log Sanitization:** Sensitive tokens are automatically masked before writing to console logs.

---

## License

Copyright 2026 Shivajith J.

This project is open-source software licensed under the [Apache License, Version 2.0](LICENSE). See [NOTICE](NOTICE) for additional attribution details.
