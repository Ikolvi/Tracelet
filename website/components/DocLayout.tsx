import React, { Suspense } from 'react'
import { Footer, Layout, Navbar } from 'nextra-theme-docs'
import { Head } from 'nextra/components'
import RainBackground from './RainBackground'
import LanguagePrompt from './LanguagePrompt'
import TrackedLink from './TrackedLink'
import NotificationBell from './NotificationBell'
import { LocaleSwitch } from 'nextra-theme-docs'
import VersionSwitch from './VersionSwitch'
import 'nextra-theme-docs/style.css'

const supportTitles: Record<string, string> = {
  en: "Support Tracelet",
  ja: "Traceletをサポート",
  zh: "支持 Tracelet",
  es: "Apoyar a Tracelet",
  hi: "ट्रेसलेट का समर्थन करें",
  ml: "ട്രേസ്‌ലെറ്റിനെ പിന്തുണയ്ക്കുക",
  ta: "ட்ரேஸ்லெட்டை ஆதரிக்கவும்",
  ru: "Поддержать Tracelet"
};

const editLinks: Record<string, string> = {
  en: "Edit this page on GitHub",
  ja: "GitHubでこのページを編集",
  zh: "在 GitHub 上编辑此页",
  es: "Editar esta página en GitHub",
  hi: "गिटहब पर इस पृष्ठ को संपादित करें",
  ml: "ഗিটഹബ്ബിൽ ഈ പേജ് തിരുത്തുക",
  ta: "இந்த பக்கத்தை GitHub இல் திருத்துக",
  ru: "Редактировать эту страницу на GitHub"
};

const tocTitles: Record<string, string> = {
  en: "On This Page",
  ja: "このページの内容",
  zh: "本页内容",
  es: "En esta página",
  hi: "इस पृष्ठ पर",
  ml: "ഈ പേജിൽ",
  ta: "இந்த பக்கத்தில்",
  ru: "На этой странице"
};

const askQuestionTitles: Record<string, string> = {
  en: "Ask a Question",
  ja: "質問する",
  zh: "提问",
  es: "Hacer una pregunta",
  hi: "प्रश्न पूछें",
  ml: "ഒരു ചോദ്യം ചോദിക്കുക",
  ta: "கேள்வி கேளுங்கள்",
  ru: "Задать вопрос"
};

const reportIssueTitles: Record<string, string> = {
  en: "Report an Issue",
  ja: "問題を報告",
  zh: "报告问题",
  es: "Informar de un problema",
  hi: "समस्या की रिपोर्ट करें",
  ml: "ഒരു പ്രശ്നം റിപ്പോർട്ട് ചെയ്യുക",
  ta: "பிரச்சனையை புகாரளிக்கவும்",
  ru: "Сообщить о проблеме"
};

const archivedNotice: Record<string, string> = {
  en: "You are reading archived documentation for",
  ja: "アーカイブされたドキュメントを読んでいます:",
  zh: "您正在阅读已归档的文档:",
  es: "Estás leyendo documentación archivada de",
  hi: "आप संग्रहीत दस्तावेज़ पढ़ रहे हैं:",
  ml: "നിങ്ങൾ ആർക്കൈവ് ചെയ്ത ഡോക്യുമെന്റേഷൻ വായിക്കുന്നു:",
  ta: "நீங்கள் காப்பகப்படுத்தப்பட்ட ஆவணங்களைப் படிக்கிறீர்கள்:",
  ru: "Вы читаете архивную документацию для"
};

const archivedCta: Record<string, string> = {
  en: "Go to the latest docs",
  ja: "最新のドキュメントへ",
  zh: "前往最新文档",
  es: "Ir a la documentación más reciente",
  hi: "नवीनतम दस्तावेज़ पर जाएँ",
  ml: "ഏറ്റവും പുതിയ ഡോക്യുമെന്റേഷനിലേക്ക്",
  ta: "சமீபத்திய ஆவணங்களுக்குச் செல்லவும்",
  ru: "Перейти к последней документации"
};

