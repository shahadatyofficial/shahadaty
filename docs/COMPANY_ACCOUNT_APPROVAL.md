# Company account approval and login

## Administrative approval

Company registrations create a Supabase Auth account and a company record with `status = pending`. A pending company cannot use the employer portal.

In the Admin dashboard, open **الشركات المشتركة** and use **اعتماد وربط الدخول**. The admin-only `company-admin-approval` Edge Function:

- Requires a valid signed-in platform administrator.
- Matches the company record to the existing Auth account by the registered email.
- Confirms the email after the administrator has reviewed the company.
- Links the Auth user to the company and changes the company status to `approved`.
- Stores the normalized Egyptian phone number on the company record; it does not depend on Supabase Phone Auth.

The service-role key is used only inside the Edge Function and is never exposed to the browser.

## Phone and password login without SMS

The company portal accepts either the registered email or an Egyptian mobile number plus the same password.

Phone login uses the `company-phone-login` Edge Function. It looks up an approved company by its registered phone number, resolves the linked Auth account on the server, and verifies the password through Supabase Auth. It returns the normal Auth session to the browser only after the password is valid. The email address is never sent back as part of the phone lookup.

**Do not enable the Supabase Phone provider and do not configure Twilio for this flow.** SMS OTP is not used. Email/password login remains unchanged.

Phone numbers are normalized to Egypt's E.164 format (+20). Supported Egyptian mobile prefixes are 010, 011, 012, and 015.

The public login function uses a generic failure response for unknown, pending, suspended, or invalid-password attempts, and applies a best-effort per-worker throttle in addition to Supabase Auth's own password sign-in limits.

## Important

Email confirmation performed by the admin approval function represents the platform's manual verification decision. Administrators must verify the company's ownership and contact channels before approving the account. Manual phone review is not equivalent to an SMS/OTP ownership check.
