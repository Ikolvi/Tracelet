'use client'

import React, { useState, useRef, useEffect } from 'react'
import versions from '../versions.json'

type Archived = {
  label: string
  slug: string
  tag?: string
  /** Locales this archive actually contains — see versions.json. */
  locales?: string[]
}

/**
 * Documentation version switcher.
 *
 * Sits next to the logo, where the version badge already lived — the badge was
 * always the thing users looked at to answer "which version am I reading?", so
 * it becomes the control that answers "how do I read a different one?".
 *
 * ## URL model
 *
 * The current release is served at the unprefixed paths (`/en/core/geofencing`)
 * and archives are nested one segment deeper (`/en/v3.7/core/geofencing`). That
 * keeps every existing link and every search result pointing at the current
 * docs, which is what a reader arriving from Google almost always wants.
 *
 * Switching preserves the page you are on where possible. An archive will not
 * contain pages added after it was cut, so a missing target would 404 on a
 * static export; `linkFor` therefore falls back to the version root rather than
 * producing a dead link. It cannot know what exists at build time without a
 * manifest of every archived path, and landing on the archive home is a better
 * outcome than a 404.
 */
export default function VersionSwitch({
  locale,
  archivedSlug
}: {
  locale: string
  /** Slug of the archive being viewed, or undefined on the current docs. */
  archivedSlug?: string
}) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)

  const archived: Archived[] = versions.archived as Archived[]
  const current = versions.current

  useEffect(() => {
    if (!open) return
    function onDocClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    function onEsc(e: KeyboardEvent) {
      if (e.key === 'Escape') setOpen(false)
    }
    document.addEventListener('mousedown', onDocClick)
    document.addEventListener('keydown', onEsc)
    return () => {
      document.removeEventListener('mousedown', onDocClick)
      document.removeEventListener('keydown', onEsc)
    }
  }, [open])

  const activeLabel = archivedSlug
    ? archived.find(v => v.slug === archivedSlug)?.label ?? archivedSlug
    : current.label

  /**
   * Maps the current path onto `targetSlug`, keeping the sub-path when the
   * switch is unambiguous.
   */
  function linkFor(targetSlug: string | null): string {
    // An archive cut before a locale existed has no pages in that locale, and a
    // static export turns a missing page into a 404 — so fall back to English
    // rather than offering a dead link. v3.7.6 predates the whole i18n tree,
    // which is exactly this case.
    const target = targetSlug ? archived.find(v => v.slug === targetSlug) : null
    const targetLocale =
      target && target.locales && !target.locales.includes(locale) ? 'en' : locale

    if (typeof window === 'undefined') {
      return targetSlug ? `/${targetLocale}/${targetSlug}` : `/${targetLocale}`
    }
    const segments = window.location.pathname.split('/').filter(Boolean)
    // segments[0] is the locale; drop it and any archive slug that follows.
    let rest = segments.slice(1)
    if (rest.length && archived.some(v => v.slug === rest[0])) rest = rest.slice(1)

    const base = targetSlug ? `/${targetLocale}/${targetSlug}` : `/${targetLocale}`
    // Only carry the sub-path when moving TO the current docs, which is a
    // superset of every archive. Moving to an archive risks a page that did not
    // exist then, so land on its home instead of a 404.
    if (!targetSlug && rest.length) return `${base}/${rest.join('/')}`
    return base
  }

  const isArchived = Boolean(archivedSlug)

  return (
    <div ref={ref} style={{ position: 'relative', display: 'inline-block' }}>
      <button
        type="button"
        onClick={() => setOpen(o => !o)}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-label={`Documentation version: ${activeLabel}`}
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '4px',
          fontSize: '12px',
          lineHeight: 1.4,
          background: isArchived ? 'rgba(217, 119, 6, 0.15)' : 'rgba(15, 157, 88, 0.2)',
          color: isArchived ? '#b45309' : '#0F9D58',
          padding: '2px 6px',
          borderRadius: '4px',
          border: 'none',
          cursor: 'pointer',
          fontWeight: 600
        }}
      >
        {activeLabel}
        <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" aria-hidden="true">
          <polyline points="6 9 12 15 18 9" />
        </svg>
      </button>

      {open && (
        <div
          role="listbox"
          style={{
            position: 'absolute',
            top: 'calc(100% + 6px)',
            left: 0,
            minWidth: '190px',
            background: 'var(--nextra-bg, #fff)',
            border: '1px solid rgba(125,125,125,0.25)',
            borderRadius: '8px',
            boxShadow: '0 8px 24px rgba(0,0,0,0.14)',
            padding: '4px',
            zIndex: 60
          }}
        >
          <VersionItem
            href={linkFor(null)}
            label={current.label}
            note="latest"
            active={!archivedSlug}
          />
          {archived.map(v => (
            <VersionItem
              key={v.slug}
              href={linkFor(v.slug)}
              label={v.label}
              note={
                v.locales && !v.locales.includes(locale)
                  ? 'archived · en'
                  : 'archived'
              }
              active={archivedSlug === v.slug}
            />
          ))}
        </div>
      )}
    </div>
  )
}

function VersionItem({
  href,
  label,
  note,
  active
}: {
  href: string
  label: string
  note: string
  active: boolean
}) {
  return (
    <a
      href={href}
      role="option"
      aria-selected={active}
      style={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        gap: '12px',
        padding: '6px 10px',
        borderRadius: '6px',
        textDecoration: 'none',
        fontSize: '13px',
        color: active ? '#0F9D58' : 'inherit',
        fontWeight: active ? 600 : 400,
        background: active ? 'rgba(15,157,88,0.10)' : 'transparent'
      }}
    >
      <span>{label}</span>
      <span style={{ fontSize: '11px', opacity: 0.55 }}>{note}</span>
    </a>
  )
}