export default function DocLayout({ children, pageMap, version, locale, archivedSlug }: { children: React.ReactNode, pageMap: any, version: string, locale: string, archivedSlug?: string }) {
  return (
    <>
      <Layout
        pageMap={pageMap}
        i18n={[
          { locale: 'en', name: 'English' },
          { locale: 'ja', name: '日本語' },
          { locale: 'zh', name: '中文' },
          { locale: 'es', name: 'Español' },
          { locale: 'hi', name: 'हिन्दी' },
          { locale: 'ml', name: 'മലയാളം' },
          { locale: 'ta', name: 'தமிழ்' },
          { locale: 'ru', name: 'Русский' }
        ]}
        navbar={<Navbar logo={
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <b style={{ color: '#0F9D58' }}>Tracelet</b>
            <VersionSwitch locale={locale} archivedSlug={archivedSlug} />
          </div>
        }>
          <div className="hidden md:flex ml-4">
            <div style={{ display: 'flex', flexDirection: 'row', alignItems: 'center', gap: '1rem' }}>
              <NotificationBell />
              <LocaleSwitch />
            </div>
          </div>
        </Navbar>}
        footer={<Footer>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', width: '100%', flexWrap: 'wrap', gap: '1rem', padding: '0.5rem 0' }}>
            <div style={{ fontSize: '0.9rem', color: '#6b7280' }}>
              Apache-2.0 {new Date().getFullYear()} © Tracelet Contributors
            </div>
            
            <div style={{ display: 'flex', alignItems: 'center', gap: '1.25rem', flexWrap: 'wrap', fontSize: '0.9rem' }}>
              <TrackedLink eventName="support_button_clicked" href={`/${locale}/sponsor`} className="footer-link" style={{ color: '#0F9D58', fontWeight: '600' }}>❤️ {supportTitles[locale] || supportTitles.en}</TrackedLink>
              
              <a href={`/${locale}/privacy`} style={{ textDecoration: 'none', color: '#6b7280' }}>Privacy Policy</a>
              <a href={`/${locale}/terms`} style={{ textDecoration: 'none', color: '#6b7280' }}>Terms of Service</a>
              <a href={`/${locale}/license`} style={{ textDecoration: 'none', color: '#6b7280' }}>License</a>

              <span style={{ borderLeft: '1px solid #d1d5db', height: '16px', margin: '0 0.5rem' }}></span>
              <span style={{ fontWeight: '600', color: '#4b5563' }}>Powered by Ikolvi</span>
            </div>
          </div>
        </Footer>}
        docsRepositoryBase="https://github.com/Ikolvi/Tracelet/tree/main/website"
        editLink={editLinks[locale] || editLinks.en}
        darkMode={true}
        toc={{
          title: tocTitles[locale] || tocTitles.en,
          extraContent: (
            <div style={{ marginTop: '2rem', display: 'flex', flexDirection: 'column', gap: '0.75rem', fontSize: '0.85rem' }}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                <TrackedLink eventName="support_button_clicked" href={`/${locale}/sponsor`} style={{ textDecoration: 'none' }}><b style={{ color: '#0F9D58' }}>❤️ {supportTitles[locale] || supportTitles.en}</b></TrackedLink>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem', paddingLeft: '1.25rem' }}>
                  <a href="https://github.com/sponsors/GalacticTitan" target="_blank" rel="noopener noreferrer" style={{ textDecoration: 'none', color: '#6b7280', display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                    <span style={{ fontSize: '12px' }}>🐙</span> GitHub Sponsors
                  </a>
                  <a href="https://www.buymeacoffee.com/kiranbjm" target="_blank" rel="noopener noreferrer" style={{ textDecoration: 'none', color: '#6b7280', display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                    <span style={{ fontSize: '12px' }}>☕</span> Buy Me a Coffee
                  </a>
                  <a href="https://thanks.dev/d/gh/galactictitan/dependencies" target="_blank" rel="noopener noreferrer" style={{ textDecoration: 'none', color: '#6b7280', display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                    <span style={{ fontSize: '12px' }}>✨</span> Thanks.dev
                  </a>
                  <a href="https://www.patreon.com/c/kiranbjm" target="_blank" rel="noopener noreferrer" style={{ textDecoration: 'none', color: '#6b7280', display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                    <span style={{ fontSize: '12px' }}>🟠</span> Patreon
                  </a>
                </div>
              </div>
              <a href="https://github.com/Ikolvi/Tracelet/discussions" target="_blank" rel="noopener noreferrer" style={{ textDecoration: 'none', color: '#6b7280', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"></path></svg>
                {askQuestionTitles[locale] || askQuestionTitles.en}
              </a>
              <a href="https://github.com/Ikolvi/Tracelet/issues/new/choose" target="_blank" rel="noopener noreferrer" style={{ textDecoration: 'none', color: '#6b7280', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="8" x2="12" y2="12"></line><line x1="12" y1="16" x2="12.01" y2="16"></line></svg>
                {reportIssueTitles[locale] || reportIssueTitles.en}
              </a>
            </div>
          )
        }}
      >
        {archivedSlug ? (
          <div
            role="note"
            style={{
              display: 'flex',
              flexWrap: 'wrap',
              alignItems: 'center',
              gap: '0.5rem',
              margin: '0 0 1.5rem',
              padding: '0.75rem 1rem',
              borderRadius: '8px',
              border: '1px solid rgba(217, 119, 6, 0.35)',
              background: 'rgba(217, 119, 6, 0.10)',
              fontSize: '0.9rem'
            }}
          >
            <span>
              {archivedNotice[locale] || archivedNotice.en} <b>{version}</b>.
            </span>
            <a href={`/${locale}`} style={{ color: '#0F9D58', fontWeight: 600 }}>
              {archivedCta[locale] || archivedCta.en} →
            </a>
          </div>
        ) : null}
        {children}
      </Layout>
      <RainBackground />
      <LanguagePrompt />
    </>
  )
}
