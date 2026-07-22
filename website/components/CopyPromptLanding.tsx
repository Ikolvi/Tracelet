"use client";

import React, { useEffect, useRef, useState } from "react";
import { buildAiSetupPrompt } from "../lib/aiSetupPrompt";
import { trackEvent } from "../lib/analytics";

// Standalone landing page reached from the GitHub / pub.dev README "Copy AI
// Setup Prompt" badge. GitHub and pub.dev sanitize away all JavaScript, so a
// working copy button can't live in the README itself — the badge is a plain
// link to this page, which does the copy here where our JS is allowed to run.
//
// Flow: on load we attempt an automatic clipboard write. Because the click that
// brought the visitor here happened on github.com (not on this page), browsers
// may reject that gesture-less write — so we always render a large, reliable
// one-click Copy button and the full prompt text as a fallback.

type CopyState = "idle" | "copied" | "manual";

const ACCENT = "#0F9D58";

export default function CopyPromptLanding() {
  const [state, setState] = useState<CopyState>("idle");
  const promptRef = useRef<string>(buildAiSetupPrompt("English"));
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const writeClipboard = async (text: string): Promise<boolean> => {
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(text);
        return true;
      }
    } catch {
      // fall through to legacy path
    }
    try {
      const textarea = document.createElement("textarea");
      textarea.value = text;
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.select();
      const ok = document.execCommand("copy");
      document.body.removeChild(textarea);
      return ok;
    } catch {
      return false;
    }
  };

  const flashCopied = () => {
    setState("copied");
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => setState("idle"), 2500);
  };

  const track = (trigger: "auto" | "button") => {
    trackEvent("copy_ai_setup_prompt", { variant: "landing", locale: "en", trigger });
  };

  // Attempt auto-copy on load. If the browser blocks the gesture-less write,
  // fall back to prompting the visitor to click the button.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const ok = await writeClipboard(promptRef.current);
      if (cancelled) return;
      if (ok) {
        track("auto");
        flashCopied();
      } else {
        setState("manual");
      }
    })();
    return () => {
      cancelled = true;
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  const handleCopy = async () => {
    const ok = await writeClipboard(promptRef.current);
    if (ok) {
      track("button");
      flashCopied();
    } else {
      setState("manual");
    }
  };

  const copied = state === "copied";

  return (
    <main
      style={{
        minHeight: "100vh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        padding: "3rem 1.25rem 4rem",
        fontFamily:
          "system-ui, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif",
        color: "#111827",
        background: "#ffffff",
        boxSizing: "border-box",
      }}
    >
      <div style={{ width: "100%", maxWidth: "820px" }}>
        <a
          href="https://tracelet.ikolvi.com"
          style={{ color: ACCENT, textDecoration: "none", fontWeight: 600, fontSize: "0.95rem" }}
        >
          ← Tracelet docs
        </a>

        <h1 style={{ fontSize: "1.9rem", fontWeight: 800, margin: "1.25rem 0 0.5rem" }}>
          Tracelet AI Setup Prompt
        </h1>
        <p style={{ fontSize: "1.05rem", lineHeight: 1.6, color: "#374151", margin: "0 0 1.5rem" }}>
          {copied
            ? "The prompt is on your clipboard. Paste it into your AI coding assistant (Cursor, Claude Code, Kiro, Copilot Chat, etc.) and it will interview you, then install and configure Tracelet for your exact use case."
            : "Copy the prompt below and paste it into your AI coding assistant (Cursor, Claude Code, Kiro, Copilot Chat, etc.). It will interview you, then install and configure Tracelet for your exact use case."}
        </p>

        <button
          type="button"
          onClick={handleCopy}
          aria-live="polite"
          style={{
            padding: "0.85rem 1.6rem",
            fontWeight: 700,
            fontSize: "1.05rem",
            borderRadius: "0.6rem",
            border: `1px solid ${ACCENT}`,
            color: copied ? "#ffffff" : ACCENT,
            backgroundColor: copied ? ACCENT : "transparent",
            cursor: "pointer",
            display: "inline-flex",
            alignItems: "center",
            gap: "0.55rem",
            transition: "background-color 0.2s, color 0.2s",
          }}
        >
          {copied ? <>✓ Prompt copied — paste it into your AI</> : <>✨ Copy AI Setup Prompt</>}
        </button>

        {state === "manual" && (
          <p style={{ marginTop: "0.75rem", color: "#b45309", fontSize: "0.9rem" }}>
            Your browser blocked automatic copying. Click the button above, or select the text
            below and copy it manually.
          </p>
        )}

        <label
          htmlFor="tracelet-prompt"
          style={{ display: "block", marginTop: "2rem", marginBottom: "0.5rem", fontWeight: 600, color: "#374151" }}
        >
          Prompt
        </label>
        <textarea
          id="tracelet-prompt"
          readOnly
          value={promptRef.current}
          onFocus={(e) => e.currentTarget.select()}
          spellCheck={false}
          style={{
            width: "100%",
            height: "420px",
            padding: "1rem",
            fontFamily:
              "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', monospace",
            fontSize: "0.82rem",
            lineHeight: 1.55,
            color: "#111827",
            background: "#f9fafb",
            border: "1px solid #e5e7eb",
            borderRadius: "0.6rem",
            resize: "vertical",
            boxSizing: "border-box",
          }}
        />

        <p style={{ marginTop: "1.5rem", fontSize: "0.9rem", color: "#6b7280", lineHeight: 1.6 }}>
          New to Tracelet? Start with the{" "}
          <a href="https://tracelet.ikolvi.com/en/quick-start" style={{ color: ACCENT }}>
            Quick Start
          </a>{" "}
          or the{" "}
          <a href="https://tracelet.ikolvi.com/en/installation" style={{ color: ACCENT }}>
            Installation guide
          </a>
          .
        </p>
      </div>
    </main>
  );
}
