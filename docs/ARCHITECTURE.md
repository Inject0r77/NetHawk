# NetHawk architecture

NetHawk is a Windows orchestration layer around the \`zapret\` / \`winws\` runtime and WinDivert.

It is an independent derivative project based substantially on operational work from Flowseal/zapret-discord-youtube, which itself is built around bol-van/zapret.

## Layers

1. **Runtime** — upstream \`winws\` and WinDivert.
2. **Upstream profiles** — synchronized General / ALT / EXP / FAKE strategy definitions.
3. **Data** — hostlists, IP sets, user-owned lists, fake payloads.
4. **NetHawk parser** — reads a strategy as data and produces effective \`winws\` arguments.
5. **Execution** — standalone launch, Windows service, tester, diagnostics.
6. **Validation** — Windows CI parses every profile and verifies referenced resources.
7. **Customization** — planned user overrides, custom TCP/UDP ports, raw extra args and adaptive profiles.

## One strategy path

\`\`\`text
upstream profile
      │
      ▼
NetHawk parser
      │
      ▼
effective arguments
 ┌────┼──────┬────────┐
 ▼    ▼      ▼        ▼
run  service tester self-test
\`\`\`

Manual and service execution should not maintain separate copies of the same strategy.

## Upstream boundary

NetHawk does not claim authorship of:

- \`winws\`;
- zapret DPI-desynchronization techniques;
- WinDivert;
- Flowseal-origin profiles, lists or fake payload resources.

Those components remain attributed to their respective projects.

NetHawk-specific work lives above that layer: orchestration, configuration, validation, service integration and future adaptive/custom-profile features.

## Pinned synchronization

The 0.2 development line pins Flowseal profile/resource synchronization to:

\`\`\`text
249a70424aae2676f99c5363e21073ed89873eda
\`\`\`

This separates a released NetHawk build from future upstream changes unless the pin is intentionally advanced.
