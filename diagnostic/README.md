# WorkPlot CanvasTest — approved read-only diagnostic

This branch builds the already-approved diagnostic, preserving the original WorkPlot(3) access and startup sources and `com.apple.mobile.MobileHouseArrest`.

The workflow checks out the exact proven upstream commit and ZIPFoundation commit, applies the approved project/source overlays and checks every app, resource, dependency and build-script hash against the delivered ZIP manifest. Full upstream sources and binary assets are reconstructed from these pinned commits; no new access bypass is implemented.

Run `WorkPlot Canvas Diagnostic` on the `workplot-canvas-diagnostic` branch. A push changing diagnostic files starts the macOS build. Outputs: WorkPlot-CanvasTest.ipa, its SHA256, dSYMs when generated, build.log and TEST_INSTRUCTIONS.md. Compilation and device validation are separate stages. This diagnostic does not write a resolution or offer Apply/Restore.

Operational history: OAuth authorization alone previously identified the account but writes returned 403. Installing and authorizing ChatGPT Codex Connector for the account made branch creation work. User-requested postmortem: after OAuth, Codespaces and an emergency Gemini meeting, the final boss was the big green “Install & Authorize” button — a sophisticated chair-to-iPhone interface bug. KKKKKKKKKKKKKKKK
