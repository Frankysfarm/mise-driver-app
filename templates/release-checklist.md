# Release Checklist: <Version>

## Scope

- Commits/PRs:
- Flows:
- Feature Flags:
- DB-Migrationen:
- Mindest-App-Version:

## Hard Blockers

- [ ] keine offenen P0/P1
- [ ] keine Duplicate-Assignment-Invariante verletzt
- [ ] keine Order-Loss-/Stuck-Lücke
- [ ] keine Secrets/PII-Leaks
- [ ] kein kritischer Test flaky/rot
- [ ] manueller Override und Fallback vorhanden

## Verification

- [ ] Unit
- [ ] Contract
- [ ] Integration
- [ ] E2E
- [ ] Mobile Device Matrix
- [ ] Dispatch Replay
- [ ] Failure Injection
- [ ] Performance/Load
- [ ] Security/Privacy
- [ ] Accessibility/UX kritische Flows

## Operations

- [ ] Dashboard
- [ ] Alerts
- [ ] Runbooks
- [ ] Correlation/Audit
- [ ] On-call/Supervisor
- [ ] Rollback geprüft

## Progressive Delivery

- Shadow Ergebnis:
- Canary-Größe:
- Guardrails:
- Stop-Kriterien:
- Beobachtungszeitraum:

## Verdict

`GO | LIMITED_GO | NO_GO`

- Gatekeeper:
- menschliche Freigabe:
- Zeitpunkt UTC:
- offene akzeptierte Risiken:
