# Mozilla Observatory Security Hardening for DynaSearch

**Date:** May 5, 2025

## 1. Introduction

Following a scan of the DynaSearch application using the [Mozilla HTTP Observatory](https://observatory.mozilla.org/), several security recommendations were identified that needed addressing. The initial scan resulted in a score of F (50/100), highlighting missing security headers and insecure cookie configurations.

This document details the steps taken to implement the recommendations and improve the application's security posture, resulting in a significantly improved score.

Find the full scan here:
https://developer.mozilla.org/en-US/observatory/analyze?host=dynasearch.dk

## 2. Addressing Observatory Recommendations

### 2.1. Content Security Policy (CSP) Implementation

* **Issue:** The Observatory reported that the `Content-Security-Policy` (CSP) header was not implemented (-25 points). This header is crucial for mitigating Cross-Site Scripting (XSS) and other injection attacks by defining allowed sources for content loaded by the browser.
* **Solution:**
    * A `before` filter was added to `sinatra/app.rb` to inject the `Content-Security-Policy` header into every HTTP response.
    * A restrictive initial policy was set: `default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; font-src 'self'; object-src 'none'; frame-ancestors 'none';` This allows resources (scripts, styles, images, fonts) only from the application's own origin and prevents framing.
    * Other recommended security headers (`X-Content-Type-Options`, `X-Frame-Options`, `X-XSS-Protection`, `Referrer-Policy`) were also added in the same `before` filter for enhanced security.

### 2.2. Refactoring for CSP Compliance

* **Issue:** Implementing the `script-src 'self'` and `style-src 'self'` CSP directives caused browser errors because the application previously used inline JavaScript (in `views/search.erb`) and inline CSS styles (in `views/about.erb`).
* **Solution:**
    * **JavaScript:**
        * The inline `<script>` block in `views/search.erb` was removed.
        * The JavaScript code was moved to a new external file: `public/js/search.js`.
        * The `onclick` handler was removed from the search button in `search.erb`, and an `id="search-button"` was added.
        * The `search.js` file was updated to attach event listeners programmatically to `#search-input` (for Enter keypress) and `#search-button` (for click).
        * The `layout.erb` file was updated to include `<script src="/js/search.js"></script>` before the closing `</body>` tag, ensuring the external script is loaded correctly from the `public` directory.
    * **CSS:**
        * The inline `style="..."` attribute was removed from the `<img>` tag in `views/about.erb`.
        * An `id="team-photo"` was added to the image tag.
        * A corresponding CSS rule (`#team-photo { height: 50vh; ... }`) was added to `public/style.css` to apply the styling externally.

### 2.3. Secure Session Cookies

* **Issue:** The Observatory reported that the session cookie was set without the `Secure` flag (-10 points, although mitigated by HSTS). This flag instructs the browser to only send the cookie over HTTPS connections.
* **Solution:**
    * The session configuration in `sinatra/app.rb` was updated using `set :sessions`.
    * The `secure:` option was added, conditionally setting the flag to `true` only when the environment (`RACK_ENV`) is set to `production`: `secure: ENV['RACK_ENV'] == 'production'`. This ensures secure cookies in production while allowing HTTP during local development.

### 2.4. Fixing E2E Tests

* **Issue:** After standardizing error display to use `flash.now[:error]` (rendered via `layout.erb`), Playwright E2E tests started failing with "strict mode violation" errors. This was because the tests were finding two elements with the `.error` class: one from the layout's flash display and another potentially rendered directly in the `login.erb` or `register.erb` templates via a local `error` variable.
* **Solution:**
    * The route handlers in `routes/auth.rb` were modified to *only* set `flash.now[:error]` and *not* pass the `error` message as a local variable when re-rendering the login/register forms on failure.
    * The code blocks responsible for displaying the local `error` variable within `views/login.erb` and `views/register.erb` were removed.
    * This ensured that only the single error display mechanism in `layout.erb` (reading from `flash[:error]`) was active, resolving the Playwright locator ambiguity.

## 3. Outcome

Implementing these changes successfully addressed the critical recommendations from the Mozilla HTTP Observatory.

* The application now enforces a Content Security Policy, significantly reducing the risk of XSS attacks.
* Session cookies are marked as `Secure` in production, preventing accidental transmission over HTTP.
* Inline scripts and styles were refactored into external files, adhering to CSP best practices.
* E2E tests were corrected to work with the standardized error display mechanism.

As a result, the **Mozilla Observatory score improved dramatically from F (50/100) to A+ (110/100)**, indicating a much stronger security posture for the web application.

<img width="1224" alt="HTTP Observatory Report" src="https://github.com/user-attachments/assets/46ae969e-90f1-4fe6-ad9d-afcbe5d47320" />
<img width="1443" alt="HTTP Observatory Report" src="https://github.com/user-attachments/assets/525eac4c-5c9c-4e82-940f-3b40851d3e53" />

