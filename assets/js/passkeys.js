// Base64url helpers
function base64urlEncode(buffer) {
  const bytes = new Uint8Array(buffer)
  let str = ""
  for (const b of bytes) str += String.fromCharCode(b)
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

function base64urlDecode(str) {
  str = str.replace(/-/g, "+").replace(/_/g, "/")
  while (str.length % 4) str += "="
  const binary = atob(str)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}

function getCsrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
}

// Fetch a JSON endpoint with CSRF
async function jsonPost(url, body = {}) {
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-csrf-token": getCsrfToken(),
    },
    body: JSON.stringify(body),
  })
  if (!resp.ok) {
    const text = await resp.text()
    throw new Error(`Request failed (${resp.status}): ${text}`)
  }
  return resp.json()
}

// Start an authentication ceremony and return the serialized assertion
async function doAuthentication(options) {
  options.challenge = base64urlDecode(options.challenge)

  if (options.allowCredentials) {
    options.allowCredentials = options.allowCredentials.map((c) => ({
      ...c,
      id: base64urlDecode(c.id),
    }))
  }

  const assertion = await navigator.credentials.get({ publicKey: options })

  return {
    rawId: base64urlEncode(assertion.rawId),
    type: assertion.type,
    authenticatorData: base64urlEncode(assertion.response.authenticatorData),
    clientDataJSON: base64urlEncode(assertion.response.clientDataJSON),
    signature: base64urlEncode(assertion.response.signature),
    userHandle: assertion.response.userHandle
      ? base64urlEncode(assertion.response.userHandle)
      : null,
  }
}

// Start a registration ceremony and return the serialized attestation
async function doRegistration(options) {
  options.challenge = base64urlDecode(options.challenge)
  options.user.id = base64urlDecode(options.user.id)

  if (options.excludeCredentials) {
    options.excludeCredentials = options.excludeCredentials.map((c) => ({
      ...c,
      id: base64urlDecode(c.id),
    }))
  }

  const credential = await navigator.credentials.create({ publicKey: options })

  return {
    rawId: base64urlEncode(credential.rawId),
    type: credential.type,
    clientDataJSON: base64urlEncode(credential.response.clientDataJSON),
    attestationObject: base64urlEncode(credential.response.attestationObject),
    transports: credential.response.getTransports ? credential.response.getTransports() : [],
  }
}

function isWebAuthnAvailable() {
  return !!window.PublicKeyCredential
}

// Initialize passkey login buttons on the login page (dead view)
export function initPasskeyLogin() {
  if (!isWebAuthnAvailable()) {
    document
      .querySelectorAll('[data-passkey-login], [data-reauth]')
      .forEach((btn) => {
        btn.disabled = true
        btn.title = "Passkeys are not supported in this browser"
        btn.classList.add("btn-disabled")
      })
    return
  }

  // Discoverable login button
  const discoverableBtn = document.querySelector('[data-passkey-login="discoverable"]')
  if (discoverableBtn) {
    discoverableBtn.addEventListener("click", async () => {
      try {
        discoverableBtn.disabled = true
        discoverableBtn.textContent = "Waiting for passkey..."

        const { token, options } = await jsonPost("/users/passkey-login/challenge")
        const assertion = await doAuthentication(options)
        const result = await jsonPost("/users/passkey-login", { token, assertion })

        if (result.ok) {
          window.location.href = result.redirect_to || "/"
        } else {
          showError(discoverableBtn, "Sign in with passkey", result.error)
        }
      } catch (err) {
        resetButton(discoverableBtn, "Sign in with passkey", err)
      }
    })
  }

  // Email-scoped login button
  const emailScopedBtn = document.querySelector('[data-passkey-login="email-scoped"]')
  if (emailScopedBtn) {
    emailScopedBtn.addEventListener("click", async () => {
      const emailInput = document.querySelector("#login_form_password_email")
      const email = emailInput?.value
      if (!email) {
        emailInput?.focus()
        return
      }

      try {
        emailScopedBtn.disabled = true
        emailScopedBtn.textContent = "Waiting for passkey..."

        const { token, options } = await jsonPost("/users/passkey-login/challenge", { email })
        const assertion = await doAuthentication(options)
        const result = await jsonPost("/users/passkey-login", { token, assertion })

        if (result.ok) {
          window.location.href = result.redirect_to || "/"
        } else {
          showError(emailScopedBtn, "Use passkey for this email", result.error)
        }
      } catch (err) {
        resetButton(emailScopedBtn, "Use passkey for this email", err)
      }
    })
  }

  // Reauth button (on the re-auth login page, dead view)
  const reauthBtn = document.querySelector('[data-reauth="true"]')
  if (reauthBtn) {
    reauthBtn.addEventListener("click", async () => {
      try {
        reauthBtn.disabled = true
        reauthBtn.textContent = "Waiting for passkey..."

        const { token, options } = await jsonPost("/users/passkey-reauth/challenge")
        const assertion = await doAuthentication(options)
        const result = await jsonPost("/users/passkey-reauth", { token, assertion })

        if (result.ok) {
          // Reload to pick up the refreshed sudo session
          const returnTo = new URLSearchParams(window.location.search).get("return_to")
          window.location.href = returnTo || window.location.href
        } else {
          showError(reauthBtn, "Re-authenticate with passkey", result.error)
        }
      } catch (err) {
        resetButton(reauthBtn, "Re-authenticate with passkey", err)
      }
    })
  }
}

function showError(btn, label, error) {
  alert("Failed: " + (error || "unknown error"))
  btn.disabled = false
  btn.textContent = label
}

function resetButton(btn, label, err) {
  console.error("Passkey error:", err)
  btn.disabled = false
  btn.textContent = label
  // Don't alert on user cancellation
  if (err.name !== "NotAllowedError") {
    alert("Passkey operation failed. Please try again.")
  }
}

// LiveView Hook for passkey registration in the settings page
export const PasskeyRegistrationHook = {
  mounted() {
    const label = this.el.dataset.label || "Add passkey"

    if (!isWebAuthnAvailable()) {
      this.el.disabled = true
      this.el.title = "Passkeys are not supported in this browser"
      this.el.classList.add("btn-disabled")
      return
    }

    this.el.addEventListener("click", async () => {
      try {
        this.el.disabled = true
        this.el.textContent = "Waiting..."

        const nameInput = document.getElementById("passkey-name-input")
        const friendlyName = nameInput?.value?.trim() || "Passkey"

        const { token, options } = await jsonPost("/users/passkey-register/challenge")
        const attestation = await doRegistration(options)
        const result = await jsonPost("/users/passkey-register", {
          token,
          attestation,
          friendly_name: friendlyName,
        })

        if (result.ok) {
          if (nameInput) nameInput.value = ""
          // Tell the LiveView to refresh the credential list
          this.pushEvent("registered", {})
        } else {
          alert("Registration failed: " + (result.error || "unknown error"))
        }

        this.el.disabled = false
        this.el.textContent = label
      } catch (err) {
        console.error("Registration error:", err)
        this.el.disabled = false
        this.el.textContent = label
        if (err.name !== "NotAllowedError") {
          alert("Passkey registration failed. Please try again.")
        }
      }
    })
  },
}
