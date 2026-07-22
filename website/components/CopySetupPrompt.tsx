"use client";

import React, { useState, useRef, useEffect } from "react";
import { usePathname } from "next/navigation";
import { buildAiSetupPrompt, LOCALE_LANGUAGE_NAMES } from "../lib/aiSetupPrompt";
import { trackEvent } from "../lib/analytics";

type Variant = "hero" | "inline";

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

export default function CopySetupPrompt({ variant = "hero" }: { variant?: Variant }) {
  const [copied, setCopied] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pathname = usePathname();
  const locale = localeFromPathname(pathname);
  const labels = LABELS[locale] ?? LABELS.en;

  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  const handleCopy = async () => {
    const prompt = buildAiSetupPrompt(LOCALE_LANGUAGE_NAMES[locale]);
    try {
      await navigator.clipboard.writeText(prompt);
    } catch (e) {
      // Fallback for browsers without clipboard API permission
      const textarea = document.createElement("textarea");
      textarea.value = prompt;
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand("copy");
      document.body.removeChild(textarea);
    }

    trackEvent("copy_ai_setup_prompt", { variant, locale, trigger: "button" });

    setCopied(true);
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => setCopied(false), 2500);
  };

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
    transition: "background-color 0.2s, color 0.2s",
  };

  return (
    <button type="button" onClick={handleCopy} style={baseStyle} aria-live="polite">
      {copied ? <>✓ {labels.copied}</> : <>✨ {labels.copy}</>}
    </button>
  );
}
