'use client'

import React, { useState, useRef, useEffect } from 'react'
import versions from '../versions.json'

const SEMVER = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/

/**
 * Semver precedence, enough for pub.dev version strings.
 *
 * The only subtle rule is that a prerelease sorts BELOW its own release
 * (`3.8.0-beta.2` < `3.8.0`), so publishing the stable build promotes the badge
 * on its own. Build metadata (`+…`) is ignored, as the spec requires.
 * Numeric prerelease identifiers compare numerically, so `beta.10` > `beta.2`.
 */
function compareSemver(a: string, b: string): number {
  const parse = (v: string) => {
    const [core, pre] = v.split('+')[0].split('-')
    return {
      nums: core.split('.').map(Number),
      pre: pre ? pre.split('.') : null
    }
  }
  const x = parse(a)
  const y = parse(b)
  for (let i = 0; i < 3; i++) {
    if (x.nums[i] !== y.nums[i]) return x.nums[i] - y.nums[i]
  }
  if (!x.pre && !y.pre) return 0
  if (!x.pre) return 1 // a release outranks any prerelease of it
  if (!y.pre) return -1
  for (let i = 0; i < Math.max(x.pre.length, y.pre.length); i++) {
    const p = x.pre[i]
    const q = y.pre[i]
    if (p === undefined) return -1
    if (q === undefined) return 1
    if (p === q) continue
    const pn = /^\d+$/.test(p)
    const qn = /^\d+$/.test(q)
    if (pn && qn) return Number(p) - Number(q)
    if (pn !== qn) return pn ? -1 : 1 // numeric identifiers rank lower
    return p < q ? -1 : 1
  }
  return 0
}

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
 * and archives live under a top-level version segment
 * (`/v3.7/en/core/geofencing`). Current URLs are untouched, so every existing
 * link and search result keeps pointing at the current docs — what a reader
 * arriving from Google almost always wants.
 *
 * The version segment comes FIRST on purpose: nesting it under the locale
 * (`/en/v3.7/…`) puts the archive inside the live locale's layout, and Next
 * composes layouts, so each archived page rendered two navbars and two footers.
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

  /**
   * Latest published version, read from pub.dev at runtime.
   *
   * `versions.json` is the seed and the fallback, never the sole source: it
   * drifts the moment a release publishes without a docs commit. pub.dev is
   * authoritative for "what can someone actually install right now".
   *
   * This is a **client-side** fetch, which is why it works here where the
   * original build-time one could not. Under `output: 'export'` there is no
   * server and no revalidation, so a build-time fetch froze whatever the CI
   * machine saw — and fell back to a hardcoded `v1.0.0` on any network hiccup,
   * silently shipping a wrong badge. See the note in `versions.json`.
   *
   * On failure the committed label stands, so the worst case is a slightly
   * stale but always *real* version rather than a fabricated one.
   */
  const [publishedLabel, setPublishedLabel] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    fetch('https://pub.dev/api/packages/tracelet', {
      headers: { Accept: 'application/json' }
    })
      .then(r => (r.ok ? r.json() : null))
      .then(
        (
          data: {
            latest?: { version?: string }
            versions?: { version?: string }[]
          } | null
        ) => {
          if (cancelled || !data) return
          // Include prereleases: the docs describe what is installable *now*,
          // and during a release cycle that is the beta. `latest` is stable-only
          // (3.7.6 while 3.8.0-beta.2 was the newest thing published), so scan
          // every version rather than trusting that field or the array order.
          const all = (data.versions ?? [])
            .map(v => v?.version)
            .filter((v): v is string => typeof v === 'string' && SEMVER.test(v))
          if (data.latest?.version && SEMVER.test(data.latest.version)) {
            all.push(data.latest.version)
          }
          const newest = all.sort(compareSemver).pop()
          if (newest) setPublishedLabel(newest)
        }
      )
      .catch(() => {
        /* Offline or blocked — keep the committed label. */
      })
    return () => {
      cancelled = true
    }
  }, [])

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

  // Archives are frozen records of what a release shipped, so they always use
  // their committed label; only the current docs track pub.dev.
  const currentLabel = publishedLabel ?? current.label
  const activeLabel = archivedSlug
    ? archived.find(v => v.slug === archivedSlug)?.label ?? archivedSlug
    : currentLabel

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
      return targetSlug ? `/${targetSlug}/${targetLocale}` : `/${targetLocale}`
    }
    // Paths are either `/<locale>/…` (current) or `/<slug>/<locale>/…`
    // (archived); strip whichever prefix is present to get the page path.
    const segments = window.location.pathname.split('/').filter(Boolean)
    let rest = segments
    if (rest.length && archived.some(v => v.slug === rest[0])) rest = rest.slice(1)
    rest = rest.slice(1) // drop the locale

    const base = targetSlug ? `/${targetSlug}/${targetLocale}` : `/${targetLocale}`
    // Only carry the sub-path when moving TO the current docs, which is a
    // superset of every archive. Moving to an archive risks a page that did not
    // exist then, so land on its home instead of a 404.
    if (!targetSlug && rest.length) return `${base}/${rest.join('/')}`
    return base
  }

  const isArchived = Boolean(archivedSlug)

  // With no archives there is nothing to switch *to*, so the control is a
  // label, not a menu. Rendering the button anyway gave a dropdown whose only
  // entry was the page you were already on — an affordance that promises a
  // choice and then offers none. The badge itself still earns its place: it
  // reports the newest published version from pub.dev.
  if (archived.length === 0) {
    return (
      <span
        aria-label={`Documentation version: ${activeLabel}`}
        style={{
          display: 'inline-flex',
          alignItems: 'center',
          fontSize: '12px',
          lineHeight: 1.4,
          background: 'rgba(15, 157, 88, 0.2)',
          color: '#0F9D58',
          padding: '2px 6px',
          borderRadius: '4px',
          fontWeight: 600
        }}
      >
        {activeLabel}
      </span>
    )
  }

  return (
    // Nextra renders the `logo` prop inside `<a href="/" aria-label="Home page">`,
    // so without stopping the event here every click on this control bubbles to
    // that anchor and navigates home — the dropdown appeared to do nothing but
    // reload the page. preventDefault kills the anchor's navigation;
    // stopPropagation keeps it from reaching any other handler.
    <div
      ref={ref}
      onClick={e => {
        e.preventDefault()
        e.stopPropagation()
      }}
      style={{ position: 'relative', display: 'inline-block' }}
    >
      <button
        type="button"
        onClick={e => {
          e.preventDefault()
          e.stopPropagation()
          setOpen(o => !o)
        }}
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
            label={currentLabel}
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
      // The wrapper above swallows clicks to stop the logo anchor from firing,
      // which would otherwise also swallow these. Navigate explicitly instead.
      onClick={e => {
        e.preventDefault()
        e.stopPropagation()
        window.location.href = href
      }}
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
