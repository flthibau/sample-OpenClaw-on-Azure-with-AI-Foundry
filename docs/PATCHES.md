# OpenClaw Patches

Patches applied to the OpenClaw runtime (`/usr/lib/node_modules/openclaw/dist/`) to enable features not yet in the upstream schema.

> ⚠️ These patches will be lost on `npm update -g openclaw`. Re-apply after upgrades or check if upstream has merged the changes.

---

## 1. Azure Responses Web Search Provider (2026-02-12)

**Problem:** OpenClaw `web-search.js` supports `azure-responses` as a search provider (Bing grounding via Azure OpenAI), but the Zod config schema only allows `brave` and `perplexity`.

**Files patched:**

### `dist/config/zod-schema.agent-runtime.js`

**Change 1 — Provider enum:** Added `azure-responses`, `azure_responses`, `azure` to the provider union:

```diff
- provider: z.union([z.literal("brave"), z.literal("perplexity")]).optional(),
+ provider: z.union([z.literal("brave"), z.literal("perplexity"), z.literal("azure-responses"), z.literal("azure_responses"), z.literal("azure")]).optional(),
```

**Change 2 — azureResponses sub-object:** Added after the `perplexity` block:

```js
    azureResponses: z
        .object({
        apiKey: z.string().optional(),
        baseUrl: z.string().optional(),
        apiVersion: z.string().optional(),
        model: z.string().optional(),
    })
        .strict()
        .optional(),
```

### `dist/agents/tools/web-search.js`

**Change — Country code validation:** The LLM sometimes sends `country: "ALL"` which is not a valid ISO 3166-1 code and causes a 400 error from the Azure Responses API.

```diff
-    if (params.country) {
-        tool.user_location = { type: "approximate", country: params.country };
-    }
+    if (params.country && params.country.toUpperCase() !== "ALL" && /^[A-Z]{2}$/i.test(params.country)) {
+        tool.user_location = { type: "approximate", country: params.country.toUpperCase() };
+    }
```

**Backup files:** `.bak` copies created alongside each patched file.

---

## Re-apply Script

```bash
# After upgrading openclaw, re-apply patches:
cd /usr/lib/node_modules/openclaw/dist

# 1. Schema: add azure-responses provider
sudo sed -i 's/provider: z.union(\[z.literal("brave"), z.literal("perplexity")\]).optional(),/provider: z.union([z.literal("brave"), z.literal("perplexity"), z.literal("azure-responses"), z.literal("azure_responses"), z.literal("azure")]).optional(),/' config/zod-schema.agent-runtime.js

# 2. Schema: add azureResponses object (use the Python patch script from session)

# 3. web-search.js: country code validation
sudo sed -i 's/if (params.country) {/if (params.country \&\& params.country.toUpperCase() !== "ALL" \&\& \/^[A-Z]{2}$\/i.test(params.country)) {/' agents/tools/web-search.js
sudo sed -i 's/tool.user_location = { type: "approximate", country: params.country };/tool.user_location = { type: "approximate", country: params.country.toUpperCase() };/' agents/tools/web-search.js
```
