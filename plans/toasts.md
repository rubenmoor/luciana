# toasts.md

Status: implemented

Transient user-facing messages shown in a corner of the viewport:
green for success ("Logged in", "Logged out", "Account created"), red
for unexpected failures ("Server error", "Bad request", "Too many
attempts — try again later"). Auto-dismiss after a few seconds.

Naming: "toast" matches the DaisyUI class (`toast`, `alert`) and avoids
collision with push notifications (`Backend.Schema.NotificationPref`,
`NotificationsRoute`), which are an unrelated feature.

## Scope

In v1:

- A `Toast` sum type with two cases — success (just a message) and
  error (a message plus optional technical JSON).
- A global toast renderer in the top-level `Frontend.hs` body.
- Reflex `EventWriter` so any widget anywhere in the tree can fire a
  toast without plumbing events through return types.
- Auto-dismiss timer per toast; multiple toasts stack.
- Locale-aware messages: a closed `ToastMsg` enum is translated to
  `Text` at render time using the user's current `Locale`. See
  [Internationalisation](#internationalisation).
- Error toasts carry optional `Aeson.Value` diagnostics (status code,
  endpoint, response body) hidden behind a toggle. See [Technical
  details on error toasts](#technical-details-on-error-toasts).

Deferred:

- I18n for inline form errors (the existing red text under login /
  signup). Toast i18n is the v1 scope; form errors stay hard-coded
  English until we revisit them in their own pass — at which point
  `Common.I18n` will likely grow a generic message catalog that both
  toasts and form errors share.
- Severity beyond two levels (`Info`, `Warning`). Add when a concrete
  caller needs it; YAGNI for now.
- Programmatic deduplication / rate-limiting of identical messages.

## Toast type and writer

`frontend/src/Frontend/Toast.hs`:

```haskell
-- Closed enum of every toast string the app can show. Translated to
-- Text at render time. See § Internationalisation.
data ToastMsg
  = MsgLoggedIn
  | MsgLoggedOut
  | MsgAccountCreated
  | MsgServerError
  | MsgBadRequest
  | MsgRateLimited
  | MsgNetworkError
  deriving stock (Eq, Show)

-- Two-case sum: success carries only a message; error optionally
-- carries arbitrary diagnostic JSON (status code, endpoint, response
-- body) shown behind a "Details" toggle. The shape of the Value is
-- not schema-checked — it is for the user to read, not for the app
-- to process.
data Toast
  = ToastSuccess ToastMsg
  | ToastError   ToastMsg (Maybe Aeson.Value)
  deriving stock (Eq, Show)

-- A widget that wants to fire toasts asks for an EventWriter constraint.
tellToast
  :: (Reflex t, EventWriter t [Toast] m)
  => Event t Toast
  -> m ()
tellToast = tellEvent . fmap (:[])
```

Splitting into `ToastSuccess` / `ToastError` (rather than a `Severity`
field plus an always-present `Maybe Value`) makes it impossible to
attach diagnostics to a success toast — there is nothing useful to
say about a "Logged in" event.

We use `[Toast]` (not just `Toast`) so simultaneous events on the same
frame merge by concatenation rather than dropping one — the
`Semigroup`-based merge that `EventWriter` requires.

Call sites never produce `Text` — they pick a `ToastMsg` constructor.
This means GHC catches missing translations as soon as a new
constructor is added (see translation function below).

## Wiring at the root

`frontend/src/Frontend.hs`'s `_frontend_body` wraps its existing `mdo`
in `runEventWriterT`. The collected `Event t [Toast]` feeds the
renderer, which is rendered after the routed content so it overlays
the page in DOM order. The renderer also takes the current locale as
a `Dynamic` (see [Internationalisation](#internationalisation)):

```haskell
, _frontend_body = prerender_ blank $ do
    (authStateD, toastsEv) <- mapRoutedT runEventWriterT $ mdo
      …existing body…  -- produces authStateD
      tellToast (ToastSuccess MsgLoggedOut <$ logoutDoneEv)
      pure authStateD
    let userLocaleD = ffor authStateD $ \case
          AuthSignedIn u -> Just (urLocale u)
          _              -> Nothing
    localeD <- toastLocale userLocaleD
    renderToasts localeD toastsEv
```

`mapRoutedT runEventWriterT` (from `Obelisk.Route.Frontend`) is the
piece that lets us interpose `EventWriterT` *under* `RoutedT` so
`subRoute` keeps typechecking — `subRoute` returns `RoutedT t (R r) m
a`, so `RoutedT` must remain the outer transformer of the inner
block.

`renderToasts :: Dynamic t Locale -> Event t [Toast] -> m ()` lives in
`Frontend.Toast`. `toastLocale :: Dynamic t (Maybe Locale) -> m
(Dynamic t Locale)` lives there too — it does *not* know about
`AuthState` (avoids a cycle with `Frontend.Auth`); the caller in
`Frontend.hs` derives the user's preferred locale from `authStateD`
before handing it in.

## Renderer

DaisyUI provides `toast` (a fixed-position container) and `alert
alert-success` / `alert alert-error` for the individual cards. The
renderer keeps a `Dynamic t (Map Int Toast)` of currently-visible
toasts, keyed by an incrementing id; new toasts insert, expired ones
delete.

Each toast leads with an icon so the severity is recognisable at a
glance, before the message reads. The icon takes its colour from the
surrounding alert (DaisyUI's `alert-success` / `alert-error` set
`currentColor` on text and inline SVG alike), and DaisyUI's `.alert`
flex layout handles the gap between icon and text.

Success toasts: leading checkmark, message text:

```html
<div class="alert alert-success">
  <svg …><!-- iconCheckCircle --></svg>
  <span>Logged in</span>
</div>
```

Error toasts add a leading warning triangle, and — when diagnostics
are present — a `<details>` block plus a close button (✕):

```html
<div class="alert alert-error">
  <svg …><!-- iconExclamationTriangle --></svg>
  <span>Server error</span>
  <details>
    <summary class="cursor-pointer text-xs opacity-70">Details</summary>
    <pre class="text-xs mt-1 whitespace-pre-wrap break-all">{
  "status": 500,
  "url": "/api/auth/login",
  "body": "Internal Server Error"
}</pre>
  </details>
  <button class="btn btn-ghost btn-xs btn-circle" aria-label="Close">✕</button>
</div>
```

The two new icons live in `Frontend.Widget.Icon` alongside the
existing button icons, following the same Heroicons-outline pattern:

- `iconCheckCircle` — circled check, used inside `alert-success`.
- `iconExclamationTriangle` — warning triangle, used inside
  `alert-error`.

They share the existing `outlineIcon` helper (so they pick up the
default `size-5` sizing). Keeping the icons in the shared module
matches the rest of the codebase (one icon per function, only
referenced ones end up in the bundle) and keeps `Frontend.Toast`
free of inline SVG path data.

Auto-dismiss timing:

- `ToastSuccess`: removed after 4s.
- `ToastError` (collapsed): removed after 8s. Errors live longer so
  the user has time to notice and decide to inspect.
- `ToastError` (details opened): timer is cancelled. The user has
  signalled they want to read it; only the close button removes the
  toast at that point.

The cancel-on-open behaviour is the reason error toasts get a manual
close button while success toasts do not — once the timer is gone,
something else has to remove the card.

Implementation: each toast holds an internal "open" `Dynamic t Bool`
fed by clicks on its `<summary>`. The dismiss event is a `delay`
gated on `not open`, plus the close button's click event.

If the map ever exceeds, say, 5 entries, drop the oldest. Cheap
insurance against floods. Toasts with details opened are exempt from
this drop — explicit user attention beats LRU. **Deferred**: the v1
implementation does not enforce a cap; add it the first time we see
a flood in practice.

The text inside each `<div class="alert …">` is `translateToast loc
msg` (see § Internationalisation), where `loc` is sampled from the
locale `Dynamic` at the moment the toast is inserted. We sample once
on insert rather than re-rendering on locale change — a toast that
appeared mid-flight should stay in its original language for its short
lifetime; the next toast picks up the new locale.

## Technical details on error toasts

`ToastError` carries an optional `Aeson.Value` whose shape is
defined by the producer, not enforced by the type. The convention
the auth decoders follow:

```json
{
  "status": 429,
  "url":    "/api/auth/login",
  "method": "POST",
  "body":   "<parsed JSON or raw text>"
}
```

If the response body parses as JSON, embed the parsed value (so the
expanded view shows nested structure, not an escaped string). If it
does not, embed the raw text. If there was no response at all
(network failure / connection refused), pass `Nothing` — the
`<details>` block is then omitted entirely.

Pretty-printing is deferred. The current implementation uses
`Data.Aeson.encode` (compact single-line JSON) inside the `<pre>`
block; the wrapping CSS still presents it readably. The `aeson-pretty`
package is in the pinned set at 0.8.9, but its GHCJS Setup binary
fails to load `libgmp.so.10` in this dev shell. Wire it back in once
that's resolved (likely via a `default.nix` override that pins a
different `aeson-pretty` build, or by switching to a build that does
not invoke a host Setup). Until then, `prettyJson` lives in
`Frontend.Toast` as a single-line helper.

Why arbitrary `Aeson.Value` and not a typed `Diagnostic` record:
the v1 producers (auth decoders) all use the shape above, but
diagnostics for future error sources (push subscription failure, DB
write failure surfaced through a different path) may want different
fields. Keeping the type open avoids forcing every error-emitting
site through one schema.

Privacy: do not put request *bodies* (passwords!) into diagnostics.
The status / URL / response body are safe; the request payload is
not. The auth decoders here only have the response in scope, which is
fine, but future producers must keep this in mind.

## Internationalisation

The translation table is a single function in `Frontend.Toast`:

```haskell
translateToast :: Locale -> ToastMsg -> Text
translateToast = \case
  LocaleEn -> \case
    MsgLoggedIn        -> "Logged in"
    MsgLoggedOut       -> "Logged out"
    MsgAccountCreated  -> "Account created"
    MsgServerError     -> "Server error"
    MsgBadRequest      -> "Bad request"
    MsgRateLimited     -> "Too many attempts — try again later"
    MsgNetworkError    -> "Network error"
  LocaleDe -> \case
    MsgLoggedIn        -> "Angemeldet"
    MsgLoggedOut       -> "Abgemeldet"
    MsgAccountCreated  -> "Konto erstellt"
    MsgServerError     -> "Serverfehler"
    MsgBadRequest      -> "Ungültige Anfrage"
    MsgRateLimited     -> "Zu viele Versuche — bitte später erneut"
    MsgNetworkError    -> "Netzwerkfehler"
```

Two nested `\case` (no catch-all) means GHC's
`-Wincomplete-patterns` flags any new `Locale` *or* new `ToastMsg`
constructor that lacks a translation. That is the entire reason
`ToastMsg` is a closed enum rather than `Text`.

### Locale source

`toastLocale :: Dynamic t AuthState -> m (Dynamic t Locale)` resolves
the active locale for the renderer:

- `AuthSignedIn u` → `urLocale u`. The user's stored preference wins
  whenever we know who they are.
- `AuthAnon` / `AuthLoading` → fall back to the browser via
  `navigator.language`, parsed by a small JS shim into `Locale`
  (only `de` / `en` recognised; anything else → `LocaleEn`).

```haskell
-- In Frontend.Toast
getBrowserLocale :: MonadJSM m => m Locale
getBrowserLocale = liftJSM $ do
  v <- eval ("(navigator.language || 'en').slice(0, 2)" :: Text)
  s <- fromJSValUnchecked v
  pure (fromMaybe LocaleEn (localeFromText s))
```

The browser locale is read once at startup (in the
`prerender_`-ed body) and held in a `Dynamic`; signed-in users'
preferences override it from `authStateD`.

### Why a closed enum and not just `Text`

We considered three shapes:

1. `tMessage :: Text` with translation done at the call site — easy
   but no exhaustiveness check; adding `LocaleDe` later silently
   leaves English strings in place.
2. `tMessage :: Locale -> Text` (a function) — exhaustiveness still
   not checked, and the call site has to know every locale.
3. `tMessage :: ToastMsg` (this plan) — closed enum, single central
   table, GHC enforces coverage.

Option 3 wins on the dimension that matters: when we add a third
locale or a new toast string, the compiler tells us exactly what is
missing.

## Sources of toasts (call sites)

- `Frontend.Login.page`: on the success event from `performLogin`,
  `tellToast (ToastSuccess MsgLoggedIn <$ okEv)`.
- `Frontend.Signup.page`: on register success → `ToastSuccess
  MsgAccountCreated`.
- `Frontend.Frontend.frontend` topBar logout flow: on `logoutDoneEv`,
  fire `ToastSuccess MsgLoggedOut`.
- `Frontend.Auth.decodeLogin` / `decodeRegister`: the `Left` branches
  become toasts *only for HTTP-layer failures*. The unexpected branch
  carries a `ToastMsg` *and* the optional diagnostic JSON:

```haskell
performLogin    :: … => Event t LoginRequest    -> m (Event t (Either LoginError UserResponse))
performRegister :: … => Event t RegisterRequest -> m (Event t (Either RegisterError UserResponse))

data LoginError    = LoginInvalid    | LoginUnexpected ToastMsg (Maybe Aeson.Value)
data RegisterError = RegisterTaken   | RegisterUnexpected ToastMsg (Maybe Aeson.Value)
```

The decoder picks the right `ToastMsg` from the response status and
builds the diagnostic `Value` from the response:

| Condition | `ToastMsg` | Diagnostic |
|---|---|---|
| status `429` | `MsgRateLimited` | `Just {status, url, method, body}` |
| status `400` | `MsgBadRequest` | `Just {status, url, method, body}` |
| status `5xx` | `MsgServerError` | `Just {status, url, method, body}` |
| no response / decode failure | `MsgNetworkError` | `Nothing` (or status 0 + url, if useful) |

The page widgets pattern-match: `*Invalid` / `*Taken` stay as inline
form errors (existing hard-coded English red text under the form);
`*Unexpected msg mDetails` becomes `tellToast (ToastError msg mDetails
<$ ...)`. This keeps form-level validation feedback adjacent to the
field that caused it, while making genuinely unexpected conditions
visible — and inspectable — from anywhere on the page.

## Inline form errors vs. toasts — when to use which

Inline error text under the form (existing `text-error text-sm mt-2`):

- The user can fix it by changing what they typed: invalid credentials,
  username already taken, password too short.

Toast (red `alert-error`):

- The user cannot fix it from the form: rate limit, server error, bad
  request from a malformed JSON body the user did not type, network
  failure.

Toast (green `alert-success`):

- A successful action whose effect happens elsewhere (route change,
  state flip) — without a toast the user has no immediate confirmation.

## Module layout

```
frontend/src/Frontend/
└── Toast.hs    -- ToastMsg, Toast, tellToast,
                   translateToast, getBrowserLocale, toastLocale,
                   renderToasts
```

Updates:

- `Frontend.hs`: wrap body in `runEventWriterT`, derive `localeD` via
  `toastLocale authStateD`, render toasts.
- `Frontend.Login`, `Frontend.Signup`: `tellToast` on success, and on
  the unexpected-error branch.
- `Frontend.Auth`: split `Either Text UserResponse` into the
  `LoginError` / `RegisterError` shapes above; emit toasts from the
  unexpected branch in callers.

## Verification

- `nix-build -A ghcjs.frontend --no-out-link` clean.
- `ob run`, browser smoke (English, the default fallback):
  - Successful login → green "Logged in" toast bottom-right, fades after
    ~4s. No close button, no Details.
  - Successful logout → green "Logged out" toast.
  - Invalid login → inline red error under the form, **no** toast.
  - Trigger a 429 by spamming login → red "Too many attempts" toast
    with a Details disclosure and a ✕ close button. Expanded JSON
    contains `"status": 429` and `"url": "/api/auth/login"`. **No**
    inline error.
  - Click Details on the 429 toast → it stops auto-dismissing; ✕
    removes it. Reload, repeat without clicking → it auto-dismisses
    after ~8s.
  - Stop the backend and submit login → red "Network error" toast,
    **no** Details disclosure (diagnostics absent for the
    no-response case).
  - Multiple consecutive triggers stack vertically and each dismisses
    on its own timer; opening Details on one does not affect the
    others' timers.
- I18n smoke:
  - Set `navigator.language` to `de` (DevTools → Sensors / Settings →
    Language) and reload the login page; trigger a 429 → toast text is
    "Zu viele Versuche — bitte später erneut".
  - Sign in as a user whose `users.locale = 'de'`; trigger logout →
    "Abgemeldet" (the signed-in user's stored preference overrides the
    browser locale).
