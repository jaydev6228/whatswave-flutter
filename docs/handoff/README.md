# Handoff Bundle

This folder is the transfer package for moving the WhatsWave Flutter project to another machine, another developer, or another AI tool.

If you need the fastest single entry point, start with:

- `../../TRANSFER_TO_NEW_PC.md`

Read these files in this order:

1. [01_project_state.md](./01_project_state.md)
2. [02_machine_setup.md](./02_machine_setup.md)
3. [05_development_guardrails.md](./05_development_guardrails.md)
4. [06_testing_and_qa.md](./06_testing_and_qa.md)
5. [03_firebase_dev_setup.md](./03_firebase_dev_setup.md)
6. [04_aws_path.md](./04_aws_path.md)
7. [07_agent_resume_brief.md](./07_agent_resume_brief.md)
8. [08_local_status_media_slice.md](./08_local_status_media_slice.md)

Existing project docs that still matter:

- [../architecture.md](../architecture.md)
- [../roadmap.md](../roadmap.md)
- [../backend_integration_plan.md](../backend_integration_plan.md)
- [../calling_strategy.md](../calling_strategy.md)
- [../test_strategy.md](../test_strategy.md)
- [../release_readiness.md](../release_readiness.md)
- [../implementation_updates_2026-06-03.md](../implementation_updates_2026-06-03.md)

## Quick facts

- Active project folder: `outputs/whatswave_flutter`
- This Flutter project is intentionally separate from the older native Swift iOS project
- Default runtime backend mode is local seeded data
- Firebase and AWS work are scaffolded but not live
- This PC could not be used to create a Firebase project because of local machine policy and protocol limits
- Current temporary app identifiers are already set and can be reused for development:
  - iOS bundle ID: `com.tsjaydevra.whatswave`
  - Android application ID: `com.tsjaydevra.whatswave`

## Recommended resume flow

1. Get the project running on a new machine.
2. Run `flutter analyze` and `flutter test`.
3. Launch on one iOS simulator and one Android emulator.
4. Read the development guardrails before changing UI or backend seams.
5. If backend work is next, read the Firebase handoff before adding packages or config files.
6. If another AI is taking over, start with the prompt in [07_agent_resume_brief.md](./07_agent_resume_brief.md).
