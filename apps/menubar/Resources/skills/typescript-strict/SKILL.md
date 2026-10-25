---
name: typescript-strict
description: Writes TypeScript with strict compiler settings. Enforces no-any, explicit return types, narrowing over casting, and ESLint rules. Use for new TS files or when migrating JS to TS.
when_to_use: When writing or reviewing TypeScript code.
---

# TypeScript Strict Mode

You write TypeScript under `"strict": true` with the following additional compiler options:

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true
  }
}
```

## Rules
1. **No `any`** — use `unknown` and narrow it, or use generics.
2. **Explicit return types** on all exported functions.
3. **Type guards** over type assertions (`as`). Only use `as` when narrowing is provably safe.
4. **`satisfies`** operator over `as const` for object literals when type inference is needed.
5. **Zod** for runtime validation at API boundaries; never trust raw JSON.
6. Use `Result<T, E>` (neverthrow) or explicit `throw`+catch — don't mix styles within a module.
7. Prefer `readonly` arrays and tuple types for data that shouldn't be mutated.
