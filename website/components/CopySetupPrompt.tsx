"use client";

import React, { useState, useRef, useEffect } from "react";
import { usePathname } from "next/navigation";
import { buildAiSetupPrompt, LOCALE_LANGUAGE_NAMES } from "../lib/aiSetupPrompt";
import { trackEvent } from "../lib/analytics";

type Variant = "hero" | "inline";

// Anchor id used both for URL hash navigation and for the auto-copy landing
// flow triggered from the GitHub / pub.dev README badge.
const COPY_ANCHOR_ID = "copy-ai-setup-prompt";

// Button labels per site locale. The prompt itself stays English (AI models
// follow English instructions most reliably) but instructs the AI to run the
// interview in the visitor's language.
const LABELS: Record<string, { copy: string; copied: string }> = {
  en: { copy: "Copy AI Setup Prompt", copied: "Prompt Copied — paste it into your AI" },
  es: { copy: "Copiar prompt de configuración IA", copied: "¡Copiado! Pégalo en tu IA" },
  hi: { copy: "AI सेटअप प्रॉम्प्ट कॉपी करें", copied: "कॉपी हो गया — अपने AI में पेस्ट करें" },
  ja: { copy: "AIセットアッププロンプトをコピー", copied: "コピーしました — AIに貼り付けてください" },
  ml: { copy: "AI സെറ്റപ്പ് പ്രോംപ്റ്റ് പകർത്തുക", copied: "പകർത്തി — നിങ്ങളുടെ AI-യിൽ പേസ്റ്റ് ചെയ്യുക" },
  ru: { copy: "Скопировать AI-промпт настройки", copied: "Скопировано — вставьте в ваш AI" },
  ta: { copy: "AI அமைவு ப்ராம்ப்டை நகலெடு", copied: "நகலெடுக்கப்பட்டது — உங்கள் AI-யில் ஒட்டவும்" },
  zh: { copy: "复制 AI 配置提示词", copied: "已复制 — 粘贴到你的 AI 中" },
};

function localeFromPathname(pathname: string | null): string {
  const first = (pathname || "").split("/").filter(Boolean)[0];
  return first && LOCALE_LANGUAGE_NAMES[first] ? first : "en";
}

async function writeClipboard(text: string): Promise<boolean> {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    // fall through to the legacy path below
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
}

// True when the visitor arrived from the README badge, e.g.
// /en?copyPrompt=1  or  /en#copy-ai-setup-prompt
function landedForCopy(): boolean {
  if (typeof window === "undefined") return false;
  const params = new URLSearchParams(window.location.search);
  if (params.get("copyPrompt") === "1") return true;
  return window.location.hash === `#${COPY_ANCHOR_ID}`;
}

// Resolves the given promise, or `fallback` if it hasn't settled within `ms`.
// A gesture-less clipboard write can hang indefinitely in some browsers when
// the tab isn't focused, so we never await it unguarded.
function withTimeout<T>(p: Promise<T>, ms: number, fallback: T): Promise<T> {
  return Promise.race([
    p,
    new Promise<T>((resolve) => setTimeout(() => resolve(fallback), ms)),
  ]);
}

export default function CopySetupPrompt({ variant = "hero" }: { variant?: Variant }) {
  const [copied, setCopied] = useState(false);
  // "attention" = the browser blocked the automatic copy on landing, so we
  // pulse-highlight the button to nudge the visitor to click it once.
  const [attention, setAttention] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const buttonRef = useRef<HTMLButtonElement | null>(null);
  const pathname = usePathname();
  const locale = localeFromPathname(pathname);
  const labels = LABELS[locale] ?? LABELS.en;

  const flashCopied = () => {
    setAttention(false);
    setCopied(true);
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => setCopied(false), 2500);
  };

  const doCopy = async (trigger: "auto" | "button"): Promise<boolean> => {
    const prompt = buildAiSetupPrompt(LOCALE_LANGUAGE_NAMES[locale]);
    const ok = await writeClipboard(prompt);
    if (ok) {
      trackEvent("copy_ai_setup_prompt", { variant, locale, trigger });
      flashCopied();
    }
    return ok;
  };

  const handleCopy = () => {
    void doCopy("button");
  };

  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  // README landing flow: only the hero button (home page) reacts to the badge
  // marker. Browsers block a clipboard write that isn't tied to a user gesture
  // on our own page (the click happened on pub.dev / GitHub), so we can't rely
  // on auto-copy. Instead we immediately scroll the button into view and pulse
  // it so a single click copies — then attempt a best-effort auto-copy in the
  // background for the browsers that do allow it.
  useEffect(() => {
    if (variant !== "hero" || !landedForCopy()) return;

    let cancelled = false;

    // Guide the visitor to the button first, no matter what the clipboard does.
    setAttention(true);
    buttonRef.current?.scrollIntoView({ behavior: "smooth", block: "center" });

    // Clean the marker out of the URL so a refresh doesn't re-trigger this.
    try {
      const url = new URL(window.location.href);
      url.searchParams.delete("copyPrompt");
      if (url.hash === `#${COPY_ANCHOR_ID}`) url.hash = "";
      window.history.replaceState(null, "", url.pathname + url.search + url.hash);
    } catch {
      // non-fatal
    }

    // Best-effort auto-copy, guarded so a hung clipboard promise can't stall.
    // On success doCopy() clears the pulse and shows the "copied" state; on
    // failure the button keeps pulsing for the visitor to click.
    void withTimeout(doCopy("auto"), 1500, false).then((ok) => {
      if (!cancelled && ok) setAttention(false);
    });

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [variant, locale]);

  const baseStyle: React.CSSProperties = {
    padding: variant === "hero" ? "0.75rem 1.5rem" : "0.5rem 1rem",
    fontWeight: 600,
    borderRadius: "0.5rem",
    border: "1px solid #0F9D58",
    color: copied ? "white" : "#0F9D58",
    backgroundColor: copied ? "#0F9D58" : "transparent",
    cursor: "pointer",
    fontSize: variant === "hero" ? "1rem" : "0.9rem",
    display: "inline-flex",
    alignItems: "center",
    gap: "0.5rem",
    transition: "background-color 0.2s, color 0.2s, box-shadow 0.2s",
  };

  return (
    <button
      type="button"
      id={variant === "hero" ? COPY_ANCHOR_ID : undefined}
      ref={buttonRef}
      onClick={handleCopy}
      style={baseStyle}
      className={attention ? "tracelet-copy-attention" : undefined}
      aria-live="polite"
    >
      {copied ? <>✓ {labels.copied}</> : <>✨ {labels.copy}</>}
    </button>
  );
}
