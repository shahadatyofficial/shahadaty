# Company account approval and login

## Administrative approval

Company registrations create a Supabase Auth account and a company record with `status = pending`. A pending company cannot use the employer portal.

In the Admin dashboard, open **الشركات المشتركة** and use **اعتماد وربط الدخول**. The admin-only `company-admin-approval` Edge Function:

- Requires a valid signed-in platform administrator.
- Matches the company record to the existing Auth account by the registered email.
- Confirms the email and registered phone after the administrator has reviewed the company.
- Links the Auth user to the company and changes the company status to `approved`.

The service-role key is used only inside the Edge Function and is never exposed to the browser.

## Phone and password login

The company portal accepts either the registered email or an Egyptian mobile number plus the same password.

Enable **Phone** under Supabase Dashboard → Authentication → Sign In / Providers. SMS delivery is not used by this password sign-in flow because the administrator confirms the phone during manual company approval. Use MFA for accounts where additional protection is required.

Phone numbers are normalized to E.164 with the Egypt country code (+20). Supported Egyptian mobile prefixes are 010, 011, 012, and 015.

## Important

Email and phone confirmation performed by the admin approval function represents the platform's manual verification decision. Administrators should verify the company's ownership and contact channels before approving the account.
