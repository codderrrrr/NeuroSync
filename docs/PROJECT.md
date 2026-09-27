# NeuroSync

NeuroSync is a longitudinal Parkinson's motor-monitoring and care-coordination platform.

## Core purpose

Collect standardized home motor tests and contextual information, establish a patient-specific baseline, detect meaningful longitudinal changes, and route evidence-backed exceptions to the appropriate care-team member.

## MVP journey

Doctor enrolls patient
→ Doctor creates monitoring plan
→ Patient receives test
→ Patient performs finger-tapping test
→ System validates quality
→ System extracts motor features
→ Medication context is attached
→ Patient baseline is updated
→ Longitudinal change is detected
→ Relevant exception is created
→ Doctor reviews evidence-backed patient brief

## MVP roles

- Patient
- Caregiver
- Health worker
- Doctor

## MVP capabilities

- Authentication and authorization
- Patient enrollment and care-team relationships
- Monitoring plans
- Medication schedule and medication events
- Finger-tapping assessment
- Test quality assessment
- Motor feature extraction
- Patient-specific baseline
- Longitudinal change detection
- Exception routing
- Doctor review

## Explicitly out of scope for MVP

- Diagnosis
- Disease staging
- Medication prescribing
- Dosage recommendations
- Autonomous treatment decisions
- Billing
- Complex interoperability
- Microservices
- Kubernetes
- Multi-region infrastructure
- Advanced analytics
- All motor tests beyond what is required for the MVP

## Product principle

NeuroSync is observational clinical decision support.

Clinical interpretation must remain evidence-backed, explainable, quality-aware, medication-context-aware, and explicit about limitations.
