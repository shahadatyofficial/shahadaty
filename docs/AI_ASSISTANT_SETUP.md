# Shahadaty AI Assistant

## Deployment

The authenticated Supabase Edge Function is:

- Name: `shahadaty-ai-assistant`
- JWT verification: enabled
- Tasks: `job_ad` for an approved company account, and `career_plan` for a signed-in graduate profile.
- API: OpenAI Responses API, called only from the Edge Function.
- Default model: `gpt-5.5`; override with `OPENAI_MODEL`.

## Required secret

Set `OPENAI_API_KEY` in **Supabase Dashboard → Project Settings → Edge Functions → Secrets**. Never put this key in HTML, JavaScript, GitHub, or the Android app.

Optional secret:
- `OPENAI_MODEL`: model identifier enabled for the OpenAI API project. If omitted, the function uses `gpt-5.5`.

Until `OPENAI_API_KEY` is configured, the UI reports that the assistant is not configured. The function does not fall back to a fake or hard-coded answer.

## Privacy and safeguards

- The browser sends only the task context required for the requested output.
- The function checks the signed-in user and the relevant employer/graduate account.
- Email addresses, Egyptian-style phone numbers, and 14-digit identity numbers are redacted before provider submission.
- The Responses API request uses `store: false`.
- AI output is advisory. It must not certify qualifications, guarantee employment, or make automated hiring decisions.
- No OpenAI key or service-role key is exposed to the browser.

## Current scope

1. Employer: improve the wording and structure of a job advertisement.
2. Graduate: produce a practical career-development plan based on the stated goal and available profile context.

Candidate discovery currently uses the platform's consent-filtered employer search and the transparent rule-based job-fit hints shown in the graduate portal. A model-based ranking of people is intentionally not enabled.
